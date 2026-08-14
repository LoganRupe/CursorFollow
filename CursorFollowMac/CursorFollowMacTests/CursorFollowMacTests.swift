//
//  CursorFollowMacTests.swift
//  CursorFollowMacTests
//
//  Created by Logan Rupe on 20/5/2026.
//

import Testing
import Foundation
import CoreGraphics
import IOSurface
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

    @Test func captureAtNativeScaleUsesFullBackingResolution() {
        // The iPad simulator case: 583x853pt on a 2x display is 1166x1706 real pixels.
        // The old 1920x1080 cap clamped this to 738x1080 (63%).
        let result = CaptureEngine.captureDimensions(
            sourceSize: CGSize(width: 583, height: 853),
            pointPixelScale: 2.0,
            scale: .native
        )

        #expect(result.width == 1166)
        #expect(result.height == 1706)
        #expect(result.effectiveScale == 2.0)
    }

    @Test func captureScalePresetsAreFractionsOfNative() {
        let source = CGSize(width: 1000, height: 800)

        let half = CaptureEngine.captureDimensions(sourceSize: source, pointPixelScale: 2.0, scale: .half)
        #expect(half.width == 1000)
        #expect(half.height == 800)

        let threeQuarters = CaptureEngine.captureDimensions(sourceSize: source, pointPixelScale: 2.0, scale: .threeQuarters)
        #expect(threeQuarters.width == 1500)
        #expect(threeQuarters.height == 1200)
    }

    @Test func captureBudgetClampsByAreaAndPreservesAspectRatio() {
        // 4000x3000 native = 12 MP, over the 8.3 MP budget.
        let result = CaptureEngine.captureDimensions(
            sourceSize: CGSize(width: 4000, height: 3000),
            pointPixelScale: 1.0,
            scale: .native
        )

        #expect(result.width * result.height <= CaptureEngine.maxCapturePixels)
        // Aspect ratio (4:3) survives the clamp.
        let aspect = Double(result.width) / Double(result.height)
        #expect(abs(aspect - 4.0 / 3.0) < 0.01)
    }

    @Test func captureBudgetTreatsPortraitAndLandscapeEqually() {
        // The old 1920x1080 cap cost a portrait source ~2x what it cost the same
        // window rotated. Under an area budget the two must come out identical.
        let landscape = CaptureEngine.captureDimensions(
            sourceSize: CGSize(width: 3000, height: 4000),
            pointPixelScale: 1.0,
            scale: .native
        )
        let portrait = CaptureEngine.captureDimensions(
            sourceSize: CGSize(width: 4000, height: 3000),
            pointPixelScale: 1.0,
            scale: .native
        )

        #expect(landscape.width == portrait.height)
        #expect(landscape.height == portrait.width)
        #expect(landscape.effectiveScale == portrait.effectiveScale)
    }

    @Test func captureDimensionsAreEvenAndNonZero() {
        let result = CaptureEngine.captureDimensions(
            sourceSize: CGSize(width: 583, height: 853),
            pointPixelScale: 1.0,
            scale: .threeQuarters
        )

        #expect(result.width % 2 == 0)
        #expect(result.height % 2 == 0)

        // Degenerate input must not produce a zero-sized surface.
        let degenerate = CaptureEngine.captureDimensions(
            sourceSize: .zero,
            pointPixelScale: 1.0,
            scale: .half
        )
        #expect(degenerate.width >= 2)
        #expect(degenerate.height >= 2)
    }

    @Test func transportSurfaceRowsStayAlignedAtAnyWidth() throws {
        // IOSurface takes an unaligned bytesPerRow at face value instead of padding it,
        // and Core Animation then renders the surface black. 582 and 1166 are both
        // 8-byte aligned at 4 bytes/px, and both are real iPad-simulator capture widths.
        let transport = try #require(SharedMemoryFrameTransport(width: 582, height: 852))
        #expect(transport.surface.bytesPerRow % 16 == 0)
        #expect(transport.surface.width == 582)

        let resized = try #require(transport.resize(width: 1166, height: 1706))
        #expect(resized.bytesPerRow % 16 == 0)
        #expect(resized.width == 1166)
        #expect(transport.surfaceSize == (width: 1166, height: 1706))
    }

    @Test func transportSkipsReallocationWhenDimensionsAreUnchanged() throws {
        let transport = try #require(SharedMemoryFrameTransport(width: 800, height: 600))
        let originalID = transport.surfaceID

        #expect(transport.resize(width: 800, height: 600) == nil)
        #expect(transport.surfaceID == originalID)

        #expect(transport.resize(width: 640, height: 480) != nil)
        #expect(transport.surfaceSize == (width: 640, height: 480))
    }

    @MainActor
    @Test func captureScaleFallsBackToNativeForUnknownValue() {
        let suiteName = "io.github.loganrupe.CursorFollowMacTests.captureScaleFallback"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("ludicrous", forKey: "settings.captureScale")

        #expect(CaptureEngine(defaults: defaults).captureScale == .native)
    }

}
