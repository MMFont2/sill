// ThumbnailHold (iOSClient/ThumbnailHold.swift) on its own: how long a window's thumbnail is touched and
// held before its lights show and it can be dragged (issue #113, docs/thumbnail-hold-plan.md). The
// range (1 to 5 s), the step (half a second), the standard 1 s (shorter than the 1.5 s before), what a
// stored value means (a number, a launch argument's string, nothing usable), the press's look (the veil
// from touch-down, the shrink over the hold, none under Reduce Motion) and every word, the row's
// VoiceOver reading among them. A child run of this binary reads `-Sill.thumbnailHold` from its own
// launch arguments, as the app's harness does (UserDefaults' argument domain, read only: nothing is
// written).
//   swiftc -O iOSClient/ThumbnailHold.swift Tests/checks/thumbnail-hold/main.swift -o check && ./check
import Foundation

typealias H = ThumbnailHold
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

// MARK: - The child run: what UserDefaults hands back for the harness's launch argument

if CommandLine.arguments.dropFirst().first == "--child" {
    let stored = UserDefaults.standard.object(forKey: H.key)
    let kind = stored is NSNumber ? "number" : stored is String ? "string" : stored == nil ? "nothing" : "other"
    print("\(kind) \(H.seconds(stored: stored))")
    exit(0)
}

// MARK: - The range, the step, the standard

check("the key is Sill.thumbnailHold", H.key == "Sill.thumbnailHold")
check("the range is 1 to 5 s", H.range.lowerBound == 1 && H.range.upperBound == 5)
check("the step is half a second", H.step == 0.5)
check("the standard is 1 s", H.standard == 1)
check("the standard is shorter than the 1.5 s before (#113)", H.standard < H.before && H.before == 1.5)
check("the standard is in the range and is one of the choices", H.range.contains(H.standard) && H.choices.contains(H.standard))
check("the choices are 1, 1.5, … 5", H.choices == [1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5])
check("the choices ascend by the step", zip(H.choices, H.choices.dropFirst()).allSatisfy { near($1 - $0, H.step) })
check("each choice is kept as it is", H.choices.allSatisfy { H.seconds($0) == $0 })

// MARK: - A length as the hold takes it

let lengths: [(Double, Double, String)] = [
    (1, 1, "1 s"), (5, 5, "5 s"), (1.5, 1.5, "1.5 s"), (3, 3, "3 s"),
    (0, 1, "0 s is 1 s"), (-3, 1, "a negative length is 1 s"), (0.99, 1, "0.99 s is 1 s"), (0.5, 1, "0.5 s (iOS's own long press) is 1 s"),
    (5.01, 5, "5.01 s is 5 s"), (100, 5, "100 s is 5 s"),
    (1.24, 1, "1.24 s is 1 s"), (1.25, 1.5, "1.25 s is 1.5 s (a quarter rounds up)"), (1.26, 1.5, "1.26 s is 1.5 s"),
    (1.74, 1.5, "1.74 s is 1.5 s"), (1.75, 2, "1.75 s is 2 s"), (2.2, 2, "2.2 s is 2 s"), (2.3, 2.5, "2.3 s is 2.5 s"),
    (4.74, 4.5, "4.74 s is 4.5 s"), (4.75, 5, "4.75 s is 5 s"), (4.9, 5, "4.9 s is 5 s"),
]
for (value, expected, name) in lengths {
    check("length: \(name)", H.seconds(value) == expected)
}
check("length: not a number is the standard", H.seconds(.nan) == H.standard)
check("length: infinity is the standard", H.seconds(.infinity) == H.standard && H.seconds(-.infinity) == H.standard)
check("length: the greatest finite number is 5 s", H.seconds(.greatestFiniteMagnitude) == 5)
// Over a grid: always a choice, never further than a quarter second from a value in the range, the
// nearest end outside it, and the same when taken again.
var grid = true
for k in -400...1000 {
    let v = Double(k) / 100
    let s = H.seconds(v)
    if !H.choices.contains(s) { grid = false }
    if H.range.contains(v), abs(s - v) > 0.25 + 1e-9 { grid = false }
    if v < 1, s != 1 { grid = false }
    if v > 5, s != 5 { grid = false }
    if H.seconds(s) != s { grid = false }
}
check("length: over -4 to 10 s by hundredths, a choice, within a quarter second in the range, the nearest end outside, kept when taken again", grid)
var monotonic = true
var last = -Double.infinity
for k in -400...1000 {
    let s = H.seconds(Double(k) / 100)
    if s < last { monotonic = false }
    last = s
}
check("length: a longer value never gives a shorter hold", monotonic)

