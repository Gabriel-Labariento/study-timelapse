# Performance notes

Version 0.2.0 reduces work in the recording loop and preview renderer. It keeps the same export resolution, playback frame rate, and timelapse speeds.

## What changed

The old loop woke every 10 ms, even when no frame was due. The new loop waits for the next sample, preview, or status update, with a health check at least every 250 ms. A busy encoder can still trigger short retries.

Visible previews keep their 10 fps target. Preview-only frames are rendered directly at 960×540 instead of creating a 1920×1080 intermediate first. When an export frame is already available, the preview reuses it.

Hidden, minimized, and fully covered windows don't generate preview images. Capture and recording continue, and status updates remain available. This doesn't turn off the camera or stop screen capture.

## Synthetic measurements

Measured on an M4 MacBook Air on September 28, 2026, using a release build. The benchmark uses identical synthetic screen and camera frames with the 4:3 crop in both paths. It draws each resulting preview, warms up both paths, alternates their order, and reports the median of three rounds of 150 previews.

| Preview path | Elapsed time | Process CPU time |
| --- | --- | --- |
| Full-HD intermediate | 0.292 s | 0.183 s |
| Direct preview | 0.179 s | 0.140 s |

That's about 39% less elapsed time and 23% less process CPU time for this preview workload. These numbers don't measure total app energy use, camera power, or battery life.

Run it locally:

```sh
swift run -c release PreviewBenchmark
```

The hidden-preview engine check recorded four frames with nine source reads over about 1.26 seconds, without generating preview images. Restoring the preview while paused produced an image without adding recording frames.

## Still to measure

A real study session needs camera capture, screen capture, and video encoding together. Compare matching sessions on the same Mac, with the same screen activity, camera settings, speed, brightness, and power source. Measure a sustained run rather than a brief CPU spike. No battery-life improvement is claimed until that comparison is done.
