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
    private var cancellable: AnyCancellable?

    init() {
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
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("CursorFollow", systemImage: "camera.viewfinder") {
            ContentView()
                .environmentObject(coordinator.windowTracker)
                .environmentObject(coordinator.captureEngine)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowHost", category: "AppDelegate")

    func applicationDidFinishLaunching(_ notification: Notification) {
        activateCameraExtension()
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
