# A picked window fits the device by default: the plan

2026-10-20. Branch `fit-by-default` (worktree `/Users/noah/Downloads/wt-fit-by-default`) from origin/main
at d1fa97e; line numbers are at d1fa97e. Issue #70 (Noah): "Some apps are quite small when not using
Virtual Display mode. Take a look and see if this can be adjusted." With it, closed PR #149 (nacben):
"Fix window streams occupying only a corner of the iOS panel", withdrawn by its author on 2026-10-18 with
no comment. The triage of 2026-10-19 (`sill-handoff/triage/2026-10-19-open-items.md`, decision 9) put
them together: "Decide fit by default now that #75 restores frames; take #149's one-line fix after a 1×
check." Noah's decision (2026-10-20): "Work on fit-by-default now that windows go back to their size."
Host, the wire (one optional field) and one rule on the device; the CLI's default output unchanged.

## The problem

Two causes make a streamed window small on the device.

**Aa unset leaves the window alone.** In regular mode (Virtual Display off) the host fits the window it
streams to the device's panel at the text scale Aa asks for, through Accessibility
(`StreamCoordinator.fitToViewport`, StreamCoordinator.swift:1116). Until Aa is first used the device
sends no scale, and no scale meant "leave the Mac window alone" (Viewport.swift's doc; the guard at
StreamCoordinator.swift:1117). So a window streams at its Mac size: a large one shrunk into the panel, a
small one small in the middle of it with black around it. Meanwhile the device's Aa reads 1×:

- `@State private var textScale: Double? = nil`, per stream screen, never saved (StreamScreen.swift:115);
- the control shows and VoiceOver reads `scale ?? 1.0` (StreamScreen.swift:1417, 1460);
- ending the slider at 1× on an untouched control sends nothing (StreamScreen.swift:1453, "a plain tap
  on an untouched control changes nothing"), so a 1× fit takes a trip through another value first.

The virtual display has always counted no scale as 1× (`VirtualStage.windowSize`, VirtualStage.swift:200),
which is why apps look bigger there. Until PR #75 (2026-10-15) nothing put a fitted window back, so a fit
nobody asked for would have left windows the device's size on the Mac for good; since #75 a window Sill
sized goes back to its own frame when it stops streaming (WindowRestore).

**On a 1× display, a window's picture fills a quarter of the frame.** The host asks ScreenCaptureKit for
the window's points × the capture scale (StreamCoordinator.swift:1384-1387; Retina, 2, by default), and a
window on a 1× display has only its points' worth of pixels. `SCStreamConfiguration.scalesToFit`
defaults to false, which only scales down (SCStream.h), so the window sat in the frame's top-left corner
with black around it, while the device maps its touches onto the whole frame. WindowCapture never set it
(WindowCapture.swift:25-31). #149 measured it and set it to true.

## The design

### The rule (pure: `Sources/SillHost/FitPolicy.swift`)

`FitPolicy.fit(panel:scale:fitWindows:)`, the fit for a window that streams in regular mode:

1. No viewport yet: none.
2. A scale from Aa: the panel at that scale, whatever the Mac's setting (`Reason.textScale`), as before.
   A scale outside `scales` (0.25 to 4: Aa's steps are 0.5 to 1.5) is no device's Aa: none (it was any
   positive number before).
3. No scale (Aa unset): with Fit windows to the device's screen on (`HostConfig.fitWindows`, on by
   default) the panel at 1×, Aa's 1× (`Reason.byDefault`); with it off, none, as before.
4. The size: the panel ÷ the scale in whole points, rounded, as the virtual display's window is worked
   out; a side that rounds to nothing or passes `maxSide` (16,384 pt, past any display) is none.

A window already larger than that is fitted down, one smaller fitted up, both within what its app allows
(a minimum, a grid, a window that cannot be resized, full screen: WindowSizer and WindowRestore as
before). `needsResize` is the 2 pt compare `fitToViewport` always made, and `moved` its "nothing moved"
test (a point either way).

`FitPolicy.Asks`, new: the last fit that left its window short of the size asked (an app at its minimum or
snapping to a grid, a window that cannot be resized or is in full screen, an app that did not answer,
Accessibility off). Asking again for the same size from where the window ended leaves it there again,
costs Accessibility's calls on the main actor (up to a second each for an app that does not answer) and,
for a refusal or full screen, a line in the log each time; and a device sends its viewport again whenever
its pointer shows or hides (`setLocalCursor`). With every pick fitting, that would be every Calculator
and every full-screen window. So the same window is not asked for the same size again while it is where
that ask left it (2 pt). The person resizing it, the window leaving full screen, its app taking the size
late, another size asked (a rotation, Aa), another window, a pick (the coordinator starts afresh, so a
busy app gets another chance) and the last device leaving all ask again.

`FitPolicy.afterSettingChange(fitWindows:scale:fitted:)`: the switch changed while a window streams in
regular mode. On, with Aa unset: the window is fitted now (`fitNow`). Off, with Aa unset and a fit on
record: the fit the setting made goes back now (`putBack`), by WindowRestore's rules ("Restored …";
moved, resized and full screen as at any stop). With Aa set, nothing: Aa's fit, or its lack of one, is
the device's.

