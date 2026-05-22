# Domain Glossary

- Active Window: The frontmost window belonging to the current foreground app.
- Window Under Cursor: The topmost window intersecting the current mouse pointer position.
- SCStream: ScreenCaptureKit stream delivering frame sample buffers.
- SCContentFilter: Filter describing what ScreenCaptureKit captures.
- CMSampleBuffer: Timed media sample container used for video frames.
- CoreMediaIO Camera Extension: Modern Apple mechanism for virtual camera devices.
- CMIO Provider/Device/Stream: Extension concepts used to expose and feed virtual camera output.
- IPC: Inter-process communication between host app and camera extension.
- Frame Budget: Maximum allowable per-frame processing time to hit target latency/FPS.
- Queue Depth: Number of frames buffered before processing; higher depth can increase latency.
- Debounce: Delay strategy to avoid rapid oscillation while switching targets.
- Exclude List: Bundle IDs ignored by window selection logic.
