//
//  CameraExtensionProvider.swift
//  CameraExtension
//
//  Created by Logan Rupe on 20/5/2026.
//

import Foundation
import CoreMediaIO
import IOKit.audio
import IOSurface
import os.log
import notify

let kFrameRate: Int = 60

/// App group identifier shared between host and extension.
private let kAppGroupID = "group.io.github.loganrupe.CursorFollowHost"

/// Darwin notification name for cross-user surface ID sharing.
private let kSurfaceNotificationName = "io.github.loganrupe.CursorFollowHost.surfaceID"

/// notify.h NOTIFY_TOKEN_INVALID = UINT32_MAX, not visible to Swift as it's a C macro.
private let kNotifyTokenInvalid: Int32 = -1

// MARK: -

class CameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
	
	private(set) var device: CMIOExtensionDevice!
	
	private var _streamSource: CameraExtensionStreamSource!
	
	private var _streamingCounter: UInt32 = 0
	
	private var _timer: DispatchSourceTimer?
	
	private let _timerQueue = DispatchQueue(label: "timerQueue", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem, target: .global(qos: .userInteractive))
	
	private var _videoDescription: CMFormatDescription!
	
	private var _bufferPool: CVPixelBufferPool!
	
	private var _bufferAuxAttributes: NSDictionary!

	// Frame receiver state
	private var _sharedSurface: IOSurfaceRef?
	private var _currentSurfaceID: UInt32 = 0
	private var _lastSeed: UInt32 = 0
	private var _notifyToken: Int32 = -1
	private var _surfaceCheckCounter: UInt64 = 0
	
	private let _log = Logger(subsystem: "io.github.loganrupe.CursorFollowHost.CameraExtension", category: "DeviceSource")
	
	init(localizedName: String) {
		
		// Register for Darwin notification to receive surfaceID from host (works cross-user)
		var token: Int32 = -1
		let status = notify_register_check(kSurfaceNotificationName, &token)
		if status == NOTIFY_STATUS_OK {
			_notifyToken = token
		}
		
		super.init()
		let deviceID = UUID()
		self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceID, legacyDeviceID: nil, source: self)
		
		let dims = CMVideoDimensions(width: 1920, height: 1080)
		CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCVPixelFormatType_32BGRA, width: dims.width, height: dims.height, extensions: nil, formatDescriptionOut: &_videoDescription)
		
		let pixelBufferAttributes: NSDictionary = [
			kCVPixelBufferWidthKey: dims.width,
			kCVPixelBufferHeightKey: dims.height,
			kCVPixelBufferPixelFormatTypeKey: _videoDescription.mediaSubType,
			kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary
		]
		CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &_bufferPool)
		
		let videoStreamFormat = CMIOExtensionStreamFormat.init(formatDescription: _videoDescription, maxFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)), minFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)), validFrameDurations: nil)
		_bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]
		
		let videoID = UUID()
		_streamSource = CameraExtensionStreamSource(localizedName: "CursorFollow Camera.Video", streamID: videoID, streamFormat: videoStreamFormat, device: device)
		do {
			try device.addStream(_streamSource.stream)
		} catch let error {
			fatalError("Failed to add stream: \(error.localizedDescription)")
		}
		
		if _notifyToken != kNotifyTokenInvalid {
			_log.error("Frame receiver ready — listening for surfaceID via Darwin notification")
		} else {
			_log.error("Cannot register Darwin notification — will output black frames")
		}
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		return [.deviceTransportType, .deviceModel]
	}
	
	func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
		
		let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
		if properties.contains(.deviceTransportType) {
			deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
		}
		if properties.contains(.deviceModel) {
			deviceProperties.model = "CursorFollow Camera"
		}
		
		return deviceProperties
	}
	
	func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
		
		// Handle settable properties here.
	}
	
	func startStreaming() {
		
		guard let _ = _bufferPool else {
			return
		}
		
		_streamingCounter += 1
		
		_timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
		_timer!.schedule(deadline: .now(), repeating: 1.0 / Double(kFrameRate), leeway: .seconds(0))
		
		_timer!.setEventHandler { [weak self] in
			self?.emitFrame()
		}
		
		_timer!.setCancelHandler {
		}
		
		_timer!.resume()
		_log.info("Streaming started")
	}
	
	func stopStreaming() {
		
		if _streamingCounter > 1 {
			_streamingCounter -= 1
		}
		else {
			_streamingCounter = 0
			if let timer = _timer {
				timer.cancel()
				_timer = nil
			}
			_log.info("Streaming stopped")
		}
	}
	
	// MARK: - Frame Emission
	
	private func emitFrame() {
		var err: OSStatus = 0
		
		var pixelBuffer: CVPixelBuffer?
		err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, _bufferPool, _bufferAuxAttributes, &pixelBuffer)
		if err != 0 {
			_log.error("out of pixel buffers \(err)")
			return
		}
		
		guard let pixelBuffer = pixelBuffer else { return }
		
		// Try to read a live frame from the shared IOSurface
		let didCopy = copySharedFrame(into: pixelBuffer)
		
		if !didCopy {
			// Fallback: output a black frame
			CVPixelBufferLockBaseAddress(pixelBuffer, [])
			let base = CVPixelBufferGetBaseAddress(pixelBuffer)!
			let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
			let height = CVPixelBufferGetHeight(pixelBuffer)
			memset(base, 0, rowBytes * height)
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		}
		
		var sbuf: CMSampleBuffer!
		var timingInfo = CMSampleTimingInfo()
		timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
		err = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: _videoDescription, sampleTiming: &timingInfo, sampleBufferOut: &sbuf)
		if err == 0 {
			_streamSource.stream.send(sbuf, discontinuity: [], hostTimeInNanoseconds: UInt64(timingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC)))
		}
	}
	
	/// Reads the shared IOSurface and copies the current frame into the pixel buffer.
	/// Returns true if a frame was successfully copied.
	private func copySharedFrame(into pixelBuffer: CVPixelBuffer) -> Bool {
		guard _notifyToken != kNotifyTokenInvalid else { return false }
		
		// Periodically re-read surfaceID from Darwin notification state (in case host restarts)
		_surfaceCheckCounter += 1
		if _sharedSurface == nil || _surfaceCheckCounter % 60 == 0 {
			var state: UInt64 = 0
			notify_get_state(_notifyToken, &state)
			let storedID = UInt32(state)
			
			if storedID != 0 && (storedID != _currentSurfaceID || _sharedSurface == nil) {
				if let surface = IOSurfaceLookup(storedID) {
					_sharedSurface = surface
					_currentSurfaceID = storedID
					_lastSeed = IOSurfaceGetSeed(surface)
					_log.error("Acquired shared IOSurface: id=\(storedID) \(IOSurfaceGetWidth(surface))x\(IOSurfaceGetHeight(surface))")
				} else {
					if _surfaceCheckCounter % 300 == 0 {
						_log.error("IOSurfaceLookup failed for ID \(storedID)")
					}
				}
			}
		}
		
		guard let surface = _sharedSurface else { return false }
		
		// Check if there's a new frame by comparing the surface seed
		// (seed auto-increments each time the host unlocks after writing)
		let currentSeed = IOSurfaceGetSeed(surface)
		if currentSeed == _lastSeed {
			// No new frame — still copy the existing content (repeat frame)
			return copySurface(into: pixelBuffer)
		}
		_lastSeed = currentSeed
		
		return copySurface(into: pixelBuffer)
	}
	
	/// Copies pixel data from the shared IOSurface into the output pixel buffer.
	private func copySurface(into pixelBuffer: CVPixelBuffer) -> Bool {
		guard let surface = _sharedSurface else { return false }
		
		// Lock surface briefly for read
		IOSurfaceLock(surface, .readOnly, nil)
		
		let srcBase = IOSurfaceGetBaseAddress(surface)
		let srcBytesPerRow = IOSurfaceGetBytesPerRow(surface)
		let srcHeight = IOSurfaceGetHeight(surface)
		let srcWidth = IOSurfaceGetWidth(surface)
		
		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		
		let dstBase = CVPixelBufferGetBaseAddress(pixelBuffer)!
		let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
		let dstHeight = CVPixelBufferGetHeight(pixelBuffer)
		let dstWidth = CVPixelBufferGetWidth(pixelBuffer)
		
		let copyWidth = min(srcWidth, dstWidth) * 4
		let copyHeight = min(srcHeight, dstHeight)
		
		for row in 0..<copyHeight {
			let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
			let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
			memcpy(dstRow, srcRow, copyWidth)
		}
		
		CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		IOSurfaceUnlock(surface, .readOnly, nil)
		
		return true
	}
}

