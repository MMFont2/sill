// TextComposition (iOSClient/TextComposition.swift) on its own: an input method's composition stays on
// the device until it is committed, and every edit the text system makes reaches the Mac as backspaces
// and text that leave the Mac's text equal to the document (#138). What was typed is kept whole while
// the text system may revise it (a long dictation's corrections land where they were made), trimmed only
// past its limit, and a correction whose range was taken before a forget or a trim sends nothing,
// wherever its offsets fall now; what the text system selects is replaced by its next edit (Korean's
// syllables). Then TextInputRules: which input moves the Mac's caret, which input modes are keyboards,
// and whose ⌃Space it is. Scenario by scenario, then 25,000 seeded random edit sequences against a model
// of the Mac's text field.
//   swiftc -O iOSClient/TextComposition.swift Sources/StreamProtocol/Input.swift \
//       Tests/checks/text-composition/main.swift -o check && ./check
import Foundation

typealias C = TextComposition
typealias R = TextInputRules
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

/// The Mac's text field: what the outputs leave there.
func apply(_ outputs: [C.Output], to text: inout String) {
    for output in outputs {
        switch output {
        case .text(let t): text += t
        case .backspaces(let n): text = String(text.dropLast(n))
        }
    }
}

/// A range of whole characters of `s`, in UTF-16 offsets, as UIKit's ranges are.
func utf16Range(_ s: String, characters: Range<Int>) -> NSRange {
    let chars = Array(s)
    let loc = String(chars[..<characters.lowerBound]).utf16.count
    let len = String(chars[characters]).utf16.count
    return NSRange(location: loc, length: len)
}

// MARK: - Scenarios

do {   // Zhuyin: symbols composed, then a candidate committed through insertText
    var c = C()
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    c.setMarked("ㄋㄧˇ", selected: NSRange(location: 3, length: 0))
    check("a composition is not sent", c.sent.isEmpty && c.isComposing && c.markedRange == NSRange(location: 0, length: 3))
    check("the caret sits where the input method put it", c.selectedRange == NSRange(location: 3, length: 0))
    let out = c.insert("你")
    check("the candidate replaces the composition and goes out", out == [.text("你")] && !c.isComposing && c.sent == "你")
}

do {   // a composition accepted as it stands (unmarkText), after text already sent
    var c = C()
    _ = c.insert("a")
    c.setMarked("你好", selected: NSRange(location: 2, length: 0))
    check("the marked range follows what was sent", c.markedRange == NSRange(location: 1, length: 2))
    check("the length is the document's, the composition's included", c.length == 3 && c.document == "a你好")
    check("the caret inside a composition is after what was sent", c.selectedRange == NSRange(location: 3, length: 0))
    check("unmark sends the composition", c.unmark() == [.text("你好")] && c.document == "a你好")
    check("unmark with nothing composed sends nothing", c.unmark() == [])
}

do {   // the input method's caret inside its composition (Japanese, moving between clauses)
    var c = C()
    _ = c.insert("x")
    c.setMarked("きょうは", selected: NSRange(location: 1, length: 2))
    check("a selection inside the composition is kept, after what was sent", c.selectedRange == NSRange(location: 2, length: 2))
}

do {   // backspace inside a composition edits it, outside it reaches the Mac
    var c = C()
    c.setMarked("ㄋㄧ", selected: NSRange(location: 2, length: 0))
    check("backspace in a composition sends nothing", c.deleteBackward() == [] && c.marked == "ㄋ")
    check("the last symbol's backspace ends it", c.deleteBackward() == [] && !c.isComposing)
    check("backspace with nothing remembered still reaches the Mac", c.deleteBackward() == [.backspaces(1)])
    _ = c.insert("你好")
    check("a remembered character is one backspace", c.deleteBackward() == [.backspaces(1)] && c.sent == "你")
}

