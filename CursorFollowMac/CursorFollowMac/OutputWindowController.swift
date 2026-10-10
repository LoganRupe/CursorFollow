//
//  OutputWindowController.swift
//  CursorFollowMac
//
//  Created by Logan Rupe on 22/5/2026.
//

import AppKit
import Combine
import IOSurface
import SwiftUI
import os.log

enum OutputWindowState: Equatable {
    case noTarget
    case missingPermissions(String?)
    case paused(String?)
    case targetUnavailable(String?)
    case waitingForFrames(String?)
    case live(String?)
}

enum OutputPresentationMode: String, CaseIterable {
    case fit
    case fill
    case actualSize

    var label: String {
        switch self {
        case .fit:
            return "FIT"
        case .fill:
            return "FILL"
        case .actualSize:
            return "ACTUAL"
        }
    }
}

/// Manages the stable NSWindow that renders captured frames in real-time.
/// This window is shareable via conferencing window-share pickers.
@MainActor
final class OutputWindowController: NSObject, ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var outputState: OutputWindowState = .noTarget
    @Published var alwaysOnTop = false { didSet { applyWindowLevel() } }
    @Published var showResolution = false { didSet { updateOverlayIfNeeded() } }
    @Published var showFrameCount = false { didSet { updateOverlayIfNeeded() } }
    @Published var presentationMode: OutputPresentationMode = .fit { didSet { applyPresentationMode() } }
    @Published private(set) var resolutionText = ""
    @Published private(set) var currentFPS: Double = 0

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "OutputWindow")
    private var window: NSWindow?
    private var surfaceView: SurfaceLayerView?
    private var overlayHostingView: NSView?
    private var frameRefreshCount: UInt64 = 0
    private var fpsFrameCount: UInt64 = 0
    private var fpsTimer: Timer?
    private var activeTargetTitle: String?

    /// The IOSurface to render. Replaced whenever the capture engine resizes its
    /// transport surface to match a new target's dimensions.
    private var surface: IOSurface

    init(surface: IOSurface) {
        self.surface = surface
        super.init()
        log.info("OutputWindowController initialized with surfaceID=\(surface.ioSurfaceID)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// The current content size for the output window.
    private var contentSize = NSSize(width: 960, height: 540)

    /// The current captured pixel dimensions used by the renderer.
    private var currentCaptureSize = NSSize(width: 1920, height: 1080)

    /// Point the renderer at a newly allocated transport surface.
    func updateSurface(_ surface: IOSurface) {
        self.surface = surface
        surfaceView?.setSurface(surface)
        log.info("Output window switched to surfaceID=\(surface.ioSurfaceID)")
    }

    func setNoTarget() {
        activeTargetTitle = nil
        outputState = .noTarget
        resolutionText = ""
    }

    func setMissingPermissions(_ message: String? = nil) {
        outputState = .missingPermissions(message)
    }

    func setPaused(targetTitle: String? = nil) {
        activeTargetTitle = targetTitle ?? activeTargetTitle
        outputState = .paused(activeTargetTitle)
    }

    func setTargetUnavailable(_ message: String? = nil) {
        outputState = .targetUnavailable(message)
    }

    func prepareForCapture(targetTitle: String? = nil) {
        activeTargetTitle = targetTitle ?? activeTargetTitle
        outputState = .waitingForFrames(activeTargetTitle)
    }

    /// Update the output renderer to match the capture dimensions.
    /// Called after capture starts/switches with the actual config dimensions.
    ///
    /// The transport surface is allocated to these exact dimensions, so the layer
    /// renders all of it — no crop rect, and no y-flip to reason about.
    func updateForCapture(captureWidth: Int, captureHeight: Int, captureScale: CGFloat, targetTitle: String? = nil) {
        guard captureWidth > 0, captureHeight > 0 else { return }
        activeTargetTitle = targetTitle ?? activeTargetTitle
        currentCaptureSize = NSSize(width: CGFloat(captureWidth), height: CGFloat(captureHeight))

        surfaceView?.setCaptureSize(currentCaptureSize)
        resolutionText = "\(captureWidth)×\(captureHeight)"

        if presentationMode == .actualSize {
            resizeWindowToActualSize()
        }

        outputState = .waitingForFrames(activeTargetTitle)
        log.info("Output window updated: capture=\(captureWidth)x\(captureHeight), captureScale=\(captureScale)")
    }

    func show() {
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            isVisible = true
            return
        }

        // Note: deliberately NOT using `.fullSizeContentView`. The title bar is
        // visible and opaque (see below), so a full-size content view would only
        // push the rendered frame up behind the title bar — hiding the top strip
        // of the captured window (its toolbar). Letting AppKit inset the content
        // view below the title bar keeps the whole frame visible.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CursorFollow Output"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.fullScreenNone, .managed]
        window.delegate = self

        let view = SurfaceLayerView(surface: surface)
        view.frame = NSRect(origin: .zero, size: contentSize)
        view.autoresizingMask = [.width, .height]
        view.presentationMode = presentationMode
        view.setCaptureSize(currentCaptureSize)
        window.contentView = view

        let hosting = PassthroughHostingView(rootView: OutputWindowOverlayView(controller: self))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]
        view.addSubview(hosting)

        // Center on screen
        window.center()

        // Show without activating (avoids stealing focus / triggering auto-follow)
        window.orderFrontRegardless()

        self.window = window
        self.surfaceView = view
        self.overlayHostingView = hosting
        self.isVisible = true
        startFPSTimer()
        log.info("Output window shown")
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
        stopFPSTimer()
        log.info("Output window hidden")
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func applyWindowLevel() {
        window?.level = alwaysOnTop ? .floating : .normal
    }

    private func updateOverlayIfNeeded() {
        // No-op: SwiftUI view reacts to @Published changes automatically.
    }

    private func applyPresentationMode() {
        surfaceView?.presentationMode = presentationMode
        if presentationMode == .actualSize {
            resizeWindowToActualSize()
        }
    }

    private func resizeWindowToActualSize() {
        guard let window else { return }
        let backingScale = max(window.backingScaleFactor, 1.0)
        let actualSize = NSSize(
            width: max(currentCaptureSize.width / backingScale, 1),
            height: max(currentCaptureSize.height / backingScale, 1)
        )
        window.setContentSize(actualSize)
    }

    // MARK: - FPS Timer

    private func startFPSTimer() {
        guard fpsTimer == nil else { return }
        fpsFrameCount = 0
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentFPS = Double(self.fpsFrameCount)
                self.fpsFrameCount = 0
            }
        }
    }

    private func stopFPSTimer() {
        fpsTimer?.invalidate()
        fpsTimer = nil
        currentFPS = 0
    }

    /// Called from the capture queue when a new frame is available on the IOSurface.
    /// Increments the per-second FPS counter used by the overlay.
    nonisolated func notifyFrameReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fpsFrameCount += 1
            self.markFrameReady()
            self.surfaceView?.refreshSurface()
        }
    }

    private func markFrameReady() {
        switch outputState {
        case .live:
            break
        default:
            outputState = .live(activeTargetTitle)
        }
    }
}

