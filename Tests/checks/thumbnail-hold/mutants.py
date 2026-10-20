"""Mutants of ThumbnailHold.swift (iOSClient): each changes it in one place and must make the check
(main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "thumbnail-hold")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/ThumbnailHold.swift")
orig = open(SRC).read()
MUTANTS = [
    ("M1 another key", 'static let key = "Sill.thumbnailHold"', 'static let key = "Sill.thumbnailHoldSeconds"'),
    ("M2 the range from iOS's half second", "static let range: ClosedRange<Double> = 1...5", "static let range: ClosedRange<Double> = 0.5...5"),
    ("M3 the range to 3 s (Noah's comment's top, not his decision's)", "static let range: ClosedRange<Double> = 1...5", "static let range: ClosedRange<Double> = 1...3"),
    ("M4 quarter-second steps", "static let step = 0.5", "static let step = 0.25"),
    ("M5 the standard as before (1.5 s)", "static let standard = 1.0", "static let standard = 1.5"),
    ("M6 the standard at iOS's half second", "static let standard = 1.0", "static let standard = 0.5"),
    ("M7 the last choice left out", "return (0...count).map { range.lowerBound + Double($0) * step }",
     "return (0..<count).map { range.lowerBound + Double($0) * step }"),
    ("M8 not a number kept", "        guard value.isFinite else { return standard }\n", ""),
    ("M9 no clamp at the bottom", "let kept = min(max(value, range.lowerBound), range.upperBound)", "let kept = min(value, range.upperBound)"),
    ("M10 no clamp at the top", "let kept = min(max(value, range.lowerBound), range.upperBound)", "let kept = max(value, range.lowerBound)"),
    ("M11 rounded down to a step", ".rounded(.toNearestOrAwayFromZero) * step", ".rounded(.down) * step"),
    ("M12 a quarter rounds to the even step", ".rounded(.toNearestOrAwayFromZero) * step", ".rounded(.toNearestOrEven) * step"),
    ("M13 steps left off", "return range.lowerBound + ((kept - range.lowerBound) / step).rounded(.toNearestOrAwayFromZero) * step",
     "return kept"),
    ("M14 a stored number ignored", "case let n as NSNumber: return seconds(n.doubleValue)", "case is NSNumber: return standard"),
    ("M15 a stored string not trimmed", "Double(s.trimmingCharacters(in: .whitespacesAndNewlines))", "Double(s)"),
    ("M16 a stored string ignored (the harness's launch argument)",
     "            guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return standard }\n            return seconds(d)",
     "            return standard"),
    ("M17 a string not clamped", "            guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return standard }\n            return seconds(d)",
     "            guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return standard }\n            return d"),
    ("M18 nothing stored is the old 1.5 s", "        default: return standard", "        default: return before"),
    ("M19 a veil when not pressed", "guard pressed else { return Look(dim: 0, scale: 1) }", "guard pressed else { return Look(dim: pressedDim, scale: 1) }"),
    ("M20 Reduce Motion ignored", "scale: reduceMotion ? 1 : pressedScale", "scale: pressedScale"),
    ("M21 Reduce Motion the wrong way round", "scale: reduceMotion ? 1 : pressedScale", "scale: reduceMotion ? pressedScale : 1"),
    ("M22 no veil", "static let pressedDim = 0.22", "static let pressedDim = 0.0"),
    ("M23 no shrink", "static let pressedScale = 0.95", "static let pressedScale = 1.0"),
    ("M24 a shrink you cannot miss", "static let pressedScale = 0.95", "static let pressedScale = 0.8"),
    ("M25 a slow veil", "static let veilIn = 0.08", "static let veilIn = 0.3"),
    ("M26 a slow release", "static let release = 0.15", "static let release = 0.5"),
    ("M27 the shrink a fixed second", "static func shrinkDuration(hold: Double) -> Double { seconds(hold) }",
     "static func shrinkDuration(hold: Double) -> Double { standard }"),
    ("M28 the shrink not clamped", "static func shrinkDuration(hold: Double) -> Double { seconds(hold) }",
     "static func shrinkDuration(hold: Double) -> Double { hold }"),
    ("M29 a trailing .0", 'return s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s)', 'return String(format: "%.1f", s)'),
    ("M30 always seconds", 'return "\\(number(s)) \\(s == 1 ? "second" : "seconds")"', 'return "\\(number(s)) seconds"'),
    ("M31 the spoken value not clamped", "        let s = seconds(value)\n        return \"\\(number(s)) \\(s == 1", "        let s = value\n        return \"\\(number(s)) \\(s == 1"),
    ("M32 the unit run in", 'static func valueText(_ value: Double) -> String { "\\(number(value)) s" }',
     'static func valueText(_ value: Double) -> String { "\\(number(value))s" }'),
    ("M33 another title", 'static let title = "Hold to Show Window Controls"', 'static let title = "Thumbnail Hold"'),
    ("M34 another VoiceOver label", 'static let spokenTitle = "Hold to show window controls"', 'static let spokenTitle = "Thumbnail hold"'),
    ("M35 the footnote without the press", "A thumbnail darkens as soon as you touch it.", "A thumbnail darkens when you hold it."),
    ("M36 a swipe the wrong way", "seconds(seconds(value) + (up ? step : -step))", "seconds(seconds(value) + (up ? -step : step))"),
    ("M37 a whole second a swipe", "seconds(seconds(value) + (up ? step : -step))", "seconds(seconds(value) + (up ? 2 * step : -2 * step))"),
    ("M38 a swipe out of the range", "seconds(seconds(value) + (up ? step : -step))", "seconds(value) + (up ? step : -step)"),
    ("M39 a swipe from the value as given", "seconds(seconds(value) + (up ? step : -step))", "seconds(value + (up ? step : -step))"),
    ("M40 no swipe down", "seconds(seconds(value) + (up ? step : -step))", "seconds(seconds(value) + (up ? step : 0))"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "ThumbnailHold.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
