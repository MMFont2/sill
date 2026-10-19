#!/bin/bash
# FitPolicy (Sources/SillHost/FitPolicy.swift; docs/fit-by-default-plan.md, issue #70) on its own: when Sill
# fits a window it streams in regular mode to a device, and to which size (Aa's scale whatever the setting,
# 1× by default with Aa unset, nothing with Fit windows to the device's screen off); the 2 pt compare; the
# memory of fits that left the window as it was; a change of the setting while a window streams; kind 16's
# `stream.fitsPanel`; the log's words. Then 5,000 random sessions of a copy of the coordinator's fit around
# the real rule against a stand-in app (a minimum, a window that cannot be resized, full screen).
#   Tests/checks/fit-policy/run.sh             compile and run the check
#   Tests/checks/fit-policy/run.sh --mutants   one-line mutants of FitPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/FitPolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
