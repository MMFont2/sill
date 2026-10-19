import Foundation
import CoreGraphics

// Which of the Mac's displays the Desktop shows (issue #91; docs/display-stepping-plan.md), both ends:
// the host's DesktopDisplays (Sources/SillHost: the order, the display a pick streams, the window list's
// entries, the lines, the TEST ONLY test displays) and the device's DisplayStepping (iOSClient: the
// steps, the display shown, what a tap picks, the button's face and a pick that stands), with
// StreamProtocol's SourcePick and DisplayInfo; then random sessions through a model of a Mac and its
// devices, old and new. Compiled with StreamProtocol's sources as one module (build.sh).

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

typealias D = DesktopDisplays.Display
func display(_ id: UInt32, _ name: String, x: CGFloat, y: CGFloat = 0, w: CGFloat = 1512, h: CGFloat = 982,
             main: Bool = false, sill: Bool = false) -> D {
    D(id: id, name: name, frame: CGRect(x: x, y: y, width: w, height: h), isMain: main, isSill: sill)
}
func ids(_ list: [D]) -> [UInt32] { list.map(\.id) }

// MARK: - The wire (the compatibility check has the rest)

let enc = { (p: SourcePick) in String(decoding: Wire.encode(p), as: UTF8.self) }
check(enc(SourcePick(.desktop)) == #"{"desktop":{}}"#, "a Desktop pick without a display is today's bytes: \(enc(SourcePick(.desktop)))")
check(enc(SourcePick(.desktop)) == String(decoding: Wire.encode(StreamSource.desktop), as: UTF8.self), "byte for byte StreamSource's")
check(enc(SourcePick(.desktop, display: 2)) == #"{"desktop":{"display":2}}"#, "with a display, inside the Desktop's object")
check(SourcePick(.window(5), display: 3).display == nil && SourcePick(.none, display: 3).display == nil, "a display only on the Desktop's pick")
check(enc(SourcePick(.window(5))) == #"{"window":{"_0":5}}"#, "a window's pick is today's bytes")
for p in [SourcePick(.desktop), SourcePick(.desktop, display: 69733632), SourcePick(.desktop, display: UInt32.max), SourcePick(.window(9)), SourcePick(.none)] {
    check(Wire.decode(SourcePick.self, from: Wire.encode(p)) == p, "round trip \(p)")
    check(Wire.decode(StreamSource.self, from: Wire.encode(p)) == p.source, "an older host reads \(p) as its source")
}

// MARK: - The host's order (DesktopDisplays.ordered, the plan's rule 1)

let builtIn = display(1, "Built-in Retina Display", x: 0, main: true)
let lgRight = display(2, "LG UltraFine", x: 1512, w: 2560, h: 1440)
let dellRight = display(3, "DELL U2723QE", x: 4072, w: 2560, h: 1440)
let leftOne = display(4, "Studio Display", x: -2560, w: 2560, h: 1440)
let farLeft = display(5, "Sidecar Display", x: -3740, w: 1180, h: 820)
let sill = display(0x5111_0001, "Sill", x: -9000, w: 4096, h: 4096, sill: true)

check(ids(DesktopDisplays.ordered([builtIn, lgRight])) == [1, 2], "the laptop and one on its right")
check(ids(DesktopDisplays.ordered([lgRight, builtIn])) == [1, 2], "the main one first whatever ScreenCaptureKit lists first")
check(ids(DesktopDisplays.ordered([leftOne, builtIn, lgRight])) == [1, 2, 4], "the right one, then round to the left one")
check(ids(DesktopDisplays.ordered([dellRight, leftOne, farLeft, builtIn, lgRight])) == [1, 2, 3, 5, 4],
      "rightwards from the main one, then from the leftmost: \(ids(DesktopDisplays.ordered([dellRight, leftOne, farLeft, builtIn, lgRight])))")
check(ids(DesktopDisplays.ordered([sill, builtIn, lgRight])) == [1, 2], "Sill's own virtual display never listed")
check(ids(DesktopDisplays.ordered([sill])) == [], "Sill's alone: nothing")
check(ids(DesktopDisplays.ordered([])) == [], "nothing: nothing")
check(ids(DesktopDisplays.ordered([builtIn, lgRight, display(2, "LG UltraFine again", x: 9000)])) == [1, 2]
      && DesktopDisplays.ordered([builtIn, lgRight, display(2, "LG UltraFine again", x: 9000)])[1].name == "LG UltraFine",
      "a duplicate ID keeps its first")
// One above the main one, its left edge on the main one's: on the right side of the split; two on one
// left edge go the higher first; two on one corner by ID.
let above = display(6, "Above", x: 0, y: -1440, w: 2560, h: 1440)
let below = display(7, "Below", x: 0, y: 982, w: 1512, h: 982)
check(ids(DesktopDisplays.ordered([lgRight, above, builtIn])) == [1, 6, 2], "one above the main one counts as on its right, at its left edge")
check(ids(DesktopDisplays.ordered([below, above, builtIn])) == [1, 6, 7], "two on one left edge: the higher first")
check(ids(DesktopDisplays.ordered([display(9, "B", x: 1512), display(8, "A", x: 1512), builtIn])) == [1, 8, 9], "one corner: by ID")
// No main among them (macOS always has one): the first stands in.
check(ids(DesktopDisplays.ordered([lgRight, dellRight])) == [2, 3], "no main: the first stands in")
check(ids(DesktopDisplays.ordered([dellRight, lgRight, leftOne])) == [3, 4, 2] , "no main, the first on the right: rightwards from it, then round")
// The main display moved elsewhere in the arrangement (System Settings › Displays): it still leads.
let mainOnRight = [display(1, "Built-in", x: -1512), display(2, "LG", x: 0, w: 2560, h: 1440, main: true), display(3, "DELL", x: 2560)]
check(ids(DesktopDisplays.ordered(mainOnRight)) == [2, 3, 1], "the main one leads wherever it is")

// MARK: - The display a pick streams (resolve, rule 2)

let two = DesktopDisplays.ordered([builtIn, lgRight])
check(DesktopDisplays.resolve(2, in: two)?.id == 2, "a listed display: that one")
check(DesktopDisplays.resolve(nil, in: two)?.id == 1, "none named: the main one")
check(DesktopDisplays.resolve(99, in: two)?.id == 1, "one not listed: the main one")
check(DesktopDisplays.resolve(nil, in: [lgRight, dellRight])?.id == 2, "no main listed: the first")
check(DesktopDisplays.resolve(nil, in: [lgRight, builtIn])?.id == 1 && DesktopDisplays.resolve(7, in: [dellRight, lgRight, builtIn])?.id == 1,
      "the main one wherever it stands in the list")
check(DesktopDisplays.resolve(1, in: []) == nil && DesktopDisplays.resolve(nil, in: []) == nil, "none listed: none")

// MARK: - The window list's entries, the lines, the names

let infos = DesktopDisplays.infos(two)
check(infos == [DisplayInfo(id: 1, name: "Built-in Retina Display", width: 1512, height: 982, main: true),
                DisplayInfo(id: 2, name: "LG UltraFine", width: 2560, height: 1440)], "the list's entries: \(infos)")
check(DesktopDisplays.infos([]).isEmpty, "none: none")
check(DesktopDisplays.which(builtIn, in: [builtIn]) == nil, "one display: the stream's line as it was")
check(DesktopDisplays.which(lgRight, in: two) == "LG UltraFine (2 of 2)", "two: which, of how many")
check(DesktopDisplays.which(dellRight, in: two) == nil, "a display not listed: nothing")
check(DesktopDisplays.missingLine(asked: 3, instead: builtIn, in: two)
      == "Desktop: display 3 is not connected; streaming Built-in Retina Display (1 of 2), the main display.",
      "the missing line: \(DesktopDisplays.missingLine(asked: 3, instead: builtIn, in: two))")
check(DesktopDisplays.missingLine(asked: 3, instead: builtIn, in: [builtIn])
      == "Desktop: display 3 is not connected; streaming Built-in Retina Display, the main display.", "missing, one display left")
check(DesktopDisplays.missingLine(asked: 3, instead: nil, in: []) == "Desktop: display 3 is not connected; no other display is listed.",
      "missing, none listed")
check(DesktopDisplays.goneLine(lgRight, instead: builtIn, in: [builtIn])
      == "Desktop: LG UltraFine is gone; streaming Built-in Retina Display, the main display, instead.",
      "the gone line: \(DesktopDisplays.goneLine(lgRight, instead: builtIn, in: [builtIn]))")
check(DesktopDisplays.goneLine(lgRight, instead: dellRight, in: [dellRight, leftOne])
      == "Desktop: LG UltraFine is gone; streaming DELL U2723QE (1 of 2) instead.", "gone, the stand-in not the main one")
check(DesktopDisplays.goneLine(lgRight, instead: nil, in: []) == "Desktop: LG UltraFine is gone; no other display is listed.", "gone, none left")
check(DesktopDisplays.name("LG UltraFine", builtIn: false) == "LG UltraFine", "macOS's name")
check(DesktopDisplays.name(nil, builtIn: true) == "Built-in Display" && DesktopDisplays.name("", builtIn: false) == "Display",
      "no name from NSScreen: a stand-in")
check(DesktopDisplays.name("LG\nUltra\u{202E}Fine\t", builtIn: false) == "LG UltraFine", "cleaned as text from a device is")
check(DesktopDisplays.name(String(repeating: "x", count: 200), builtIn: false).count == SafeText.labelLimit, "capped")
check(DesktopDisplays.name("\u{200B}\u{202E}", builtIn: true) == "Built-in Display", "nothing printable: the stand-in")

// MARK: - TEST ONLY: SILL_TEST_DISPLAYS

check(DesktopDisplays.testSpec("2") == .init(count: 2, goneAfter: nil) && DesktopDisplays.testSpec(" 4 ") == .init(count: 4, goneAfter: nil),
      "2 and 4")
check(DesktopDisplays.testSpec("3@20") == .init(count: 3, goneAfter: 20) && DesktopDisplays.testSpec("2@0.5") == .init(count: 2, goneAfter: 0.5),
      "N@S")
for bad in ["1", "5", "0", "-2", "x", "2@", "@3", "2@-1", "2@x", "2@1@2", "2@inf", "2@nan", "", "  "] {
    check(DesktopDisplays.testSpec(bad) == nil, "\(bad.debugDescription) is not read")
}
check(DesktopDisplays.testSpec(nil) == nil, "unset")
let one = DesktopDisplays.testDisplays(count: 1)
check(one == [D(id: 1, name: "Test Pattern", frame: CGRect(x: 0, y: 0, width: 1512, height: 949), isMain: true)],
      "one test pattern, as every synthetic host always streamed: \(one)")
let four = DesktopDisplays.testDisplays(count: 4)
check(ids(four) == [1, 2, 3, 4] && four.map(\.name) == ["Test Pattern", "Test Pattern 2", "Test Pattern 3", "Test Pattern 4"],
      "four, named")
check(four.map(\.frame) == [CGRect(x: 0, y: 0, width: 1512, height: 949), CGRect(x: 1512, y: 0, width: 1440, height: 900),
                            CGRect(x: 2952, y: 0, width: 1280, height: 800), CGRect(x: 4232, y: 0, width: 1920, height: 1080)],
      "side by side: \(four.map(\.frame))")
check(four.filter(\.isMain).map(\.id) == [1], "the first is the main one")
check(DesktopDisplays.ordered(four) == four, "listed in the order the devices step")
check(DesktopDisplays.testDisplays(count: 9).count == 4 && DesktopDisplays.testDisplays(count: 0) == one, "clamped to 1…4")

// MARK: - The device: the steps, the display shown, a tap (DisplayStepping, rules 1 to 3)

let bi = DisplayInfo(id: 1, name: "Built-in Retina Display", width: 1512, height: 982, main: true)
let lg = DisplayInfo(id: 69733632, name: "LG UltraFine", width: 2560, height: 1440)
let dell = DisplayInfo(id: 69733633, name: "DELL U2723QE", width: 2560, height: 1440)
check(DisplayStepping.steps(nil).isEmpty && DisplayStepping.steps([]).isEmpty && DisplayStepping.steps([bi]).isEmpty,
      "fewer than two: no steps")
check(DisplayStepping.steps([bi, lg]) == [bi, lg] && DisplayStepping.steps([bi, lg, dell]) == [bi, lg, dell], "two or more, in the Mac's order")
check(DisplayStepping.steps([bi, bi]).isEmpty && DisplayStepping.steps([bi, lg, bi]) == [bi, lg], "a duplicate ID dropped")
let s2 = [bi, lg], s3 = [bi, lg, dell]
check(DisplayStepping.shown([], desktop: 1, asked: 1) == nil, "no steps: nothing shown")
check(DisplayStepping.shown(s2, desktop: nil, asked: nil) == 0, "nothing said: the main one")
check(DisplayStepping.shown([lg, bi], desktop: nil, asked: nil) == 1, "the main one wherever it is")
check(DisplayStepping.shown([lg, dell], desktop: nil, asked: nil) == 0, "no main: the first")
check(DisplayStepping.shown(s3, desktop: lg.id, asked: nil) == 1, "the Mac's word")
check(DisplayStepping.shown(s3, desktop: lg.id, asked: dell.id) == 2, "this device's pick over the Mac's word")
check(DisplayStepping.shown(s3, desktop: lg.id, asked: 7) == 1, "a pick not listed: the Mac's word")
check(DisplayStepping.shown(s3, desktop: 7, asked: nil) == 0, "the Mac's word not listed: the main one")
check(DisplayStepping.pick([], shown: nil, desktopStreams: true) == nil && DisplayStepping.pick([], shown: 0, desktopStreams: false) == nil,
      "no steps: today's pick")
check(DisplayStepping.pick(s3, shown: 0, desktopStreams: true) == lg.id, "from the Desktop: the next")
check(DisplayStepping.pick(s3, shown: 2, desktopStreams: true) == bi.id, "from the last: round to the first")
check(DisplayStepping.pick(s3, shown: 1, desktopStreams: false) == lg.id, "from a window: the one shown")
check(DisplayStepping.pick(s3, shown: nil, desktopStreams: false) == bi.id && DisplayStepping.pick(s3, shown: 9, desktopStreams: true) == bi.id,
      "nothing shown, or out of range: from the ends")

// MARK: - The face (rules 4 and 5)

check(DisplayStepping.face([], shown: nil, desktopStreams: true) == DisplayStepping.plain
      && DisplayStepping.plain == DisplayStepping.Face(label: "Desktop", accessibilityLabel: "Show the full Mac desktop", hint: nil, largeTitle: "Desktop"),
      "fewer than two: today's button, word for word")
let streaming = DisplayStepping.face(s2, shown: 0, desktopStreams: true)
check(streaming == DisplayStepping.Face(label: "1 of 2", accessibilityLabel: "Desktop, Built-in Retina Display, 1 of 2",
                                        hint: "Shows the next display, LG UltraFine.", largeTitle: "Desktop, 1 of 2"),
      "the Desktop on the first of two: \(streaming)")
let fromWindow = DisplayStepping.face(s3, shown: 1, desktopStreams: false)
check(fromWindow == DisplayStepping.Face(label: "2 of 3", accessibilityLabel: "Desktop, LG UltraFine, 2 of 3",
                                         hint: "Shows this display’s desktop.", largeTitle: "Desktop, 2 of 3"),
      "a window streams, the label on the second of three: \(fromWindow)")
check(DisplayStepping.face(s3, shown: 2, desktopStreams: true).hint == "Shows the next display, Built-in Retina Display.", "the next from the last is the first")
check(DisplayStepping.face(s2, shown: 5, desktopStreams: true) == DisplayStepping.plain, "a shown out of range: the plain button")
let odd = [bi, DisplayInfo(id: 9, name: "\u{202E}\n", width: 1, height: 1)]
check(DisplayStepping.face(odd, shown: 1, desktopStreams: false).accessibilityLabel == "Desktop, Display 2, 2 of 2", "a name with nothing printable")
check(DisplayStepping.face([bi, DisplayInfo(id: 9, name: "Side\ncar", width: 1, height: 1)], shown: 0, desktopStreams: true).hint
      == "Shows the next display, Side car.", "names cleaned")

// MARK: - A pick that stands (rule 6)

check(DisplayStepping.askHold(rttMs: nil) == 3 && DisplayStepping.askHold(rttMs: 500) == 3 && DisplayStepping.askHold(rttMs: -40) == 3,
      "three seconds at home")
check(DisplayStepping.askHold(rttMs: 1000) == 4 && DisplayStepping.askHold(rttMs: 2500) == 10, "four round trips from afar")
check(DisplayStepping.askStands(lg.id, askedAt: 10, now: 11, hold: 3, steps: s2, desktop: bi.id), "standing")
check(!DisplayStepping.askStands(lg.id, askedAt: 10, now: 13, hold: 3, steps: s2, desktop: bi.id), "past its hold")
check(!DisplayStepping.askStands(lg.id, askedAt: 10, now: 11, hold: 3, steps: s2, desktop: lg.id), "the Mac took it")
check(!DisplayStepping.askStands(dell.id, askedAt: 10, now: 11, hold: 3, steps: s2, desktop: bi.id), "no longer listed")

// MARK: - Random sessions: a Mac and its devices
//
// The Mac's side is a copy of StreamCoordinator's glue around DesktopDisplays (`handlePick`, select's
// Desktop branch, `displaysChanged`, the list); the devices run DisplayStepping as StreamClient does
// (`tapDesktop`, `desktopPick`, `receiveDisplays`). Devices from before pick the Desktop with no display.

struct Mac {
    var displays: [D]                 // as the catalog lists them, unordered
    var desktopDisplayID: UInt32?
    var streamed: D?
    var active: StreamSource = .none
    var lines: [String] = []
    var listed: [D] { DesktopDisplays.ordered(displays) }
    var shown: D? {
        if active == .desktop, let s = streamed, let d = listed.first(where: { $0.id == s.id }) { return d }
        return DesktopDisplays.resolve(desktopDisplayID, in: listed)
    }
    var list: WindowList {
        WindowList(macName: "M", windows: [], active: active, displays: listed.isEmpty ? nil : DesktopDisplays.infos(listed),
                   desktopDisplay: listed.isEmpty ? nil : shown?.id)
    }
    mutating func pick(_ payload: Data) {
        guard let p = Wire.decode(SourcePick.self, from: payload) else { return }
        if p.source == .desktop { desktopDisplayID = p.display }
        switch p.source {
        case .desktop:
            let s = DesktopDisplays.resolve(desktopDisplayID, in: listed)
            if let asked = desktopDisplayID, s?.id != asked { lines.append(DesktopDisplays.missingLine(asked: asked, instead: s, in: listed)); desktopDisplayID = nil }
            streamed = s
            active = s == nil ? .none : .desktop
        case .window(let id): active = .window(id); streamed = nil
        case .none: active = .none; streamed = nil
        }
    }
    mutating func unplug(_ id: UInt32) {
        displays.removeAll { $0.id == id }
        guard active == .desktop, let gone = streamed, !listed.contains(where: { $0.id == gone.id }) else { return }
        lines.append(DesktopDisplays.goneLine(gone, instead: DesktopDisplays.resolve(nil, in: listed), in: listed))
        desktopDisplayID = nil
        streamed = DesktopDisplays.resolve(nil, in: listed)
        if streamed == nil { active = .none }
    }
}

struct Device {
    var old: Bool
    var displays: [DisplayInfo] = []
    var desktop: UInt32?
    var active: StreamSource = .none
    var ask: (display: UInt32, at: Double)?
    var steps: [DisplayInfo] { DisplayStepping.steps(displays) }
    var shownIndex: Int? { DisplayStepping.shown(steps, desktop: desktop, asked: ask?.display) }
    mutating func receive(_ list: WindowList, now: Double) {
        displays = list.displays ?? []; desktop = list.desktopDisplay; active = list.active
        if let a = ask, !DisplayStepping.askStands(a.display, askedAt: a.at, now: now, hold: 3, steps: steps, desktop: desktop) { ask = nil }
    }
    /// The Desktop button's tap: what goes on the wire.
    mutating func tap(now: Double) -> Data {
        if old { return Wire.encode(StreamSource.desktop) }
        let p = SourcePick(.desktop, display: DisplayStepping.pick(steps, shown: shownIndex, desktopStreams: active == .desktop))
        if let d = p.display { ask = (d, now) }
        return Wire.encode(p)
    }
    var face: DisplayStepping.Face { DisplayStepping.face(steps, shown: shownIndex, desktopStreams: active == .desktop) }
}

var rng = SystemRandomNumberGenerator()
var modelFailures = 0
var stepsTaken = 0
var judged = (fromDesktop: 0, fromWindow: 0, old: 0, unplugged: 0, gone: 0, cycles: 0, faces: 0)
func fail(_ what: String) { modelFailures += 1; if modelFailures <= 10 { print("FAIL (model): \(what)") } }
func arrangement(_ n: Int) -> [D] {
    // The main display at 0,0, some to its left and the rest to its right, now and then one above, and
    // now and then Sill's own (a staged window's); shuffled, as ScreenCaptureKit lists them.
    let left = Int.random(in: 0..<n, using: &rng)
    var out: [D] = (0..<n).map { i in
        let w = CGFloat([1512, 1440, 2560, 1920].randomElement(using: &rng)!)
        let y: CGFloat = i != left && Int.random(in: 0..<5, using: &rng) == 0 ? -1440 : 0
        return display(UInt32(100 + i), "Display \(100 + i)", x: CGFloat(i - left) * 3000, y: y, w: w, h: w * 0.6, main: i == left)
    }
    if Bool.random(using: &rng) { out.append(display(0x5111_0002, "Sill", x: 90000, sill: true)) }
    return out.shuffled(using: &rng)
}

for session in 0..<4000 {
    let n = Int.random(in: 1...4, using: &rng)
    var mac = Mac(displays: arrangement(n))
    var devices = (0..<Int.random(in: 1...3, using: &rng)).map { _ in Device(old: Int.random(in: 0..<4, using: &rng) == 0) }
    var now = 0.0
    func deliver() { for i in devices.indices { devices[i].receive(mac.list, now: now) } }
    deliver()
    for _ in 0..<40 {
        now += Double.random(in: 0.05...2, using: &rng)
        stepsTaken += 1
        let i = Int.random(in: 0..<devices.count, using: &rng)
        switch Int.random(in: 0..<10, using: &rng) {
        case 0...5:
            // A tap on the Desktop button, the list back at once (or, sometimes, after another tap).
            let before = mac.shown?.id
            let wasDesktop = mac.active == .desktop && devices[i].active == .desktop
            let current = devices[i].steps.count >= 2 && devices[i].desktop == before && devices[i].ask == nil
            let payload = devices[i].tap(now: now)
            let pick = Wire.decode(SourcePick.self, from: payload)
            if devices[i].old || devices[i].steps.count < 2 {
                if String(decoding: payload, as: UTF8.self) != #"{"desktop":{}}"# { fail("session \(session): a pick with fewer than two displays, or from an old device, is not today's bytes") }
            }
            mac.pick(payload)
            if devices[i].old { judged.old += 1 }
            if devices[i].old, mac.shown?.id != DesktopDisplays.resolve(nil, in: mac.listed)?.id {
                fail("session \(session): an old device's Desktop is not the main display")
            }
            if !devices[i].old, current, mac.listed.count >= 2, let before {
                let order = mac.listed.map(\.id)
                let at = order.firstIndex(of: before)!
                let want = wasDesktop ? order[(at + 1) % order.count] : before
                if wasDesktop { judged.fromDesktop += 1 } else { judged.fromWindow += 1 }
                if mac.shown?.id != want { fail("session \(session): a tap went to \(String(describing: mac.shown?.id)), not \(want) (\(wasDesktop ? "from the Desktop" : "from a window"))") }
            }
            if let d = pick?.display, let k = devices[i].steps.firstIndex(where: { $0.id == d }),
               devices[i].face.label != "\(k + 1) of \(devices[i].steps.count)" {
                fail("session \(session): the face does not show the pick at once")
            }
            if Int.random(in: 0..<4, using: &rng) > 0 { deliver() }
        case 6:
            // A window picked.
            mac.pick(Wire.encode(StreamSource.window(UInt32.random(in: 1...9, using: &rng)))); deliver()
        case 7:
            // A display unplugged (sometimes the main one: macOS then makes another main), or one plugged in.
            if mac.displays.filter({ !$0.isSill }).count > 1, Bool.random(using: &rng) {
                let victim = mac.displays.filter { !$0.isSill }.randomElement(using: &rng)!
                let wasMain = victim.isMain
                judged.unplugged += 1
                if mac.active == .desktop, mac.streamed?.id == victim.id { judged.gone += 1 }
                mac.unplug(victim.id)
                if wasMain, let k = mac.displays.firstIndex(where: { !$0.isSill }) { mac.displays[k].isMain = true }
                if mac.active == .desktop, mac.streamed.map({ s in !mac.listed.contains { $0.id == s.id } }) ?? true {
                    fail("session \(session): the Desktop streams a display gone")
                }
            } else if mac.displays.count < 6 {
                let id = UInt32(200 + Int.random(in: 0..<50, using: &rng))
                if !mac.displays.contains(where: { $0.id == id }) { mac.displays.append(display(id, "New \(id)", x: CGFloat.random(in: -9000...9000, using: &rng))) }
            }
            deliver()
        default:
            // Time passes; the lists come.
            now += 4; deliver()
        }
        // Invariants after each step.
        if mac.active == .desktop, mac.streamed.map({ s in !mac.listed.contains { $0.id == s.id } }) ?? true {
            fail("session \(session): the Desktop streams a display not listed")
        }
        if mac.listed.contains(where: \.isSill) { fail("session \(session): Sill's own display listed") }
        for d in devices where d.ask == nil && d.displays == (mac.list.displays ?? []) && d.desktop == mac.list.desktopDisplay {
            let face = d.face
            if mac.listed.count < 2 {
                if face != DisplayStepping.plain { fail("session \(session): one display, not today's button: \(face)") }
            } else if let shown = mac.shown, let k = mac.listed.firstIndex(where: { $0.id == shown.id }) {
                judged.faces += 1
                if face.label != "\(k + 1) of \(mac.listed.count)" { fail("session \(session): the face says \(face.label), the Mac shows \(k + 1) of \(mac.listed.count)") }
            }
        }
    }
    // Every display in turn: as many taps from the Desktop as the Mac has displays come back to the start.
    var dev = Device(old: false)
    dev.receive(mac.list, now: now)
    if mac.listed.count >= 2 {
        mac.pick(dev.tap(now: now)); now += 5; dev.receive(mac.list, now: now)   // from wherever: the Desktop, on the display shown
        let start = mac.shown?.id
        var seen: [UInt32] = []
        for _ in 0..<mac.listed.count {
            mac.pick(dev.tap(now: now)); now += 5; dev.receive(mac.list, now: now)
            if let s = mac.shown?.id { seen.append(s) }
        }
        judged.cycles += 1
        if mac.shown?.id != start || Set(seen).count != mac.listed.count {
            fail("session \(session): \(mac.listed.count) taps did not visit every display and come back: \(seen)")
        }
    }
}
print("model: \(stepsTaken) steps; taps judged against the order: \(judged.fromDesktop) from the Desktop, \(judged.fromWindow) from a window; "
      + "\(judged.old) older devices' picks; \(judged.unplugged) displays unplugged, \(judged.gone) of them under the Desktop; "
      + "\(judged.faces) faces against the Mac's; \(judged.cycles) full turns")
check(modelFailures == 0, "4,000 random sessions (\(stepsTaken) steps): \(modelFailures) failures")
check(judged.fromDesktop > 1000 && judged.fromWindow > 1000 && judged.old > 1000 && judged.gone > 100 && judged.cycles > 1000,
      "the sessions reach every rule: \(judged)")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