// MARK: -

class CameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
	
	private(set) var stream: CMIOExtensionStream!
	
	let device: CMIOExtensionDevice
	
	private let _streamFormat: CMIOExtensionStreamFormat
	
	init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
		
		self.device = device
		self._streamFormat = streamFormat
		super.init()
		self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: .source, clockType: .hostTime, source: self)
	}
	
	var formats: [CMIOExtensionStreamFormat] {
		
		return [_streamFormat]
	}
	
	var activeFormatIndex: Int = 0 {
		
		didSet {
			if activeFormatIndex >= 1 {
				os_log(.error, "Invalid index")
			}
		}
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		return [.streamActiveFormatIndex, .streamFrameDuration]
	}
	
	func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
		
		let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
		if properties.contains(.streamActiveFormatIndex) {
			streamProperties.activeFormatIndex = 0
		}
		if properties.contains(.streamFrameDuration) {
			let frameDuration = CMTime(value: 1, timescale: Int32(kFrameRate))
			streamProperties.frameDuration = frameDuration
		}
		
		return streamProperties
	}
	
	func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
		
		if let activeFormatIndex = streamProperties.activeFormatIndex {
			self.activeFormatIndex = activeFormatIndex
		}
	}
	
	func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
		
		// An opportunity to inspect the client info and decide if it should be allowed to start the stream.
		return true
	}
	
	func startStream() throws {
		
		guard let deviceSource = device.source as? CameraExtensionDeviceSource else {
			fatalError("Unexpected source type \(String(describing: device.source))")
		}
		deviceSource.startStreaming()
	}
	
	func stopStream() throws {
		
		guard let deviceSource = device.source as? CameraExtensionDeviceSource else {
			fatalError("Unexpected source type \(String(describing: device.source))")
		}
		deviceSource.stopStreaming()
	}
}

// MARK: -

class CameraExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
	
	private(set) var provider: CMIOExtensionProvider!
	
	private var deviceSource: CameraExtensionDeviceSource!
	
	// CMIOExtensionProviderSource protocol methods (all are required)
	
	init(clientQueue: DispatchQueue?) {
		
		super.init()
		
		provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
		deviceSource = CameraExtensionDeviceSource(localizedName: "CursorFollow Camera")
		
		do {
			try provider.addDevice(deviceSource.device)
		} catch let error {
			fatalError("Failed to add device: \(error.localizedDescription)")
		}
	}
	
	func connect(to client: CMIOExtensionClient) throws {
		
		// Handle client connect
	}
	
	func disconnect(from client: CMIOExtensionClient) {
		
		// Handle client disconnect
	}
	
	var availableProperties: Set<CMIOExtensionProperty> {
		
		// See full list of CMIOExtensionProperty choices in CMIOExtensionProperties.h
		return [.providerManufacturer]
	}
	
	func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
		
		let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
		if properties.contains(.providerManufacturer) {
			providerProperties.manufacturer = "Logan Rupe"
		}
		return providerProperties
	}
	
	func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
		
		// Handle settable properties here.
	}
}