do {   // an empty composition ends it without sending
    var c = C()
    c.setMarked("ㄅ", selected: NSRange(location: 1, length: 0))
    c.setMarked("", selected: NSRange(location: 0, length: 0))
    check("an empty composition ends it", !c.isComposing && c.sent.isEmpty && c.markedRange == nil)
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    check("a nil composition ends it", !c.isComposing)
}

do {   // dictation corrects a word it already typed
    var c = C()
    var mac = ""
    apply(c.insert("I sea it"), to: &mac)
    apply(c.replace(NSRange(location: 2, length: 3), with: "see"), to: &mac)
    check("a correction deletes back to the change and types the rest", mac == "I see it" && c.document == "I see it")
    let out = c.replace(NSRange(location: 8, length: 0), with: ".")
    apply(out, to: &mac)
    check("an insertion at the end is only typed", out == [.text(".")] && mac == "I see it.")
}

do {   // a long dictation: its corrections land where they were made, however much came before
    var c = C()
    var mac = ""
    var ok = true
    var phrase = 0
    while c.sent.count < 1_500 {
        phrase += 1
        let start = c.length
        apply(c.insert("wurd\(phrase) "), to: &mac)          // the first hypothesis
        apply(c.replace(NSRange(location: start, length: c.length - start), with: "word\(phrase), "), to: &mac)   // corrected
        if mac != c.document { ok = false; break }
    }
    check("a dictation of 1,500 characters corrected phrase by phrase: the Mac's text is the document", ok && mac == c.document)
    check("…and nothing of it was cut from under a correction", c.sent.count >= 1_500 && c.sent.hasPrefix("word1, "))
    let first = utf16Range(c.document, characters: 0..<4)
    apply(c.replace(first, with: "Word"), to: &mac)
    check("a correction at the very start of a long dictation goes there", mac == c.document && mac.hasPrefix("Word1, "))
}

do {   // a replacement over the composition commits it
    var c = C()
    var mac = ""
    apply(c.insert("x"), to: &mac)
    c.setMarked("ni", selected: NSRange(location: 2, length: 0))
    apply(c.replace(NSRange(location: 1, length: 2), with: "你"), to: &mac)
    check("replacing the marked text commits the replacement", mac == "x你" && !c.isComposing)
}

do {   // emoji and combining marks count as one character on the Mac
    var c = C()
    var mac = ""
    apply(c.insert("a👍🏽é"), to: &mac)
    let out = c.deleteBackward()
    apply(out, to: &mac)
    check("one backspace per character, not per UTF-16 unit", out == [.backspaces(1)] && mac == "a👍🏽")
    let utf16 = c.document.utf16.count
    apply(c.replace(NSRange(location: 1, length: utf16 - 1), with: "b"), to: &mac)
    check("a replacement over an emoji deletes it once", mac == "ab")
    let combining = c.insert("e")
    apply(combining, to: &mac)
    let accent = c.insert("\u{301}")
    apply(accent, to: &mac)
    check("a combining mark that joins the last character retypes it whole", accent == [.backspaces(1), .text("é")] && mac == "abé")
}

do {   // a forget (the Mac's caret is about to move: a click, a key, a pick) sends what is composed
       // first, as it stands, where the caret still is, then forgets everything
    var c = C()
    var mac = ""
    apply(c.insert("hello"), to: &mac)
    c.setMarked("ㄏㄠ", selected: NSRange(location: 2, length: 0))
    let out = c.forget()
    apply(out, to: &mac)
    check("a forget sends what is composed, as it stands, before the caret moves", out == [.text("ㄏㄠ")] && mac == "helloㄏㄠ")
    check("…then forgets it all", c.sent.isEmpty && !c.isComposing && c.length == 0 && c.markedRange == nil)
    check("a forget with nothing composed sends nothing", c.forget() == [] && c.sent.isEmpty)
}

