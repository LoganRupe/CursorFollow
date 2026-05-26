//
//  CursorFollowHostApp.swift
//  CursorFollowHost
//
//  Created by Logan Rupe on 20/5/2026.
//

import SwiftUI
import Combine
import SystemExtensions
import os.log

/// Coordinates WindowTracker and CaptureEngine at the app level,
/// independent of whether the MenuBarExtra panel is visible.
@MainActor
final class AppCoordinator: ObservableObject {
    let windowTracker = WindowTracker()
    let captureEngine = CaptureEngine()
    let outputWindowController: OutputWindowController?
    private var cancellable: AnyCancellable?

    init() {
        // Set up output window with the shared IOSurface
        if let surface = captureEngine.ioSurface {
            let owc = OutputWindowController(surface: surface)
            self.outputWindowController = owc
            captureEngine.onFrameDelivered = { [weak owc] in
                owc?.notifyFrameReady()
            }
        } else {
            self.outputWindowController = nil
        }

        windowTracker.startObservingFrontApp()

        cancellable = windowTracker.$selectedWindow
            .dropFirst()
            .sink { [weak self] newWindow in
                guard let self, let window = newWindow else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.captureEngine.isCapturing {
                        await self.captureEngine.switchTarget(to: window)
                    } else if self.windowTracker.autoFollowEnabled {
                        await self.captureEngine.startCapture(window: window)
                    }
                    // Update output window after capture starts (dimensions now set)
                    self.outputWindowController?.updateForCapture(
                        windowFrame: window.frame,
                        captureWidth: self.captureEngine.activeCaptureWidth,
                        captureHeight: self.captureEngine.activeCaptureHeight
                    )
                }
            }

        Task {
            await windowTracker.refreshWindows()
        }
    }
}

@main
struct CursorFollowHostApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowHost", category: "AppDelegate")
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var coordinator: AppCoordinator?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()

        // Set up the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 440)
        popover.behavior = .transient
        let rootView = ContentView()
            .environmentObject(coordinator!.windowTracker)
            .environmentObject(coordinator!.captureEngine)
        if let owc = coordinator!.outputWindowController {
            popover.contentViewController = NSHostingController(
                rootView: rootView.environmentObject(owc)
            )
        } else {
            popover.contentViewController = NSHostingController(rootView: rootView)
        }

        // Set up the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "CursorFollow")
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        activateCameraExtension()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func activateCameraExtension() {
        let extensionID = "io.github.loganrupe.CursorFollowHost.CameraExtension"
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        log.info("Submitted activation request for \(extensionID)")
    }

    // MARK: - OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("Replacing existing extension \(existing.bundleIdentifier) v\(existing.bundleShortVersion) with v\(ext.bundleShortVersion)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.warning("System extension requires user approval")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            log.info("Camera extension activated successfully")
        case .willCompleteAfterReboot:
            log.info("Camera extension will activate after reboot")
        @unknown default:
            log.warning("Unknown activation result: \(String(describing: result))")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        log.error("Camera extension activation failed: \(error.localizedDescription)")
    }
}
