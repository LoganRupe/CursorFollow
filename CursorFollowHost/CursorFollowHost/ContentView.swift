//
//  ContentView.swift
//  CursorFollowHost
//
//  Created by Logan Rupe on 20/5/2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var windowTracker: WindowTracker
    @EnvironmentObject var captureEngine: CaptureEngine
    @EnvironmentObject var outputWindowController: OutputWindowController

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.tint)
                Text("CursorFollow")
                    .font(.headline)
                Spacer()
                captureStatusBadge
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit CursorFollow")
            }

            Divider()

            // Auto-follow toggle
            HStack {
                Toggle(isOn: $windowTracker.autoFollowEnabled) {
                    Label("Auto-follow cursor", systemImage: "cursorarrow.motionlines")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Window list
            if windowTracker.windows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No windows available")
                        .foregroundStyle(.secondary)
                    Text("Grant Screen Recording permission in System Settings → Privacy & Security")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(windowTracker.windows, selection: Binding(
                    get: { windowTracker.selectedWindow },
                    set: { window in
                        if let window {
                            windowTracker.selectWindow(window)
                        }
                    }
                )) { window in
                    WindowRow(window: window, isSelected: window == windowTracker.selectedWindow)
                        .tag(window)
                }
                .listStyle(.bordered)
                .frame(minHeight: 200)
            }

            // Controls
            HStack {
                Button("Refresh") {
                    Task { await windowTracker.refreshWindows() }
                }

                Spacer()

                Button(outputWindowController.isVisible ? "Hide Output Window" : "Show Output Window") {
                    outputWindowController.toggle()
                }

                if captureEngine.isCapturing {
                    Button("Stop") {
                        Task { await captureEngine.stopCapture() }
                    }
                    .tint(.red)
                } else {
                    Button("Start Capture") {
                        guard let window = windowTracker.selectedWindow else { return }
                        Task { await captureEngine.startCapture(window: window) }
                    }
                    .disabled(windowTracker.selectedWindow == nil)
                    .tint(.green)
                }
            }

            // Status bar
            if captureEngine.isCapturing {
                HStack {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Capturing")
                        .font(.caption)
                    Spacer()
                    Text("\(captureEngine.frameCount) frames")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
            }

            if let error = captureEngine.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .frame(width: 380, height: 440)
        .onChange(of: windowTracker.autoFollowEnabled) { _, enabled in
            if enabled {
                windowTracker.startObservingFrontApp()
            } else {
                windowTracker.stopObservingFrontApp()
            }
        }
    }

    @ViewBuilder
    private var captureStatusBadge: some View {
        if captureEngine.isCapturing {
            Text("LIVE")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red, in: Capsule())
        }
    }
}

// MARK: - Window Row

struct WindowRow: View {
    let window: TrackedWindow
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                    .font(.body)
                    .lineLimit(1)
                Text(window.ownerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
