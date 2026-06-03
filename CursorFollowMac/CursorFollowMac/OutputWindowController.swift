//
//  OutputWindowController.swift
//  CursorFollowMac
//
//  Created by Logan Rupe on 22/5/2026.
//

import AppKit
import Combine
import CoreVideo
import IOSurface
import SwiftUI
import os.log

/// Manages a borderless NSWindow that renders captured frames in real-time.
/// This window is shareable via Slack's "Share Screen → Window" picker.
@MainActor
final class OutputWindowController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published var alwaysOnTop = false { didSet { applyWindowLevel() } }
    @Published var showResolution = false { didSet { updateOverlayIfNeeded() } }
    @Published var showFrameCount = false { didSet { updateOverlayIfNeeded() } }
    @Published private(set) var resolutionText = ""
    @Published private(set) var currentFPS: Double = 0

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "OutputWindow")
    private var window: NSWindow?
    private var surfaceView: SurfaceLayerView?
    private var overlayHostingView: NSView?
    private var frameRefreshCount: UInt64 = 0
    private var displayLink: CVDisplayLink?
    private var fpsFrameCount: UInt64 = 0
    private var fpsTimer: Timer?

    /// The IOSurface to render. Set before showing the window.
    private let surface: IOSurface

    init(surface: IOSurface) {
        self.surface = surface
        log.info("OutputWindowController initialized with surfaceID=\(surface.surfaceID)")
    }

    deinit {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        NotificationCenter.default.removeObserver(self)
    }

    /// The current content size for the output window.
    private var contentSize = NSSize(width: 960, height: 540)

    /// The IOSurface total dimensions (constant).
    private let surfaceWidth: CGFloat = 1920
    private let surfaceHeight: CGFloat = 1080

    /// Current crop rect for the layer (stored so it can be applied when window is first shown).
    private var currentContentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Update the output window size and crop to match the capture dimensions.
    /// Called after capture starts/switches with the actual config dimensions.
    func updateForCapture(windowFrame: CGRect, captureWidth: Int, captureHeight: Int) {
        guard captureWidth > 0, captureHeight > 0 else { return }

        // Window size matches the captured content's aspect ratio
        let newSize = NSSize(width: CGFloat(captureWidth), height: CGFloat(captureHeight))
        contentSize = newSize

        // Crop the layer to show only the portion of the IOSurface that has pixels.
        // y-origin is flipped: CA content coords have y=0 at bottom, but our pixel
        // data starts at the top of the surface. Use (1 - cropH) to select from top.
        let cropW = min(CGFloat(captureWidth) / surfaceWidth, 1.0)
        let cropH = min(CGFloat(captureHeight) / surfaceHeight, 1.0)
        currentContentsRect = CGRect(x: 0, y: 1.0 - cropH, width: cropW, height: cropH)
        surfaceView?.layer?.contentsRect = currentContentsRect
        resolutionText = "\(captureWidth)×\(captureHeight)"

        if let window {
            window.contentAspectRatio = newSize
            window.setContentSize(newSize)
        }
        log.info("Output window updated: capture=\(captureWidth)x\(captureHeight), contentsRect=(\(cropW), \(cropH))")
    }

    func show() {
        if let window {
            window.orderFrontRegardless()
            isVisible = true
            startDisplayLink()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CursorFollow Output"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.contentAspectRatio = contentSize
        window.isReleasedWhenClosed = false
        window.sharingType = .readOnly
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.fullScreenNone, .managed]

        let view = SurfaceLayerView(surface: surface)
        view.frame = NSRect(origin: .zero, size: contentSize)
        view.autoresizingMask = [.width, .height]
        view.layer?.contentsRect = currentContentsRect
        window.contentView = view

        // Overlay (top-left metrics)
        let hosting = PassthroughHostingView(rootView: OverlayView(controller: self))
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
        startDisplayLink()
        startFPSTimer()
        log.info("Output window shown")
    }

    func hide() {
        window?.orderOut(nil)
        isVisible = false
        stopDisplayLink()
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

    // MARK: - Display Link

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else {
            log.error("Failed to create CVDisplayLink")
            return
        }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, _ -> CVReturn in
            // Trigger a main-thread refresh on every vsync
            DispatchQueue.main.async {
                // Posted as notification-less; actual refresh happens below
                NotificationCenter.default.post(name: .outputWindowRefresh, object: nil)
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, nil)
        CVDisplayLinkStart(link)
        self.displayLink = link

        // Observe refresh notifications
        NotificationCenter.default.addObserver(
            forName: .outputWindowRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.surfaceView?.refreshSurface()
            }
        }

        log.info("Display link started")
    }

    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
        NotificationCenter.default.removeObserver(self, name: .outputWindowRefresh, object: nil)
        log.info("Display link stopped")
    }

    /// Called from the capture queue when a new frame is available on the IOSurface.
    /// Increments the per-second FPS counter used by the overlay.
    nonisolated func notifyFrameReady() {
        DispatchQueue.main.async { [weak self] in
            self?.fpsFrameCount += 1
        }
    }
}

// MARK: - Surface Layer View

/// A layer-hosting NSView that displays frames from a shared IOSurface.
/// Uses layer-hosting mode (not layer-backed) so AppKit does not interfere
/// with the layer's contents — we manage it directly.
private final class SurfaceLayerView: NSView {
    private let surface: IOSurface

    init(surface: IOSurface) {
        self.surface = surface
        super.init(frame: .zero)

        // Create the hosting layer
        let hostingLayer = CALayer()
        hostingLayer.contents = surface
        hostingLayer.contentsGravity = .resize
        hostingLayer.backgroundColor = NSColor.black.cgColor

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
    }

    /// Re-assign the IOSurface as layer contents to force Core Animation
    /// to re-read the surface pixels on the next composite pass.
    func refreshSurface() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = nil
        layer?.contents = surface
        CATransaction.commit()
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

private struct OverlayView: View {
    @ObservedObject var controller: OutputWindowController

    var body: some View {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Notification Names

private extension Notification.Name {
    static let outputWindowRefresh = Notification.Name("io.github.loganrupe.CursorFollowMac.outputWindowRefresh")
}