extension OutputWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}

// MARK: - Surface Layer View

/// A layer-hosting NSView that displays frames from a shared IOSurface.
/// Uses layer-hosting mode (not layer-backed) so AppKit does not interfere
/// with the layer's contents — we manage it directly.
private final class SurfaceLayerView: NSView {
    private var surface: IOSurface
    private let contentLayer = CALayer()
    private var captureSize = NSSize(width: 1920, height: 1080)

    var presentationMode: OutputPresentationMode = .fit {
        didSet { needsLayout = true }
    }

    init(surface: IOSurface) {
        self.surface = surface
        super.init(frame: .zero)

        let hostingLayer = CALayer()
        hostingLayer.backgroundColor = NSColor.black.cgColor
        hostingLayer.masksToBounds = true

        contentLayer.contents = surface
        contentLayer.contentsGravity = .resize
        contentLayer.backgroundColor = NSColor.black.cgColor
        hostingLayer.addSublayer(contentLayer)

        // Setting self.layer BEFORE wantsLayer = true creates a layer-hosting view.
        // AppKit won't touch the layer's contents — we own it entirely.
        self.layer = hostingLayer
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func layout() {
        super.layout()
        // Layer-hosting views don't auto-resize the layer — sync it manually.
        layer?.frame = bounds
        applyContentsScale()
        layoutContentLayer()
    }

    /// Layer-hosting views are also excluded from AppKit's automatic contentsScale
    /// propagation, so the layer stays at 1.0 and Core Animation filters for the
    /// wrong output density. Track the window's backing scale by hand instead.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyContentsScale()
    }

