"""Mutants of TextComposition.swift (iOSClient): each changes it in one place, is compiled with the check
(main.swift) and StreamProtocol's Input.swift, and must make the check fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "text-composition")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/TextComposition.swift")
INPUT = os.path.join(ROOT, "Sources/StreamProtocol/Input.swift")
orig = open(SRC).read()
MUTANTS = [
    # The composition stays on the device until it is committed
    ("T1 a typed candidate keeps the composition before it (sent twice)", "        return commit(sent + text)\n", "        return commit(document + text)\n"),
    ("T2 an empty composition stays one", "guard let text, !text.isEmpty else {", "guard let text else {"),
    ("T3 the input method's caret unclamped", "let location = min(max(selected.location, 0), count)", "let location = max(selected.location, 0)"),
    ("T4 the selection's length unclamped", "length: min(max(selected.length, 0), count - location))", "length: max(selected.length, 0))"),
    ("T5 unmark drops the composition", "        guard let marked else { return [] }\n        return commit(sent + marked)",
     "        guard marked != nil else { return [] }\n        return commit(sent)"),
    ("T6 a backspace in a composition also reaches the Mac", "            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))\n            return []",
     "            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))\n            return [.backspaces(1)]"),
    ("T7 a backspace with nothing remembered never reaches the Mac", "guard !sent.isEmpty else { return [.backspaces(1)] }", "guard !sent.isEmpty else { return [] }"),
    ("T8 the marked range at the document's start", "marked.map { NSRange(location: sent.utf16.count, length: $0.utf16.count) }",
     "marked.map { NSRange(location: 0, length: $0.utf16.count) }"),
    ("T9 the caret ignores the input method's selection", "return NSRange(location: sent.utf16.count + markedSelection.location, length: markedSelection.length)",
     "return NSRange(location: length, length: 0)"),
    ("T10 the length leaves out the composition", "var length: Int { sent.utf16.count + (marked?.utf16.count ?? 0) }", "var length: Int { sent.utf16.count }"),
    # Corrections
    ("T11 a correction taken before a forget is typed at the end (the PR's clamp: sent twice)",
     "        guard range.location <= utf16.count else { return [] }\n        let start = max(range.location, 0)\n",
     "        let start = min(max(range.location, 0), utf16.count)\n"),
    ("T12 a correction only at the very end is stale too", "guard range.location <= utf16.count else { return [] }", "guard range.location < utf16.count else { return [] }"),
    ("T13 a range past the end is not cut there", "let end = min(max(range.location + range.length, start), utf16.count)",
     "let end = max(range.location + range.length, start)"),
    ("T14 a correction leaves out what follows its range", "        return commit(before + text + after)\n", "        return commit(before + text)\n"),
    ("T15 a forget drops what is composed, unsent", "        let out = unmark()\n        sent = \"\"\n",
     "        marked = nil\n        let out: [Output] = []\n        sent = \"\"\n"),
    ("T16 a forget forgets nothing", "        let out = unmark()\n        sent = \"\"\n", "        let out = unmark()\n"),
    ("T47 a forget keeps what is composed on the device (the PR's: dropped by the input method at the next key)",
     "        let out = unmark()\n", "        let out: [Output] = []\n"),
    # The tail
    ("T17 what was sent trimmed to 200 characters in every edit (the PR's cut)", "        sent = new\n", "        sent = String(new.suffix(200))\n"),
    ("T18 a trim while an input method composes", "var wantsTrim: Bool { marked == nil && sent.count > Self.limit }", "var wantsTrim: Bool { sent.count > Self.limit }"),
    ("T19 a trim at the limit itself", "var wantsTrim: Bool { marked == nil && sent.count > Self.limit }", "var wantsTrim: Bool { marked == nil && sent.count >= Self.limit }"),
    ("T20 a trim keeps one character less", "sent = String(sent.suffix(Self.keep))", "sent = String(sent.suffix(Self.keep - 1))"),
    ("T21 a trim keeps the front", "sent = String(sent.suffix(Self.keep))", "sent = String(sent.prefix(Self.keep))"),
    ("T22 a trim whenever asked", "        guard wantsTrim else { return }\n        sent = String", "        sent = String"),
    ("T23 a smaller limit", "static let limit = 4_000", "static let limit = 200"),
    # Backspaces and retyping
    ("T24 one backspace too many", "if old.count > common { out.append(.backspaces(old.count - common)) }", "if old.count > common { out.append(.backspaces(old.count - common + 1)) }"),
    ("T25 backspaces counted in code points, not characters", "let old = Array(sent), now = Array(new)",
     "let old = sent.unicodeScalars.map(Character.init), now = new.unicodeScalars.map(Character.init)"),
    ("T26 the first difference one character late", "while common < old.count, common < now.count, old[common] == now[common] { common += 1 }",
     "while common < old.count, common < now.count, old[common] == now[common] { common += 1 }\n        if common < old.count, common < now.count { common += 1 }"),
    ("T27 a commit keeps the composition", "        marked = nil\n        markedSelection = NSRange(location: 0, length: 0)\n        let old",
     "        markedSelection = NSRange(location: 0, length: 0)\n        let old"),
    # Which input moves the Mac's caret
    ("T28 a right click moves no caret", "return action == .leftDown || action == .rightDown", "return action == .leftDown"),
    ("T29 a button's up moves the caret", "return action == .leftDown || action == .rightDown", "return action != .move"),
    ("T30 a key's up moves the caret", "case .key(_, let down, _): return down", "case .key: return true"),
    ("T31 a key moves no caret", "case .key(_, let down, _): return down", "case .key: return false"),
    ("T32 typing moves the caret (nothing is ever revised)", "case .text, .scroll, .scrollGesture: return false",
     "case .text: return true\n        case .scroll, .scrollGesture: return false"),
    ("T33 a scroll moves the caret", "case .text, .scroll, .scrollGesture: return false",
     "case .text, .scrollGesture: return false\n        case .scroll: return true"),
    # Keyboards and ⌃Space
    ("T34 Emoji is a keyboard", "language != \"emoji\" && language != \"dictation\"", "language != \"dictation\""),
    ("T35 dictation is a keyboard", "language != \"emoji\" && language != \"dictation\"", "language != \"emoji\""),
    ("T36 ⌃Space is iPadOS's with one keyboard (the PR's: always)", "return Set(languages().filter(isKeyboard)).count >= 2", "return true"),
    ("T37 ⌃Space is iPadOS's with one keyboard and Emoji", "return Set(languages().filter(isKeyboard)).count >= 2", "return Set(languages()).count >= 2"),
    ("T38 a keyboard in the same language counted twice", "return Set(languages().filter(isKeyboard)).count >= 2", "return languages().filter(isKeyboard).count >= 2"),
    ("T39 ⌃⇧Space is iPadOS's too", "modifiers & (shift | control | option | command) == control", "modifiers & (control | option | command) == control"),
    ("T40 any key with ⌃ is the switch", "guard usage == space, modifiers", "guard modifiers"),
    ("T42 the keyboards asked for at every key", "        guard usage == space, modifiers & (shift | control | option | command) == control else { return false }\n        return Set(languages().filter(isKeyboard)).count >= 2",
     "        let asked = Set(languages().filter(isKeyboard))\n        guard usage == space, modifiers & (shift | control | option | command) == control else { return false }\n        return asked.count >= 2"),
    ("T41 caps lock makes ⌃Space the Mac's", "modifiers & (shift | control | option | command) == control", "modifiers == control"),
    # The document a correction's range was taken in
    ("T43 a forget keeps the document (a correction taken before it lands in what was typed since)",
     "        sent = \"\"\n        generation += 1\n", "        sent = \"\"\n"),
    ("T44 a trim keeps the document", "        sent = String(sent.suffix(Self.keep))\n        generation += 1\n",
     "        sent = String(sent.suffix(Self.keep))\n"),
    ("T45 the document a correction was taken in ignored", "        if let taken, taken != generation { return [] }\n", ""),
    ("T46 every edit starts a new document", "        sent = new\n        return out\n", "        sent = new\n        generation += 1\n        return out\n"),
    # What the text system selects, for its next edit
    ("S1 text typed over a selection is added after it (Korean's syllables twice)",
     "        if marked == nil, let selection { return commit(sentReplacing(selection, with: text)) }\n", ""),
    ("S2 a backspace over a selection deletes one character", "        if let selection { return commit(sentReplacing(selection, with: \"\")) }\n", ""),
    ("S3 an empty selection kept (typing goes where the caret moved)",
     "selection = end > start ? NSRange(location: start, length: end - start) : nil", "selection = NSRange(location: start, length: end - start)"),
    ("S4 a selection kept while an input method composes", "    mutating func select(_ range: NSRange) {\n        guard marked == nil else { return }\n",
     "    mutating func select(_ range: NSRange) {\n"),
    ("S5 a selection not cut at the end", "let end = min(max(range.location + range.length, start), count)", "let end = max(range.location + range.length, start)"),
    ("S6 an edit keeps the selection", "        selection = nil\n        marked = nil\n", "        marked = nil\n"),
    ("S7 a forget keeps the selection", "        generation += 1\n        selection = nil\n        return out\n", "        generation += 1\n        return out\n"),
    ("S8 a trim keeps the selection", "        generation += 1\n        selection = nil\n    }\n", "        generation += 1\n    }\n"),
    ("S9 a composition over a selection keeps the selected text",
     "        if marked == nil, let selection { out = commit(sentReplacing(selection, with: \"\")) }\n", ""),
    ("S10 the selection never reported to the text system", "guard marked != nil else { return selection ?? NSRange(location: length, length: 0) }",
     "guard marked != nil else { return NSRange(location: length, length: 0) }"),
    ("S11 a selection's edit leaves out what follows it", "            + String(utf16CodeUnits: Array(units[upper...]), count: units.count - upper)", "            + \"\""),
    ("S12 a selection one unit short at its start", "let lower = min(range.location, units.count), upper", "let lower = min(range.location + 1, units.count), upper"),
    ("S13 an empty composition drops a selection", "guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); return [] }",
     "guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); selection = nil; return [] }"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "TextComposition.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, INPUT, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    try:
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        print(f"{name}: SURVIVED (timed out)"); continue
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else 'exit status ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
