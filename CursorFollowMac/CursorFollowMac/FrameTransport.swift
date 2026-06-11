//
//  FrameTransport.swift
//  CursorFollowMac
//
//  Created by Logan Rupe on 20/5/2026.
//

import Foundation
import CoreMedia
import CoreVideo
import IOSurface
import os.log
import notify

/// Protocol for publishing captured frames into the host renderer surface.
protocol FrameTransport: Sendable {
    func publishFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func stop()
}

/// Publishes captured frames to a shared IOSurface that the host output window renders.
///
/// Transport mechanism:
/// - A shared IOSurface (1920x1080 BGRA) acts as the frame buffer.
/// - The host output window reads the surface directly after each capture callback.
/// - Darwin notification hooks remain available for the historical extension path.
final class SharedMemoryFrameTransport: FrameTransport, @unchecked Sendable {
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "FrameTransport")

    let surface: IOSurface
    private let width: Int
    private let height: Int

    private let lock = NSLock()
    private var sequenceNumber: UInt64 = 0
    private var isActive = true
    private var notifyToken: Int32 = -1
    private var frameNotifyToken: Int32 = -1

    /// App group identifier retained for historical extension compatibility.
    static let appGroupID = "group.io.github.loganrupe.CursorFollowMac"

    /// Darwin notification name for cross-process surface ID sharing.
    static let surfaceNotificationName = "io.github.loganrupe.CursorFollowMac.surfaceID"

    /// Darwin notification name posted on each new frame.
    static let frameNotificationName = "io.github.loganrupe.CursorFollowMac.newFrame"

    init?(width: Int = 1920, height: Int = 1080) {
        self.width = width
        self.height = height

        // Create shared IOSurface. isGlobal preserves compatibility with the historical extension path.
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: width * 4,
            .allocSize: width * height * 4,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            IOSurfacePropertyKey(rawValue: "IOSurfaceIsGlobal"): true
        ]

        guard let surface = IOSurface(properties: properties as [IOSurfacePropertyKey: Any]) else {
            log.error("Failed to create IOSurface (\(width)x\(height) BGRA)")
            return nil
        }

        self.surface = surface
        log.info("Frame transport initialized: \(width)x\(height) BGRA, surfaceID=\(surface.surfaceID), alloc=\(surface.allocationSize) bytes")

        // Publish surface ID via Darwin notification state (system-global, works cross-process)
        var token: Int32 = -1
        let status = notify_register_check(Self.surfaceNotificationName, &token)
        if status == NOTIFY_STATUS_OK {
            self.notifyToken = token
            notify_set_state(token, UInt64(surface.surfaceID))
            notify_post(Self.surfaceNotificationName)
            log.info("Published surfaceID=\(surface.surfaceID) via Darwin notification")
        } else {
            log.error("Failed to register Darwin notification for surfaceID broadcast")
        }

        // Register token for per-frame notifications
        var frameToken: Int32 = -1
        let frameStatus = notify_register_check(Self.frameNotificationName, &frameToken)
        if frameStatus == NOTIFY_STATUS_OK {
            self.frameNotifyToken = frameToken
        }
    }

    func publishFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        lock.lock()
        guard isActive else {
            lock.unlock()
            return
        }
        sequenceNumber += 1
        let seq = sequenceNumber
        lock.unlock()

        // Lock source pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            log.error("Failed to get pixel buffer base address")
            return
        }

        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)

        // Lock IOSurface for writing
        surface.lock(options: [], seed: nil)

        let dstBase = surface.baseAddress
        let dstBytesPerRow = surface.bytesPerRow

        // Copy frame data row by row (handles stride differences)
        let copyWidth = min(srcWidth, width) * 4
        let copyHeight = min(srcHeight, height)

        for row in 0..<copyHeight {
            let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
            let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
            memcpy(dstRow, srcRow, copyWidth)
        }

        surface.unlock(options: [], seed: nil)

        // Signal new frame via Darwin notification
        if frameNotifyToken != -1 {
            notify_set_state(frameNotifyToken, seq)
            notify_post(Self.frameNotificationName)
        }

        if seq % 300 == 0 {
            log.info("Transport: published frame #\(seq) at \(timestamp.seconds)s")
        }
    }

    func stop() {
        lock.lock()
        isActive = false
        lock.unlock()
        if notifyToken != -1 {
            notify_cancel(notifyToken)
            notifyToken = -1
        }
        if frameNotifyToken != -1 {
            notify_cancel(frameNotifyToken)
            frameNotifyToken = -1
        }
        log.info("Frame transport stopped after \(self.sequenceNumber) frames")
    }

    /// Clear the IOSurface to black. Used when switching capture targets
    /// to prevent stale pixels from the previous window bleeding through.
    func clearSurface() {
        surface.lock(options: [], seed: nil)
        let size = width * height * 4
        memset(surface.baseAddress, 0, size)
        surface.unlock(options: [], seed: nil)
    }

    /// The IOSurface seed for consumers that need to verify surface changes.
    var surfaceSeed: UInt32 {
        surface.seed
    }

    /// The IOSurface ID for diagnostics and compatibility consumers.
    var surfaceID: IOSurfaceID {
        surface.surfaceID
    }
}
