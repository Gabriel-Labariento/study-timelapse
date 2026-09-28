# Testing

## Automated checks

Run `./check.sh` on macOS 15 or later with Swift 6 or later.

`CoreChecks` exercises sampling speeds, pause exclusion, frame indices, portrait-screen fitting, inset placement, camera freshness, session transitions, interruption state, replacement consent, and bounded backpressure.

`MediaChecks` uses generated images and the real compositor and video writer. It checks all four inset corners, a portrait screen, a 90-frame H.264 export, 1920×1080 dimensions, three seconds of video, increasing timestamps, and the absence of an audio track. It also checks empty recordings, frames submitted after finishing, existing-file protection, and a file that appears before recording starts.

The engine check uses synthetic frame input and an injected asynchronous encoder failure. The real recording loop must report that failure even while paused with the preview hidden. Another check records with the preview hidden, confirms that no preview images are generated, and restores the preview while paused without adding recording frames. Framing checks verify that both camera edges survive full-view composition and that the preview matches the export.

`./build.sh` validates the app's property list and signature. It creates a ZIP, extracts it into a fresh temporary directory, and verifies the extracted app too.

For the bundled export check:

```sh
"Study Timelapse.app/Contents/MacOS/StudyTimelapse" \
  --verify-export /tmp/study-timelapse-check.mp4
```

Use a new filename each time. This check doesn't access the screen or camera.

## Before relying on a long recording

Automated checks don't grant macOS permissions or exercise physical devices. On the Mac you'll use to record:

- Enable preview and check the selected display and camera. Confirm that the camera is mirrored and positioned as expected.
- Record a short session at 10×. Pause, wait, resume, and finish. Play the MP4 and check that the break isn't included.
- Compare Full camera view with Crop to 4:3. Open Camera controls and check the framing options available on your Mac.
- Minimize the window during a short recording, then restore it. Check that recording continued and the preview returns.
- Cancel the save dialog and confirm that recording doesn't start.
- Try an existing filename and check that canceling replacement leaves the file alone.
- Test denied camera and screen permissions, then grant access and retry.
- During a disposable test session, lock the Mac or disconnect the selected source. Check the error and any saved portion.
- Test the length of session you actually need, watching memory, CPU use, and available disk space.

Live permission flows, camera orientation, lock/sleep notifications, device disconnections, and prolonged recording performance remain unverified in live sessions. Synthetic export checks aren't a substitute for those tests.

## Known limits

The app records one display and one camera, without audio. The initial download targets Apple silicon and macOS 15 or later; Intel builds haven't been tested.

The sampling clock keeps its timing phase after a delayed callback. Under load, two samples can end up closer together than the nominal interval. Output timestamps still advance at 30 fps.

A crash, force quit, power loss, or full disk can leave an unfinalized MP4. Recovery isn't guaranteed. The app is ad-hoc signed and isn't notarized for distribution.