do {   // a correction taken before a forget: nothing goes to the Mac
    var c = C()
    var mac = "earlier text "
    apply(c.insert("I sea it"), to: &mac)
    let stale = NSRange(location: 2, length: 3)        // "sea", taken before the Mac's caret moved
    apply(c.forget(), to: &mac)                        // a click on the Mac
    apply(c.insert("x"), to: &mac)                     // typed where the caret is now
    let out = c.replace(stale, with: "see")
    check("a range that starts past the document after a forget sends nothing", out == [] && mac == "earlier text I sea itx")
    check("…and changes nothing here", c.sent == "x" && !c.isComposing)
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    let underComposition = c.replace(NSRange(location: 9, length: 1), with: "y")
    check("…a composition in progress carries on", underComposition == [] && c.marked == "ㄋ")
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    let atEnd = c.replace(NSRange(location: c.length, length: 0), with: "z")
    apply(atEnd, to: &mac)
    check("an insertion at the very end still goes", atEnd == [.text("z")] && c.sent == "xz")
    let overhanging = c.replace(NSRange(location: 1, length: 40), with: "Z")
    apply(overhanging, to: &mac)
    check("a range that starts inside and runs past the end is cut at the end",
          overhanging == [.backspaces(1), .text("Z")] && c.sent == "xZ" && mac == "earlier text I sea itxZ")
}

do {   // dictation's last correction of a phrase (its punctuation and capitals) comes after a click: its
       // range was taken before the forget and reaches into what was typed since
    var c = C()
    var mac = "earlier "
    apply(c.insert("hello"), to: &mac)
    let taken = c.generation
    let phrase = NSRange(location: 0, length: 5)       // "hello", as the text system holds it
    apply(c.forget(), to: &mac)                        // a click on the Mac
    check("a forget starts a new document", c.generation == taken + 1)
    apply(c.insert("x"), to: &mac)                     // typed where the caret is now
    check("typing keeps the document", c.generation == taken + 1)
    let out = c.replace(phrase, with: "Hello.", taken: taken)
    check("a correction taken before a forget sends nothing, even where what was typed since reaches",
          out == [] && mac == "earlier hellox" && c.sent == "x")
    let now = c.replace(NSRange(location: 0, length: 1), with: "y", taken: c.generation)
    apply(now, to: &mac)
    check("…and one taken since goes", now == [.backspaces(1), .text("y")] && mac == "earlier helloy")
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    let marked = c.generation
    let composed = c.forget()
    apply(composed, to: &mac)
    check("a forget while composing sends the composition, then starts a new document",
          composed == [.text("ㄋ")] && mac == "earlier helloyㄋ" && c.generation == marked + 1 && !c.isComposing)
    check("…and a correction of the composition taken before it sends nothing",
          c.replace(NSRange(location: 1, length: 1), with: "你", taken: marked) == [] && c.length == 0 && mac == "earlier helloyㄋ")
}

do {   // Korean: the input method selects the syllables it is still building, deletes them and types them
       // again, as each letter comes (2-Set on a hardware keyboard in the iPad simulator, 2026-10-20: g k s
       // r m f, 한글; ignoring the selection, the Mac got 한한한글)
    var c = C()
    var mac = ""
    apply(c.insert("ㅎ"), to: &mac)
    c.select(NSRange(location: 0, length: 1))
    apply(c.deleteBackward(), to: &mac)
    apply(c.insert("하"), to: &mac)
    c.select(NSRange(location: 0, length: 1))
    apply(c.deleteBackward(), to: &mac)
    apply(c.insert("한"), to: &mac)
    apply(c.insert("ㄱ"), to: &mac)
    c.select(NSRange(location: 0, length: 2))
    check("a selection is kept for the next edit", c.selection == NSRange(location: 0, length: 2) && c.selectedRange == NSRange(location: 0, length: 2))
    let deleted = c.deleteBackward()
    apply(deleted, to: &mac)
    check("a backspace deletes the selection, all of it", deleted == [.backspaces(2)] && mac == "" && c.selection == nil)
    apply(c.insert("한"), to: &mac)
    apply(c.insert("그"), to: &mac)
    c.select(NSRange(location: 1, length: 1))
    apply(c.deleteBackward(), to: &mac)
    apply(c.insert("글"), to: &mac)
    check("Korean's syllables reach the Mac once: 한글", mac == "한글" && c.document == "한글")
}

