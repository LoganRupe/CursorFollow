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

            // Filter mode
            Picker("Filter", selection: $windowTracker.filterMode) {
                ForEach(FilterMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("All: follow any window. Exclude: skip selected windows. Include: only follow selected windows.")

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

                Toggle("Pin", isOn: $outputWindowController.alwaysOnTop)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Keep output window above all other windows")

                if captureEngine.isCapturing {
                    Button("Stop") {
                        Task { await captureEngine.userStop() }
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
    let isFiltered: Bool
    let filterMode: FilterMode

    var body: some View {
        HStack {
            // Filter indicator
            if filterMode != .all {
                Image(systemName: isFiltered ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isFiltered ? (filterMode == .exclude ? .red : .green) : .secondary)
                    .font(.body)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(window.title)
                    .font(.body)
                    .lineLimit(1)
                Text(window.ownerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "video.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
