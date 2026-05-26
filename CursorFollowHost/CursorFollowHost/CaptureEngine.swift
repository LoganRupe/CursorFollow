//
//  CaptureEngine.swift
//  CursorFollowHost
//
//  Created by Logan Rupe on 20/5/2026.
//

import Foundation
import Combine
import ScreenCaptureKit
import CoreMedia
import os.log

/// Captures a target window using ScreenCaptureKit and delivers frames
/// to the FrameTransport for consumption by the camera extension.
@MainActor
final class CaptureEngine: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var frameCount: UInt64 = 0
    @Published private(set) var lastError: String?
    @Published private(set) var transportReady = false

    /// Callback invoked on the capture queue after each frame is published.
    /// Used by OutputWindowController to trigger layer redisplay.
    nonisolated(unsafe) var onFrameDelivered: (@Sendable () -> Void)?

    /// The shared IOSurface used for frame transport.
    var ioSurface: IOSurface? { frameTransport?.surface }

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowHost", category: "CaptureEngine")

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private let frameTransport: SharedMemoryFrameTransport?

    private let captureQueue = DispatchQueue(label: "io.github.loganrupe.CursorFollowHost.capture", qos: .userInteractive)

    /// Target capture dimensions (updated per window).
    @Published private(set) var activeCaptureWidth: Int = 1920
    @Published private(set) var activeCaptureHeight: Int = 1080
    let maxCaptureWidth = 1920
    let maxCaptureHeight = 1080
    let frameRate = 60

    override init() {
        self.frameTransport = SharedMemoryFrameTransport()
        super.init()
        if let transport = frameTransport {
            self.transportReady = true
            log.info("CaptureEngine initialized with frame transport (surfaceID=\(transport.surfaceID))")
        } else {
            log.error("CaptureEngine: frame transport unavailable — check app group entitlement")
        }
    }

    /// Start capturing the specified window.
    func startCapture(window: TrackedWindow) async {
        if isCapturing {
            log.warning("Capture already in progress, stopping first")
            await stopCapture()
        }

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)

            // Calculate dimensions that preserve the window's aspect ratio
            // while fitting within the IOSurface bounds (1920x1080).
            let windowW = window.frame.width
            let windowH = window.frame.height
            let scale = min(CGFloat(maxCaptureWidth) / windowW, CGFloat(maxCaptureHeight) / windowH, 1.0)
            let captureW = Int(windowW * scale)
            let captureH = Int(windowH * scale)
            self.activeCaptureWidth = captureW
            self.activeCaptureHeight = captureH

            let config = SCStreamConfiguration()
            config.width = captureW
            config.height = captureH
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 3 // Low queue depth for latency
            config.showsCursor = true

            let transport = self.frameTransport
            let onFrame = self.onFrameDelivered
            let output = CaptureStreamOutput(
                frameHandler: { [weak self, transport] sampleBuffer in
                    guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    transport?.publishFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
                    onFrame?()
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.frameCount += 1
                        if self.frameCount % 300 == 0 {
                            self.log.info("Frame delivery milestone: \(self.frameCount) frames")
                        }
                    }
                },
                errorHandler: { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleStreamError(error)
                    }
                }
            )
            self.streamOutput = output

            let newStream = SCStream(filter: filter, configuration: config, delegate: output)
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
            try await newStream.startCapture()

            self.stream = newStream
            self.isCapturing = true
            self.lastError = nil
            self.frameCount = 0

            log.info("Started capture of window '\(window.title)' (ID: \(window.id)) at \(captureW)x\(captureH)@\(self.frameRate)fps (source: \(Int(windowW))x\(Int(windowH)))")
        } catch {
            log.error("Failed to start capture: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            self.isCapturing = false
        }
    }

    /// Stop the current capture session.
    func stopCapture() async {
        guard let stream = self.stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            log.error("Error stopping capture: \(error.localizedDescription)")
        }

        self.stream = nil
        self.streamOutput = nil
        self.isCapturing = false
        log.info("Capture stopped. Total frames delivered: \(self.frameCount)")
    }

    /// Switch to capturing a different window with minimal interruption.
    func switchTarget(to window: TrackedWindow) async {
        let wasCapturing = isCapturing
        if wasCapturing {
            await stopCapture()
        }
        // Clear stale pixels from the previous capture
        frameTransport?.clearSurface()
        // Restart with new target
        await startCapture(window: window)
    }

    /// Handle a stream error reported by the delegate.
    func handleStreamError(_ error: any Error) {
        self.isCapturing = false
        self.lastError = error.localizedDescription
    }
}

// MARK: - SCStream Output Delegate

/// Handles SCStream callbacks on the capture queue. All interactions with the
/// @MainActor-isolated CaptureEngine are dispatched via closures to avoid
/// mutating @Published properties off the main thread.
private final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let frameHandler: @Sendable (CMSampleBuffer) -> Void
    private let errorHandler: @Sendable (any Error) -> Void
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowHost", category: "CaptureStreamOutput")

    init(frameHandler: @escaping @Sendable (CMSampleBuffer) -> Void,
         errorHandler: @escaping @Sendable (any Error) -> Void) {
        self.frameHandler = frameHandler
        self.errorHandler = errorHandler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Check for valid frame status
        guard sampleBuffer.isValid else {
            log.debug("Received invalid sample buffer, skipping")
            return
        }

        frameHandler(sampleBuffer)
    }

    // MARK: - SCStreamDelegate (error handling)

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        log.error("Stream stopped with error: \(error.localizedDescription)")
        errorHandler(error)
    }
}