do {   // a selection's edit, wherever it is, then the caret at the end again
    var c = C()
    var mac = ""
    apply(c.insert("abcd"), to: &mac)
    c.select(NSRange(location: 1, length: 2))           // "bc"
    let out = c.insert("X")
    apply(out, to: &mac)
    check("text typed over a selection replaces it", out == [.backspaces(3), .text("Xd")] && mac == "aXd")
    check("…and the caret is at the end again", c.selection == nil && c.selectedRange == NSRange(location: 3, length: 0))
    c.select(NSRange(location: 1, length: 0))           // the caret moved, nothing selected
    check("an empty selection is not kept: the caret stays at the end", c.selection == nil && c.selectedRange == NSRange(location: 3, length: 0))
    apply(c.insert("e"), to: &mac)
    check("…and typing goes on at the end", mac == "aXde")
    c.select(NSRange(location: 2, length: 99))
    check("a selection past the end is cut at the end", c.selection == NSRange(location: 2, length: 2))
    c.select(NSRange(location: -3, length: 4))
    check("…and one from before the start at the start", c.selection == NSRange(location: 0, length: 1))
    c.select(NSRange(location: 9, length: 2))
    check("…and one wholly past the end is none", c.selection == nil)
    c.select(NSRange(location: 3, length: 1))
    apply(c.replace(NSRange(location: 0, length: 1), with: "A", taken: c.generation), to: &mac)
    check("a correction ends the selection", c.selection == nil && mac == "AXde")
    c.select(NSRange(location: 0, length: 1))
    apply(c.forget(), to: &mac)
    check("a forget ends it", c.selection == nil && c.selectedRange == NSRange(location: 0, length: 0))
    let emoji = c.insert("a👍🏽")
    apply(emoji, to: &mac)
    c.select(utf16Range(c.sent, characters: 1..<2))
    let gone = c.deleteBackward()
    apply(gone, to: &mac)
    check("a selected emoji is one backspace", gone == [.backspaces(1)] && c.sent == "a")
}

do {   // a selection and a composition
    var c = C()
    var mac = ""
    apply(c.insert("ab"), to: &mac)
    c.select(NSRange(location: 1, length: 1))
    let out = c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    apply(out, to: &mac)
    check("a composition over a selection replaces it: the selected text goes from the Mac first",
          out == [.backspaces(1)] && mac == "a" && c.document == "aㄋ" && c.selection == nil)
    c.select(NSRange(location: 0, length: 1))
    check("no selection is kept while an input method composes", c.selection == nil && c.selectedRange == NSRange(location: 2, length: 0))
    apply(c.insert("你"), to: &mac)
    check("…and its candidate follows what was sent", mac == "a你")
    c.select(NSRange(location: 0, length: 1))
    check("an empty composition with nothing composed sends nothing and leaves a selection as it was",
          c.setMarked("", selected: NSRange(location: 0, length: 0)) == [] && c.selection == NSRange(location: 0, length: 1) && mac == "a你")
}

do {   // the tail: kept whole to its limit, trimmed past it, never while composing
    var c = C()
    _ = c.insert(String(repeating: "字", count: C.limit))
    check("a tail of exactly the limit wants no trim", !c.wantsTrim && c.sent.count == C.limit)
    c.trim()
    check("…and a trim then keeps it all, and the document", c.sent.count == C.limit && c.generation == 0)
    _ = c.insert("x")
    check("one character past the limit wants a trim", c.wantsTrim)
    c.setMarked("ㄅ", selected: NSRange(location: 1, length: 0))
    check("no trim while an input method composes", !c.wantsTrim)
    c.trim()
    check("…and a trim then does nothing", c.sent.count == C.limit + 1 && c.marked == "ㄅ" && c.generation == 0)
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    let lastCharacter = NSRange(location: c.length - 1, length: 1)
    c.select(lastCharacter)
    c.trim()
    check("a trim ends a selection", c.selection == nil)
    check("a trim keeps the last characters", c.sent.count == C.keep && c.sent.hasSuffix("字x") && !c.wantsTrim)
    check("…and starts a new document", c.generation == 1)
    check("…so a correction taken before it sends nothing",
          c.replace(lastCharacter, with: "y", taken: 0) == [] && c.sent.hasSuffix("字x"))
    check("the limits as documented", C.limit == 4_000 && C.keep == 1_000)
}

