//
//  CursorFollowMacTests.swift
//  CursorFollowMacTests
//
//  Created by Logan Rupe on 20/5/2026.
//

import Testing
import Foundation
@testable import CursorFollowMac

struct CursorFollowMacTests {

    @Test func phase3AlwaysExcludesCursorFollowAndSystemWindows() {
        #expect(WindowTracker.isAlwaysExcludedBundleID("io.github.loganrupe.CursorFollowMac"))
        #expect(WindowTracker.isAlwaysExcludedBundleID("com.apple.controlcenter"))
        #expect(WindowTracker.isAlwaysExcludedBundleID("com.apple.notificationcenterui"))
        #expect(!WindowTracker.isAlwaysExcludedBundleID("com.apple.TextEdit"))
        #expect(!WindowTracker.isAlwaysExcludedBundleID(nil))
    }

    @Test func phase3UnavailableTargetMessageNamesRecoveryCases() {
        let message = WindowTracker.targetUnavailableMessage(for: "Release Notes")

        #expect(message.contains("Release Notes"))
        #expect(message.contains("disappeared"))
        #expect(message.contains("minimized"))
        #expect(message.contains("Space"))
    }

    @Test func phase4SavedOutputPreferencesLoadFromDefaults() {
        let suiteName = "io.github.loganrupe.CursorFollowMacTests.phase4SavedOutputPreferences"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "settings.hideWhenNotSharingEnabled")
        defaults.set(true, forKey: "settings.pinOutputOnTopEnabled")
        defaults.set(true, forKey: "settings.showResolution")
        defaults.set(true, forKey: "settings.showFrameCount")
        defaults.set(OutputPresentationMode.fill.rawValue, forKey: "settings.outputPresentationMode")

        let preferences = AppSettings.savedOutputPreferences(defaults: defaults)

        #expect(preferences.hideWhenNotSharing)
        #expect(preferences.pinOutputOnTop)
        #expect(preferences.showResolution)
        #expect(preferences.showFrameCount)
        #expect(preferences.presentationMode == .fill)
    }

    @Test func phase4InvalidOutputPresentationModeFallsBackToFit() {
        let suiteName = "io.github.loganrupe.CursorFollowMacTests.phase4InvalidOutputPresentationMode"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("stretched", forKey: "settings.outputPresentationMode")

        #expect(AppSettings.savedOutputPresentationMode(defaults: defaults) == .fit)
    }

}
