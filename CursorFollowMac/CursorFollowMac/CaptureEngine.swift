//
//  CaptureEngine.swift
//  CursorFollowMac
//
//  Created by Logan Rupe on 20/5/2026.
//

import Foundation
import Combine
import AppKit
import ScreenCaptureKit
import CoreMedia
import os.log

enum CaptureQuality: String, CaseIterable {
    case balanced
    case performant
    case lowLatency

    var label: String {
        switch self {
        case .balanced:
            return "BALANCED"
        case .performant:
            return "PERFORMANT"
        case .lowLatency:
            return "LOW-LATENCY"
        }
    }

    var frameRate: Int {
        switch self {
        case .balanced:
            return 60
        case .performant:
            return 30
        case .lowLatency:
            return 60
        }
    }

    var queueDepth: Int {
        switch self {
        case .balanced:
            return 3
        case .performant:
            return 5
        case .lowLatency:
            return 2
        }
    }
}

/// Captures a target window using ScreenCaptureKit and publishes frames
/// into the host-owned IOSurface rendered by CursorFollow Output.
@MainActor
final class CaptureEngine: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    // Internal counter for logging only. Intentionally NOT @Published: it is
    // mutated every captured frame (~60fps), and publishing it would fire
    // objectWillChange on every observing view (e.g. ContentView), forcing a
    // full panel relayout 60×/sec. No UI reads this value.
    private(set) var frameCount: UInt64 = 0
    @Published private(set) var lastError: String?
    @Published private(set) var transportReady = false
    /// Set when the user explicitly stops capture; prevents auto-follow from restarting.
    @Published private(set) var userStopped = true
    @Published private(set) var captureQuality: CaptureQuality

    /// Callback invoked on the capture queue after each frame is published.
    /// Used by OutputWindowController to trigger layer redisplay.
    nonisolated(unsafe) var onFrameDelivered: (@Sendable () -> Void)?

    /// The shared IOSurface used for frame transport.
    var ioSurface: IOSurface? { frameTransport?.surface }

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "CaptureEngine")

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private let frameTransport: SharedMemoryFrameTransport?

    private let captureQueue = DispatchQueue(label: "io.github.loganrupe.CursorFollowMac.capture", qos: .userInteractive)

    /// Target capture dimensions (updated per window).
    @Published private(set) var activeCaptureWidth: Int = 1920
    @Published private(set) var activeCaptureHeight: Int = 1080
    @Published private(set) var activeCaptureScale: CGFloat = 1.0
    let maxCaptureWidth = 1920
    let maxCaptureHeight = 1080

    private let defaults: UserDefaults

    private enum Keys {
        static let captureQuality = "settings.captureQuality"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let savedQuality = defaults.string(forKey: Keys.captureQuality),
           let quality = CaptureQuality(rawValue: savedQuality) {
            self.captureQuality = quality
        } else {
            self.captureQuality = .balanced
            defaults.set(CaptureQuality.balanced.rawValue, forKey: Keys.captureQuality)
        }

        self.frameTransport = SharedMemoryFrameTransport()
        super.init()
        if let transport = frameTransport {
            self.transportReady = true
            log.info("CaptureEngine initialized with frame transport (surfaceID=\(transport.surfaceID))")
        } else {
            log.error("CaptureEngine: frame transport unavailable — check app group entitlement")
        }
    }

    func setCaptureQuality(_ quality: CaptureQuality) {
        guard captureQuality != quality else { return }
        captureQuality = quality
        defaults.set(quality.rawValue, forKey: Keys.captureQuality)
        log.info("Capture quality set to \(quality.rawValue, privacy: .public)")
    }

    /// Start capturing the specified window.
    func startCapture(window: TrackedWindow) async {
        userStopped = false

        if isCapturing {
            log.warning("Capture already in progress, stopping first")
            await stopCapture()
        }

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window.scWindow)

            // Calculate dimensions that preserve the window's aspect ratio
            // while fitting within the IOSurface bounds (1920x1080).
            let pointPixelScale = Self.backingScaleFactor(for: window.frame)
            let windowW = max(window.frame.width, 1)
            let windowH = max(window.frame.height, 1)
            let sourcePixelW = windowW * pointPixelScale
            let sourcePixelH = windowH * pointPixelScale
            let surfaceScale = min(CGFloat(maxCaptureWidth) / sourcePixelW, CGFloat(maxCaptureHeight) / sourcePixelH, 1.0)
            let captureW = max(Int(sourcePixelW * surfaceScale), 1)
            let captureH = max(Int(sourcePixelH * surfaceScale), 1)
            self.activeCaptureWidth = captureW
            self.activeCaptureHeight = captureH
            self.activeCaptureScale = pointPixelScale * surfaceScale

            let config = SCStreamConfiguration()
            config.width = captureW
            config.height = captureH
            let frameRate = captureQuality.frameRate
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = captureQuality.queueDepth
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

            log.info("Started capture of window '\(window.title)' (ID: \(window.id)) at \(captureW)x\(captureH)@\(frameRate)fps, quality=\(self.captureQuality.rawValue, privacy: .public), queueDepth=\(config.queueDepth), captureScale=\(self.activeCaptureScale) (source: \(Int(windowW))x\(Int(windowH))pt)")
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

    /// User-initiated stop: stops capture and prevents auto-follow from restarting.
    func userStop() async {
        userStopped = true
        await stopCapture()
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

    private static func backingScaleFactor(for frame: CGRect) -> CGFloat {
        let intersections = NSScreen.screens.map { screen in
            (screen: screen, area: screen.frame.intersection(frame).area)
        }
        if let bestScreen = intersections.max(by: { $0.area < $1.area })?.screen,
           intersections.contains(where: { $0.area > 0 }) {
            return bestScreen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 1.0
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

// MARK: - SCStream Output Delegate

/// Handles SCStream callbacks on the capture queue. All interactions with the
/// @MainActor-isolated CaptureEngine are dispatched via closures to avoid
/// mutating @Published properties off the main thread.
private final class CaptureStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let frameHandler: @Sendable (CMSampleBuffer) -> Void
    private let errorHandler: @Sendable (any Error) -> Void
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "CaptureStreamOutput")

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
