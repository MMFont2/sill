# How long a thumbnail is held for its lights — the plan

2026-10-20. Branch `thumbnail-hold` (worktree `/Users/noah/Downloads/wt-thumbnail-hold`) from origin/main
at d1fa97e; line numbers are at d1fa97e. Issue #113. Device app only: no wire change, nothing on the Mac.

**Noah's decision (as the workflow relayed it):** "Create thumbnail hold (by default shorter and
user-adjustable between 1s and 5s, so a setting is required)", after his comment on #113 (2026-10-18):
"Might just lower the time to 2-3s and have it be user adjustable." The workflow's brief: the hold's
length a setting of the device's own in Settings › This iPad (or iPhone), after Share Clipboard and
before Three-Finger Gestures, 1 to 5 s in half seconds, 1 s by default, stored as `Sill.thumbnailHold`
and never sent to the Mac, read aloud by VoiceOver as "Hold to show window controls, 1 second"; a
pressed state from touch-down, without changing the drag's threshold; and why 1.5 s can feel like 4,
measured.

An outside pull request, #164 (addhumal, 2026-10-19), takes on the same issue with a 0.5 s default and
a picker of 0.5, 1, 1.5, 2 and 3 s, and no pressed state. This branch follows Noah's decision; which of
the two goes in is his.

## The problem

**#113** (BrodyOS, an iPad Pro M5): "holding down on a desktop screen in the iPad app takes about 3.5 to
4 seconds for the controls to pop up … half the time I don't know if the press actually worked for a
few seconds because I second guess it." A second person on the issue: "I just didn't understand why I
couldn't see those buttons, yeah indeed the timing is wayyy to long."

**The code.** Every bar draws its thumbnails with one view, `WindowStrip` (StreamScreen.swift:1541):
the landscape bar (`TopBar`, StreamScreen.swift:1247), an iPad's portrait window bar and a phone's row 2
(PortraitStreamScreen.swift:477). Each thumbnail carries `HoldDragOverlay` (StreamScreen.swift:1672), a
UIView with a `UITapGestureRecognizer` (a tap picks the window) and a `UILongPressGestureRecognizer` of
`WindowStrip.holdToOpen`, a fixed 1.5 s (StreamScreen.swift:1560, 1685), `allowableMovement` 12 pt; the
long press opens the lights (`openMenu`, a light impact haptic: an iPad has no Taptic Engine, so none
there) and, held on and moved more than 8 pt, lifts the thumbnail and drags it to a new slot. The
screen root draws the lights over everything (`overlayPreferenceValue`, a 0.25 s spring,
StreamScreen.swift:334). Until the lights come nothing on screen changes: no highlight, no sound, and on
an iPad no haptic. `updateUIView` never touched `minimumPressDuration` (StreamScreen.swift:1692), so a
setting would have reached only thumbnails made after it changed.

**Why 1.5 s can feel like 4.** Measured on a private simulator with the real app (Results, M1–M3):
nothing between the finger and the long press holds it back. The strip is a SwiftUI `ScrollView`, whose
`delaysContentTouches` holds back a touch from *views* until it can tell a scroll, never from gesture
recognizers, so the long press's clock starts at touch-down; it fires at its 1.5 s (main's build) and
the lights show some 30 ms later; the strip's scroll gives way at that moment. What the person meets is
1.5 s with no sign that the press took, three times iOS's own long press (0.5 s, which the reporter
cites), on a device with no haptic: a person who sees nothing when a press usually answers lifts, or
wonders and presses again, and a second press of 1.5 s puts the lights 3 to 4 s after the first touch.
Anything that ends the press before the hold (a finger that creeps more than 12 pt, the strip starting
to scroll under it) starts the count again with the next press, also unseen. So: a shorter default, the
length the person's to set, and the press shown from touch-down; the Debug console now says when a
press ended before the hold and why, for a device that still feels slow.

## The design

### 1. The setting

`ThumbnailHold` (iOSClient/ThumbnailHold.swift, pure, Foundation only; `Tests/checks/thumbnail-hold`):
the range 1 to 5 s, the step half a second, 1 s unless changed (`standard`; `before`, 1.5 s, is what it
was), the UserDefaults key `Sill.thumbnailHold`, what a stored value means (`seconds(stored:)`: a
number; a string, as a launch argument gives one; nothing usable is 1 s; outside the range the nearest
end; between steps the nearest step, a quarter rounding up), the press's look (`look`) and every word.