// MARK: - One step up or down (VoiceOver's swipe on the Settings row, an adjustable element)

let ups = zip(H.choices, H.choices.dropFirst())
check("step: up from each choice is the next", ups.allSatisfy { H.adjusted($0, up: true) == $1 })
check("step: down from each choice is the one before", ups.allSatisfy { H.adjusted($1, up: false) == $0 })
check("step: up from 5 s stays 5 s", H.adjusted(5, up: true) == 5)
check("step: down from 1 s stays 1 s", H.adjusted(1, up: false) == 1)
check("step: from the standard, up is 1.5 s and down stays 1 s",
      H.adjusted(H.standard, up: true) == 1.5 && H.adjusted(H.standard, up: false) == 1)
check("step: from a length between steps, from the step it is taken as (2.2 s is 2 s: up 2.5, down 1.5)",
      H.adjusted(2.2, up: true) == 2.5 && H.adjusted(2.2, up: false) == 1.5)
check("step: from a length outside the range, from its end (7 s down is 4.5 s, 0.2 s up is 1.5 s)",
      H.adjusted(7, up: false) == 4.5 && H.adjusted(0.2, up: true) == 1.5 && H.adjusted(7, up: true) == 5)
check("step: from nothing usable, from the standard (up 1.5 s)", H.adjusted(.nan, up: true) == 1.5 && H.adjusted(.nan, up: false) == 1)
var stepsUp = H.range.lowerBound, walked = [stepsUp]
for _ in 0..<12 { stepsUp = H.adjusted(stepsUp, up: true); walked.append(stepsUp) }
check("step: twelve swipes up from 1 s pass every choice once and stop at 5 s",
      Array(walked.prefix(H.choices.count)) == H.choices && walked.dropFirst(H.choices.count).allSatisfy { $0 == 5 })

// MARK: - What a stored value means

let stored: [(Any?, Double, String)] = [
    (nil, 1, "nothing stored is the standard"),
    (NSNumber(value: 2.5), 2.5, "an NSNumber"),
    (2.5, 2.5, "a Double"),
    (3, 3, "an Int"),
    (NSNumber(value: Float(1.75)), 2, "a Float between steps"),
    ("2.5", 2.5, "a launch argument's string"),
    (NSString(string: "3.5"), 3.5, "an NSString"),
    (" 4 \n", 4, "a string with spaces round it"),
    ("7", 5, "a string above the range"),
    ("0.2", 1, "a string below the range"),
    ("abc", 1, "a string that is no number"),
    ("", 1, "an empty string"),
    ("nan", 1, "the string nan"),
    ("inf", 1, "the string inf"),
    (true, 1, "true (1) is 1 s"),
    (false, 1, "false (0) is 1 s"),
    (Date(), 1, "a date"),
    (["2"], 1, "an array"),
    (Data([0x32]), 1, "data"),
]
for (value, expected, name) in stored {
    check("stored: \(name)", H.seconds(stored: value) == expected)
}
// The way UserDefaults hands them back: its registration domain (memory only, nothing written).
if let suite = UserDefaults(suiteName: "me.saffer.sill.check.thumbnail-hold.\(ProcessInfo.processInfo.processIdentifier)") {
    suite.register(defaults: [H.key: 4.5])
    check("stored: a registered Double comes back as a number and reads 4.5 s",
          suite.object(forKey: H.key) is NSNumber && H.seconds(stored: suite.object(forKey: H.key)) == 4.5)
    suite.register(defaults: [H.key: "2"])
    check("stored: a registered string comes back as a string and reads 2 s",
          suite.object(forKey: H.key) is String && H.seconds(stored: suite.object(forKey: H.key)) == 2)
} else {
    check("stored: a UserDefaults suite to register in", false)
}
// The harness's launch argument, `-Sill.thumbnailHold <s>`, in a child run of this binary.
func child(_ arguments: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    p.arguments = ["--child"] + arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    do { try p.run() } catch { return "did not run: \(error)" }
    p.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}
