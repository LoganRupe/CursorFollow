# CursorFollow (macOS)

A macOS menu bar utility that captures an app window and publishes it as a virtual camera feed via a CoreMediaIO camera extension. Use it in Zoom, Slack, Google Meet, OBS, and other camera-enabled apps.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Screenshots](#screenshots)
- [Permissions](#permissions)
- [Troubleshooting](#troubleshooting)
    - [Reset Checklist](#reset-checklist-when-things-are-stuck)
- [Developer Docs](#developer-docs)

## Overview

CursorFollow runs in your menu bar and publishes a virtual camera named **CursorFollow Camera**. It can follow your active window automatically, or let you lock to a specific window manually.

## Quick Start

1. Launch `CursorFollowMac.app`.
2. When prompted, allow:
   - **Screen Recording** (required for window capture)
   - **System Extension** approval in System Settings
3. Open the CursorFollow menu bar panel.
4. Pick a target window from the list (or keep **Auto-follow cursor** enabled).
5. Click **Start**.
6. In your video app, select **CursorFollow Camera** as your camera source.

## Usage

- **Auto-follow cursor**: Automatically tracks the app/window you are actively using.
- **Filter mode**: Use **All / Exclude / Include** to control which windows appear as capture targets.
- **Refresh**: Re-scan active windows if the list looks stale or incomplete.
- **Show**: Bring the output preview window to the front.
- **Start / Stop**: Start or stop virtual camera output.

## Screenshots

### Menu bar panel

![CursorFollow menu bar panel](Docs/images/readme/main-panel.png)

### Settings window

![CursorFollow settings window](Docs/images/readme/settings-window.png)

## Permissions

- **Screen Recording**: Required for ScreenCaptureKit window capture.
- **System Extension**: Approve in System Settings → Privacy & Security when prompted.

## Troubleshooting

### Reset checklist (when things are stuck)

1. Quit your video app (Zoom/Meet/Slack/OBS) and quit CursorFollow.
2. In **System Settings → Privacy & Security → Screen Recording**, verify CursorFollow is enabled.
3. In **System Settings → Privacy & Security**, confirm the system extension is approved.
4. Reopen CursorFollow, click **Refresh**, select the target window, then click **Start**.
5. Reopen your video app and reselect **CursorFollow Camera** as the camera source.

### Permission paths by macOS version

- **macOS 13 Ventura / 14 Sonoma / 15 Sequoia**
    - Screen capture access: **System Settings → Privacy & Security → Screen Recording**
    - System extension approval: **System Settings → Privacy & Security** (look for the allow prompt near the bottom after first launch)

### CursorFollow Camera does not appear in Zoom/Meet/Slack

- Ensure CursorFollow is running and capture is started.
- Confirm **System Extension** approval in System Settings → Privacy & Security.
- Quit and reopen the video app after first-time extension approval.
- In the video app's camera selector, choose **CursorFollow Camera** explicitly (some apps stay on the previous camera device).

### Output is black or frozen

- Confirm **Screen Recording** permission is enabled for CursorFollow in System Settings → Privacy & Security → Screen Recording.
- Click **Refresh**, then reselect the target window.
- Stop and restart capture from the menu bar panel.

### Wrong window is being captured

- Disable **Auto-follow cursor** and manually select a specific window.
- Use **Include** mode to limit capture targets to approved windows.

### Capture feels choppy or high CPU

- In Settings, switch capture quality from **Balanced** to **Performant** or **Low-Latency**.
- Reduce competing screen capture/recording tools running at the same time.
- If needed, capture a smaller target window instead of a full-size display window.

## Developer Docs

- App and build documentation: [CursorFollowMac/README.md](CursorFollowMac/README.md)
- Additional architecture and planning docs: [Docs/README.md](Docs/README.md)