do {   // a selection out of range is clamped
    var c = C()
    c.setMarked("ㄋㄧ", selected: NSRange(location: 9, length: 4))
    check("the marked selection stays inside the composition", c.selectedRange == NSRange(location: 2, length: 0))
    c.setMarked("ㄋㄧ", selected: NSRange(location: 1, length: 9))
    check("…and so does its length", c.selectedRange == NSRange(location: 1, length: 1))
}

// MARK: - Which input moves the Mac's caret

check("a click moves the caret", R.movesCaret(.pointer(.leftDown, x: 0.5, y: 0.5)))
check("a right click moves the caret", R.movesCaret(.pointer(.rightDown, x: 0.5, y: 0.5)))
check("a pointer move does not", !R.movesCaret(.pointer(.move, x: 0.5, y: 0.5)))
check("a button's up does not", !R.movesCaret(.pointer(.leftUp, x: 0.5, y: 0.5)) && !R.movesCaret(.pointer(.rightUp, x: 0.5, y: 0.5)))
check("a key going down does (an arrow, a shortcut, a modifier)",
      R.movesCaret(.key(hidUsage: 0x50, down: true, modifiers: 0)) && R.movesCaret(.key(hidUsage: 0xE3, down: true, modifiers: R.command)))
check("a key going up does not", !R.movesCaret(.key(hidUsage: 0x50, down: false, modifiers: 0)))
check("typed text does not, a backspace among it", !R.movesCaret(.text("a")) && !R.movesCaret(.text("\u{8}")) && !R.movesCaret(.text("\n")))
check("a scroll does not", !R.movesCaret(.scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.1)))
check("a scroll's phases do not", [ScrollPhase.began, .ended, .momentumBegan, .momentumEnded].allSatisfy { !R.movesCaret(.scrollGesture($0, x: 0.5, y: 0.5)) })

// MARK: - Keyboards and ⌃Space

check("a language's keyboard is a keyboard", R.isKeyboard("en-US") && R.isKeyboard("zh-Hant") && R.isKeyboard("ja-JP"))
check("Emoji and dictation are not", !R.isKeyboard("emoji") && !R.isKeyboard("dictation"))

let capsLock: UInt64 = 1 << 16, numericPad: UInt64 = 1 << 21
func switches(_ modifiers: UInt64, _ keyboards: [String], usage: UInt16 = R.space) -> Bool {
    R.isKeyboardSwitch(usage: usage, modifiers: modifiers, keyboards: keyboards)
}
let two = ["en-US", "zh-Hant", "emoji"]
check("⌃Space with two keyboards is iPadOS's switch", switches(R.control, two))
check("…with caps lock on too", switches(R.control | capsLock, two) && switches(R.control | numericPad, two))
check("⌃Space with one keyboard (and Emoji) is the Mac's", !switches(R.control, ["en-US", "emoji"]))
check("…with one keyboard, Emoji and dictation, the Mac's", !switches(R.control, ["en-US", "emoji", "dictation"]))
check("…with no keyboard listed, the Mac's", !switches(R.control, []))
check("a third-party keyboard in the same language counts once", !switches(R.control, ["en-US", "en-US", "emoji"]))
check("two layouts of one language set up in two languages' keyboards switch", switches(R.control, ["en-US", "en-GB"]))
check("three keyboards switch", switches(R.control, ["en-US", "zh-Hant", "ja-JP"]))
check("⌃⇧Space is the Mac's", !switches(R.control | R.shift, two))
check("⌃⌥Space and ⌃⌘Space are the Mac's", !switches(R.control | R.option, two) && !switches(R.control | R.command, two))
check("Space alone, ⇧Space, ⌥Space and ⌘Space are not the switch",
      !switches(0, two) && !switches(R.shift, two) && !switches(R.option, two) && !switches(R.command, two))
