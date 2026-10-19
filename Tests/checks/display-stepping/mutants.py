"""Mutants of DesktopDisplays.swift (Sources/SillHost), DisplayStepping.swift (iOSClient) and SourcePick in
Switcher.swift (Sources/StreamProtocol): each changes one file in one place, is compiled with the check by
build.sh and must make the check fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
HOST = "Sources/SillHost/DesktopDisplays.swift"
DEVICE = "iOSClient/DisplayStepping.swift"
WIRE = "Sources/StreamProtocol/Switcher.swift"
ORDER = "        return [main] + right + left\n"
MUTANTS = [
    # The host's order (rule 1)
    ("Sill's own virtual display listed", HOST, "displays.filter { !$0.isSill && seen.insert($0.id).inserted }",
     "displays.filter { seen.insert($0.id).inserted }"),
    ("a duplicate ID kept", HOST, "displays.filter { !$0.isSill && seen.insert($0.id).inserted }", "displays.filter { !$0.isSill }"),
    ("the main display last", HOST, ORDER, "        return right + left + [main]\n"),
    ("the left ones before the right ones", HOST, ORDER, "        return [main] + left + right\n"),
    ("one at the main one's left edge counts as on its left", HOST, "rest.filter { $0.frame.minX >= main.frame.minX }",
     "rest.filter { $0.frame.minX > main.frame.minX }"),
    ("right to left", HOST, "if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }",
     "if a.frame.minX != b.frame.minX { return a.frame.minX > b.frame.minX }"),
    ("the lower first on one left edge", HOST, "if a.frame.minY != b.frame.minY { return a.frame.minY < b.frame.minY }",
     "if a.frame.minY != b.frame.minY { return a.frame.minY > b.frame.minY }"),
    ("no stand-in for a missing main display", HOST, "guard let main = own.first(where: { $0.isMain }) ?? own.first else { return [] }",
     "guard let main = own.first(where: { $0.isMain }) else { return [] }"),
    # The display a pick streams (rule 2)
    ("a pick's display ignored", HOST, "        if let asked, let d = listed.first(where: { $0.id == asked }) { return d }\n", ""),
    ("none named: the first, not the main one", HOST, "        return listed.first(where: { $0.isMain }) ?? listed.first\n    }",
     "        return listed.first\n    }"),
    # The list's entries, the lines, the names
    ("main written on every display", HOST, "main: $0.isMain ? true : nil)", "main: $0.isMain)"),
    ("width and height swapped", HOST, "width: Double($0.frame.width), height: Double($0.frame.height)",
     "width: Double($0.frame.height), height: Double($0.frame.width)"),
    ("one display named in the stream's line", HOST, "guard listed.count > 1, let i", "guard listed.count > 0, let i"),
    ("which counts from 0", HOST, 'return "\\(d.name) (\\(i + 1) of \\(listed.count))"', 'return "\\(d.name) (\\(i) of \\(listed.count))"'),
    ("the main display not said", HOST, '(d.isMain ? ", the main display" : "")', '""'),
    ("NSScreen's name not cleaned", HOST, 'let clean = SafeText.label(localized ?? "")', 'let clean = localized ?? ""'),
    ("the stand-in names swapped", HOST, 'return builtIn ? "Built-in Display" : "Display"', 'return builtIn ? "Display" : "Built-in Display"'),
    # TEST ONLY: SILL_TEST_DISPLAYS
    ("one test display taken as a spec", HOST, "(2...testSizes.count).contains(count)", "(1...testSizes.count).contains(count)"),
    ("any seconds taken", HOST, "guard let seconds = Double(parts[1]), seconds.isFinite, seconds >= 0 else { return nil }",
     "guard let seconds = Double(parts[1]) else { return nil }"),
    ("the test displays on top of each other", HOST, "defer { x += size.width }", "defer { x += 0 }"),
    ("a test display misnamed", HOST, '"Test Pattern \\(i + 1)"', '"Test Pattern \\(i)"'),
    # The device: the steps, the display shown, a tap (rules 1 to 3)
    ("one display steps", DEVICE, "return unique.count >= 2 ? unique : []", "return unique.count >= 1 ? unique : []"),
    ("a duplicate ID stepped through", DEVICE, "let unique = (displays ?? []).filter { seen.insert($0.id).inserted }",
     "let unique = displays ?? []"),
    ("this device's pick never shown", DEVICE, "        if let asked, let i = steps.firstIndex(where: { $0.id == asked }) { return i }\n", ""),
    ("the Mac's word ignored", DEVICE, "        if let desktop, let i = steps.firstIndex(where: { $0.id == desktop }) { return i }\n", ""),
    ("the Mac's word over this device's pick", DEVICE,
     "        if let asked, let i = steps.firstIndex(where: { $0.id == asked }) { return i }\n        if let desktop, let i = steps.firstIndex(where: { $0.id == desktop }) { return i }\n",
     "        if let desktop, let i = steps.firstIndex(where: { $0.id == desktop }) { return i }\n        if let asked, let i = steps.firstIndex(where: { $0.id == asked }) { return i }\n"),
    ("nothing said: the first, not the main one", DEVICE, "return steps.firstIndex(where: { $0.main == true }) ?? 0", "return 0"),
    ("no wrap from the last", DEVICE, "desktopStreams ? (at + 1) % steps.count : at", "desktopStreams ? min(at + 1, steps.count - 1) : at"),
    ("a tap from a window steps too", DEVICE, "desktopStreams ? (at + 1) % steps.count : at", "(at + 1) % steps.count"),
    ("a tap never steps", DEVICE, "desktopStreams ? (at + 1) % steps.count : at", "at"),
    # The face (rules 4 and 5)
    ("the label counts from 0", DEVICE, 'let position = "\\(shown + 1) of \\(steps.count)"', 'let position = "\\(shown) of \\(steps.count)"'),
    ("the hint names the display shown, not the next", DEVICE, 'hint = "Shows the next display, \\(name(steps[next], at: next))."',
     'hint = "Shows the next display, \\(name(steps[shown], at: shown))."'),
    ("the next display's hint from a window too", DEVICE, "        if desktopStreams {\n            let next", "        if true {\n            let next"),
    ("today's button with an empty hint", DEVICE, 'accessibilityLabel: "Show the full Mac desktop", hint: nil,', 'accessibilityLabel: "Show the full Mac desktop", hint: "",'),
    ("today's label changed", DEVICE, 'static let plain = Face(label: "Desktop",', 'static let plain = Face(label: "Desktops",'),
    ("the Mac's names not cleaned", DEVICE, "let clean = SafeText.label(display.name)", "let clean = display.name"),
    # A pick that stands (rule 6)
    ("no floor under the hold", DEVICE, "max(3, 4 * Double(max(rttMs ?? 0, 0)) / 1000)", "max(0, 4 * Double(max(rttMs ?? 0, 0)) / 1000)"),
    ("two round trips, not four", DEVICE, "max(3, 4 * Double(max(rttMs ?? 0, 0)) / 1000)", "max(3, 2 * Double(max(rttMs ?? 0, 0)) / 1000)"),
    ("a pick the Mac took still stands", DEVICE, "guard desktop != asked, steps.contains(where: { $0.id == asked }) else { return false }",
     "guard steps.contains(where: { $0.id == asked }) else { return false }"),
    ("a pick no longer listed stands", DEVICE, "guard desktop != asked, steps.contains(where: { $0.id == asked }) else { return false }",
     "guard desktop != asked else { return false }"),
    ("a pick stands for ever", DEVICE, "        return now - askedAt < hold\n", "        return true\n"),
    # SourcePick
    ("a display kept on a window's pick", WIRE, "self.display = source == .desktop ? display : nil", "self.display = display"),
]
caught = 0
for name, rel, old, new in MUTANTS:
    src = open(os.path.join(WT, rel)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "c")
        mf = os.path.join(t, os.path.basename(rel)); open(mf, "w").write(src.replace(old, new, 1))
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"{os.path.basename(rel)}={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else r.stdout.strip()[-150:]})")
        else:
            print(f"{name}: SURVIVED")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
