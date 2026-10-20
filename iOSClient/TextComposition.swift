import Foundation
// In the app StreamProtocol is its own module; the text-composition check compiles this file together
// with Sources/StreamProtocol/Input.swift as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

// What the stream's input view holds for iPadOS's text system (#138): the text an input method is
// still composing (Zhuyin's ㄋㄧˇ, Pinyin's nihao, Japanese kana before conversion), kept on the device
// and sent only once chosen (or, as it stands, when the Mac's caret is about to move or the input view
// lets go of it), and what was typed since the Mac's caret was last moved by something else, so
// dictation and an input method can revise what they put there (a dictated word corrected a moment
// later: backspaces on the Mac, then the new text; Korean's syllables built again as each letter comes,
// through a selection: `selection`). Beside it, `TextInputRules`: which input moves the Mac's caret,
// and whose ⌃Space it is.
//
// Pure: Foundation and StreamProtocol's InputEvent only, checked on its own with swiftc
// (Tests/checks/text-composition). Offsets are UTF-16, as UITextInput's are; the Mac is sent whole
// characters.

struct TextComposition: Equatable {
    /// What goes to the Mac: text, or that many backspaces (each one deletes one character there).
    enum Output: Equatable {
        case text(String)
        case backspaces(Int)
    }

    /// What was sent since the last `forget`, which the text system may still revise. Kept whole while it
    /// may: the text system's offsets point into it, and cutting its front in the middle of an edit moved
    /// every offset under a correction still to come (dictation's, say, past 200 characters), which then
    /// landed at the end and typed the corrected words a second time. Past `limit` the input view trims it
    /// (`trim`), between edits, with the text system told.
    private(set) var sent = ""
    /// The text being composed, never sent while it is; nil when nothing is.
    private(set) var marked: String?
    /// The selection inside the marked text, relative to its start (UTF-16).
    private(set) var markedSelection = NSRange(location: 0, length: 0)
    /// What the text system selected of what was sent (UTF-16), for its next edit, which replaces it as in
    /// any text field: Korean's input method selects the syllables it is still building, deletes them and
    /// types them again (한ㄱ selected, deleted, then 한 and 그 typed; with the selection ignored, 한글
    /// reached the Mac as 한한한글 in the iPad simulator, 2026-10-20), and the text system selects the
    /// character a backspace deletes. Never empty and never while composing: nil is the caret at the
    /// end, where every edit, a forget and a trim put it back. An empty selection elsewhere (the caret
    /// moved, as the on-screen keyboard's trackpad does) is not kept: the Mac's caret cannot be moved
    /// from here.
    private(set) var selection: NSRange?
    /// Which document the text system's positions were taken in: each `forget` and each trim
    /// starts a new one, as every offset moves then. A correction whose range was taken in an older one
    /// is stale wherever its offsets fall now (`replace`).
    private(set) var generation = 0

    /// Past this many characters, the tail is due a trim (`wantsTrim`): only a long stretch of typing or
    /// dictation with no click, key or pick in it gets there.
    static let limit = 4_000
    /// What a trim keeps, in characters: more than any correction dictation or an input method makes.
    static let keep = 1_000

    /// The document the text system sees: what was sent, then what is being composed.
    var document: String { sent + (marked ?? "") }
    var length: Int { sent.utf16.count + (marked?.utf16.count ?? 0) }
    var isComposing: Bool { marked != nil }

    var markedRange: NSRange? {
        marked.map { NSRange(location: sent.utf16.count, length: $0.utf16.count) }
    }

    /// The caret is at the end, or where the input method put it inside the marked text, or what the text
    /// system selected for its next edit.
    var selectedRange: NSRange {
        guard marked != nil else { return selection ?? NSRange(location: length, length: 0) }
        return NSRange(location: sent.utf16.count + markedSelection.location, length: markedSelection.length)
    }

