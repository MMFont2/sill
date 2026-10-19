# holdrig — TEST ONLY

Presses the window thumbnails in Sill's bar in the real Debug app on a simulator, and stamps from each
touch-down what UIKit did with the press: the thumbnail's long press (the hold that shows its lights) and
tap, and the strip's scroll, beside the app's own console lines (`hold:` and `lights:`, in a Debug build
from issue #113 on). It was written to measure why a 1.5 s hold could feel like 4 s (issue #113,
docs/thumbnail-hold-plan.md), and works on any Debug build, main's from before #113 included.

**Private interfaces, simulator only.** A driver library (`holdrig.m`, with the touch rig's
`Tests/touchrig/TouchSynth`: UITouch and UIEvent private setters, as KIF does) is injected into the app at
launch through `DYLD_INSERT_LIBRARIES` (`simctl launch`'s `SIMCTL_CHILD_` environment). The app itself is
not changed or rebuilt; the library is built only for the simulator, does nothing without
`SIMULATOR_UDID` in its environment, and is never part of Sill.

```
Tests/holdrig/run.sh UDID APP NAME ['hold 3; tap; swipe; drift; drag'] [-- launch arguments]
```

- `UDID`: a booted simulator of your own, made for the test (an iPad Pro 13-inch on iOS 27.0 holds the
  harness's 1000×710 and 710×1000 screens).
- `APP`: a Debug build of Sill for the simulator, such as
  `.build/dd/Build/Products/Debug-iphonesimulator/Sill.app` from CI's iOS command with `-derivedDataPath
  .build/dd`. It is installed first.
- `NAME`: the log, `.build/holdrig/NAME.log`.
- The script, steps separated by `;`: `hold S` (the first thumbnail, S seconds, then a lift), `tap` (the
  second, 80 ms), `swipe` (the third, 120 pt left over 0.25 s), `drift` (the first, the finger creeping
  7.5 pt over 2.5 s), `drag` (the first: past the hold, then 150 pt right over 0.6 s), `set S`
  (`Sill.thumbnailHold` written as the Settings panel's stepper writes it, the strip on screen), `wait
  S`. After each press it notes where the strip is and where the pressed thumbnail is now, then taps the
  stream under the bar, which puts away the lights if they opened.
- Launch arguments: `-SillLayout 1000x710` (the harness's mock: no Mac, no network) unless others
  follow `--`, such as `-SillLayout 1000x710 -Sill.thumbnailHold 2.5`.
- `RIG_ROUTE=enqueue` hands the touches to UIKit's own HID entry point (`_enqueueHIDEvent:`) instead of
  `sendEvent:`; on iOS 27.0 that delivered no touch to the app (with screen points), so the default is
  `sendEvent:`, whose touches UIKit's gesture environment hands to every recognizer from the touched
  view up, the strip's scroll view's included.

A log line is `RIG +1.019 [thumbnail 1 hold] began`: seconds from that scenario's touch-down. The app's
own lines sit between them unprefixed.

## What it measured

(Filled in from the runs; docs/thumbnail-hold-plan.md, Results, has the tables.)