The Settings panel's This iPad (or iPhone) group (HostSettingsPanel.swift `thisDevice`), after Share
Clipboard and before Three-Finger Gestures, in the order the branches before agreed (Larger Picture on
an iPhone, Share Clipboard while the Mac shares it, then this, then the gestures): a row "Hold to Show
Window Controls" with its value ("1 s") and a stepper, a half second a press, from 1 to 5 s, as iOS's
own Settings › Accessibility › Touch › Touch Accommodations › Hold Duration has; under it the footnote
"How long you touch and hold a window’s thumbnail before Close, Minimize and Full Screen show and you
can drag it to a new place. A thumbnail darkens as soon as you touch it." VoiceOver reads the row as
"Hold to show window controls, 1 second, adjustable" and swipes it up or down a half second at a time
(the value beside it is hidden from VoiceOver, which hears it as the stepper's value). The row is there
whatever the Mac, as the thumbnails are the device's; at accessibility text sizes it stacks, the title
over the value and the stepper (`AdaptiveRow`). Nothing of it is sent to the Mac.

### 2. The hold

`WindowStrip` reads the setting (`@AppStorage` redraws the strip when the panel changes it; the value
itself through `ThumbnailHold.seconds(stored:)`, since the harness's `-Sill.thumbnailHold 2.5` is a
string in UserDefaults) and hands it to every thumbnail of every bar. `HoldDragOverlay.updateUIView`
sets a changed length on the thumbnails already on screen, so the next press waits the new length
without the strip being made again. The drag to a new slot begins from the same hold, so it comes
sooner too; its rules (12 pt before the hold is a scroll, not a hold; 8 pt after it lifts the
thumbnail) do not change.

### 3. The press, shown from touch-down

`ThumbnailPressRecognizer` (StreamScreen.swift), the thumbnail's long press, says when a finger comes
down on it (its own `touchesBegan`: a recognizer gets the touch at once) and when the press ends (its
state's change to failed, cancelled or ended, key-value observed, since the strip's scroll fails it
from outside; at the latest its reset). How it recognizes does not change. `WindowStrip` keeps which
thumbnail is pressed, and `WindowThumbnail` draws `ThumbnailHold.look`: the picture under a black veil
of 22 % at once (an ease of 0.08 s), and the thumbnail at 95 % by the end of the hold (linear over the
whole length, so the lights come as it ends; a fixed ease would be over long before a 5 s hold). Under
Reduce Motion only the veil. A press that ends without the hold (a tap, a scroll of the strip) goes back
over 0.15 s; when the hold fires the press's look goes and the menu's wiggle and 104 % take over, as
before. A swipe across the strip shows the veil only until the scroll takes the touch (about 10 pt),
its short ease keeping that faint.

### 4. The console (DEBUG)

`hold: touch-down on a thumbnail (the hold is 1 s), delivered 0.007 s after the touch`, `hold: held
1.017 s after touch-down (the hold is 1 s): the lights`, `lights: shown 1.045 s after touch-down`,
`hold: the press ended 0.084 s after touch-down, before the hold: another gesture took the touch (the
strip's scroll, say)` (or "the finger lifted", "the finger moved more than 12 pt", "UIKit cancelled the
touch"), and `hold: the finger came up 3.120 s after touch-down` after a hold. On a device, Xcode's
console then measures what the person felt.

### 5. The measurement rig (TEST ONLY)

`Tests/holdrig`: a driver library injected into the real Debug app on a private simulator
(`DYLD_INSERT_LIBRARIES` through `simctl launch`; the app is not changed), which presses thumbnails with
the touch rig's synthesized touches (`Tests/touchrig/TouchSynth`) and stamps, from touch-down, the
thumbnail's long press and tap and the strip's scroll beside the app's own console lines. Scenarios: a
hold, a tap, a swipe across the strip, a finger creeping 7.5 pt during the hold, a hold then a drag.

## Open questions (the default is taken unless Noah says otherwise)

1. **The default.** 1 s, the workflow's brief of Noah's "shorter by default". His comment on #113 said
   2 to 3 s; the reporter cited iOS's 0.5 s (outside the range), and #164 takes 0.5 s.
2. **The range and step.** 1 to 5 s in half seconds, as decided. Nothing under a second: the strip
   scrolls under a finger, and a short hold would open the lights while a finger rests on a thumbnail.
3. **The control.** A stepper with the value beside it, as iOS's own Hold Duration, adjustable by
   VoiceOver. Alternative: a slider with nine detents (wider, harder at accessibility sizes).
4. **The words.** "Hold to Show Window Controls" with "1 s"; VoiceOver "Hold to show window controls,
   1 second". Alternative title: "Thumbnail Hold" (#164's).
5. **The press's look.** A veil from touch-down and a shrink over the hold, drawn, with no haptic (an
   iPad has none; the iPhone keeps its light tap as the lights open). Alternatives: a ring filling round
   the thumbnail; the veil alone; a haptic at touch-down on an iPhone.
6. **The veil on a swipe.** It shows from touch-down, so a swipe across the strip shows it faintly for
   the moment before the scroll takes the touch. Alternative: hold it back about 0.15 s, as a button in
   a scroll view holds its highlight (then it no longer shows from touch-down).
7. **Where.** This iPad, after Share Clipboard and before Three-Finger Gestures, always shown (on a
   phone with Larger Picture too, whose Desktop keeps the thumbnails). Alternative: only while the Mac
   lists windows.
8. **Per device.** Stored on the device and not synced, as the group's other rows.
9. **A trackpad's click and hold.** Not tried: whether iPadOS hands a Magic Keyboard trackpad's (or a
   mouse's) click and hold to the long press as a finger's (Untested, 9).

## Test plan

- **H1** `Tests/checks/thumbnail-hold` (new): the range, the step, the standard, every length (a grid
  from -4 to 10 s by hundredths), what a stored value means (numbers, strings, nothing, other types; a
  UserDefaults registration; the launch argument in a child run), the press's look, every word.
  Mutants, every one caught; in CI's mutants matrix.
- **H2** Builds: the iOS app Debug for the generic simulator exactly as CI builds it, Release for the
  simulator, Debug for a generic device, only the known StreamClient warning; `swift build -c release`
  (no host file changed); `Tests/checks/run-all.sh`, all.
- **H3** Measured with `Tests/holdrig` on a private iPad simulator, main's build against this branch's:
  touch-down to the long press and to the lights, a tap, a swipe across the strip, a creep, a drag,
  and the setting at 1, 2.5 and 5 s.
- **H4** Harness photos on that simulator: the This iPad group at 1000×710 and 710×1000, default and
  accessibility-extra-large text; the same screens from main's build, pixel for pixel but the new row;
  the bars sideways and upright with nothing pressed, pixel for pixel main's; a thumbnail pressed
  (`-SillThumbnailPress 1`).

## Untested, for Noah

On the iPad (the reporter's is an iPad Pro M5) with a Debug build of this branch (Xcode's console has
the `hold:` and `lights:` lines), against Sill.app from main or this branch (nothing on the Mac changed):

1. **The hold.** Touch and hold a thumbnail: it darkens at once and shrinks a little, and the lights come
   at 1 s (`hold: held 1.0… s after touch-down`, `lights: shown …`). Does it feel like a second?
2. **The setting.** Settings › This iPad › Hold to Show Window Controls: − and + go from 1 s to 5 s by
   half seconds, the value beside them; close Settings, and a hold takes that long; quit and reopen Sill:
   kept. Back to 1 s.
3. **Tap, swipe, drag.** A tap picks the window (a flash of darker, no lights); a swipe across the strip
   scrolls it (no lights; the console: `before the hold: another gesture took the touch` or `moved more
   than 12 pt`); hold, then drag: the thumbnail moves to a new slot, as before.
4. **Every bar.** The iPad upright (the window bar under the picture) and the iPhone upright (row 2) and
   sideways: the same.
5. **VoiceOver.** The row: "Hold to show window controls, 1 second, adjustable"; a swipe up makes it
   1.5 seconds. A thumbnail's actions (Close, Minimize, Full screen, Move left or right) as before.
6. **Reduce Motion** (Settings › Accessibility › Motion): a press only darkens.
7. **The largest text sizes:** the row stacks, the title over the value and the stepper.
8. **If a hold still feels long:** what the console says between touch-down and the lights, and
   whether a press ends before the hold while the finger stays put.
9. **A trackpad or mouse** (a Magic Keyboard): click and hold a thumbnail: whether the lights come.

## Results

(In progress.)
