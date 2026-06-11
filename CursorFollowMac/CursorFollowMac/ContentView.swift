//
//  ContentView.swift
//  CursorFollowMac
//
//  Created by Logan Rupe on 20/5/2026.
//


@MainActor
final class AppSettings: ObservableObject {
    @Published private(set) var startOnLoginEnabled = false
    @Published private(set) var showInDockEnabled = false
    @Published private(set) var autoShareOnStart = false
    @Published private(set) var hideWhenNotSharingEnabled = false
    @Published private(set) var pinOutputOnTopEnabled = false
    @Published private(set) var showResolution = false
    @Published private(set) var showFrameCount = false
    @Published private(set) var outputPresentationMode: OutputPresentationMode

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "AppSettings")
    private let defaults: UserDefaults

    private enum Keys {
        static let showInDockEnabled = "settings.showInDockEnabled"
        static let autoShareOnStart = "settings.autoShareOnStart"
        static let hideWhenNotSharingEnabled = "settings.hideWhenNotSharingEnabled"
        static let pinOutputOnTopEnabled = "settings.pinOutputOnTopEnabled"
        static let showResolution = "settings.showResolution"
        static let showFrameCount = "settings.showFrameCount"
        static let outputPresentationMode = "settings.outputPresentationMode"
    }

    nonisolated static func savedOutputPresentationMode(defaults: UserDefaults = .standard) -> OutputPresentationMode {
        guard let rawMode = defaults.string(forKey: Keys.outputPresentationMode),
              let mode = OutputPresentationMode(rawValue: rawMode) else {
            return .fit
        }
        return mode
    }

    nonisolated static func savedOutputPreferences(defaults: UserDefaults = .standard) -> (
        hideWhenNotSharing: Bool,
        pinOutputOnTop: Bool,
        showResolution: Bool,
        showFrameCount: Bool,
        presentationMode: OutputPresentationMode
    ) {
        (
            hideWhenNotSharing: defaults.bool(forKey: Keys.hideWhenNotSharingEnabled),
            pinOutputOnTop: defaults.bool(forKey: Keys.pinOutputOnTopEnabled),
            showResolution: defaults.bool(forKey: Keys.showResolution),
            showFrameCount: defaults.bool(forKey: Keys.showFrameCount),
            presentationMode: savedOutputPresentationMode(defaults: defaults)
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outputPresentationMode = Self.savedOutputPresentationMode(defaults: defaults)
        if defaults.string(forKey: Keys.outputPresentationMode) == nil {
            defaults.set(OutputPresentationMode.fit.rawValue, forKey: Keys.outputPresentationMode)
        }
        showInDockEnabled = defaults.bool(forKey: Keys.showInDockEnabled)
        Self.applyDockVisibility(showInDockEnabled)
        autoShareOnStart = defaults.bool(forKey: Keys.autoShareOnStart)
        hideWhenNotSharingEnabled = defaults.bool(forKey: Keys.hideWhenNotSharingEnabled)
        pinOutputOnTopEnabled = defaults.bool(forKey: Keys.pinOutputOnTopEnabled)
        showResolution = defaults.bool(forKey: Keys.showResolution)
        showFrameCount = defaults.bool(forKey: Keys.showFrameCount)
        refreshStartOnLoginStatus()
    }

    func setStartOnLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            log.error("Failed to update login item registration: \(error.localizedDescription, privacy: .public)")
        }

        refreshStartOnLoginStatus()
    }

    func refreshStartOnLoginStatus() {
        startOnLoginEnabled = Self.isEnabled(status: SMAppService.mainApp.status)
    }

    func setShowInDock(_ enabled: Bool) {
        showInDockEnabled = enabled
        defaults.set(enabled, forKey: Keys.showInDockEnabled)
        Self.applyDockVisibility(enabled)
    }

    /// Shows or hides the app's Dock icon (the macOS equivalent of the taskbar).
    /// The app ships as an `LSUIElement` agent, so `.accessory` keeps it out of the
    /// Dock while `.regular` adds it.
    private static func applyDockVisibility(_ enabled: Bool) {
        NSApp.setActivationPolicy(enabled ? .regular : .accessory)
    }

    func setAutoShareOnStart(_ enabled: Bool) {
        autoShareOnStart = enabled
        defaults.set(enabled, forKey: Keys.autoShareOnStart)
    }

    func setHideWhenNotSharing(_ enabled: Bool) {
        hideWhenNotSharingEnabled = enabled
        defaults.set(enabled, forKey: Keys.hideWhenNotSharingEnabled)
    }

    func setPinOutputOnTop(_ enabled: Bool) {
        pinOutputOnTopEnabled = enabled
        defaults.set(enabled, forKey: Keys.pinOutputOnTopEnabled)
    }

    func setShowResolution(_ enabled: Bool) {
        showResolution = enabled
        defaults.set(enabled, forKey: Keys.showResolution)
    }

    func setShowFrameCount(_ enabled: Bool) {
        showFrameCount = enabled
        defaults.set(enabled, forKey: Keys.showFrameCount)
    }

    func setOutputPresentationMode(_ mode: OutputPresentationMode) {
        outputPresentationMode = mode
        defaults.set(mode.rawValue, forKey: Keys.outputPresentationMode)
    }

    private static func isEnabled(status: SMAppService.Status) -> Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notFound, .notRegistered:
            return false
        @unknown default:
            return false
        }
    }
}
import SwiftUI
import Combine
import AppKit
import Carbon
import ServiceManagement
import os

