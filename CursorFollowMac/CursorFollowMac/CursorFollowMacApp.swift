//
//  CursorFollowMacApp.swift
//  CursorFollowMac
//
//  Created by Logan Rupe on 20/5/2026.
//

import SwiftUI
import Combine
import SystemExtensions
import Carbon
import os.log

struct HotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

@MainActor
final class AutoFollowHotKeyManager: ObservableObject {
    private static let hotKeySignature: OSType = 0x4346484B // 'CFHK'
    private static let hotKeyID: UInt32 = 1

    private enum DefaultsKeys {
        static let keyCode = "hotkey.autoFollow.keyCode"
        static let modifiers = "hotkey.autoFollow.modifiers"
    }

    @Published private(set) var shortcutTokens: [String]
    @Published private(set) var registrationError: String?

    var onTriggered: (() -> Void)?

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "AutoFollowHotKeyManager")
    private let defaults: UserDefaults

    private var keyCode: UInt32
    private var modifiers: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultKeyCode = UInt32(kVK_ANSI_F)
        let defaultModifiers = UInt32(optionKey)

        if defaults.object(forKey: DefaultsKeys.keyCode) == nil {
            defaults.set(defaultKeyCode, forKey: DefaultsKeys.keyCode)
        }
        if defaults.object(forKey: DefaultsKeys.modifiers) == nil {
            defaults.set(defaultModifiers, forKey: DefaultsKeys.modifiers)
        }

        keyCode = UInt32(defaults.integer(forKey: DefaultsKeys.keyCode))
        modifiers = UInt32(defaults.integer(forKey: DefaultsKeys.modifiers))
        shortcutTokens = Self.tokens(forKeyCode: keyCode, modifiers: modifiers)
    }

    func start() {
        installHotKeyHandlerIfNeeded()
        let status = registerHotKey(keyCode: keyCode, modifiers: modifiers)
        if status == noErr {
            registrationError = nil
        } else {
            registrationError = Self.errorMessage(for: status, tokens: shortcutTokens)
            log.error("Failed to register existing hotkey on startup: \(status)")
        }
    }

    func stop() {
        unregisterHotKey()
        removeHotKeyHandler()
    }

    var currentShortcut: HotKeyShortcut {
        HotKeyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    func updateShortcut(from event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !relevantFlags.isEmpty else {
            log.debug("Rejected hotkey update without modifiers")
            return false
        }

        let newKeyCode = UInt32(event.keyCode)
        let newModifiers = Self.carbonModifiers(from: relevantFlags)
        return applyShortcut(HotKeyShortcut(keyCode: newKeyCode, modifiers: newModifiers))
    }

    @discardableResult
    func applyShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard shortcut.keyCode != keyCode || shortcut.modifiers != modifiers else {
            registrationError = nil
            return true
        }

        let previousKeyCode = keyCode
        let previousModifiers = modifiers
        let newTokens = Self.tokens(forKeyCode: shortcut.keyCode, modifiers: shortcut.modifiers)

        let status = registerHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        guard status == noErr else {
            let rollbackStatus = registerHotKey(keyCode: previousKeyCode, modifiers: previousModifiers)
            if rollbackStatus != noErr {
                registrationError = "Failed to restore previous shortcut (OSStatus \(rollbackStatus))."
                log.error("Failed to restore previous hotkey after remap failure: \(rollbackStatus)")
            } else {
                registrationError = Self.errorMessage(for: status, tokens: newTokens)
            }
            log.error("Failed to register requested hotkey: \(status)")
            return false
        }

        keyCode = shortcut.keyCode
        modifiers = shortcut.modifiers
        shortcutTokens = newTokens

        defaults.set(Int(keyCode), forKey: DefaultsKeys.keyCode)
        defaults.set(Int(modifiers), forKey: DefaultsKeys.modifiers)

        registrationError = nil
        log.info("Updated auto-follow hotkey to \(self.shortcutTokens.joined(separator: " + "), privacy: .public)")
        return true
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<AutoFollowHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyPressed(event)
            },
            1,
            &eventType,
            userData,
            &hotKeyHandlerRef
        )

        guard status == noErr else {
            log.error("Failed to install global hotkey handler: \(status)")
            return
        }
    }

    private func removeHotKeyHandler() {
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        var registeredHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registeredHotKeyRef
        )

        guard status == noErr else {
            return status
        }

        hotKeyRef = registeredHotKeyRef
        return status
    }

    private static func errorMessage(for status: OSStatus, tokens: [String]) -> String {
        if status == eventHotKeyExistsErr {
            return "Shortcut \(tokens.joined(separator: " + ")) is already in use by another app."
        }
        return "Could not register shortcut \(tokens.joined(separator: " + ")) (OSStatus \(status))."
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleHotKeyPressed(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            log.error("Failed to decode hotkey event: \(status)")
            return status
        }

        guard hotKeyID.signature == Self.hotKeySignature,
              hotKeyID.id == Self.hotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        onTriggered?()
        return noErr
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func tokens(forKeyCode keyCode: UInt32, modifiers: UInt32) -> [String] {
        var tokens: [String] = []

        if modifiers & UInt32(controlKey) != 0 { tokens.append("⌃ Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { tokens.append("⌥ Opt") }
        if modifiers & UInt32(shiftKey) != 0 { tokens.append("⇧ Shift") }
        if modifiers & UInt32(cmdKey) != 0 { tokens.append("⌘ Cmd") }

        tokens.append(keyLabel(for: keyCode))
        return tokens
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "Tab"
        default:
            return "Key \(keyCode)"
        }
    }
}

@MainActor
final class ToggleShareHotKeyManager: ObservableObject {
    private static let hotKeySignature: OSType = 0x43464853 // 'CFHS'
    private static let hotKeyID: UInt32 = 2

    private enum DefaultsKeys {
        static let keyCode = "hotkey.toggleShare.keyCode"
        static let modifiers = "hotkey.toggleShare.modifiers"
    }

    @Published private(set) var shortcutTokens: [String]
    @Published private(set) var registrationError: String?

    var onTriggered: (() -> Void)?

    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "ToggleShareHotKeyManager")
    private let defaults: UserDefaults

    private var keyCode: UInt32
    private var modifiers: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let defaultKeyCode = UInt32(kVK_ANSI_S)
        let defaultModifiers = UInt32(optionKey)

        if defaults.object(forKey: DefaultsKeys.keyCode) == nil {
            defaults.set(defaultKeyCode, forKey: DefaultsKeys.keyCode)
        }
        if defaults.object(forKey: DefaultsKeys.modifiers) == nil {
            defaults.set(defaultModifiers, forKey: DefaultsKeys.modifiers)
        }

        keyCode = UInt32(defaults.integer(forKey: DefaultsKeys.keyCode))
        modifiers = UInt32(defaults.integer(forKey: DefaultsKeys.modifiers))
        shortcutTokens = Self.tokens(forKeyCode: keyCode, modifiers: modifiers)
    }

    func start() {
        installHotKeyHandlerIfNeeded()
        let status = registerHotKey(keyCode: keyCode, modifiers: modifiers)
        if status == noErr {
            registrationError = nil
        } else {
            registrationError = Self.errorMessage(for: status, tokens: shortcutTokens)
            log.error("Failed to register existing share hotkey on startup: \(status)")
        }
    }

    func stop() {
        unregisterHotKey()
        removeHotKeyHandler()
    }

    var currentShortcut: HotKeyShortcut {
        HotKeyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    @discardableResult
    func updateShortcut(from event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let relevantFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !relevantFlags.isEmpty else {
            log.debug("Rejected share hotkey update without modifiers")
            return false
        }

        let newKeyCode = UInt32(event.keyCode)
        let newModifiers = Self.carbonModifiers(from: relevantFlags)
        return applyShortcut(HotKeyShortcut(keyCode: newKeyCode, modifiers: newModifiers))
    }

    @discardableResult
    func applyShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard shortcut.keyCode != keyCode || shortcut.modifiers != modifiers else {
            registrationError = nil
            return true
        }

        let previousKeyCode = keyCode
        let previousModifiers = modifiers
        let newTokens = Self.tokens(forKeyCode: shortcut.keyCode, modifiers: shortcut.modifiers)

        let status = registerHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        guard status == noErr else {
            let rollbackStatus = registerHotKey(keyCode: previousKeyCode, modifiers: previousModifiers)
            if rollbackStatus != noErr {
                registrationError = "Failed to restore previous shortcut (OSStatus \(rollbackStatus))."
                log.error("Failed to restore previous share hotkey after remap failure: \(rollbackStatus)")
            } else {
                registrationError = Self.errorMessage(for: status, tokens: newTokens)
            }
            log.error("Failed to register requested share hotkey: \(status)")
            return false
        }

        keyCode = shortcut.keyCode
        modifiers = shortcut.modifiers
        shortcutTokens = newTokens

        defaults.set(Int(keyCode), forKey: DefaultsKeys.keyCode)
        defaults.set(Int(modifiers), forKey: DefaultsKeys.modifiers)

        registrationError = nil
        log.info("Updated share-toggle hotkey to \(self.shortcutTokens.joined(separator: " + "), privacy: .public)")
        return true
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<ToggleShareHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyPressed(event)
            },
            1,
            &eventType,
            userData,
            &hotKeyHandlerRef
        )

        guard status == noErr else {
            log.error("Failed to install global share hotkey handler: \(status)")
            return
        }
    }

    private func removeHotKeyHandler() {
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        unregisterHotKey()

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        var registeredHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &registeredHotKeyRef
        )

        guard status == noErr else {
            return status
        }

        hotKeyRef = registeredHotKeyRef
        return status
    }

    private static func errorMessage(for status: OSStatus, tokens: [String]) -> String {
        if status == eventHotKeyExistsErr {
            return "Shortcut \(tokens.joined(separator: " + ")) is already in use by another app."
        }
        return "Could not register shortcut \(tokens.joined(separator: " + ")) (OSStatus \(status))."
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleHotKeyPressed(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            log.error("Failed to decode hotkey event: \(status)")
            return status
        }

        guard hotKeyID.signature == Self.hotKeySignature,
              hotKeyID.id == Self.hotKeyID else {
            return OSStatus(eventNotHandledErr)
        }

        onTriggered?()
        return noErr
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func tokens(forKeyCode keyCode: UInt32, modifiers: UInt32) -> [String] {
        var tokens: [String] = []

        if modifiers & UInt32(controlKey) != 0 { tokens.append("⌃ Ctrl") }
        if modifiers & UInt32(optionKey) != 0 { tokens.append("⌥ Opt") }
        if modifiers & UInt32(shiftKey) != 0 { tokens.append("⇧ Shift") }
        if modifiers & UInt32(cmdKey) != 0 { tokens.append("⌘ Cmd") }

        tokens.append(keyLabel(for: keyCode))
        return tokens
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "Tab"
        default:
            return "Key \(keyCode)"
        }
    }
}

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
                    } else if self.windowTracker.autoFollowEnabled && !self.captureEngine.userStopped {
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

            // Auto-share on start: begin capture immediately if the user opted in
            if UserDefaults.standard.bool(forKey: "settings.autoShareOnStart"),
               let window = windowTracker.selectedWindow ?? windowTracker.windows.first {
                windowTracker.selectWindow(window)
                await captureEngine.startCapture(window: window)
            }
        }
    }
}

