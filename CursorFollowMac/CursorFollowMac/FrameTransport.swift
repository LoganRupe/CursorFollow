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
/// - A shared BGRA IOSurface acts as the frame buffer. It is reallocated to match
///   the capture dimensions exactly (see `resize(width:height:)`), so consumers can
///   render the whole surface without cropping.
/// - The host output window reads the surface directly after each capture callback.
/// - Darwin notification hooks remain available for the historical extension path.
final class SharedMemoryFrameTransport: FrameTransport, @unchecked Sendable {
    private let log = Logger(subsystem: "io.github.loganrupe.CursorFollowMac", category: "FrameTransport")

    private let lock = NSLock()
    private var currentSurface: IOSurface
    private var width: Int
    private var height: Int
    private var sequenceNumber: UInt64 = 0
    private var isActive = true
    private var notifyToken: Int32 = -1
    private var frameNotifyToken: Int32 = -1

    /// The surface currently receiving frames.
    var surface: IOSurface { lock.withLock { currentSurface } }

    /// The surface's current pixel dimensions.
    var surfaceSize: (width: Int, height: Int) { lock.withLock { (width, height) } }

    /// Darwin notification name for cross-process surface ID sharing.
    static let surfaceNotificationName = "io.github.loganrupe.CursorFollowMac.surfaceID"

    /// Darwin notification name posted on each new frame.
    static let frameNotificationName = "io.github.loganrupe.CursorFollowMac.newFrame"

    init?(width: Int = 1920, height: Int = 1080) {
        guard let surface = Self.makeSurface(width: width, height: height) else {
            log.error("Failed to create IOSurface (\(width)x\(height) BGRA)")
            return nil
        }

        self.width = width
        self.height = height
        self.currentSurface = surface
        log.info("Frame transport initialized: \(width)x\(height) BGRA, surfaceID=\(surface.surfaceID), alloc=\(surface.allocationSize) bytes")

        // Publish surface ID via Darwin notification state (system-global, works cross-process)
        var token: Int32 = -1
        let status = notify_register_check(Self.surfaceNotificationName, &token)
        if status == NOTIFY_STATUS_OK {
            self.notifyToken = token
            broadcastSurfaceID(surface)
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

    /// Reallocates the shared surface so it matches the capture dimensions exactly.
    ///
    /// Returns the new surface when a reallocation happened, and `nil` when the current
    /// surface already has these dimensions (the common case while auto-follow hops
    /// between same-sized windows) or when allocation failed. On failure the existing
    /// surface is kept, so capture degrades to a cropped frame rather than going dark.
    @discardableResult
    func resize(width newWidth: Int, height newHeight: Int) -> IOSurface? {
        guard newWidth > 0, newHeight > 0 else { return nil }

        lock.lock()
        defer { lock.unlock() }

        guard newWidth != width || newHeight != height else { return nil }

        guard let newSurface = Self.makeSurface(width: newWidth, height: newHeight) else {
            log.error("Failed to resize frame transport to \(newWidth)x\(newHeight); keeping \(self.width)x\(self.height)")
            return nil
        }

        currentSurface = newSurface
        width = newWidth
        height = newHeight
        broadcastSurfaceID(newSurface)
        log.info("Frame transport resized to \(newWidth)x\(newHeight), surfaceID=\(newSurface.surfaceID), alloc=\(newSurface.allocationSize) bytes")
        return newSurface
    }

    private static func makeSurface(width: Int, height: Int) -> IOSurface? {
        // bytesPerRow must be aligned or Core Animation renders the surface black.
        // IOSurface takes an unaligned stride at face value rather than padding it,
        // so `width * 4` only happens to work when width is a multiple of 4 — a 582px
        // wide capture yields 2328 bytes/row (8-byte aligned) and never displays.
        let bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4)

        // isGlobal preserves compatibility with the historical extension path.
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: bytesPerRow,
            .allocSize: IOSurfaceAlignProperty(kIOSurfaceAllocSize, bytesPerRow * height),
            .pixelFormat: kCVPixelFormatType_32BGRA,
            IOSurfacePropertyKey(rawValue: "IOSurfaceIsGlobal"): true
        ]
        return IOSurface(properties: properties)
    }

    /// Publishes the surface ID to the system-global Darwin notification state.
    /// Must be called with `lock` held (or from `init`, before the instance escapes).
    private func broadcastSurfaceID(_ surface: IOSurface) {
        guard notifyToken != -1 else { return }
        notify_set_state(notifyToken, UInt64(surface.surfaceID))
        notify_post(Self.surfaceNotificationName)
        log.info("Published surfaceID=\(surface.surfaceID) via Darwin notification")
    }

    func publishFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        lock.lock()
        guard isActive else {
            lock.unlock()
            return
        }
        sequenceNumber += 1
        let seq = sequenceNumber
        // Snapshot the destination under the lock: a concurrent resize() swaps in a
        // new surface, and this frame must finish writing to the one it started on.
        let surface = currentSurface
        let width = self.width
        let height = self.height
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
        let (surface, size) = lock.withLock { (currentSurface, height * currentSurface.bytesPerRow) }
        surface.lock(options: [], seed: nil)
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
