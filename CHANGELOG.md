# Changelog

## 0.2.0

- Schedule recording work around frame deadlines instead of polling at 100 Hz.
- Render previews directly at 960×540 and skip them while the window isn't visible.
- Keep recording and encoder error checks running with the preview hidden.
- Show the full camera image by default, with the original 4:3 crop available as an option.
- Add a shortcut to the native macOS camera controls.

Export remains silent 1080p at 30 fps, with the same timelapse speeds. Battery savings and native camera zoom still need live testing.

## 0.1.0

First public release of Study Timelapse.

- Screen capture with a mirrored camera inset in any corner.
- Three inset sizes and 10×, 30×, or 60× playback speeds.
- Live preview, pause/resume, and local 1080p MP4 export.
- Explicit file replacement confirmation and interruption handling.
- Automated timing, composition, encoder, and file-safety checks.

This is an early release. Live permission flows and long recording sessions still need testing. See [testing notes](docs/testing.md).