struct ContentView: View {
    @EnvironmentObject var windowTracker: WindowTracker
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var outputWindowController: OutputWindowController
    @EnvironmentObject var autoFollowHotKeyManager: AutoFollowHotKeyManager
    @EnvironmentObject var toggleShareHotKeyManager: ToggleShareHotKeyManager
    @StateObject private var appSettings = AppSettings()
    @State private var isSettingsPresented = false
    @State private var isQuitConfirmationPresented = false

    var body: some View {
        VStack(spacing: 13) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.tint)
                    .font(.title3.weight(.semibold))
                Text("CursorFollow")
                    .font(.title2.weight(.semibold))
                Spacer()
                captureStatusBadge
                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .popover(isPresented: $isSettingsPresented, arrowEdge: .bottom) {
                    SettingsModalView(
                        onCancel: { isSettingsPresented = false },
                        onSave: { isSettingsPresented = false }
                    )
                    .environmentObject(appSettings)
                    .environmentObject(captureEngine)
                    .environmentObject(autoFollowHotKeyManager)
                    .environmentObject(toggleShareHotKeyManager)
                    .frame(width: 840, height: 650)
                }
                Button {
                    isQuitConfirmationPresented = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit CursorFollow")
            }
            .padding(.horizontal, 6)

            Divider()
                .overlay(Color.white.opacity(0.12))

