#!/bin/bash
# Which of the Mac's displays the Desktop shows (issue #91; docs/display-stepping-plan.md), both ends.
# DesktopDisplays (Sources/SillHost): the displays a device steps through in their order (the main one
# first, then those to its right, then those to its left; never Sill's own virtual display), the
# display a pick streams (the one it names if listed, else the main one), the window list's entries,
# the lines, and the TEST ONLY test displays (SILL_TEST_DISPLAYS). DisplayStepping (iOSClient): the
# steps, the display shown, what a tap picks (the next while the Desktop streams, the one shown
# otherwise, today's pick with fewer than two), the button's face and VoiceOver's words, a pick that
# stands; with SourcePick's bytes. Then 4,000 random sessions through a model of a Mac and its devices,
# old and new, displays plugged and unplugged. Compiled with StreamProtocol's sources as one module
# (build.sh).
#   Tests/checks/display-stepping/run.sh             compile and run the check
#   Tests/checks/display-stepping/run.sh --mutants   one-line mutants of DesktopDisplays.swift,
#                                                    DisplayStepping.swift and Switcher.swift; each
#                                                    must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
