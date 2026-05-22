//
//  WindowTracker.swift
//  CursorFollowHost
//
//  Created by Logan Rupe on 20/5/2026.
//

import Foundation
import Combine
import AppKit
import ScreenCaptureKit
import os.log

/// Represents a window available for capture.
struct TrackedWindow: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let bundleID: String?
    let frame: CGRect
    let scWindow: SCWindow

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        lhs.id == rhs.id
    }
}

/// Enumerates on-screen windows and publishes a selectable list.
/// Filters out system UI elements, menu bar items, and utility windows.
/// When auto-follow is enabled, automatically switches to the frontmost window.
@MainActor
final class WindowTracker: ObservableObject {
    @Published private(set) var windows: [TrackedWindow] = []
    @Published var selectedWindow: TrackedWindow?
    @Published var autoFollowEnabled = true

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowHost", category: "WindowTracker")

    /// Bundle IDs to exclude from the window list.
    private let excludedBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
    ]

    /// Minimum window size to include (filters tiny overlay/utility windows).
    private let minimumWindowSize = CGSize(width: 100, height: 100)

    /// Debounce interval for auto-follow switches to avoid thrashing.
    private let switchDebounceInterval: TimeInterval = 0.15

    private var lastSwitchTime: Date = .distantPast
    private var activationObserver: Any?

    func startObservingFrontApp() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                await self.handleAppActivation(app)
            }
        }
        log.info("Started observing frontmost app changes")
    }

    func stopObservingFrontApp() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
            log.info("Stopped observing frontmost app changes")
        }
    }

    private func handleAppActivation(_ app: NSRunningApplication) async {
        guard autoFollowEnabled else { return }

        let bundleID = app.bundleIdentifier ?? ""

        // Don't follow our own app or excluded apps
        guard bundleID != "io.github.loganrupe.CursorFollowHost",
              !excludedBundleIDs.contains(bundleID) else {
            return
        }

        // Debounce rapid switches
        let now = Date()
        guard now.timeIntervalSince(lastSwitchTime) >= switchDebounceInterval else {
            log.debug("Debounced switch to \(app.localizedName ?? bundleID)")
            return
        }
        lastSwitchTime = now

        log.info("App activated: \(app.localizedName ?? bundleID)")

        // Refresh windows and find the best match for the activated app
        await refreshWindows()

        guard let target = windows.first(where: { $0.bundleID == bundleID }) else {
            log.debug("No capturable window found for \(bundleID)")
            return
        }

        // Don't switch if already tracking this window
        guard target.id != selectedWindow?.id else { return }

        selectWindow(target)
    }

    func refreshWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let filtered = content.windows.compactMap { window -> TrackedWindow? in
                let bundleID = window.owningApplication?.bundleIdentifier

                // Skip windows from excluded apps
                if let bundleID, excludedBundleIDs.contains(bundleID) {
                    return nil
                }

                // Skip our own app
                if bundleID == "io.github.loganrupe.CursorFollowHost" {
                    return nil
                }

                // Skip windows without titles (typically system overlays)
                guard let title = window.title, !title.isEmpty else {
                    return nil
                }

                // Skip tiny windows (status items, popups)
                let frame = window.frame
                guard frame.width >= minimumWindowSize.width,
                      frame.height >= minimumWindowSize.height else {
                    return nil
                }

                return TrackedWindow(
                    id: window.windowID,
                    title: title,
                    ownerName: window.owningApplication?.applicationName ?? "Unknown",
                    bundleID: bundleID,
                    frame: frame,
                    scWindow: window
                )
            }

            self.windows = filtered
            log.info("Refreshed window list: \(filtered.count) windows available")

            // If selected window disappeared, clear selection
            if let selected = selectedWindow,
               !filtered.contains(where: { $0.id == selected.id }) {
                log.warning("Selected window (ID: \(selected.id)) no longer available")
                selectedWindow = nil
            }
        } catch {
            log.error("Failed to enumerate windows: \(error.localizedDescription)")
            windows = []
        }
    }

    func selectWindow(_ window: TrackedWindow) {
        selectedWindow = window
        log.info("Selected window: '\(window.title)' (ID: \(window.id), app: \(window.ownerName))")
    }
}