let argument = child(["-Sill.thumbnailHold", "2.5"])
check("launch argument: -Sill.thumbnailHold 2.5 comes as a string and reads 2.5 s (\(argument))", argument == "string 2.5")
let argumentHigh = child(["-Sill.thumbnailHold", "9"])
check("launch argument: -Sill.thumbnailHold 9 reads 5 s (\(argumentHigh))", argumentHigh.hasSuffix(" 5.0"))
let argumentNone = child([])
check("launch argument: none reads the standard 1 s (\(argumentNone))", argumentNone.hasSuffix(" 1.0"))

// MARK: - The press's look

let rest = H.look(pressed: false, reduceMotion: false)
check("look: not pressed, no veil and full size", rest == H.Look(dim: 0, scale: 1))
check("look: not pressed under Reduce Motion, the same", H.look(pressed: false, reduceMotion: true) == rest)
let pressed = H.look(pressed: true, reduceMotion: false)
check("look: pressed, a veil from touch-down (\(pressed.dim))", pressed.dim > 0.1 && pressed.dim < 0.4)
check("look: pressed, a little smaller (\(pressed.scale))", pressed.scale < 1 && pressed.scale >= 0.9)
let pressedStill = H.look(pressed: true, reduceMotion: true)
check("look: pressed under Reduce Motion, the veil and no shrink", pressedStill.dim == pressed.dim && pressedStill.scale == 1)
check("look: the veil comes in within a tenth of a second (\(H.veilIn) s)", H.veilIn > 0 && H.veilIn <= 0.1)
check("look: a press that ends goes back within 0.2 s (\(H.release) s)", H.release > 0 && H.release <= 0.2)
check("look: the shrink lasts the whole hold, each choice", H.choices.allSatisfy { H.shrinkDuration(hold: $0) == $0 })
check("look: the shrink of a length outside the range is the hold's", H.shrinkDuration(hold: 0.2) == 1 && H.shrinkDuration(hold: 12) == 5)

// MARK: - Words

check("words: the row's title", H.title == "Hold to Show Window Controls")
check("words: the row's VoiceOver label", H.spokenTitle == "Hold to show window controls")
check("words: VoiceOver reads the row as \"Hold to show window controls, 1 second\"",
      "\(H.spokenTitle), \(H.spokenValue(H.standard))" == "Hold to show window controls, 1 second")
let values: [(Double, String, String)] = [
    (1, "1 s", "1 second"), (1.5, "1.5 s", "1.5 seconds"), (2, "2 s", "2 seconds"), (2.5, "2.5 s", "2.5 seconds"),
    (3, "3 s", "3 seconds"), (4.5, "4.5 s", "4.5 seconds"), (5, "5 s", "5 seconds"),
]
for (value, shown, spoken) in values {
    check("words: \(value) shows \"\(shown)\" and is read \"\(spoken)\"", H.valueText(value) == shown && H.spokenValue(value) == spoken)
}
check("words: a whole number has no \".0\"", H.number(2) == "2" && H.number(5) == "5" && H.number(1) == "1")
check("words: a value outside the range shows and reads as the hold takes it",
      H.valueText(0.2) == "1 s" && H.spokenValue(0.2) == "1 second" && H.valueText(9) == "5 s" && H.spokenValue(9) == "5 seconds")
check("words: each choice shows differently", Set(H.choices.map(H.valueText)).count == H.choices.count)
check("words: each choice is read differently", Set(H.choices.map(H.spokenValue)).count == H.choices.count)
check("words: the footnote says touch and hold, the three buttons and the drag",
      H.footnote.contains("touch and hold a window’s thumbnail") && H.footnote.contains("Close, Minimize and Full Screen")
      && H.footnote.contains("drag it to a new place"))
check("words: the footnote says the press shows at once", H.footnote.contains("darkens as soon as you touch it"))
check("words: no straight apostrophe or quote in any of them",
      ([H.title, H.spokenTitle, H.footnote] + H.choices.map(H.valueText) + H.choices.map(H.spokenValue))
        .allSatisfy { !$0.contains("'") && !$0.contains("\"") })

print(fails == 0 ? "ok: \(passes) checks" : "FAILED: \(fails) of \(passes + fails) checks")
exit(fails == 0 ? 0 : 1)
