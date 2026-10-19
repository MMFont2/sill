#!/bin/bash
# TEST ONLY. What ScreenCaptureKit's scalesToFit changes in the host's WindowCapture (closed PR #149 by
# nacben, whose test this extends; issue #70; README.md): the real WindowCapture.swift captures a white
# window of the check's own, and the display under it, on a 1× and a 2× virtual display of its own
# (the host's VirtualDisplay.swift, the private CGVirtualDisplay API), at the sizes the host asks; white
# must fill each frame. Not a pure check: it needs Screen Recording for the app that runs it, the
# window server and an unlocked screen, so it is not in CI or run-all.sh.
#   Tests/capture-fit/run.sh               this worktree's WindowCapture.swift: every case must pass
#   Tests/capture-fit/run.sh --rev REV     WindowCapture.swift as REV has it (origin/main before the fix:
#                                          the cases that ask for more pixels than the source has fail)
# Never another app's window, never input, never the hardware encoder (nothing is encoded); the
# displays exist for a few seconds each and go with the process.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="$PWD/.build/capture-fit"
mkdir -p "$out"
capture="$PWD/Sources/SillHost/WindowCapture.swift"
if [ "${1:-}" = "--rev" ]; then
    git show "$2:Sources/SillHost/WindowCapture.swift" > "$out/WindowCapture.swift"
    capture="$out/WindowCapture.swift"
fi
xcrun swiftc -O -swift-version 5 -module-cache-path "$out/modules" \
    "$capture" Sources/SillHost/VirtualDisplay.swift Tests/capture-fit/main.swift -o "$out/CaptureFit"
if otool -L "$out/CaptureFit" | grep -q VideoToolbox; then echo "REFUSED: it links VideoToolbox"; exit 1; fi
exec "$out/CaptureFit"
