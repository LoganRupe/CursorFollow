//
//  WindowTracker.swift
//  CursorFollowMac
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

/// Controls how the auto-follow filter list is applied.
enum FilterMode: String, CaseIterable {
    case all = "All"
    case exclude = "Exclude"
    case include = "Include"
}

/// Enumerates on-screen windows and publishes a selectable list.
/// Filters out system UI elements, menu bar items, and utility windows.
/// When auto-follow is enabled, automatically switches to the frontmost window.
@MainActor
final class WindowTracker: ObservableObject {
    @Published private(set) var windows: [TrackedWindow] = []
    @Published var selectedWindow: TrackedWindow?
    @Published var autoFollowEnabled = true
    @Published var filterMode: FilterMode = .all {
        didSet { UserDefaults.standard.set(filterMode.rawValue, forKey: "filterMode") }
    }
    @Published var excludedBundleIDs: Set<String> = [] {
        didSet { Self.saveSet(excludedBundleIDs, key: "excludedBundleIDs") }
    }
    @Published var includedBundleIDs: Set<String> = [] {
        didSet { Self.saveSet(includedBundleIDs, key: "includedBundleIDs") }
    }

    private static func saveSet(_ set: Set<String>, key: String) {
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    private static func loadSet(key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "WindowTracker")

    /// Bundle IDs to always exclude from the window list (system UI).
    private let systemExcludedBundleIDs: Set<String> = [
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
    private var focusPollTimer: Timer?

    /// The CGWindowID of the frontmost window we last detected via polling.
    private var lastPolledFrontWindowID: CGWindowID = 0

    init() {
        if let raw = UserDefaults.standard.string(forKey: "filterMode"),
           let mode = FilterMode(rawValue: raw) {
            filterMode = mode
        }
        excludedBundleIDs = Self.loadSet(key: "excludedBundleIDs")
        includedBundleIDs = Self.loadSet(key: "includedBundleIDs")
    }

    /// Returns whether auto-follow should switch to the given window based on the current filter.
    func shouldFollowWindow(_ window: TrackedWindow) -> Bool {
        guard let bundleID = window.bundleID else { return true }
        switch filterMode {
        case .all:
            return true
        case .exclude:
            return !excludedBundleIDs.contains(bundleID)
        case .include:
            return includedBundleIDs.contains(bundleID)
        }
    }

    /// Returns whether a window is in the active filter list for the current mode.
    func isWindowFiltered(_ window: TrackedWindow) -> Bool {
        guard let bundleID = window.bundleID else { return false }
        switch filterMode {
        case .all:
            return false
        case .exclude:
            return excludedBundleIDs.contains(bundleID)
        case .include:
            return includedBundleIDs.contains(bundleID)
        }
    }

    /// Toggle a window's membership in the current filter list (exclude or include).
    func toggleFilterMembership(_ window: TrackedWindow) {
        guard let bundleID = window.bundleID else { return }
        switch filterMode {
        case .all:
            break
        case .exclude:
            if excludedBundleIDs.contains(bundleID) {
                excludedBundleIDs.remove(bundleID)
            } else {
                excludedBundleIDs.insert(bundleID)
            }
        case .include:
            if includedBundleIDs.contains(bundleID) {
                includedBundleIDs.remove(bundleID)
            } else {
                includedBundleIDs.insert(bundleID)
            }
        }
    }

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
        startFocusPollTimer()
        log.info("Started observing frontmost app changes")
    }

    func stopObservingFrontApp() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            activationObserver = nil
            log.info("Stopped observing frontmost app changes")
        }
        stopFocusPollTimer()
    }

    // MARK: - Focus Polling (detects tab/window changes within the same app)

    private func startFocusPollTimer() {
        guard focusPollTimer == nil else { return }
        focusPollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollFrontmostWindow()
            }
        }
        log.info("Started focus poll timer")
    }

    private func stopFocusPollTimer() {
        focusPollTimer?.invalidate()
        focusPollTimer = nil
    }

    /// Polls CGWindowList to detect if the frontmost window of the active app changed
    /// (e.g. macOS tab switch within VS Code). This catches cases where AX notifications
    /// aren't delivered by Electron/Chromium-based apps.
    private func pollFrontmostWindow() async {
        guard autoFollowEnabled else { return }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        let bundleID = frontApp.bundleIdentifier ?? ""

        // Skip our own app and system apps
        guard bundleID != "io.github.loganrupe.CursorFollowMac",
              !systemExcludedBundleIDs.contains(bundleID) else {
            return
        }

        let pid = frontApp.processIdentifier

        // Query CGWindowList for on-screen windows (ordered front-to-back)
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return }

        // Find the frontmost window belonging to the active app
        guard let frontWindow = windowList.first(where: { info in
            guard let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer] as? Int,
                  layer == 0 else { // Layer 0 = normal windows
                return false
            }
            // Must have reasonable size (skip tiny overlays)
            if let bounds = info[kCGWindowBounds] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"],
               w < 100 || h < 100 {
                return false
            }
            return true
        }) else { return }

        guard let windowID = frontWindow[kCGWindowNumber] as? CGWindowID else { return }

        // If the frontmost window changed, trigger a target switch
        if windowID != lastPolledFrontWindowID {
            lastPolledFrontWindowID = windowID

            // Only act if this differs from what we're currently capturing
            guard windowID != selectedWindow?.id else { return }

            // Debounce
            let now = Date()
            guard now.timeIntervalSince(lastSwitchTime) >= switchDebounceInterval else { return }
            lastSwitchTime = now

            log.info("Detected frontmost window change via poll (windowID: \(windowID), app: \(bundleID))")

            await refreshWindows()

            guard let target = windows.first(where: { $0.id == windowID }) else {
                // Fallback: pick first window matching the app
                if let fallback = windows.first(where: { $0.bundleID == bundleID }) {
                    guard fallback.id != selectedWindow?.id else { return }
                    guard shouldFollowWindow(fallback) else { return }
                    selectWindow(fallback)
                }
                return
            }

            guard shouldFollowWindow(target) else { return }
            selectWindow(target)
        }
    }

    private func handleAppActivation(_ app: NSRunningApplication) async {
        guard autoFollowEnabled else { return }

        let bundleID = app.bundleIdentifier ?? ""

        // Don't follow our own app or system apps
        guard bundleID != "io.github.loganrupe.CursorFollowMac",
              !systemExcludedBundleIDs.contains(bundleID) else {
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

        // Respect the filter mode
        guard shouldFollowWindow(target) else {
            log.debug("Blocked switch to '\(target.title)' by filter (mode: \(self.filterMode.rawValue))")
            return
        }

        selectWindow(target)
    }

    func refreshWindows() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let filtered = content.windows.compactMap { window -> TrackedWindow? in
                let bundleID = window.owningApplication?.bundleIdentifier

                // Skip windows from system apps
                if let bundleID, systemExcludedBundleIDs.contains(bundleID) {
                    return nil
                }

                // Skip our own app
                if bundleID == "io.github.loganrupe.CursorFollowMac" {
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