check("⌃ with another key is not the switch", !switches(R.control, two, usage: 0x2B) && !switches(R.control, two, usage: 0x04))
var keyboardsAsked = 0
func keyboards() -> [String] { keyboardsAsked += 1; return two }
_ = R.isKeyboardSwitch(usage: 0x04, modifiers: R.control, keyboards: keyboards())
_ = R.isKeyboardSwitch(usage: R.space, modifiers: 0, keyboards: keyboards())
_ = R.isKeyboardSwitch(usage: R.space, modifiers: R.command, keyboards: keyboards())
check("the keyboards are asked for only for ⌃Space, not for every key", keyboardsAsked == 0)
_ = R.isKeyboardSwitch(usage: R.space, modifiers: R.control, keyboards: keyboards())
check("…and are for it", keyboardsAsked == 1)
check("Space's usage", R.space == 0x2C)
check("the modifier bits are UIKeyModifierFlags'", R.shift == 1 << 17 && R.control == 1 << 18 && R.option == 1 << 19 && R.command == 1 << 20)

// MARK: - Random edit sequences

/// SplitMix64: the same sequences on every run, so a failure can be run again.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
var generator = Seeded(state: 0x5111_0138)

/// `runs` sequences of 12 edits each from `alphabet`, with selections among them, and forgets, stale
/// corrections and trims when `forgets`, against a model of the Mac's text field: it always ends with
/// what is remembered, and is exactly that while nothing was forgotten; a new document (`generation`)
/// comes with a forget or a trim, and only then; a selection is never empty, never while composing,
/// inside what was sent, and gone after an edit. The first failure is printed; the number of failed
/// runs, of stale corrections tried (past the end, and taken in a document since forgotten), and of
/// selections an edit replaced, are returned.
func randomRuns(_ runs: Int, alphabet: [String], forgets: Bool) -> (fails: Int, stale: Int, taken: Int, replaced: Int) {
    func word() -> String { (0..<Int.random(in: 1...3, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! }.joined() }
    var failed = 0, staleTried = 0, takenTried = 0, replaced = 0
    var firstFailure: String?
    for run in 0..<runs {
        var c = C()
        var mac = ""
        var everReset = false
        var stale: NSRange?
        var taken: (range: NSRange, generation: Int)?
        for step in 0..<12 {
            let before = c
            var why: String?
            let op = forgets ? Int.random(in: 0..<11, using: &generator) : [0, 1, 2, 3, 4, 9].randomElement(using: &generator)!
            switch op {
            case 0: apply(c.insert(word()), to: &mac)
            case 1:
                let w = word()
                apply(c.setMarked(w, selected: NSRange(location: Int.random(in: 0...w.utf16.count, using: &generator), length: 0)), to: &mac)
                if let selected = before.selection {
                    if c.sent != (before.sent as NSString).replacingCharacters(in: selected, with: "") {
                        why = "a composition over a selection did not replace it"
                    }
                } else if c.sent != before.sent { why = "a composition changed what was sent" }
            case 2: apply(c.unmark(), to: &mac)
            case 3: apply(c.deleteBackward(), to: &mac)
            case 4:
                // Whole characters only: UIKit's ranges never split one.
                let chars = Array(c.document)
                let a = Int.random(in: 0...chars.count, using: &generator)
                let b = Int.random(in: a...chars.count, using: &generator)
                let range = utf16Range(c.document, characters: a..<b)
                if c.length > 0, stale == nil { stale = NSRange(location: c.length + 1, length: Int.random(in: 0...3, using: &generator)) }
                if taken == nil { taken = (range, c.generation) }
                apply(c.replace(range, with: word(), taken: c.generation), to: &mac)
            case 5:
                apply(c.forget(), to: &mac)
                everReset = true
                if c.isComposing { why = "a forget kept the composition on the device" }
                else if let composed = before.marked, !mac.hasSuffix(before.sent + composed) {
                    why = "a forget lost what was composed"
                }
            case 6:
                // A correction whose range the text system took before a forget: past the document's end.
                guard let range = stale, range.location > c.length else { break }
                staleTried += 1
                let out = c.replace(range, with: word())
                if out != [] || c != before { why = "a stale correction changed something" }
            case 7:
                c.trim()
                everReset = everReset || c.sent != before.sent
            case 8:
                // A correction whose range the text system took in a document since forgotten, wherever
                // its offsets fall now (inside what was typed since, too).
                guard let (range, generation) = taken, generation != c.generation else { break }
                takenTried += 1
                let out = c.replace(range, with: word(), taken: generation)
                if out != [] || c != before { why = "a correction taken before a forget changed something" }
            case 9:
                // A selection of whole characters of what was sent (UIKit's never split one), or the caret
                // moved inside it.
                let chars = Array(c.sent)
                let a = Int.random(in: 0...chars.count, using: &generator)
                let b = Int.random(in: a...chars.count, using: &generator)
                c.select(utf16Range(c.sent, characters: a..<b))
                if c.sent != before.sent || c.marked != before.marked { why = "a selection changed the document" }
            default: break
            }
            if why == nil, let selected = c.selection,
               c.isComposing || selected.length == 0 || selected.location + selected.length > c.sent.utf16.count {
                why = "a selection while composing, empty, or past what was sent"
            }
            if why == nil, [0, 3, 4, 5].contains(op), c.selection != nil { why = "an edit or a forget kept the selection" }
            if before.selection != nil, [0, 1, 3].contains(op) { replaced += 1 }
            let newDocument = op == 5 || (op == 7 && before.wantsTrim)
            if why == nil, c.generation != before.generation + (newDocument ? 1 : 0) {
                why = "the document's generation moved without a forget or a trim, or stayed through one"
            }
            if why == nil, c.length != c.document.utf16.count { why = "the length is not the document's" }
            if why == nil, !mac.hasSuffix(c.sent) { why = "the Mac's text does not end with what is remembered" }
            if why == nil, !everReset, mac != c.sent { why = "with nothing forgotten, the Mac's text is not what was sent" }
            if why == nil, let m = c.markedRange, m.location != c.sent.utf16.count { why = "the composition does not follow what was sent" }
            if let why {
                failed += 1
                if firstFailure == nil { firstFailure = "run \(run), step \(step): \(why) (Mac \(mac.debugDescription), sent \(c.sent.debugDescription))" }
                break
            }
        }
    }
    if let firstFailure { print("     \(firstFailure)") }
    return (failed, staleTried, takenTried, replaced)
}

// Forgets among the edits. No lone combining mark here: one typed right after a forget joins a
// character the Mac has from before it, which this side never knew (the model's suffix would not hold).
let forgetful = randomRuns(20_000, alphabet: ["a", "b", "你", "好", "ㄋ", "ˇ", "👍🏽", "é", "e", " ", "\n"], forgets: true)
check("20,000 seeded random sequences: the Mac's text always ends with what is remembered, and is it while nothing was forgotten",
      forgetful.fails == 0)
check("…stale corrections among them (\(forgetful.stale) past the end, \(forgetful.taken) taken before a forget), none of which sent anything",
      forgetful.stale > 1_000 && forgetful.taken > 1_000)
check("…and \(forgetful.replaced) selections replaced by the next insert, backspace or composition", forgetful.replaced > 1_000)
// No forget: a combining mark that joins the character before it is retyped with it.
let joining = randomRuns(5_000, alphabet: ["a", "e", "\u{301}", "👍", "\u{1F3FD}", "ㄋ", "ˇ", " "], forgets: false)
check("5,000 seeded random sequences with combining marks and skin tones: the Mac's text is what was sent", joining.fails == 0)
check("…\(joining.replaced) selections among them replaced", joining.replaced > 500)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