@main
struct CursorFollowMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "AppDelegate")
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var coordinator: AppCoordinator?
    private var eventMonitor: Any?
    private let autoFollowHotKeyManager = AutoFollowHotKeyManager()
    private let toggleShareHotKeyManager = ToggleShareHotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
        autoFollowHotKeyManager.onTriggered = { [weak self] in
            guard let self, let tracker = self.coordinator?.windowTracker else { return }
            tracker.autoFollowEnabled.toggle()
            self.log.info("Auto-follow toggled via global hotkey: \(tracker.autoFollowEnabled ? "enabled" : "disabled")")
        }
        toggleShareHotKeyManager.onTriggered = { [weak self] in
            guard let self, let coordinator = self.coordinator else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if coordinator.captureEngine.isCapturing {
                    await coordinator.captureEngine.userStop()
                    self.log.info("Capture toggled via global hotkey: stopped")
                } else if let window = coordinator.windowTracker.selectedWindow {
                    await coordinator.captureEngine.startCapture(window: window)
                    self.log.info("Capture toggled via global hotkey: started")
                } else {
                    self.log.info("Capture toggle hotkey ignored: no window selected")
                }
            }
        }
        autoFollowHotKeyManager.start()
        toggleShareHotKeyManager.start()

        // Set up the popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 252, height: 456)
        popover.behavior = .transient
        let rootView = ContentView()
            .environmentObject(coordinator!.windowTracker)
            .environmentObject(coordinator!.captureEngine)
            .environmentObject(autoFollowHotKeyManager)
            .environmentObject(toggleShareHotKeyManager)
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

    func applicationWillTerminate(_ notification: Notification) {
        autoFollowHotKeyManager.stop()
        toggleShareHotKeyManager.stop()
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
        let extensionID = "io.github.loganrupe.CursorFollowMac.CameraExtension"
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