    private func applyContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        guard scale > 0, contentLayer.contentsScale != scale else { return }
        layer?.contentsScale = scale
        contentLayer.contentsScale = scale
    }

    func setCaptureSize(_ size: NSSize) {
        captureSize = NSSize(width: max(size.width, 1), height: max(size.height, 1))
        needsLayout = true
    }

    func setSurface(_ surface: IOSurface) {
        self.surface = surface
        refreshSurface()
    }

    /// Re-assign the IOSurface as layer contents to force Core Animation
    /// to re-read the surface pixels on the next composite pass.
    func refreshSurface() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = nil
        contentLayer.contents = surface
        CATransaction.commit()
    }

    private func layoutContentLayer() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale: CGFloat
        switch presentationMode {
        case .fit:
            scale = min(bounds.width / captureSize.width, bounds.height / captureSize.height)
        case .fill:
            scale = max(bounds.width / captureSize.width, bounds.height / captureSize.height)
        case .actualSize:
            scale = 1.0 / max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0, 1.0)
        }

        let displaySize = NSSize(width: captureSize.width * scale, height: captureSize.height * scale)
        contentLayer.frame = CGRect(
            x: (bounds.width - displaySize.width) / 2,
            y: (bounds.height - displaySize.height) / 2,
            width: displaySize.width,
            height: displaySize.height
        )
    }

    override var isOpaque: Bool { true }
}

// MARK: - Overlay View

/// Transparent passthrough host so clicks reach the surface view beneath.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = .clear
    }
}

private struct OutputWindowOverlayView: View {
    @ObservedObject var controller: OutputWindowController

    var body: some View {
        ZStack {
            fallbackView

            metricsView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let presentation = fallbackPresentation {
            VStack(spacing: 12) {
                Image(systemName: presentation.icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                VStack(spacing: 5) {
                    Text(presentation.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(presentation.message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.74))
        }
    }

    @ViewBuilder
    private var metricsView: some View {
        let hasContent = (controller.showResolution && !controller.resolutionText.isEmpty)
            || controller.showFrameCount
        if hasContent {
            VStack(alignment: .leading, spacing: 3) {
                if controller.showResolution && !controller.resolutionText.isEmpty {
                    Text(controller.resolutionText)
                }
                if controller.showFrameCount {
                    Text(String(format: "%.0f fps", controller.currentFPS))
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(10)
        }
    }

    private var fallbackPresentation: (icon: String, title: String, message: String)? {
        switch controller.outputState {
        case .live:
            return nil
        case .noTarget:
            return (
                "rectangle.dashed",
                "No Target Selected",
                "Choose a window in CursorFollow to start sharing."
            )
        case .missingPermissions(let detail):
            return (
                "lock.rectangle",
                "Screen Recording Needed",
                detail ?? "Grant Screen Recording permission in System Settings, then refresh the window list."
            )
        case .paused(let targetTitle):
            return (
                "pause.circle",
                "Output Paused",
                targetTitle.map { "Ready to resume \($0)." } ?? "Start capture when you are ready."
            )
        case .targetUnavailable(let detail):
            return (
                "exclamationmark.triangle",
                "Target Unavailable",
                detail ?? "The selected window disappeared, minimized, or moved to another Space."
            )
        case .waitingForFrames(let targetTitle):
            return (
                "rectangle.2.swap",
                "Preparing Output",
                targetTitle.map { "Waiting for the first frame from \($0)." } ?? "Waiting for the first captured frame."
            )
        }
    }
}

