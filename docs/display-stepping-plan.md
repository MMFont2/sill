# Which of the Mac's displays the Desktop shows — the plan

2026-10-20. Branch `display-stepping` (worktree `/Users/noah/Downloads/wt-display-stepping`) from
origin/main at d1fa97e. Issue #91 (ByartMyars, a MacBook Pro docked to two external monitors: "Sill
lets me pick individual windows or Desktop, but I can’t find a way to choose which physical display
Desktop mode shows"), with #139 closed into it (xeonforcecz: "click "Desktop" icon for next monitor
switch. Then the "Desktop" icon would then show the screen number"). Noah's decision on #91:

> the tapping method. The Desktop button shows which desktop the stream is on, a monitor or the
> virtual display, and when there is another one it says so and a tap moves to the next. With one
> display it is the plain Desktop button as today.

Wire, host and device; additive (the compatibility floor in CLAUDE.md). The run that started this
branch took a default for every open question below.

## The problem

The Desktop source captures `catalog.display`, which `WindowCatalog.refreshWindows` sets to
`SCShareableContent.displays.first` (with Virtual Display on, the display whose ID is
`CGMainDisplayID()`, so Sill's own virtual display is never taken). macOS does not order that list,
so on a Mac with two or three displays the Desktop is whichever comes first, not necessarily the one
with the menu bar, and nothing on the device can pick another. The device's Desktop button sends
kind 6 `{"desktop":{}}`; the window list says nothing of displays.

## Decision

### In one paragraph

The Mac lists its displays in every window list (`displays`, each with its ID, name, size in
points and whether it is the main one, and `desktopDisplay`, the one the Desktop shows), main first
and then the others as they stand to its right, so a tap moves one display to the right and from the
rightmost round to the leftmost. Sill's own virtual display is never listed (below). A device's
pick of the Desktop may name one of them (`{"desktop":{"display":N}}` in kind 6): the Mac streams
that display's desktop, keeps it for the Desktop through restarts and window picks, and every
device sees the same one; a pick without a display (every device until now) gets the main display.
On the device, with two or more displays listed, the Desktop button's label says which one the
Desktop shows, "1 of 2" under its symbol where it said "Desktop", and while the Desktop streams a
tap moves to the next (wrapping); from a window a tap shows the display the label names. VoiceOver
hears "Desktop, Built-in Display, 1 of 2" and, while the Desktop streams, "Shows the next display,
LG UltraFine." With one display, or a Mac from before, the button is exactly today's: its label, its
words, its pick. A display the Desktop streams that goes away (unplugged, or the lid closed under a
monitor) gives way to the main display at once, with a line in the log. The rules are pure:
`DesktopDisplays` on the Mac, `DisplayStepping` on the device, checked together in
`Tests/checks/display-stepping`.

### The wire

Additive both ways; no new kind (29–31 and 33–44 stay where open pull requests put theirs).

- **Kind 2, the window list** gains two optional keys, the shape pull request #66 (the Mac viewer)
  gave them, so whichever lands second reconciles only code:
  - `displays: [DisplayInfo]?` — the Mac's displays in the order above. `DisplayInfo` is `{id,
    name, width, height, main}`: `id` the display's `CGDirectDisplayID` (UInt32), `name` the name
    macOS gives it (NSScreen's `localizedName`: "Built-in Retina Display", "LG UltraFine"), `width`
    and `height` its size in points (Double, as #66 has them, so a later host's fractional size
    never fails a device's decoding of the whole list), `main` true for the display with the menu
    bar (optional, as #66 has it). Nil from every host before this change, and from a host that
    cannot read its displays (no Screen Recording). A synthetic host lists its test pattern as one
    display (or more, TEST ONLY: `SILL_TEST_DISPLAYS`, below).
  - `desktopDisplay: UInt32?` — the display the Desktop shows: the one it streams while it
    streams, else the one it streamed last (the last Desktop pick's), else the main one. The run's
    brief asked for this as a flag on each entry ("whether it is the one the Desktop streams now");
    one key beside the list says the same once, in #66's shape, and cannot name two.
- **Kind 6, a pick** (JSON `StreamSource`): the Desktop's object may carry the display,
  `{"desktop":{"display":69733632}}`. `SourcePick` (Switcher.swift) writes and reads it; without a
  display it writes exactly `{"desktop":{}}`, byte for byte what `StreamSource.desktop` writes.
  An older host decodes it as `StreamSource` and gets `.desktop` (the synthesized decoder reads the
  Desktop's object with an empty set of keys and ignores the rest: checked against v0.5.1's
  StreamProtocol, Results). A display on a window's or `none`'s pick is ignored; one that is not a
  number reads as none.
- **Who sends what:** a device sends a display only when the Mac's last window list listed two or
  more (so never to a host from before, which lists none, and never with one display: the pick is
  today's bytes); a host reads it from any device. A device from before sends none and gets the
  main display.

### The rule (the Mac: `DesktopDisplays`, StreamCoordinator, WindowCatalog)

1. **The list.** Every display `SCShareableContent` lists, but Sill's own virtual displays
   (vendor ID `VirtualStage.vendorID`): the main display (`CGMainDisplayID()`) first; then those
   whose left edge is at or right of the main one's, left to right; then those to its left, left to
   right (top to bottom, then by ID, where two share a left edge). Names from NSScreen, read when the
   displays change; a display NSScreen does not know yet (the CLI has no AppKit loop to learn of a
   new one) is "Built-in Display" or "Display". Names go through `SafeText.label`.
2. **A pick of the Desktop** with a display listed streams that display; without one, the main
   display; with one not listed (gone meanwhile, or never this Mac's), the main display and a line
   ("Desktop: display 3 is not connected; streaming Built-in Retina Display (1 of 2), the main
   display."). The pick sets the Desktop's display for every device (`desktopDisplay`).
3. **Restarts keep it.** A settings change, a rate change, the encoder's fallback or return, a
   viewport: the Desktop restarts on its display. Picking a window keeps it too, so the Desktop
   button, and a pick of the Desktop that names it, go back to it. A pick that named none keeps
   meaning the main display: after the main display changes (System Settings › Displays, the menu
   bar dragged to another), a restart shows the new main one, as a pick from a device from before
   would.
4. **A pick of another display during a restart of the Desktop** waits for that restart and runs
   after it (the rule picks of another source follow, `handlePick`); one of the display being
   restarted needs nothing.
5. **A display gone while the Desktop streams it** (the catalog's poll no longer lists it, or its
   capture stops and it is no longer online): the Desktop restarts on the main display, with a line
   ("Desktop: LG UltraFine is gone; streaming Built-in Retina Display, the main display, instead.");
   the devices see the new list. When the capture stopped first, the displays are read again before
   the restart, so the main display is the one macOS names now (a lid closed under a monitor makes
   that monitor main), not the one of the catalog's last look.
6. **The log.** With two or more displays, the stream's line says which: "Streaming the whole
   desktop of LG UltraFine (2 of 2) at 3024×1964, 60 fps, 40 Mbps"; with one, it is today's line
   ("Streaming the whole desktop at …"), and a synthetic host with one test pattern prints exactly
   what it printed (H2).
7. **Where input lands, the pointer, the re-check's test size:** the streamed display's frame and
   size, as the Desktop's always were.
8. **Sill's own virtual display is left out.** It exists only while a window is staged on it
   (Virtual Display on), and a Desktop pick releases the stage before the Desktop's capture starts
   (select's virtual-display block: "none or desktop puts the window back and removes the
   display"), so a Desktop of it would remove what it picked. Kept alive for it, its picture would be
   the staged window on an envelope display many times the window's size (a square of the panel's
   longer edge ÷ 0.5), wallpaper around it, which the window's own stream shows better, and every
   other window is moved off it (the eviction scan), so it has no desktop of its own. Listed, it would
   come and go with every window picked in that mode, and the devices' "1 of 2" would become "1 of
   3" and back. Other virtual displays macOS lists (Sidecar, AirPlay, a dummy display) are listed
   and stream like any monitor: "a monitor or the virtual display" holds for them.

### The rule (the device: `DisplayStepping`, StreamClient, the three bars)

1. **The steps.** The Mac's `displays` when it lists two or more (in its order, a duplicate ID
   dropped); else none, and the button is today's.
2. **The display shown.** This device's own pick while it stands (below), else the Mac's
   `desktopDisplay` if listed, else the main one, else the first.
3. **A tap.** With no steps: today's pick, `{"desktop":{}}`. While the Desktop streams: the next
   display after the one shown, wrapping. Otherwise (a window, or nothing): the display shown, as
   the label says.
4. **The button.** With steps, its label is "1 of 2" (the display shown, of how many) where it said
   "Desktop": the symbol stays, so it reads as Aa's "1×" under "Aa" does. The button keeps its size
   in every bar: the landscape bar (TopBar), the iPad's portrait window bar, a phone's row 1 (five
   to a row, six beside Menus with Larger Picture), and its light (the Desktop streaming).
5. **VoiceOver.** With steps: "Desktop, Built-in Display, 1 of 2", and as its hint "Shows the next
   display, LG UltraFine." while the Desktop streams, "Shows this display’s desktop." otherwise
   (Apple's hint form: the result, no gesture named, since Switch Control and Voice Control users do
   not double tap). A phone's Large Content Viewer shows "Desktop, 1 of 2". Without: today's "Show
   the full Mac desktop", no hint.
6. **A pick that stands.** The display a tap picks shows at once and holds until the Mac's list
   names it (or another), no longer lists it, or max(3 s, 4 × the worst recent round trip) passes:
   two quick taps step twice, and a lost pick shows the Mac's word again.
7. **The device's own Desktop requests** (on a connection's first list, when the Mac stopped the
   Desktop, after a watched window closed, a move's resume, a gesture made over a window) pick the
   display shown, as a tap from a window does; with no steps, today's pick.

### Test hooks (TEST ONLY)

- `SILL_TEST_DISPLAYS=N` (2 to 4), honoured only by a `--synthetic` host (anywhere else one line
  says it is ignored): its Desktop is N test patterns, "Test Pattern" (1512×949 pt, the main one)
  then "Test Pattern 2" (1440×900), 3 (1280×800) and 4 (1920×1080), side by side, each its own
  grey (2 to 4 tinted, so a photo tells them apart). `N@S`: the last of them goes away S seconds
  after the host starts, as an unplugged display. One line at start says so.
- `Scripts/sillclient.py`: `--pick=desktop:N@T` (and the positional `desktop:N`) sends
  `{"desktop":{"display":N}}`; each window list line shows `displays=` and `desktopDisplay=`.
- The device: `-SillDisplays N` (the mock's Mac lists N displays: "Built-in Retina Display" and "LG
  UltraFine", then "DELL U2723QE" and "Sidecar Display"; 0 or none: no list, as a Mac from before);
  `-SillInputScript`'s `desktop` step (the Desktop button's action, with the rest of the script's
  guard: a loopback test host only); the console's `desktop button: …` line whenever the button's
  face changes (DEBUG).

### Where it meets the open pull requests

- **#66** (the Mac viewer; #72 and #73 on it): `DisplayInfo`, `WindowList.displays` and
  `desktopDisplay` are its names and shape, word for word; it picks the Desktop's display with a kind
  40 `PickDisplay {display}` and lists every display as a Desktop window (`DesktopWindow`), its catalog
  keeping `realDisplays` and `desktopDisplayID`. Whichever lands second keeps one `DisplayInfo`, one
  catalog rule (this one's order, its own filter of Sill's displays) and both picks (kind 6's display
  here, kind 40 there) setting the one `desktopDisplayID`.
- **#156 and #161** (the device desktop: a virtual display of the device's size made main while the
  Desktop streams): their catalog filters Sill's displays (vendor `VirtualStage.vendorID`) out of the
  Desktop's real screen, as `DesktopDisplays.ordered` does; `preferMainDisplay`, which both change, is
  gone here (the main display always leads). While their device desktop is main, the main display is
  not listed here, and the first listed stands in for it; whichever lands second decides whether the
  device desktop is the Desktop's display while it lives (it is, there: their Desktop is that display).
  #156's second tap on Desktop (its full screen) is out since Noah's word on #92 (a Settings toggle and
  a shake), so a tap while the Desktop streams is free for the next display.
- **#158** (visionOS, a coordinator per session): each would keep its own Desktop display.
- **#173** (addhumal, opened 2026-10-19 at f1189e7, "Closes #91"): the same decision built
  separately, so only one of the two should land. Read from its diff (nine files, 199 lines added):
  - *The wire.* The same `DisplayInfo`, `displays` and `desktopDisplay` (#66's shape, as here), so a
    device of either reads the other's lists. The pick differs: #173 puts the display beside the
    Desktop's object, `{"desktop":{},"display":N}` (`DesktopPick`), this branch inside it,
    `{"desktop":{"display":N}}` (`SourcePick`). A host from before reads either as the Desktop (the
    synthesized decoder ignores keys it does not know at both levels), and neither host reads the
    other's: a device of one against a host of the other steps nothing, its taps showing the
    Desktop.
  - *The label.* #173: "Desktop 1", "Desktop 2" in "Desktop"'s place, which says which display but
    not that there is another; VoiceOver "Built-in Retina Display (1 of 2), showing now. Tap for
    Studio Display." (the gesture named), "Show Built-in Retina Display (1 of 2)" from a window.
    Here: "1 of 2", which says which and of how many (Noah: "when there is another one it says so"),
    narrower in the phone's 42 pt buttons; VoiceOver "Desktop, Built-in Retina Display, 1 of 2" with a
    hint in Apple's form. With one display both are today's button.
  - *The rules.* #173 orders the displays main first, then by display ID (here: by where they
    stand, so a tap moves one display to the right). A pick without a display (a device from before,
    and #173's own automatic Desktop requests, which never name one) keeps the display picked last
    (here: the main display, as before #91). No line says which display streams. A display that goes
    while the Desktop shows it ends the stream (the capture stops and nothing streams) until the
    device asks for the Desktop again, and the catalog's next look names the main display in the list
    while the old capture may still run (here: the main display at once, with a line). A pick of
    another display while the Desktop restarts is queued as `.desktop`, which select's defer drops
    because the Desktop is what streams, so the list can name a display the stream does not show
    (here: a pick of another display waits for the restart and runs after it, rule 4). Two quick
    taps step once (the second reads the Mac's list before it changes) and restart the Desktop twice
    (here: a pick stands, device rule 6).
  - *What backs it.* #173: eight cases and five mutants in `compatibility`, the builds; no rule of
    the host's or the device's in a check, no test host with two displays, no live run, no docs.
    Here: `display-stepping` (105 checks, 42 mutants, 4,000 random sessions through a model of a Mac
    and its devices), `compatibility` and `protocol`, `SILL_TEST_DISPLAYS`, the live gates below, the
    docs and the site's words.
  - *Which should land.* This branch: it does what Noah decided on #91 in every bar, keeps every
    device from before on the main display as today, and its host rules hold through restarts and
    unplugging. #173's author got there first, so the pull request for this branch credits the
    report and #173 (Noah's call whether to close #173 in its favour). Were #173 to land instead, it
    would need the label to say how many ("1 of 2"), the dropped pick during a restart fixed, the
    fallback when a display goes, and the docs.

## Open questions for Noah (the default is taken unless Noah says otherwise)

1. **Sill's own virtual display.** Default: **left out** (rule 8). The alternative keeps a staged
   window's display alive while its Desktop streams (a VirtualStage change), showing the staged
   window on its envelope display.
2. **The label.** Default: **"1 of 2" under the symbol, in "Desktop"'s place** (Aa's precedent),
   which says which display and that there is another, and fits every bar's narrowest button (42 pt
   in Larger Picture's six). Alternatives: "Desktop" kept with the number drawn on the symbol's screen
   (#139's ask), or the display's short name ("Built-in", "LG"), which does not fit the narrow
   buttons and repeats for two identical monitors.
3. **The order.** Default: **the main display first, then the others as they stand to its right,
   then those to its left**, each left to right, so a tap moves one display to the right and wraps.
   The alternative: the main one, then the rest left to right.
4. **A tap from a window.** Default: **the display the label names** (the Desktop's last). The
   alternative: always the main display.
5. **One Desktop for every device.** Default: **the Mac's** (a pick sets it for all, as the Desktop
   was always shared). The alternative is a display per device, which one stream cannot show.
6. **Remembered across launches.** Default: **no**: Sill for Mac starts on the main display (the
   issue's "optionally remember the preferred display"). The alternative saves the display's ID.
7. **A display unplugged while the Desktop shows it.** Default: **the main display at once**, with
   a line (rule 5). The alternative stops the stream, as before, and lets the device ask again.
8. **VoiceOver's words.** Default: the label "Desktop, ‹name›, 1 of 2" and a hint saying what a tap
   does (the next display, by name; or this display's desktop). The run's brief said "double tap for
   the next display": the hint says it without naming the gesture.
9. **A pick that stands** (device rule 6). Default: **this device's pick shows at once** and holds
   until the Mac confirms or 3 s pass. The alternative waits for the Mac's list each time (a second
   tap within a round trip then picks the same display again).
10. **The Mac's menu card and the device's Settings panel** say "Whole Desktop" as before; only the
   log names the display. The alternative names it in the card's Desktop row with several displays.
11. **The tour** says nothing of it. The alternative adds a line to the bar card when the Mac lists
   several displays.
12. **One display listed.** Default: **the list carries it** (one entry), and the device shows
   today's button. The alternative leaves the keys out with one display.

## Test plan

Hard rules: only this worktree; nothing on Noah's devices, Sill.app, his windows, his displays or
his keychain; never the hardware encoder: every host `--synthetic` with `SILL_TEST_LOOPBACK=1
SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`, each under a minute and killed by PID;
simulators private and deleted after, `simctl io screenshot` only; DerivedData inside the worktree.

| # | Check | Pass when |
|---|---|---|
| H1 | `swift build -c release`; iOS Debug for the simulator as CI builds it, Release for the simulator, Debug for a generic device, `CODE_SIGNING_ALLOWED=NO` | Built, only the known CaptureProbe and `StreamClient` capture warnings |
| H2 | The CLI's stdout against origin/main's (each from `git archive`), idle 35 s and with a client picking the Desktop, masked and sorted | Identical |
| H3 | `Tests/checks/display-stepping`: the wire, the host's order and choice and lines, the test displays' spec, the device's steps, shown, tap, face and standing pick, random sessions through a model of a Mac and its devices; mutants of each rule | All pass, every mutant caught |
| H4 | `compatibility` and `protocol` with the new fields; the payloads read by v0.5.1's StreamProtocol | All pass; v0.5.1 reads the list and takes the pick as the Desktop |
| H5 | `Tests/checks/run-all.sh` | All pass |
| H6 | `sillclient.py` against a synthetic host with `SILL_TEST_DISPLAYS=2` (and `3`, and `2@S`): the list, a pick of each display, of none, of an unknown one; a restart (a settings change) on display 2; the unplug | The list and the lines as the rule says; the stream's size follows the display |
| H7 | `sillclient.py` with `--pick=desktop:2` against v0.5.1's SillHost | It streams its Desktop, nothing refused |
| S1 | Harness photos at the Duo's four sizes, an iPad's and a phone's: `-SillDisplays 1` and none against origin/main's build; `-SillDisplays 2`, the Desktop and a window streaming | One display and none pixel for pixel main's; two: "1 of 2" in every bar |
| S2 | Live on a private iPad simulator against `SILL_TEST_DISPLAYS=2`: `-SillInputScript` taps Desktop from a window, then twice more | The host's lines name each display in turn; the button's label follows (console and photos) |
| S3 | Live against v0.5.1's SillHost | Today's button; the pick is `{"desktop":{}}`; the host streams |
| S4 | VoiceOver's words (`-SillAXDump`) with two displays | "Desktop, …, 1 of 2" and its hint |

## Results

On this Mac (macOS 27, Xcode 27.1 27A9275), 2026-10-20, shared with other agents' builds and
simulators: load averages of 400 to 1,000 throughout. Every host was `--synthetic` with
`SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`, under a minute but for the
live gates' (S2: five minutes), and was ended with SIGTERM: a job a script starts in the background
inherits SIGINT ignored, and the CLI keeps an ignored signal ignored (`HostShutdown.installKeyRelease`,
as for `nohup`), so a `kill -INT` there does nothing.

- **H1, the builds.** `swift build -c release` from a clean `git archive` of 7cc8bcc: only the
  CaptureProbe warning. The iOS app, `CODE_SIGNING_ALLOWED=NO`: Debug for the simulator as CI builds
  it, Release for the simulator and Debug for a generic device, each built with only the known
  `StreamClient` capture warning (StreamClient.swift:3830) and appintentsmetadataprocessor's
  "Metadata extraction skipped" note.
- **H2, the CLI against main's.** origin/main at 9a8e30c and this branch, each from `git archive`:
  idle 35 s, the stdout identical masked and sorted (7 lines); with a client picking the Desktop for
  12 s, every line but the `[1s]` stats identical in order (12 lines) and 13 stats lines each. In the
  first pair one of the branch's seconds counted `net.dropped 1` (the loopback client slow to read at a
  load average of 900); two more pairs had none in any of the four runs, the rest as before.
- **H3, the check.** `Tests/checks/display-stepping`: 105 checks, among them 4,000 random sessions
  (160,000 steps: 41,104 taps judged from the Desktop and 10,966 from a window, 23,440 older devices'
  picks, 6,568 displays unplugged, 1,927 of them under the Desktop, 3,432 full turns); 42 of 42
  mutants caught. The run that built it had one survivor ("none named: the first, not the main
  one"); the case of the main display listed second catches it.
- **H4, the wire.** `compatibility` 121 checks and 29 of 29 mutants; `protocol` 193 + 8; `clipboard`
  259, and the two of its mutants that change the window list's initializer (one's pattern followed
  the new parameters) caught. Every other `clipboard` mutant's pattern (72 in all) and every one of
  `protocol`'s (24) is still found once in its file; their full runs were stopped at an hour's pace
  for 72 compiles. v0.5.1's StreamProtocol (`git archive v0.5.1`), compiled with a reader of the
  payloads the compatibility check writes: the window list with `displays` and `desktopDisplay`
  decodes, and `{"desktop":{"display":69733632}}` reads as `.desktop`.
- **H5.** `Tests/checks/run-all.sh`: RUNALL
- **H6, the host's rules (`sillclient.py` against this branch's CLI).** `SILL_TEST_DISPLAYS=2`, the
  client picking the Desktop, then `desktop:2` at 4 s, a bitrate at 8, `desktop` at 12 and
  `desktop:99` at 16: "TEST: the Desktop is 2 test patterns (SILL_TEST_DISPLAYS), Test Pattern
  1512×949, Test Pattern 2 1440×900.", then "Streaming a synthetic test pattern for Test Pattern (1
  of 2) (software encoder) at 1512×948", "… for Test Pattern 2 (2 of 2) … at 1440×900", the bitrate's
  restart on Test Pattern 2 at 25 Mbps, Test Pattern (1 of 2) for the pick that names none, and
  "Desktop: display 99 is not connected; streaming Test Pattern (1 of 2), the main display."; every
  window list `displays=1:Test Pattern:1512x949:main,2:Test Pattern 2:1440x900` with
  `desktopDisplay` 1, 1, 2, 2, 1, 1 (the first before anything streamed). `SILL_TEST_DISPLAYS=3`, `desktop:2` at 4 s and `desktop:3` 20 ms
  later, during the restart: Test Pattern 2, then Test Pattern 3 (3 of 3) once it had started.
  `SILL_TEST_DISPLAYS=2@10` with `desktop:2` at 3 s: "TEST: Test Pattern 2 goes away
  (SILL_TEST_DISPLAYS).", "Desktop: Test Pattern 2 is gone; streaming Test Pattern, the main display,
  instead.", the stream's line as it always was (one display left), and the last list with one
  display, `desktopDisplay` 1.
- **H7, against v0.5.1's CLI.** `desktop:2` and `desktop:69733632` from the client: the Desktop
  restarted for each (as any Desktop pick does there), nothing refused, its lists without
  `displays`.
- **S1, photos.** PHOTOS
- **S2, live.** LIVE
- **S3, against v0.5.1's host.** OLDHOST
- **S4, VoiceOver's words.** AXDUMP

## Progress

- 2026-10-20: the plan; the wire, the host, the device, the check, the docs (4dbe37b to ec59d30),
  the AX dump's hints (c56ed70); a run cut off by a usage limit and by CoreSimulatorService wedged
  for two hours.
- 2026-10-20, the next run: read what the first had built and kept it; main at 9a8e30c (#136)
  merged in (ci.yml's matrix and CLAUDE.md's Layout, both sides kept); a stopped capture's display
  read again before the restart (7cc8bcc); #173 in the plan; the Results.