            // Target mode
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.motionlines")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                        .frame(width: 12)
                    Text("TARGET MODE")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }

                Picker("Target mode", selection: targetModeBinding) {
                    Text("Auto").tag(true)
                    Text("Manual").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(mainPanelCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            // Filter mode
            HStack(alignment: .center) {
                Text("FILTER")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Filter", selection: $windowTracker.filterMode) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 188)
            }
            .frame(height: 34)
            .padding(.horizontal, 12)
            .help("All: follow any window. Exclude: skip selected windows. Include: only follow selected windows.")

            // Window list
            if windowTracker.windows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No windows available")
                        .foregroundStyle(.secondary)
                    Text(windowTracker.permissionError == nil
                        ? "Open or unminimize a window, then refresh."
                        : "Grant Screen Recording permission in System Settings > Privacy & Security.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    if windowTracker.permissionError != nil {
                        Button {
                            openScreenRecordingSettings()
                        } label: {
                            Label("Open Screen Recording", systemImage: "gearshape")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 210)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background(mainPanelCardBackground)
            } else {
                List(windowTracker.windows) { window in
                    WindowRow(
                        window: window,
                        isSelected: window == windowTracker.selectedWindow,
                        isFiltered: windowTracker.isWindowFiltered(window),
                        filterMode: windowTracker.filterMode
                    )
                    .tag(window)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if windowTracker.filterMode != .all {
                            windowTracker.toggleFilterMembership(window)
                        } else {
                            windowTracker.selectWindow(window)
                        }
                    }
                    .contextMenu {
                        Button("Switch to this window") {
                            windowTracker.selectWindow(window)
                        }
                    }
                    .listRowSeparatorTint(Color.white.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                    .listRowBackground(Color.clear)
                }
                .listStyle(.bordered)
                .frame(minHeight: 242)
                .scrollContentBackground(.hidden)
                .background(mainPanelCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }

            // Controls
            HStack(spacing: 8) {
                Button {
                    Task { await windowTracker.refreshWindows() }
                } label: {
                    Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .frame(minWidth: 94, minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )
                }
                .help("Refresh window list")
                .buttonStyle(.plain)

                Spacer()

                Button {
                    outputWindowController.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: outputWindowController.isVisible ? "rectangle.slash" : "rectangle.on.rectangle")
                            .frame(width: 12, alignment: .center)
                        Text(outputWindowController.isVisible ? "Hide" : "Show")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(minWidth: 76, minHeight: 28, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .help(outputWindowController.isVisible ? "Hide Output Window" : "Show Output Window")
                .buttonStyle(.plain)
            }
            .controlSize(.regular)
            .padding(.horizontal, 6)
            .padding(.top, 1)

            // Status bar
            HStack {
                Circle()
                    .fill(captureEngine.isCapturing ? .green : .secondary)
                    .frame(width: 9, height: 9)
                Text(captureEngine.isCapturing ? "Capturing" : "Idle")
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)

                if captureEngine.isCapturing {
                    Button {
                        Task { await captureEngine.userStop() }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(minHeight: 28)
                    }
                    .help("Pause output without closing the shared window")
                    .tint(.red)
                } else {
                    Button {
                        guard let window = windowTracker.selectedWindow else { return }
                        Task { await captureEngine.startCapture(window: window) }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(minHeight: 28)
                    }
                    .help("Resume output")
                    .disabled(windowTracker.selectedWindow == nil)
                    .tint(.green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(mainPanelCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            if let error = captureEngine.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    if capturePermissionError != nil {
                        Spacer(minLength: 4)
                        Button("Open") {
                            openScreenRecordingSettings()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(12)
        .frame(width: 308, height: 552)
        .onChange(of: windowTracker.autoFollowEnabled) { _, enabled in
            if enabled {
                windowTracker.startObservingFrontApp()
            } else {
                windowTracker.stopObservingFrontApp()
            }
        }
        .onAppear {
            outputWindowController.alwaysOnTop = appSettings.pinOutputOnTopEnabled
            outputWindowController.showResolution = appSettings.showResolution
            outputWindowController.showFrameCount = appSettings.showFrameCount
            outputWindowController.presentationMode = appSettings.outputPresentationMode
        }
        .onChange(of: appSettings.pinOutputOnTopEnabled) { _, enabled in
            outputWindowController.alwaysOnTop = enabled
        }
        .onChange(of: appSettings.showResolution) { _, enabled in
            outputWindowController.showResolution = enabled
        }
        .onChange(of: appSettings.showFrameCount) { _, enabled in
            outputWindowController.showFrameCount = enabled
        }
        .onChange(of: appSettings.outputPresentationMode) { _, mode in
            outputWindowController.presentationMode = mode
        }
        .onChange(of: appSettings.hideWhenNotSharingEnabled) { _, enabled in
            if enabled && !captureEngine.isCapturing {
                outputWindowController.hide()
            }
        }
        .onChange(of: captureEngine.isCapturing) { _, isCapturing in
            if appSettings.hideWhenNotSharingEnabled {
                if isCapturing {
                    outputWindowController.show()
                } else {
                    outputWindowController.hide()
                }
            }
        }
        .alert("Quit CursorFollow?", isPresented: $isQuitConfirmationPresented) {
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to quit CursorFollow?")
        }
    }

    @ViewBuilder
    private var captureStatusBadge: some View {
        if captureEngine.isCapturing {
            Text("LIVE")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red, in: Capsule())
        }
    }

    private var targetModeBinding: Binding<Bool> {
        Binding(
            get: { windowTracker.autoFollowEnabled },
            set: { windowTracker.autoFollowEnabled = $0 }
        )
    }

    private var capturePermissionError: String? {
        guard let error = captureEngine.lastError else { return nil }
        let lowercased = error.lowercased()
        guard lowercased.contains("permission") || lowercased.contains("not authorized") || lowercased.contains("denied") else {
            return nil
        }
        return error
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private var mainPanelCardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.075),
                Color.white.opacity(0.035)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Window Row

struct WindowRow: View {
    let window: TrackedWindow
    let isSelected: Bool
    let isFiltered: Bool
    let filterMode: FilterMode

    var body: some View {
        HStack(spacing: 10) {
            // Filter indicator
            if filterMode != .all {
                Image(systemName: isFiltered ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isFiltered ? (filterMode == .exclude ? .red : .green) : .secondary)
                    .font(.headline)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(window.ownerName)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "video.fill")
                    .foregroundStyle(.green)
                    .font(.body)
            }
            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Modal

private struct SettingsModalView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var captureEngine: CaptureEngine
    @EnvironmentObject private var autoFollowHotKeyManager: AutoFollowHotKeyManager
    @EnvironmentObject private var toggleShareHotKeyManager: ToggleShareHotKeyManager

    let onCancel: () -> Void
    let onSave: () -> Void

    private enum HotkeyCaptureTarget {
        case autoFollow
        case toggleShare
    }

    @State private var selectedQuality: CaptureQuality = .balanced
    @State private var activeHotkeyCapture: HotkeyCaptureTarget?
    @State private var keyEventMonitor: Any?
    @State private var autoFollowShortcutStatusMessage: String?
    @State private var toggleShareShortcutStatusMessage: String?
    @State private var autoFollowClearStatusWorkItem: DispatchWorkItem?
    @State private var toggleShareClearStatusWorkItem: DispatchWorkItem?
    @State private var draftStartOnLoginEnabled = false
    @State private var draftShowInDockEnabled = false
    @State private var draftAutoShareOnStart = false
    @State private var draftHideWhenNotSharingEnabled = false
    @State private var draftPinOutputOnTopEnabled = false
    @State private var draftShowResolution = false
    @State private var draftShowFrameCount = false
    @State private var draftOutputPresentationMode: OutputPresentationMode = .fit
    @State private var initialCaptureQuality: CaptureQuality = .balanced
    @State private var initialAutoFollowShortcut: HotKeyShortcut?
    @State private var initialToggleShareShortcut: HotKeyShortcut?
    @State private var didSaveChanges = false
    @State private var escapeKeyEventMonitor: Any?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.078, blue: 0.141),
                    Color(red: 0.051, green: 0.067, blue: 0.122)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 16) {
                header
                ScrollView(showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 18) {
                            generalSection
                            captureQualitySection
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        VStack(alignment: .leading, spacing: 18) {
                            hotkeysSection
                            displaySection
                            aboutSection
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                footer
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            loadDraftState()
            didSaveChanges = false
            startEscapeMonitor()
        }
        .onDisappear {
            stopEscapeMonitor()
            stopShortcutCapture()
            if !didSaveChanges {
                restoreDiscardedChanges()
            }
        }
    }

    private var header: some View {
        HStack {
            Label("Settings", systemImage: "gearshape")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()
        }
    }

    private var generalSection: some View {
        SettingsCard(title: "GENERAL") {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    title: "Start on Login",
                    subtitle: "Launch CursorFollow automatically",
                    isOn: $draftStartOnLoginEnabled
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsToggleRow(
                    title: "Show in Dock",
                    subtitle: "Show the CursorFollow icon in the Dock",
                    isOn: $draftShowInDockEnabled
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsToggleRow(
                    title: "Resume output on launch",
                    subtitle: "Resume output when a target is available",
                    isOn: $draftAutoShareOnStart
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsToggleRow(
                    title: "Hide when not sharing",
                    subtitle: draftPinOutputOnTopEnabled && !draftHideWhenNotSharingEnabled
                        ? "Disabled while Pin output on top is enabled"
                        : "Hide the output window while paused",
                    isOn: hideWhenNotSharingBinding,
                    isDisabled: draftPinOutputOnTopEnabled && !draftHideWhenNotSharingEnabled
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsToggleRow(
                    title: "Pin output on top",
                    subtitle: draftHideWhenNotSharingEnabled && !draftPinOutputOnTopEnabled
                        ? "Disabled while Hide when not sharing is enabled"
                        : "Keep output window above other windows",
                    isOn: pinOutputOnTopBinding,
                    isDisabled: draftHideWhenNotSharingEnabled && !draftPinOutputOnTopEnabled
                )
            }
        }
    }

    private var hideWhenNotSharingBinding: Binding<Bool> {
        Binding(
            get: { draftHideWhenNotSharingEnabled },
            set: { enabled in
                draftHideWhenNotSharingEnabled = enabled
                if enabled {
                    draftPinOutputOnTopEnabled = false
                }
            }
        )
    }

    private var pinOutputOnTopBinding: Binding<Bool> {
        Binding(
            get: { draftPinOutputOnTopEnabled },
            set: { enabled in
                draftPinOutputOnTopEnabled = enabled
                if enabled {
                    draftHideWhenNotSharingEnabled = false
                }
            }
        )
    }

    private var showResolutionBinding: Binding<Bool> {
        Binding(
            get: { draftShowResolution },
            set: { draftShowResolution = $0 }
        )
    }

    private var showFrameCountBinding: Binding<Bool> {
        Binding(
            get: { draftShowFrameCount },
            set: { draftShowFrameCount = $0 }
        )
    }

    private var captureQualitySection: some View {
        SettingsCard(title: "CAPTURE QUALITY") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(CaptureQuality.allCases, id: \.self) { quality in
                        Button {
                            selectedQuality = quality
                        } label: {
                            Text(quality.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(quality == selectedQuality ? .white : Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(quality == selectedQuality ? Color(red: 0.09, green: 0.43, blue: 0.95) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Optimization level for real-time cursor tracking and window refreshes.")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .italic()
                    .foregroundStyle(Color.white.opacity(0.78))
            }
        }
    }

    private var hotkeysSection: some View {
        SettingsCard(title: "HOTKEYS") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toggle Auto-follow")
                            .font(.system(size: 26 / 2, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Global system shortcut")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        ForEach(Array(autoFollowHotKeyManager.shortcutTokens.enumerated()), id: \.offset) { index, token in
                            if index > 0 {
                                Text("+")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            shortcutKey(token)
                        }

                        Button {
                            if activeHotkeyCapture == .autoFollow {
                                stopShortcutCapture()
                            } else {
                                startShortcutCapture(for: .autoFollow)
                            }
                        } label: {
                            Image(systemName: activeHotkeyCapture == .autoFollow ? "xmark" : "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.65, green: 0.76, blue: 1.0))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(activeHotkeyCapture == .autoFollow ? "Cancel shortcut recording" : "Change shortcut")
                    }
                }
                .padding(.vertical, 2)

                if activeHotkeyCapture == .autoFollow {
                    Text("Press the new Auto-follow shortcut now (must include Control, Option, Shift, or Command).")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.67, green: 0.80, blue: 1.0))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }

                if let registrationError = autoFollowHotKeyManager.registrationError {
                    Text(registrationError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.62))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }

                if autoFollowHotKeyManager.registrationError == nil,
                   let autoFollowShortcutStatusMessage {
                    Text(autoFollowShortcutStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.64, green: 0.93, blue: 0.73))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toggle Output")
                            .font(.system(size: 26 / 2, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Global system shortcut")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        ForEach(Array(toggleShareHotKeyManager.shortcutTokens.enumerated()), id: \.offset) { index, token in
                            if index > 0 {
                                Text("+")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white.opacity(0.85))
                            }
                            shortcutKey(token)
                        }

                        Button {
                            if activeHotkeyCapture == .toggleShare {
                                stopShortcutCapture()
                            } else {
                                startShortcutCapture(for: .toggleShare)
                            }
                        } label: {
                            Image(systemName: activeHotkeyCapture == .toggleShare ? "xmark" : "pencil")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.65, green: 0.76, blue: 1.0))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(activeHotkeyCapture == .toggleShare ? "Cancel shortcut recording" : "Change shortcut")
                    }
                }
                .padding(.vertical, 2)

                if activeHotkeyCapture == .toggleShare {
                    Text("Press the new Toggle Output shortcut now (must include Control, Option, Shift, or Command).")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.67, green: 0.80, blue: 1.0))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }

                if let registrationError = toggleShareHotKeyManager.registrationError {
                    Text(registrationError)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.62))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }

                if toggleShareHotKeyManager.registrationError == nil,
                   let toggleShareShortcutStatusMessage {
                    Text(toggleShareShortcutStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.64, green: 0.93, blue: 0.73))
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: activeHotkeyCapture)
            .animation(.easeInOut(duration: 0.2), value: autoFollowHotKeyManager.registrationError)
            .animation(.easeInOut(duration: 0.2), value: toggleShareHotKeyManager.registrationError)
            .animation(.easeInOut(duration: 0.2), value: autoFollowShortcutStatusMessage)
            .animation(.easeInOut(duration: 0.2), value: toggleShareShortcutStatusMessage)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        }
    }

    private var displaySection: some View {
        SettingsCard(title: "DISPLAY") {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output scaling")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 6) {
                        ForEach(OutputPresentationMode.allCases, id: \.self) { mode in
                            Button {
                                draftOutputPresentationMode = mode
                            } label: {
                                Text(mode.label)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(mode == draftOutputPresentationMode ? .white : Color.white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(mode == draftOutputPresentationMode ? Color(red: 0.09, green: 0.43, blue: 0.95) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(.vertical, 10)
                Divider().overlay(Color.white.opacity(0.06))

                SettingsToggleRow(
                    title: "Show resolution",
                    subtitle: "Display resolution on output window",
                    isOn: showResolutionBinding
                )
                Divider().overlay(Color.white.opacity(0.06))
                SettingsToggleRow(
                    title: "Show frame count",
                    subtitle: "Display frame counter on output window",
                    isOn: showFrameCountBinding
                )
            }
        }
    }

    private var aboutSection: some View {
        SettingsCard(title: "ABOUT") {
            VStack(spacing: 14) {
                Image(systemName: "video.badge.waveform")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(red: 0.78, green: 0.84, blue: 1.0))
                    .frame(width: 58, height: 58)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 3) {
                    Text("CursorFollow")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(versionText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.74))
                }

                HStack(spacing: 20) {
                    aboutLink(
                        "DOCUMENTATION",
                        icon: "doc.text",
                        destination: "https://github.com/LoganRupe/CursorFollow/src/branch/main/README.md"
                    )
                    aboutLink(
                        "CHANGELOG",
                        icon: "clock.arrow.circlepath",
                        destination: "https://github.com/LoganRupe/CursorFollow/src/branch/main/CHANGELOG.md"
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.74, green: 0.79, blue: 1.0))
                    .frame(width: 8, height: 8)
                Text("SYSTEM READY")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            Spacer()

            Button {
                handleCancel()
            } label: {
                Text("Cancel")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                handleSave()
            } label: {
                Text("Save Changes")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.07, green: 0.17, blue: 0.38))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.72, green: 0.79, blue: 1.0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var versionText: String {
        let bundle = Bundle.main
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.4.1"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1082"
        return "Version \(shortVersion) (Build \(build))"
    }

    private func shortcutKey(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func aboutLink(_ title: String, icon: String, destination: String) -> some View {
        Button {
            guard let url = URL(string: destination) else {
                return
            }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(Color(red: 0.74, green: 0.82, blue: 1.0))
        }
        .buttonStyle(.plain)
    }

    private func loadDraftState() {
        appSettings.refreshStartOnLoginStatus()

        draftStartOnLoginEnabled = appSettings.startOnLoginEnabled
        draftShowInDockEnabled = appSettings.showInDockEnabled
        draftAutoShareOnStart = appSettings.autoShareOnStart
        draftHideWhenNotSharingEnabled = appSettings.hideWhenNotSharingEnabled
        draftPinOutputOnTopEnabled = appSettings.pinOutputOnTopEnabled
        draftShowResolution = appSettings.showResolution
        draftShowFrameCount = appSettings.showFrameCount
        draftOutputPresentationMode = appSettings.outputPresentationMode

        initialCaptureQuality = captureEngine.captureQuality
        selectedQuality = initialCaptureQuality

        initialAutoFollowShortcut = autoFollowHotKeyManager.currentShortcut
        initialToggleShareShortcut = toggleShareHotKeyManager.currentShortcut
    }

    private func handleCancel() {
        onCancel()
    }

    private func handleSave() {
        stopShortcutCapture()

        appSettings.setStartOnLogin(draftStartOnLoginEnabled)
        appSettings.setShowInDock(draftShowInDockEnabled)
        appSettings.setAutoShareOnStart(draftAutoShareOnStart)
        appSettings.setHideWhenNotSharing(draftHideWhenNotSharingEnabled)
        appSettings.setPinOutputOnTop(draftPinOutputOnTopEnabled)
        appSettings.setShowResolution(draftShowResolution)
        appSettings.setShowFrameCount(draftShowFrameCount)
        appSettings.setOutputPresentationMode(draftOutputPresentationMode)
        captureEngine.setCaptureQuality(selectedQuality)

        didSaveChanges = true
        initialCaptureQuality = selectedQuality
        initialAutoFollowShortcut = autoFollowHotKeyManager.currentShortcut
        initialToggleShareShortcut = toggleShareHotKeyManager.currentShortcut
        onSave()
    }

    private func restoreDiscardedChanges() {
        if let initialAutoFollowShortcut {
            _ = autoFollowHotKeyManager.applyShortcut(initialAutoFollowShortcut)
        }
        if let initialToggleShareShortcut {
            _ = toggleShareHotKeyManager.applyShortcut(initialToggleShareShortcut)
        }

        autoFollowShortcutStatusMessage = nil
        toggleShareShortcutStatusMessage = nil
    }

    private func startShortcutCapture(for target: HotkeyCaptureTarget) {
        stopShortcutCapture()
        withAnimation(.easeInOut(duration: 0.2)) {
            activeHotkeyCapture = target
            switch target {
            case .autoFollow:
                autoFollowShortcutStatusMessage = nil
            case .toggleShare:
                toggleShareShortcutStatusMessage = nil
            }
        }

        switch target {
        case .autoFollow:
            autoFollowClearStatusWorkItem?.cancel()
            autoFollowClearStatusWorkItem = nil
        case .toggleShare:
            toggleShareClearStatusWorkItem?.cancel()
            toggleShareClearStatusWorkItem = nil
        }

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopShortcutCapture()
                return nil
            }

            let didUpdate: Bool
            switch target {
            case .autoFollow:
                didUpdate = autoFollowHotKeyManager.updateShortcut(from: event)
            case .toggleShare:
                didUpdate = toggleShareHotKeyManager.updateShortcut(from: event)
            }

            if didUpdate {
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch target {
                    case .autoFollow:
                        autoFollowShortcutStatusMessage = "Shortcut updated to \(autoFollowHotKeyManager.shortcutTokens.joined(separator: " + "))."
                    case .toggleShare:
                        toggleShareShortcutStatusMessage = "Shortcut updated to \(toggleShareHotKeyManager.shortcutTokens.joined(separator: " + "))."
                    }
                }
                scheduleShortcutStatusClear(for: target)
                stopShortcutCapture()
                return nil
            }

            NSSound.beep()
            return nil
        }
    }

    private func stopShortcutCapture() {
        withAnimation(.easeInOut(duration: 0.2)) {
            activeHotkeyCapture = nil
        }
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func scheduleShortcutStatusClear(for target: HotkeyCaptureTarget) {
        switch target {
        case .autoFollow:
            autoFollowClearStatusWorkItem?.cancel()
        case .toggleShare:
            toggleShareClearStatusWorkItem?.cancel()
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                switch target {
                case .autoFollow:
                    autoFollowShortcutStatusMessage = nil
                case .toggleShare:
                    toggleShareShortcutStatusMessage = nil
                }
            }
            switch target {
            case .autoFollow:
                autoFollowClearStatusWorkItem = nil
            case .toggleShare:
                toggleShareClearStatusWorkItem = nil
            }
        }

        switch target {
        case .autoFollow:
            autoFollowClearStatusWorkItem = workItem
        case .toggleShare:
            toggleShareClearStatusWorkItem = workItem
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
    }

    private func startEscapeMonitor() {
        stopEscapeMonitor()
        escapeKeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.keyCode == UInt16(kVK_Escape), activeHotkeyCapture == nil else {
                return event
            }
            onCancel()
            return nil
        }
    }

    private func stopEscapeMonitor() {
        if let escapeKeyEventMonitor {
            NSEvent.removeMonitor(escapeKeyEventMonitor)
            self.escapeKeyEventMonitor = nil
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 21 / 2, weight: .bold))
                .foregroundStyle(Color(red: 0.68, green: 0.76, blue: 1.0))

            content
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                )
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.74))
            }

            Spacer(minLength: 10)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 10)
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}
