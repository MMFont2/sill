"""Mutants of Sources/SillHost/FitPolicy.swift (docs/fit-by-default-plan.md, issue #70): each changes it in one
place and must make the check (main.swift) fail. A mutant that does not compile is not caught (it would prove
nothing). usage: mutants.py"""
import os, subprocess
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "fit-policy")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/FitPolicy.swift")
orig = open(SRC).read()
MUTANTS = [
    # The fit.
    ("F1 the default at 1.25×", "static let defaultScale = 1.0", "static let defaultScale = 1.25"),
    ("F2 Aa unset fits with the setting off (no setting)", "            guard fitWindows else { return nil }\n", ""),
    ("F3 Aa unset never fits (no default)", "            guard fitWindows else { return nil }\n", "            return nil\n"),
    ("F4 Aa's scale only while the setting is on", "        if let scale {\n", "        if let scale, fitWindows {\n"),
    ("F5 any scale taken", "            guard scales.contains(scale) else { return nil }\n", ""),
    ("F6 a scale off Aa's range falls to the default", "            guard scales.contains(scale) else { return nil }\n",
     "            guard scales.contains(scale) else { return fit(panel: panel, scale: nil, fitWindows: fitWindows) }\n"),
    ("F7 the range from 0.5×", "static let scales: ClosedRange<Double> = 0.25...4", "static let scales: ClosedRange<Double> = 0.5...4"),
    ("F8 the range to 2×", "static let scales: ClosedRange<Double> = 0.25...4", "static let scales: ClosedRange<Double> = 0.25...2"),
    ("F9 Aa's fit called the default's", "            s = scale\n            reason = .textScale\n", "            s = scale\n            reason = .byDefault\n"),
    ("F10 the default's fit called Aa's", "            s = defaultScale\n            reason = .byDefault\n", "            s = defaultScale\n            reason = .textScale\n"),
    ("F13 the scale kept as the default", "        return Fit(size: size, scale: s, reason: reason)", "        return Fit(size: size, scale: defaultScale, reason: reason)"),
    # The size.
    ("Z1 the width not rounded", "let w = (panel.width / scale).rounded()", "let w = (panel.width / scale)"),
    ("Z2 the height rounded down", "h = (panel.height / scale).rounded()", "h = (panel.height / scale).rounded(.down)"),
    ("Z3 times instead of divided", "let w = (panel.width / scale).rounded(), h = (panel.height / scale).rounded()",
     "let w = (panel.width * scale).rounded(), h = (panel.height * scale).rounded()"),
    ("Z4 a side of nothing taken", "        guard w >= 1, h >= 1, w <= maxSide, h <= maxSide else { return nil }\n",
     "        guard w >= 0, h >= 0, w <= maxSide, h <= maxSide else { return nil }\n"),
    ("Z5 no longest side", "        guard w >= 1, h >= 1, w <= maxSide, h <= maxSide else { return nil }\n",
     "        guard w >= 1, h >= 1 else { return nil }\n"),
    ("Z6 the longest side for the width alone", "        guard w >= 1, h >= 1, w <= maxSide, h <= maxSide else { return nil }\n",
     "        guard w >= 1, h >= 1, w <= maxSide else { return nil }\n"),
    ("Z7 a longest side of 8,192", "static let maxSide: CGFloat = 16_384", "static let maxSide: CGFloat = 8_192"),
    # The compare and a move.
    ("C1 a tolerance of 3", "static let tolerance: CGFloat = 2", "static let tolerance: CGFloat = 3"),
    ("C2 the tolerance's own edge counted", "abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance",
     "abs(current.width - target.width) >= tolerance || abs(current.height - target.height) >= tolerance"),
    ("C3 the width alone compared", "abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance",
     "abs(current.width - target.width) > tolerance"),
    ("C4 the height alone compared", "abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance",
     "abs(current.height - target.height) > tolerance"),
    ("C5 a move of a point not counted", "abs(after.width - before.width) >= 1 || abs(after.height - before.height) >= 1",
     "abs(after.width - before.width) > 1 || abs(after.height - before.height) > 1"),
    ("C6 a move of the height not counted", "abs(after.width - before.width) >= 1 || abs(after.height - before.height) >= 1",
     "abs(after.width - before.width) >= 1"),
    # Not asking again for nothing.
    ("A1 any window's short ask counts", "            guard let s = short, s.window == window else { return true }\n",
     "            guard let s = short else { return true }\n"),
    ("A2 the size asked ignored", "            return FitPolicy.needsResize(current: s.asked, target: target) || FitPolicy.needsResize(current: s.at, target: current)",
     "            return FitPolicy.needsResize(current: s.at, target: current)"),
    ("A3 where it was left ignored", "            return FitPolicy.needsResize(current: s.asked, target: target) || FitPolicy.needsResize(current: s.at, target: current)",
     "            return FitPolicy.needsResize(current: s.asked, target: target)"),
    ("A4 never remembered", "            short = FitPolicy.needsResize(current: after, target: target) ? Short(window: window, asked: target, at: after) : nil",
     "            short = nil"),
    ("A5 remembered when it got there too", "            short = FitPolicy.needsResize(current: after, target: target) ? Short(window: window, asked: target, at: after) : nil",
     "            short = Short(window: window, asked: target, at: after)"),
    ("A6 never asks again", "            guard let s = short, s.window == window else { return true }\n",
     "            guard let s = short, s.window == window else { return true }\n            if s.window == window { return false }\n"),
    # The setting changed while a window streams.
    ("S1 Aa's fit put back with the setting", "        if scale != nil { return .nothing }\n", ""),
    ("S2 on fits nothing now", "        if fitWindows { return .fitNow }\n", "        if fitWindows { return .nothing }\n"),
    ("S3 off puts back a window never fitted", "        return fitted ? .putBack : .nothing", "        return .putBack"),
    ("S4 off leaves the fit", "        return fitted ? .putBack : .nothing", "        return .nothing"),
    # What the device is told.
    ("P1 the Desktop fitted", "        window && (onVirtualDisplay || fit != nil)", "        onVirtualDisplay || fit != nil"),
    ("P2 the virtual display not counted", "        window && (onVirtualDisplay || fit != nil)", "        window && fit != nil"),
    ("P3 every window fitted", "        window && (onVirtualDisplay || fit != nil)", "        window"),
    # The log.
    ("L1 the default's line in Aa's words", 'let at = fit.reason == .byDefault ? "1×, by default" : "\\(fit.scale)×"', 'let at = "\\(fit.scale)×"'),
    ("L2 Aa's line in the default's words", 'let at = fit.reason == .byDefault ? "1×, by default" : "\\(fit.scale)×"', 'let at = "1×, by default"'),
    ("L3 the size asked for the size taken", 'pt (asked \\(Int(fit.size.width))×\\(Int(fit.size.height)) "', 'pt (asked \\(Int(took.width))×\\(Int(took.height)) "'),
    ("L4 the launch line's words", "is off: a picked window keeps its size until the device sets one with Aa.", "is off."),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "FitPolicy.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile (not caught): {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
