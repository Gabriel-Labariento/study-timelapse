# Contributing

Thanks for taking a look. If something breaks, open an issue with your macOS version, Mac model, selected display and camera, and the steps to reproduce it. Include the error text if there is any. Please crop personal information out of screenshots and avoid uploading recordings with private content.

## Working on the app

Fork the repository and create a branch for your change. You'll need macOS 15 or later and Swift 6 or later through Xcode or Command Line Tools.

```sh
./check.sh
./build.sh
open "Study Timelapse.app"
```

Keep a pull request focused on one change. Describe what was broken or missing, what the change does, and how you checked it. If you're changing capture or recording behavior, include a short live recording check as well as automated coverage where possible. Mention any hardware-dependent checks you couldn't run.

The checks are executable Swift targets instead of XCTest targets. Add timing, geometry, and state checks to `Tests/TimelapseCoreTests`. Media and engine checks belong in `Tests/TimelapseMediaTests`.

## Things to preserve

Recording should always start from an explicit user action. Audio capture, network uploads, and telemetry are outside the current app's scope. A capture failure should stop the session visibly, and existing files should never be replaced without confirmation.

Keep frame storage bounded. UI changes belong on the main thread, and writer operations belong on the serial recording queue. Test the behavior a person will notice, especially when a session is paused, interrupted, or finishing.

## Before opening a pull request

Run the checks and the release build. For a UI change, include a screenshot. For recording changes, describe the exported video's duration and whether pause/resume worked. Don't commit app bundles, recordings, ZIPs, build caches, or local logs.

Contributions are covered by the repository's MIT license.
