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
