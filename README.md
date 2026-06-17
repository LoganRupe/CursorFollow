<p align="center">
  <img src="Docs/images/app-icon.png" alt="CursorFollow app icon" width="128" height="128">
</p>

# CursorFollow (macOS)

A macOS menu bar utility that captures a target window and renders it into a stable window named **CursorFollow Output**. Share that output window from Zoom, Google Meet, Slack Huddles, Teams, OBS, or any app with a window-share picker.

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

CursorFollow runs in your menu bar and keeps **CursorFollow Output** pointed at the window you want to share. It can follow the frontmost eligible window automatically, or let you lock to a specific window manually.

## Quick Start

1. Launch `CursorFollowMac.app`.
2. When prompted, allow:
   - **Screen Recording** (required for window capture)
3. Open the CursorFollow menu bar panel.
4. Pick a target window from the list, or set **Target Mode** to **Auto**.
5. Click **Resume** if output is paused.
6. In your meeting app, share the window named **CursorFollow Output**.

## Usage

- **Target Mode**: Use **Auto** to track the active eligible window, or **Manual** to keep the selected target.
- **Filter mode**: Use **All / Exclude / Include** to control which windows appear as capture targets.
- **Output scaling**: Choose **Fit**, **Fill**, or **Actual** for the shared output window.
- **Refresh**: Re-scan active windows if the list looks stale or incomplete.
- **Show / Hide**: Bring the persistent output window forward or hide it.
- **Resume / Pause**: Start or pause output without changing the share-source window identity.

## Screenshots

### Menu bar panel

![CursorFollow menu bar panel](Docs/images/readme/main-panel.png)

### Settings window

![CursorFollow settings window](Docs/images/readme/settings-window.png)

## Permissions

- **Screen Recording**: Required for ScreenCaptureKit window capture.

## Troubleshooting

### Reset checklist (when things are stuck)

1. Quit your video app (Zoom/Meet/Slack/OBS) and quit CursorFollow.
2. In **System Settings → Privacy & Security → Screen Recording**, verify CursorFollow is enabled.
3. Reopen CursorFollow, click **Refresh**, select the target window, then click **Resume**.
4. Reopen your meeting app and reselect **CursorFollow Output** as the shared window.

### Permission paths by macOS version

- **macOS 13 Ventura / 14 Sonoma / 15 Sequoia**
    - Screen capture access: **System Settings → Privacy & Security → Screen Recording**

### CursorFollow Output does not appear in Zoom/Meet/Slack/Teams

- Ensure CursorFollow is running and **CursorFollow Output** is visible.
- Use the meeting app's **Share Screen** or **Share Window** picker, not the camera selector.
- If the picker was already open, close and reopen the picker after showing the output window.

### Output is black or frozen

- Confirm **Screen Recording** permission is enabled for CursorFollow in System Settings → Privacy & Security → Screen Recording.
- Click **Refresh**, then reselect the target window.
- Pause and resume output from the menu bar panel.

### Wrong window is being captured

- Set **Target Mode** to **Manual** and select a specific window.
- Use **Include** mode to limit capture targets to approved windows.

### Capture feels choppy or high CPU

- In Settings, switch capture quality from **Balanced** to **Performant** or **Low-Latency**.
- Reduce competing screen capture/recording tools running at the same time.
- If needed, capture a smaller target window instead of a full-size display window.

## Developer Docs

- App and build documentation: [CursorFollowMac/README.md](CursorFollowMac/README.md)
- Additional architecture and planning docs: [Docs/README.md](Docs/README.md)
