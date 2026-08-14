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

/// Fraction of the target window's native pixel resolution to capture.
///
/// Deliberately a multiplier rather than a fixed resolution list: window sizes and
/// display scales vary too much for absolute presets to mean anything consistent.
enum CaptureScale: String, CaseIterable {
    case half
    case threeQuarters
    case native

    var factor: CGFloat {
        switch self {
        case .half:
            return 0.5
        case .threeQuarters:
            return 0.75
        case .native:
            return 1.0
        }
    }

    var label: String {
        switch self {
        case .half:
            return "50%"
        case .threeQuarters:
            return "75%"
        case .native:
            return "100%"
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
    @Published private(set) var captureScale: CaptureScale

    /// Invoked on the main actor when the frame transport reallocates its surface,
    /// so the output window can re-point its layer at the new one.
    var onSurfaceChanged: ((IOSurface) -> Void)?

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

    /// Ceiling on captured pixels per frame (~8.3 MP, i.e. 3840x2160 worth at any
    /// aspect ratio). Expressed as an area rather than a width/height pair on purpose:
    /// a landscape-shaped cap clamps tall windows on their long axis while leaving most
    /// of the width unused, which cost portrait sources roughly twice as much resolution
    /// as landscape ones. Bounds both the IOSurface allocation and the per-frame row copy.
    nonisolated static let maxCapturePixels = 3840 * 2160

    private let defaults: UserDefaults

    private enum Keys {
        static let captureQuality = "settings.captureQuality"
        static let captureScale = "settings.captureScale"
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

        if let savedScale = defaults.string(forKey: Keys.captureScale),
           let scale = CaptureScale(rawValue: savedScale) {
            self.captureScale = scale
        } else {
            self.captureScale = .native
            defaults.set(CaptureScale.native.rawValue, forKey: Keys.captureScale)
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

    func setCaptureScale(_ scale: CaptureScale) {
        guard captureScale != scale else { return }
        captureScale = scale
        defaults.set(scale.rawValue, forKey: Keys.captureScale)
        log.info("Capture scale set to \(scale.rawValue, privacy: .public)")
    }

    /// Resolves the pixel dimensions to request from ScreenCaptureKit.
    ///
    /// `sourceSize` is in points and `pointPixelScale` is the scale of the display the
    /// window lives on, so their product is the window's true backing-store resolution.
    /// The user's preset is applied to that, then clamped by area to `pixelBudget`.
    nonisolated static func captureDimensions(
        sourceSize: CGSize,
        pointPixelScale: CGFloat,
        scale: CaptureScale,
        pixelBudget: Int = maxCapturePixels
    ) -> (width: Int, height: Int, effectiveScale: CGFloat) {
        let pixelScale = max(pointPixelScale, 1)
        let nativeWidth = max(sourceSize.width, 1) * pixelScale
        let nativeHeight = max(sourceSize.height, 1) * pixelScale

        var factor = scale.factor
        let requestedPixels = (nativeWidth * factor) * (nativeHeight * factor)
        if requestedPixels > CGFloat(pixelBudget) {
            factor *= sqrt(CGFloat(pixelBudget) / requestedPixels)
        }

        // Round to even: some capture/encode paths dislike odd dimensions, and the
        // half-pixel it costs is invisible next to the scaling already happening.
        return (
            width: evenDimension(nativeWidth * factor),
            height: evenDimension(nativeHeight * factor),
            effectiveScale: pixelScale * factor
        )
    }

    /// Floors rather than rounds, so a budget-clamped pair can never land back above
    /// the budget: rounding 3325.5 up to 3326 is enough to breach it.
    nonisolated private static func evenDimension(_ value: CGFloat) -> Int {
        max(Int(value.rounded(.down)) & ~1, 2)
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

            // Take the scale from the filter rather than deriving it from NSScreen:
            // ScreenCaptureKit knows which display the window is actually on. Matching
            // it by hand means reconciling SCWindow.frame (CoreGraphics, y-down, origin
            // at the main display's top-left) against NSScreen.frame (AppKit, y-up,
            // origin bottom-left), which silently resolves to the wrong display for
            // screens arranged above the main one.
            let pointPixelScale = CGFloat(filter.pointPixelScale)
            let sourceRect = filter.contentRect.isEmpty ? window.frame : filter.contentRect
            let dimensions = Self.captureDimensions(
                sourceSize: sourceRect.size,
                pointPixelScale: pointPixelScale,
                scale: captureScale
            )
            let captureW = dimensions.width
            let captureH = dimensions.height
            self.activeCaptureWidth = captureW
            self.activeCaptureHeight = captureH
            self.activeCaptureScale = dimensions.effectiveScale

            // Size the shared surface to the capture exactly, so the output window
            // renders all of it and needs no crop rect.
            if let resizedSurface = frameTransport?.resize(width: captureW, height: captureH) {
                onSurfaceChanged?(resizedSurface)
            }

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

            log.info("Started capture of window '\(window.title)' (ID: \(window.id)) at \(captureW)x\(captureH)@\(frameRate)fps, quality=\(self.captureQuality.rawValue, privacy: .public), scale=\(self.captureScale.rawValue, privacy: .public), queueDepth=\(config.queueDepth), captureScale=\(self.activeCaptureScale) (source: \(Int(sourceRect.width))x\(Int(sourceRect.height))pt @\(pointPixelScale)x)")
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

    /// Re-applies the current quality and scale settings to a live capture.
    ///
    /// `SCStreamConfiguration` is fixed when the stream is created, so changing either
    /// setting has no effect until the stream restarts.
    func reapplyConfiguration(to window: TrackedWindow) async {
        guard isCapturing else { return }
        await switchTarget(to: window)
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