    /// The text system selects `range` of the document for its next edit: kept, inside what was sent,
    /// when it selects something while nothing is being composed (the input method's own selection is
    /// the marked text's then); an empty one, the caret moved, puts the caret back at the end.
    mutating func select(_ range: NSRange) {
        guard marked == nil else { return }
        let count = sent.utf16.count
        let start = min(max(range.location, 0), count)
        let end = min(max(range.location + range.length, start), count)
        selection = end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// Text typed or committed: it replaces the marked text if there is any, else the selection if there
    /// is one, and goes to the Mac.
    mutating func insert(_ text: String) -> [Output] {
        if marked == nil, let selection { return commit(sentReplacing(selection, with: text)) }
        return commit(sent + text)
    }

    /// The input method's composition so far (an empty one ends it: nothing is sent). One that starts
    /// over a selection replaces it, as in a text field: the selected text goes from the Mac first, and
    /// the composition follows what was sent, as every composition does here.
    @discardableResult
    mutating func setMarked(_ text: String?, selected: NSRange) -> [Output] {
        guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); return [] }
        var out: [Output] = []
        if marked == nil, let selection { out = commit(sentReplacing(selection, with: "")) }
        marked = text
        let count = text.utf16.count
        let location = min(max(selected.location, 0), count)
        markedSelection = NSRange(location: location, length: min(max(selected.length, 0), count - location))
        return out
    }

    /// The composition is accepted as it stands: sent.
    mutating func unmark() -> [Output] {
        guard let marked else { return [] }
        return commit(sent + marked)
    }

    /// Backspace: inside a composition it edits the composition; otherwise it deletes the selection if
    /// there is one, else one backspace to the Mac, whether or not this side still remembers what it
    /// deletes.
    mutating func deleteBackward() -> [Output] {
        if var text = marked {
            text.removeLast()
            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))
            return []
        }
        if let selection { return commit(sentReplacing(selection, with: "")) }
        guard !sent.isEmpty else { return [.backspaces(1)] }
        return commit(String(sent.dropLast()))
    }

    /// `range` of the document replaced with `text` (dictation's corrections, an input method's own
    /// edits): any composition ends, and the Mac is brought to the new document by deleting back to
    /// where the old and new first differ and typing the rest. A range taken before this side forgot or
    /// trimmed what it held (`taken`, its positions' `generation`, older than the document's; or one the
    /// text system built again from offsets it kept, which then starts past the document's end) no
    /// longer points at the text it means: the Mac's caret moved since, or every offset did. Nothing is
    /// sent, rather than its replacement typed a second time at the caret (dictation's last correction
    /// of a phrase, its punctuation or capitals, coming after a click).
    mutating func replace(_ range: NSRange, with text: String, taken: Int? = nil) -> [Output] {
        if let taken, taken != generation { return [] }
        let utf16 = Array(document.utf16)
        guard range.location <= utf16.count else { return [] }
        let start = max(range.location, 0)
        let end = min(max(range.location + range.length, start), utf16.count)
        let before = String(utf16CodeUnits: Array(utf16[..<start]), count: start)
        let after = String(utf16CodeUnits: Array(utf16[end...]), count: utf16.count - end)
        return commit(before + text + after)
    }

    /// The Mac's caret is about to move some other way (a click, an arrow, a shortcut, a pick): what is
    /// being composed goes to the Mac first, as it stands, where the caret still is, as a text field keeps
    /// a composition when a tap moves its caret; then what was sent is forgotten, and every position the
    /// text system holds is stale. Kept on the device across the move, the composition was lost: told
    /// that the document changed, iPadOS's input method dropped it at the next key.
    mutating func forget() -> [Output] {
        let out = unmark()
        sent = ""
        generation += 1
        selection = nil
        return out
    }

    /// The tail is past `limit` and nothing is being composed: the input view trims it at its next turn.
    var wantsTrim: Bool { marked == nil && sent.count > Self.limit }

    /// The tail's last `keep` characters are kept, when it wants a trim. Every offset moves: the input
    /// view tells the text system, as for a `forget`, and every position it holds is stale.
    mutating func trim() {
        guard wantsTrim else { return }
        sent = String(sent.suffix(Self.keep))
        generation += 1
        selection = nil
    }

    /// What was sent with `range` of it (UTF-16) replaced by `text`: a selection's edit.
    private func sentReplacing(_ range: NSRange, with text: String) -> String {
        let units = Array(sent.utf16)
        let lower = min(range.location, units.count), upper = min(range.location + range.length, units.count)
        return String(utf16CodeUnits: Array(units[..<lower]), count: lower) + text
            + String(utf16CodeUnits: Array(units[upper...]), count: units.count - upper)
    }

    /// The document becomes `new`, all of it sent: backspaces over what differs, then the rest. The caret
    /// is at the end again.
    private mutating func commit(_ new: String) -> [Output] {
        selection = nil
        marked = nil
        markedSelection = NSRange(location: 0, length: 0)
        let old = Array(sent), now = Array(new)
        var common = 0
        while common < old.count, common < now.count, old[common] == now[common] { common += 1 }
        var out: [Output] = []
        if old.count > common { out.append(.backspaces(old.count - common)) }
        if now.count > common { out.append(.text(String(now[common...]))) }
        sent = new
        return out
    }
}

/// The stream's input view's rules beside its document (#138).
enum TextInputRules {
    /// The modifier bits a key carries (UIKeyModifierFlags raw values, as KeyModifiers' are).
    static let shift: UInt64 = 1 << 17
    static let control: UInt64 = 1 << 18
    static let option: UInt64 = 1 << 19
    static let command: UInt64 = 1 << 20
    /// Space's HID usage.
    static let space: UInt16 = 0x2C

    /// Whether an input sent to the Mac, by any path (the picture, the portrait trackpad and key row, a
    /// hardware keyboard, Esc's key command), may move its caret: a button going down (a click, or the
    /// start of a drag) or a key going down (an arrow, Return as a key, a shortcut, a modifier). Then
    /// what was typed is no longer just before the caret there, so the input view forgets it
    /// (`TextComposition.forget`, what is composed going first), and a correction dictation makes later
    /// never backspaces where the caret is now. Typing (text, a backspace among it), moves, scrolls and
    /// every up leave it.
    static func movesCaret(_ event: InputEvent) -> Bool {
        switch event {
        case .pointer(let action, _, _): return action == .leftDown || action == .rightDown
        case .key(_, let down, _): return down
        case .text, .scroll, .scrollGesture: return false
        }
    }

    /// Whether an active input mode (`UITextInputMode.activeInputModes`, by its primary language) is a
    /// keyboard a person switches to: every one but Emoji and dictation.
    static func isKeyboard(_ language: String) -> Bool {
        language != "emoji" && language != "dictation"
    }

    /// Whether a hardware key's press is iPadOS's own switch between keyboards, never the Mac's: Space
    /// with control alone (caps lock aside) while the person set up keyboards in two languages or more
    /// in Settings › General › Keyboard › Keyboards (Emoji and dictation aside, and a third-party
    /// keyboard in a language already there counted once), as any iPad text field switches them and as
    /// macOS's own ⌃Space does with several input sources. With one, ⌃Space is the Mac's shortcut
    /// (Xcode's completions, VS Code's suggestions). Judged at the press: the release follows wherever
    /// the press went (ForwardedKeys). The keyboards are asked for only for ⌃Space.
    static func isKeyboardSwitch(usage: UInt16, modifiers: UInt64, keyboards languages: @autoclosure () -> [String]) -> Bool {
        guard usage == space, modifiers & (shift | control | option | command) == control else { return false }
        return Set(languages().filter(isKeyboard)).count >= 2
    }
}
