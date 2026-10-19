#!/bin/bash
# holdrig (TEST ONLY; README.md): presses a window thumbnail in the real Debug app on a private simulator
# and stamps, from touch-down, what UIKit does (the thumbnail's long press and tap, the strip's scroll)
# beside the app's own console lines. A driver library is injected at launch (DYLD_INSERT_LIBRARIES
# through simctl); the app itself is not changed.
#
#   Tests/holdrig/run.sh UDID APP NAME [RIG_SCRIPT] [-- launch arguments]
#     UDID   a booted simulator of your own, made for the test (never a shared one)
#     APP    a Debug build of Sill for the simulator (…/Debug-iphonesimulator/Sill.app); it is installed
#     NAME   the log: .build/holdrig/NAME.log
#     RIG_SCRIPT  default "hold 3; tap; swipe; drift; drag" (holdrig.m says what each does)
#   Launch arguments default to the harness's -SillLayout 1000x710 (the mock: no Mac, no network).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/holdrig"
[ $# -ge 3 ] || { sed -n '6,12p' "$0" | sed 's/^# //' >&2; exit 2; }
udid="$1" app="$2" name="$3"; shift 3
script="hold 3; tap; swipe; drift; drag"
if [ $# -gt 0 ] && [ "$1" != "--" ]; then script="$1"; shift; fi
[ "${1:-}" = "--" ] && shift
args=("$@")
[ ${#args[@]} -gt 0 ] || args=(-SillLayout 1000x710)
state="$(xcrun simctl list devices --json | python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["udid"] == sys.argv[1]: print(d["state"])
' "$udid")"
[ "$state" = Booted ] || { echo "holdrig: $udid is not a booted simulator (${state:-none})" >&2; exit 2; }
[ -d "$app" ] || { echo "holdrig: no app at $app" >&2; exit 2; }

mkdir -p "$out"
target=arm64-apple-ios17.0-simulator
xcrun -sdk iphonesimulator clang -target $target -fobjc-arc -Wall -Werror -dynamiclib \
    -I "$here/../touchrig" "$here/../touchrig/TouchSynth.m" "$here/holdrig.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -o "$out/holdrig.dylib"
codesign -s - --force "$out/holdrig.dylib" 2>/dev/null
# A simulator's process cannot read under ~/Downloads, where this repository lives: the library goes in
# the simulator's own data/tmp.
lib="$(xcrun simctl getenv "$udid" HOME)/tmp/holdrig.dylib"
install -m 755 "$out/holdrig.dylib" "$lib"

xcrun simctl install "$udid" "$app"
log="$out/$name.log"
SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="$lib" SIMCTL_CHILD_RIG_SCRIPT="$script" SIMCTL_CHILD_RIG_ROUTE="${RIG_ROUTE:-}" SIMCTL_CHILD_RIG_NORMALIZED="${RIG_NORMALIZED:-}" perl -e 'alarm shift; exec @ARGV' 120 \
    xcrun simctl launch --console-pty --terminate-running-process "$udid" me.saffer.sill "${args[@]}" < /dev/null > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 110); do
    sleep 1
    grep -q '^RIG done' "$log" 2>/dev/null && break
done
xcrun simctl terminate "$udid" me.saffer.sill >/dev/null 2>&1 || true
wait $pid 2>/dev/null || true
rm -f "$lib"
grep -q '^RIG done' "$log" || { echo "holdrig: the run did not finish; see $log" >&2; exit 1; }
echo "holdrig: the log is $log"
