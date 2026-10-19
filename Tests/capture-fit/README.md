# What `scalesToFit` changes in window capture (TEST ONLY)

Closed PR #149 (nacben) found that a window on a 1× display, streamed at Retina, filled only the top-left
quarter of the frame: the host asks ScreenCaptureKit for the window's points × 2 pixels, a 1× display's
window has only its points' worth, and ScreenCaptureKit's `scalesToFit` defaults to false, which only scales
down. Its fix, `config.scalesToFit = true` in `Sources/SillHost/WindowCapture.swift`, came with issue #70's
fit by default (docs/fit-by-default-plan.md). This is #149's test, extended:

```
Tests/capture-fit/run.sh                      # this worktree's WindowCapture.swift: every case passes
Tests/capture-fit/run.sh --rev origin/main    # WindowCapture.swift as a revision has it (before the fix: 2 fail)
CAPTURE_FIT_FRAMES=DIR Tests/capture-fit/run.sh [--rev REV]   # also saves the patterned frames as PGMs
python3 -I Tests/capture-fit/compare.py DIR-A DIR-B           # two runs' patterned frames, pixel by pixel
```

It makes a 1× and then a 2× virtual display of its own (the host's `VirtualDisplay.swift`, the private
CGVirtualDisplay API, with Sill's virtual display's identity, as `SillHost --virtual-display-selftest`
does, so the Mac remembers no new display), puts one white window of its own on each, and captures it with
the real `WindowCapture` at the sizes the host asks: the window at its points (Standard) and twice them
(Retina), on the 2× display also four times (twice its pixels), and the display under it at its points and
twice, sampling each first frame's luma at nine points over the window: white must reach the right and the
bottom. Then the window drawn with one-pixel lines, at its own pixels and at half, its hash printed and its
frame saved with `CAPTURE_FIT_FRAMES`.

Needs Screen Recording for the app that runs it, the window server and an unlocked screen, so it is not a
pure check (not in CI or `Tests/checks/run-all.sh`). Never another app's window, never input, never the
hardware encoder (nothing is encoded); each display lasts a few seconds and goes with the process.

What it showed on 2026-10-20 (macOS 27.0, this M2 Pro): before the fix, a window asked for twice its
pixels (Retina on the 1× display; four times its points on the 2× display) sat in the frame's top-left
quarter; the Desktop of a 1× display at Retina filled its frame already. With the fix all ten cases fill
the frame. At the window's own pixels the frames are byte for byte the same with and without the fix; at
half of them (Standard on a Retina display) they differ by at most 2 luma levels in a few pixels, as two
runs of the same build do.
