#!/bin/bash
# ThumbnailHold (iOSClient/ThumbnailHold.swift) on its own: how long a window's thumbnail is held before
# its lights show and it can be dragged (issue #113, docs/thumbnail-hold-plan.md): the range, the step,
# the standard 1 s, what a stored value means (a launch argument's string in a child run), the press's
# look and every word.
#   Tests/checks/thumbnail-hold/run.sh             compile and run the check
#   Tests/checks/thumbnail-hold/run.sh --mutants   one-line mutants of ThumbnailHold.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/ThumbnailHold.swift "$here/main.swift" -o "$out/check"
"$out/check"