`FitPolicy.fitsPanel(window:onVirtualDisplay:fit:)`: what the device is told (below). `resizedLine` keeps
Aa's line as it always read ("Resized Safari to 667×473 pt (asked 667×473 for a 1000×710 panel at
1.5×)") and says "… at 1×, by default)" for the setting's. `offLine` is the one line at launch while the
setting is off.

### Where the coordinator calls it

- `fitToViewport` asks FitPolicy with the running settings' `fitWindows` (`currentFit`), then the 2 pt
  compare and `fitAsks.shouldAsk`; makes the fit through `WindowSizer.resize` as before (recorded by
  WindowRestore, so the window goes back at the stop); notes what the ask came to (`fitAsks.asked`). It
  runs where Aa's fit always ran: a pick (select's regular path), every restart of the same window (a
  rate change, the encoder fallback, the catalog's resize check), and every new viewport
  (`applyViewportToActiveWindow`: a rotation, Aa).
- `select` starts the memory afresh at a pick (`bringForward`); the last device leaving clears it with
  the viewport.
- `adopt`: a change of `fitWindows` sets `fitSettingChanged` and runs `applyFitSetting` once no switch is
  in flight (select's defer comes back to it): `fitNow` through `applyViewportToActiveWindow`, `putBack`
  through `restoreFits(keeping: nil)` and a catalog refresh, whose resize check then restarts the stream
  at the window's new size. The setting needs no restart of its own (`restartNeeded` does not look at it).
- `start`: `FitPolicy.offLine` while the setting is off; nothing new otherwise.
- `startPipeline` puts `fitsPanel` in the status's stream (kind 16's `stream`), and `noteFitsPanel`
  updates it after a viewport or the setting changed while the window streams.

### The setting

`HostConfig.fitWindows`: on in `standard` (the CLI's values and Sill.app's defaults), in `changes(to:)`
("fit windows on → off" in the "Settings:" line). The Mac's alone, like Share clipboard with devices:
absent from StreamSettings, HostSettingsChange, DeviceSettings.accepted, `applying` and `restartNeeded`,
so no device changes it.

- Sill.app: Settings › Streaming's last section, "Fit windows to the device’s screen", with its
  footnote; the status menu's "Fit Windows to the Device’s Screen" right after Virtual Display, with the
  subtitle "Picked windows take the device’s size while they stream" (absolute, as Virtual Display's:
  it sets what it showed); saved under `fitWindows` (registered on: an existing install fits from its
  next launch); `-SillSetAfter '<s> fitWindows=0|1'` in the bare binary.
- The CLI: `SillHost --no-fit`, which prints `FitPolicy.offLine` at launch ("Fit windows to the device's
  screen is off: a picked window keeps its size until the device sets one with Aa.").

### What the device is told: `RunningStream.fitsPanel`, and the iPhone Duo

One device rule depended on Aa unset meaning "the Mac keeps the window's shape": the iPhone Duo open flat
and upright sizes its picture's pane to the picture's own shape, and to 16:10 "while the Mac fits the
window to the pane (a window with Aa set, or on the virtual display), so the pane never follows a shape
it gave the window itself (an app's least size would shrink the pane step by step)" (DuoPosture.swift's
`paneAspect`, decided in DuoPostureReader.swift:208 from `textScale != nil`). With the Mac fitting a
window with Aa unset and the device not knowing it, that loop comes back for any app whose least width is
over the pane's: the pane follows the picture, the Mac fits the window to the pane, the app keeps its
least width, the picture gets wider for its height, the pane shorter, and so on down to the app's least
height.

So kind 16's `stream` gains `fitsPanel: Bool?` (HostSettings.swift's RunningStream; optional, host to
device): true while the Mac sizes the streamed window to the device's panel (a window on the virtual
display, or one in regular mode that a fit applies to, Aa's or the setting's; its app refusing or
clamping the size all the same, since the Mac keeps asking for the panel), false for the Desktop and a
window left alone, nil from a host before it. The device's rule is now pure and checked:
`DuoPosture.fitsWindowToPane(window:textScale:onVirtualDisplay:macFitsPanel:)`, true for a window with Aa
set, on the virtual display, or one the Mac says it fits; never the Desktop. An older device ignores the
field (JSONDecoder skips unknown keys); a newer device and an older Mac keep today's rule (nil). Nothing a
device sends changes: the compatibility floor's rule for host-to-device fields (optional, never renamed).

### #149: `scalesToFit`

`WindowCapture.start` sets `config.scalesToFit = true`, with #149's reason in its comment and its credit.
It applies to every capture (a window, the Desktop, the virtual display's crop), and changes only a
source asked for more pixels than it has (Tests/capture-fit, below): a window on a 1× display at Retina,
which now fills the frame. A source with as many pixels as asked is captured byte for byte as before, and
one with more is scaled down as before (a luma level or two of the GPU's noise either way). The Desktop of
a 1× display already filled its frame. The virtual display is always 2× and its crop asks for its own
pixels or fewer, so nothing changes there.

### What does not change

- The Desktop is never fitted; a synthetic test host streams no real window, so the CLI's stdout on one is
  unchanged with the setting on (H2, below), and gains one line at launch with `--no-fit`.
- The virtual display: it fits a window as it always did, Aa unset counting as 1×, whatever the setting.
- Aa's fits, their lines and their way back: as before. Only scales outside 0.25 to 4 now count as none.
- The device's Aa: it reads 1× from the start as before, which is now what a Mac with the setting on
  does; its first touch works as before (a value away from 1× is sent; a plain tap sends nothing). No
  device file changes but the Duo's pane rule.
- Nothing is stored but the Mac's setting; the fits live in memory, as WindowRestore's records do.

## Open questions, and the default taken for each

1. **When the default fit applies.** Default: wherever Aa's fit applies, "as if Aa were set to 1×": a
   pick, every restart of the same window, every new viewport (a rotation fits it again). Alternative: at
   a pick only.
2. **A window resized on the Mac while it streams.** Default: fitted again at the catalog's next look
   (within about two seconds), as with Aa set; WindowRestore forgets the resize a re-fit undid, so the
   window still goes back to its own frame. Alternative: the default fit keeps a size the person at the
   Mac gave it until the next pick or viewport (a rotation), which a later change can add to FitPolicy.
3. **Where the switch lives.** Default: Settings › Streaming, and the status menu after Virtual Display
   (it changes every pick, and turning it off is one click). Alternative: Settings only.
4. **The device's Settings panel.** Default: no switch there; the Mac's alone, like Share clipboard with
   devices (Aa is the device's own control). A later change can add it to kind 16 and 17 as the floor's
   rules allow.
5. **A change of the switch while a window streams.** Default: at once: turned on, the window is fitted;
   turned off, a window the setting fitted goes back ("Restored …"). Alternative: from the next pick.
6. **Aa's look on the device.** Default: as before, 1× from the start (the task's call: "the device's Aa
   reads 1× from the start as it does today"), now true on a Mac with the setting on. The triage's "stop
   Aa reading 1× while unset" would matter on a Mac with the setting off or before this change; a later
   device change can read `fitsPanel` for it.
7. **The iPhone Duo open flat.** Default: the pane keeps 16:10 while the Mac says it fits the window
   (`fitsPanel`). Alternative: no wire change, and the pane's step-by-step shrink for an app wider than the
   pane at its least.
8. **Repeated asks.** Default: a fit that left the window short is not asked again until the window, its
   size or the size asked changes, or a pick (`FitPolicy.Asks`). Alternative: ask at every viewport, as
   Aa did, with a refusal's line each time.
9. **Malformed viewports.** Default: a scale outside 0.25 to 4, or a side past 16,384 pt, leaves the
   window alone (a device's Aa sends 0.5 to 1.5; a viewport the device did not send could have resized a
   window to any size before).
10. **The CLI.** Default: `--no-fit`, one line at launch, nothing new without it.
11. **The log.** Default: the default's fit says "… at 1×, by default)"; the refusal names the window
    ("Window sizing: Calculator refused the size (AX error -25200); it streams at its own size."), once
    per size asked.
12. **#149's fix everywhere.** Default: every capture, as #149 had it, since it changes only a source
    asked for more pixels than it has (the capture check). Alternative: only when the host asks for more.
13. **`fitsPanel` for a window its app will not resize.** Default: true (the Mac keeps asking for the
    panel), so a Duo pane is 16:10 with the window letterboxed in it, as with Aa set today.
14. **The words.** Default: support.html, README and DEVELOPMENT.md say windows fit by default; the next
    What's New gains a paragraph, and Larger Picture's sentence there loses "Set a window's text size with
    Aa". The App Store description's "Aa makes text larger or smaller" stays true. The site's new words are
    marked `<!-- Fit windows` for the release that ships them (docs/release-checklist.md part 1 §3).

15. **An iPhone Duo on Sill 0.5.1 (4)**, before `fitsPanel`: open flat and upright with Aa unset, its pane
    follows the picture's shape, and with a Mac that fits by default an app whose least width is over the
    pane's (about 653 pt: Xcode, Music, Mail…) shrinks the pane step by step to its least height, until
    the device updates. Default: accepted, since both apps ship together and the App Store updates the
    device. Alternative, for the host: when an app takes more than the size asked on a side, ask once
    more for the panel's shape at the larger of the two ratios, so the window keeps the panel's shape at
    its least size (no loop on any device, and no black bars on any device either); a second resize per
    fit, which no device needs once it reads `fitsPanel`.

## The test plan

- **`Tests/checks/fit-policy`** (FitPolicy.swift alone; in CI's run and its mutants matrix): the fit at
  its edges (Aa's scale whatever the setting, the default, the setting off, scales and sides out of
  bounds, the devices' panels), the size's rounding, the compare and a move, the ask memory, a change of
  the setting, `fitsPanel`, the lines. Then a model: a copy of the coordinator's `fitToViewport`,
  `applyFitSetting` and a pick's fresh start around the real rule against a stand-in app (a minimum, a
  window that cannot be resized, full screen): random sessions of viewports, the same viewport sent
  again (never an ask), Aa, the setting, the person resizing the window, full screen, restarts and picks,
  each window held to where it should be and no fit skipped that would have moved it. Mutants of
  FitPolicy.swift, every one caught.
- **`Tests/checks/window-restore`**: its model fits through FitPolicy (compiled in), each session with the
  setting on or off and turned on and off while a window streams, with the ask memory and a pick's
  fresh start; its 95 mutants again.
- **`away-quality`** (the setting in HostConfig), **`away-wire`** (`fitsPanel` on the wire, an older
  host's and an older device's), **`duo`** (`fitsWindowToPane`), with mutants for each new rule.
- **Builds**: `swift build -c release` (only the CaptureProbe warning); the iOS app Debug for the
  simulator as CI builds it, Release for the simulator and Debug for a device (only the StreamClient
  capture warning).
- **`Tests/checks/run-all.sh`**: all.
- **H2, the CLI's stdout**: origin/main's `SillHost` and this branch's, each built from `git archive`,
  `--synthetic` with `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`: idle,
  and a test client picking the Desktop; digits masked, lines sorted: identical. With `--no-fit`: the
  same plus its one line.
- **Previews** (`-SillRenderPreviews`) of main's bare SillMenuBar and this branch's, run from one path:
  only the Streaming pane and menu.txt differ.
- **The restore probe** (`Scripts/restore-probe/run.sh`, its own window): new steps 15 to 19, through
  FitPolicy as `fitToViewport` asks: a pick with Aa unset fitted up to a 1000×710 panel and down to an
  iPhone's 386×241 pane at 1×, each back whole at the stop; the setting off (nothing asked, Aa's 1.5×
  still fitted); the setting turned off while the window streams (back now); a window that cannot be
  resized asked once, not again for the same viewport, and again after a pick.
- **`Tests/capture-fit`** (TEST ONLY, #149's test extended): the real WindowCapture on a 1× and a 2×
  virtual display of its own, a white window of its own on each, before the fix (`--rev origin/main`) and
  after; frames of a patterned window compared pixel by pixel between the two.
- **Untested, for Noah**: below, in Results.

## Results

All on 2026-10-20, on this Mac (macOS 27.0, M2 Pro, one 1512×982 Retina display), with Sill.app idle and
its Virtual Display off, while other agents' builds kept the load average between 170 and 1,000.

- **`Tests/checks/fit-policy`**: 147 cases of the rule and 5,000 model sessions, 293,631 checks in all,
  pass. In the sessions: 110,309 asks (19,979 by default, 90,330 for Aa); 53,576 fits that moved the
  window, 14,548 refused, 32,105 in full screen, 10,080 at an app's minimum; 50,548 asks not made again;
  59,384 viewports sent again, none of which asked; the setting turned on with a window fitted now 3,286
  times, turned off with one put back 2,387 times. **41 of 41 mutants** caught (the default's scale, the
  setting, Aa's scale under the setting, the bounds, the reason, the rounding, the compare, a move, every
  branch of the memory, of the setting's change and of `fitsPanel`, the lines).
- **What the model found** while it was being written: the memory first remembered only an ask that left
  the window where it was, so an app clamped to its minimum was asked once more at the next viewport (the
  ask had moved it, to its minimum); it now remembers where an ask left a window short of the size asked
  (`Asks.Short`), and the same viewport sent again never asks. A scale of 1e-300 gave a finite, absurd
  size that the coordinator would have asked for (as main's code would): scales outside 0.25 to 4 and
  sides past 16,384 pt are now none.
- **`Tests/checks/window-restore`**: 42,514 checks pass (208 cases; the model's 5,000 sessions now fit
  through FitPolicy: 2,240 fits by default, 2,384 asks not made again, the setting turned on with a window
  fitted 512 times and off with one put back 128 times, every outcome of the way back as before).
  **95 of 95 mutants** caught.
- **`away-quality`** 78 cases (71 before), **`away-wire`** 56 (47), **`duo`** 252,566 (252,557): pass.
- **Builds**: `swift build -c release`, only the known CaptureProbe warning; the iOS app, Debug for the
  simulator exactly as CI builds it (`-derivedDataPath` in the worktree, `CODE_SIGNING_ALLOWED=NO
  ARCHS=arm64`), Release for the simulator and Debug for a generic device, `** BUILD SUCCEEDED **` each,
  only the known StreamClient capture warning.
- **The restore probe** (`Scripts/restore-probe/run.sh`, the screen unlocked, Noah idle for 22 minutes):
  34 of 34. The new steps: 15, a 900×600 window fitted up to a 1000×710 panel at 1× ("1× by default"),
  "already there" for the same viewport again, then back to (20,73,900×600) whole; 16, fitted down to an
  iPhone's 386×241 pane at 1×, back whole; 17, with the setting off nothing asked and nothing recorded,
  Aa's 1.5× fitted to 667×473 all the same, back whole; 18, the setting turned off while the window
  streams: `putBack`, back whole, and nothing fits it again; 19, a window that cannot be resized refused
  once (AX error -25200), "not asked again" for the same viewport, refused again after a pick. The front
  app never changed.
- **`Tests/capture-fit`** (the screen unlocked; two virtual displays of its own, 1000×700 pt, each for a
  few seconds): with origin/main's WindowCapture.swift, 2 of 10 cases fail: the window on the 1× display
  at twice its points (Retina) and the window on the 2× display at four times its points, luma
  [255, 255, 0, 255, 255, 0, 0, 0, 0]: white in the top-left quarter, black to the right and below. The
  Desktop of the 1× display at Retina already filled its frame. With this branch's, 10 of 10. The
  patterned window's frames, two runs of each build: at the window's own pixels (800×500 on the 1× display,
  1600×1000 on the 2× one) byte for byte the same in all four runs; at half of them (400×250, 800×500) at
  most 2 luma levels apart (mean 0.0023 and 0.0003), main against main as much as main against this
  branch: `scalesToFit` changes only a source asked for more pixels than it has.
- **Not verified here**: Sill.app with a device (no device was used, and none may be); a fit by default of
  one of Noah's real windows (a synthetic host never fits, and the restore probe fits only its own
  window); the coordinator's glue around FitPolicy live (`applyFitSetting`, `noteFitsPanel`, a pick's fresh
  start: the check's model is a copy of it); the iPhone Duo's pane with `fitsPanel` (pure and checked,
  one line of glue); a real 1× display (the capture check's is virtual).

### Untested, for Noah (N1–N12)

With Sill.app built from this branch and this iOS build, Virtual Display off unless a step says otherwise.
Sill.log's lines are the way to tell what happened.

- **N1, a small window on the iPad.** A Notes window of about 600×400 picked on the iPad fills the iPad's
  picture from the start, Aa reading 1×; Sill.log: "Resized Notes to … pt (asked … for a … panel at 1×, by
  default)". Aa to 1.25×, then back to 1×: each fits ("… at 1.25×)", "… at 1.0×)"). Pick another window:
  "Restored Notes — … to (…)", and Notes is back at its size on the Mac. Disconnect, and Quit Sill: the
  same.
- **N2, the iPhone.** A Safari window across the display, picked on the iPhone held upright, is fitted
  down to the 16:10 picture (377×235 pt on the 15 Pro); held sideways, to the landscape picture; with
  Larger Picture on, to its room (377×340), so the picture reaches the keyboard's top without Aa.
- **N3, the switch.** With a window streaming, Settings › Streaming's "Fit windows to the device’s screen"
  off: the window goes back at once ("Restored …", one restart), and the device's picture follows; on:
  fitted at once. The menu's "Fit Windows to the Device’s Screen" does the same, and the setting survives a
  relaunch (`defaults read me.saffer.sill.mac fitWindows`); the log says "Settings: fit windows on → off".
- **N4, a window that cannot be resized** (Calculator): one "… refused the size (AX error -25200); it
  streams at its own size." per pick, and no more while it streams (move the Pencil over the picture, or
  tap the trackpad, which makes the device send its viewport again).
- **N5, full screen.** A window already in full screen when picked: "… is full screen; not resizing."
  once, never the display's size; full screen and out again while it streams: fitted again, as with Aa.
- **N6, a resize on the Mac.** Resize the streaming window on the Mac: back to the device's size within
  about two seconds, as with Aa (open question 2: say whether the fit by default should keep the size you
  gave it until the next pick or rotation).
- **N7, a large least size** (Xcode, Music) on the iPhone held upright: the app's least size, black
  around it, as with Aa (open question 15's rule would keep the picture's shape instead).
- **N8, a 1× display.** A window on an external display at 1× streams across the whole frame at Retina
  (before, in its top-left quarter), and taps land where they should; the Desktop of that display.
- **N9, two devices.** The iPad and the iPhone connected: the window takes the size of the one that sent
  its viewport last (as with Aa), and goes back when the last one leaves.
- **N10, the iPhone Duo** (from October 23), open flat and upright, Aa unset, a window streaming: a 16:10
  picture (the console's `viewport:` lines), which Xcode's least width does not shrink. With Sill 0.5.1 (4)
  on the Duo instead, note what the picture does with Xcode (open question 15).
- **N11, the virtual display on**: windows fit as before, whatever the switch; the switch turned off while
  a window is staged changes nothing.
- **N12, mixed builds and the CLI.** The iPad on Sill 0.5.1 (4) against this Sill.app: windows fit by
  default (Aa reads 1×, as it always did). This iPad build against Sill for Mac 0.5.1: as before (no fit
  until Aa). `SillHost --no-fit`: its line at launch, windows keep their size, Aa still fits.
