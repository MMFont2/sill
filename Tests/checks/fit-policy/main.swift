import Foundation
import CoreGraphics

// Checks FitPolicy (Sources/SillHost/FitPolicy.swift; docs/fit-by-default-plan.md, issue #70): when
// Sill fits a window it streams in regular mode to a device, and to which size. First the rule at its
// edges: the fit (Aa's scale whatever the setting, 1× by default with Aa unset, nothing with the setting
// off, malformed panels and scales), the size's rounding, the 2 pt compare, a move, the memory of fits
// that left the window as it was (`Asks`), a change of the setting while a window streams, what kind
// 16's `stream.fitsPanel` says, and the log's words. Then a model: a copy of the coordinator's
// `fitToViewport`, `applyFitSetting` and a pick's fresh start around the real rule, against a stand-in
// app (a minimum, a window that cannot be resized, full screen): random sessions of viewports, the same
// viewport sent again, Aa, the setting turned on and off, the person at the Mac resizing the window or
// taking it into or out of full screen, restarts and picks, each window held to where it should be and
// no fit asked twice for nothing.
//
// Compiled alone with this file: swiftc -O Sources/SillHost/FitPolicy.swift main.swift

var failures = 0
var passes = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    if ok { passes += 1 } else { failures += 1; if failures <= 40 { print("FAIL: \(what())") } }
}
func eq<T: Equatable>(_ got: T, _ want: T, _ what: String) { check(got == want, "\(what): got \(got), want \(want)") }
func S(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }
func fit(_ size: CGSize, _ scale: Double, _ reason: FitPolicy.Reason) -> FitPolicy.Fit { FitPolicy.Fit(size: size, scale: scale, reason: reason) }

// MARK: The fit

let ipad = S(1000, 710)                       // the Duo's guess, sideways (docs/iphone-duo-plan.md)
eq(FitPolicy.defaultScale, 1.0, "the default scale is Aa's 1×")
eq(FitPolicy.fit(panel: ipad, scale: nil, fitWindows: true), fit(S(1000, 710), 1, .byDefault), "Aa unset, the setting on: the panel at 1×")
eq(FitPolicy.fit(panel: ipad, scale: nil, fitWindows: false), nil, "Aa unset, the setting off: leave the window alone")
for on in [true, false] {
    eq(FitPolicy.fit(panel: ipad, scale: 1.5, fitWindows: on), fit(S(667, 473), 1.5, .textScale), "Aa 1.5× (setting \(on)): a third smaller, rounded")
    eq(FitPolicy.fit(panel: ipad, scale: 1.0, fitWindows: on), fit(S(1000, 710), 1.0, .textScale), "Aa 1× (setting \(on)): Aa's own, not the default")
    eq(FitPolicy.fit(panel: ipad, scale: 0.75, fitWindows: on), fit(S(1333, 947), 0.75, .textScale), "Aa 0.75× (setting \(on))")
    eq(FitPolicy.fit(panel: ipad, scale: 0.5, fitWindows: on), fit(S(2000, 1420), 0.5, .textScale), "Aa 0.5× (setting \(on)): twice the panel")
    eq(FitPolicy.fit(panel: ipad, scale: 1.25, fitWindows: on), fit(S(800, 568), 1.25, .textScale), "Aa 1.25× (setting \(on))")
    for bad in [0.0, -1.0, -0.5, 0.2, 0.249, 4.01, 10, 1e-300, 1e300, Double.nan, Double.infinity, -Double.infinity] {
        eq(FitPolicy.fit(panel: ipad, scale: bad, fitWindows: on), nil, "a scale of \(bad) (setting \(on)): no device's Aa, the window left alone, never the default")
    }
    eq(FitPolicy.fit(panel: ipad, scale: 0.25, fitWindows: on), fit(S(4000, 2840), 0.25, .textScale), "the smallest scale taken, 0.25× (setting \(on))")
    eq(FitPolicy.fit(panel: ipad, scale: 4, fitWindows: on), fit(S(250, 178), 4, .textScale), "the largest scale taken, 4× (setting \(on))")
    eq(FitPolicy.fit(panel: nil, scale: nil, fitWindows: on), nil, "no viewport yet (setting \(on))")
    eq(FitPolicy.fit(panel: nil, scale: 1.5, fitWindows: on), nil, "no viewport yet, a scale (setting \(on))")
    for empty in [S(0, 710), S(1000, 0), S(-1, 710), S(1000, -2), S(0, 0)] {
        eq(FitPolicy.fit(panel: empty, scale: nil, fitWindows: on), nil, "an empty panel \(empty) (setting \(on))")
        eq(FitPolicy.fit(panel: empty, scale: 1.0, fitWindows: on), nil, "an empty panel \(empty) at Aa 1× (setting \(on))")
    }
}
// The panels the device's layouts send (CLAUDE.md, docs/iphone-portrait-plan.md, docs/larger-picture-plan.md).
for (what, panel, want) in [("an iPhone 18 Pro's 16:10 pane", S(386, 241), S(386, 241)),
                            ("an 18 Pro Max's pane", S(424, 265), S(424, 265)),
                            ("a 15 Pro's Larger Picture room", S(377, 340), S(377, 340)),
                            ("a half point", S(386.5, 241.5), S(387, 242)),
                            ("a scaled harness screen's 693.99…", S(693.99, 409.4), S(694, 409)),
                            ("an iPad Pro 13 sideways", S(1366, 960), S(1366, 960))] {
    eq(FitPolicy.fit(panel: panel, scale: nil, fitWindows: true)?.size, want, "\(what), by default")
}
eq(FitPolicy.fit(panel: S(0.4, 300), scale: nil, fitWindows: true), nil, "a side that rounds to nothing at 1×")
eq(FitPolicy.fit(panel: S(0.4, 300), scale: 0.5, fitWindows: true), fit(S(1, 600), 0.5, .textScale), "…but not at 0.5×")
eq(FitPolicy.fit(panel: S(1000, 0.49), scale: 1, fitWindows: true), nil, "a height that rounds to nothing")
eq(FitPolicy.fit(panel: S(1000, 0.5), scale: 1, fitWindows: true), fit(S(1000, 1), 1, .textScale), "half a point rounds to one")
eq(FitPolicy.scales, 0.25...4, "the scales taken: Aa's 0.5× to 1.5× with room either side")
eq(FitPolicy.maxSide, 16_384, "the longest side asked")
eq(FitPolicy.fit(panel: S(16_384, 710), scale: nil, fitWindows: true), fit(S(16_384, 710), 1, .byDefault), "a side of 16,384 pt is taken")
eq(FitPolicy.fit(panel: S(16_385, 710), scale: nil, fitWindows: true), nil, "a side past 16,384 pt is no device's panel")
eq(FitPolicy.fit(panel: S(710, 4097), scale: 0.25, fitWindows: true), nil, "…nor 16,388 pt at 0.25×")
eq(FitPolicy.fit(panel: S(1e9, 1e9), scale: nil, fitWindows: true), nil, "a panel of a billion points")
eq(FitPolicy.fit(panel: S(.infinity, 710), scale: nil, fitWindows: true), nil, "an infinite panel")

// MARK: The size

eq(FitPolicy.size(panel: S(1000, 710), scale: 1.5), S(667, 473), "size: 666.67 × 473.33 rounds to 667 × 473")
eq(FitPolicy.size(panel: S(1000, 710), scale: 3), S(333, 237), "size: 333.33 × 236.67")
eq(FitPolicy.size(panel: S(1, 1), scale: 2), S(1, 1), "size: half a point rounds up to one")
eq(FitPolicy.size(panel: S(1, 1), scale: 2.01), nil, "size: under half a point is nothing")
eq(FitPolicy.size(panel: S(.nan, 10), scale: 1), nil, "size: not a number")
eq(FitPolicy.size(panel: S(10, .nan), scale: 1), nil, "size: not a number, the height")
eq(FitPolicy.size(panel: S(16_384, 16_384), scale: 1), S(16_384, 16_384), "size: 16,384 pt on both sides")
eq(FitPolicy.size(panel: S(16_384.6, 100), scale: 1), nil, "size: rounding past 16,384")

// MARK: The compare and a move

eq(FitPolicy.tolerance, 2, "the tolerance is WindowRestore's 2 pt")
eq(FitPolicy.needsResize(current: S(1000, 710), target: S(1000, 710)), false, "at the size: no resize")
eq(FitPolicy.needsResize(current: S(1002, 708), target: S(1000, 710)), false, "2 pt off each way: there")
eq(FitPolicy.needsResize(current: S(1002.5, 710), target: S(1000, 710)), true, "2.5 pt wider: not there")
eq(FitPolicy.needsResize(current: S(1000, 707.5), target: S(1000, 710)), true, "2.5 pt shorter: not there")
eq(FitPolicy.needsResize(current: S(600, 400), target: S(1000, 710)), true, "a smaller window: fitted up")
eq(FitPolicy.needsResize(current: S(1512, 900), target: S(1000, 710)), true, "a larger window: fitted down")
eq(FitPolicy.moved(from: S(600, 400), to: S(600, 400)), false, "moved: the same size is not")
eq(FitPolicy.moved(from: S(600, 400), to: S(600.9, 399.1)), false, "moved: under a point is not")
eq(FitPolicy.moved(from: S(600, 400), to: S(601, 400)), true, "moved: a point wider is")
eq(FitPolicy.moved(from: S(600, 400), to: S(600, 399)), true, "moved: a point shorter is")

// MARK: Not asking again for nothing

do {
    typealias Short = FitPolicy.Asks.Short
    var a = FitPolicy.Asks()
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(600, 400)), true, "asks: nothing remembered, ask")
    a.asked(window: 7, target: S(1000, 710), after: S(600, 400))                       // refused
    eq(a.short, Short(window: 7, asked: S(1000, 710), at: S(600, 400)), "asks: a refusal remembered")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(600, 400)), false, "asks: the same again is not asked")
    eq(a.shouldAsk(window: 7, target: S(1002, 708), current: S(598, 402)), false, "asks: within 2 pt is the same")
    eq(a.shouldAsk(window: 7, target: S(1003, 710), current: S(600, 400)), true, "asks: another size asked (a rotation, Aa)")
    eq(a.shouldAsk(window: 7, target: S(1000, 707), current: S(600, 400)), true, "asks: 3 pt shorter asked")
    eq(a.shouldAsk(window: 7, target: S(710, 1000), current: S(600, 400)), true, "asks: turned upright")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(603, 400)), true, "asks: the window resized since (the person, full screen left, a late app)")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(600, 397)), true, "asks: 3 pt shorter since")
    eq(a.shouldAsk(window: 8, target: S(1000, 710), current: S(600, 400)), true, "asks: another window")
    a.asked(window: 7, target: S(1000, 710), after: S(1001, 709))                     // it took it
    eq(a.short, nil, "asks: a fit that got there is forgotten")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(600, 400)), true, "asks: …so the same is asked again")
    a.asked(window: 7, target: S(1000, 710), after: S(1100, 750))                     // clamped to its minimum
    eq(a.short, Short(window: 7, asked: S(1000, 710), at: S(1100, 750)), "asks: short of it at its minimum: where it ended remembered")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(1100, 750)), false, "asks: …not asked again from there")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(1200, 800)), true, "asks: …but from where it was before, yes")
    a.asked(window: 7, target: S(1000, 710), after: S(1003, 710))                     // 3 pt short: a grid
    eq(a.short?.at, S(1003, 710), "asks: 3 pt short is short")
    a.asked(window: 9, target: S(386, 241), after: S(500, 400))
    eq(a.short?.window, 9, "asks: one window remembered, the newest")
    eq(a.shouldAsk(window: 7, target: S(1000, 710), current: S(1003, 710)), true, "asks: …the one before is asked again")
    eq(FitPolicy.Asks(), FitPolicy.Asks(), "asks: a fresh start remembers nothing")
    eq(FitPolicy.Asks().short, nil, "asks: a fresh start remembers nothing (short)")
}

// MARK: The setting changed while a window streams

eq(FitPolicy.afterSettingChange(fitWindows: true, scale: nil, fitted: false), .fitNow, "on, Aa unset: fitted now")
eq(FitPolicy.afterSettingChange(fitWindows: true, scale: nil, fitted: true), .fitNow, "on, Aa unset, a fit on record: fitted now (the 2 pt compare skips one there)")
eq(FitPolicy.afterSettingChange(fitWindows: false, scale: nil, fitted: true), .putBack, "off, Aa unset, fitted: back now")
eq(FitPolicy.afterSettingChange(fitWindows: false, scale: nil, fitted: false), .nothing, "off, Aa unset, never fitted: nothing")
for on in [true, false] {
    for fitted in [true, false] {
        for scale in [0.5, 1.0, 1.5] {
            eq(FitPolicy.afterSettingChange(fitWindows: on, scale: scale, fitted: fitted), .nothing, "Aa \(scale)× keeps Aa's fit (setting \(on), fitted \(fitted))")
        }
    }
}

// MARK: What the device is told

let anyFit = fit(S(1000, 710), 1, .byDefault)
eq(FitPolicy.fitsPanel(window: false, onVirtualDisplay: false, fit: anyFit), false, "fitsPanel: never the Desktop")
eq(FitPolicy.fitsPanel(window: false, onVirtualDisplay: true, fit: nil), false, "fitsPanel: never the Desktop, whatever else")
eq(FitPolicy.fitsPanel(window: true, onVirtualDisplay: false, fit: anyFit), true, "fitsPanel: a window the setting fits")
eq(FitPolicy.fitsPanel(window: true, onVirtualDisplay: false, fit: fit(S(667, 473), 1.5, .textScale)), true, "fitsPanel: a window Aa fits")
eq(FitPolicy.fitsPanel(window: true, onVirtualDisplay: true, fit: nil), true, "fitsPanel: a window on the virtual display")
eq(FitPolicy.fitsPanel(window: true, onVirtualDisplay: false, fit: nil), false, "fitsPanel: a window left alone")

// MARK: The log

eq(FitPolicy.resizedLine(app: "Safari", took: S(667, 473), fit: fit(S(667, 473), 1.5, .textScale), panel: S(1000, 710)),
   "Resized Safari to 667×473 pt (asked 667×473 for a 1000×710 panel at 1.5×)", "the line for Aa's scale, as it always read")
eq(FitPolicy.resizedLine(app: "Notes", took: S(1000, 710), fit: fit(S(1000, 710), 1.0, .textScale), panel: S(1000, 710)),
   "Resized Notes to 1000×710 pt (asked 1000×710 for a 1000×710 panel at 1.0×)", "the line for Aa's 1×")
eq(FitPolicy.resizedLine(app: "Notes", took: S(1000, 720), fit: fit(S(1000, 710), 1.0, .byDefault), panel: S(1000, 710.4)),
   "Resized Notes to 1000×720 pt (asked 1000×710 for a 1000×710 panel at 1×, by default)", "the line for the setting's fit")
eq(FitPolicy.offLine, "Fit windows to the device's screen is off: a picked window keeps its size until the device sets one with Aa.",
   "the line at launch while the setting is off")

let unitPasses = passes, unitFailures = failures
print("fit-policy: the rule, \(unitPasses + unitFailures) cases, \(unitFailures) failed")

// MARK: The model: the coordinator's fit around the real rule, against a stand-in app

/// A seeded generator, so a failing session can be run again.
struct RNG {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
}

/// One window of the stand-in Mac and how its app takes a size (WindowSizer.resize through
/// Accessibility, as the coordinator calls it).
struct App {
    var minSize: CGSize
    var fixed: Bool          // cannot be resized: the size write is refused
    var size: CGSize
    var fullScreen = false
    var beforeFullScreen = CGSize.zero
    static let display = S(1512, 982)
    /// What a size write leaves: nothing in full screen or for a window that cannot be resized, else at
    /// least its minimum.
    func takes(_ s: CGSize) -> CGSize? {
        if fixed || fullScreen { return nil }
        return S(max(s.width, minSize.width), max(s.height, minSize.height))
    }
}

struct Session {
    var rng: RNG
    let seed: UInt64
    var app: App
    var window: CGWindowID = 1
    var panel: CGSize? = nil
    var scale: Double? = nil
    var fitWindows: Bool
    var asks = FitPolicy.Asks()
    var fitted = false                       // a fit on record (WindowRestore's ledger) for this window
    var ownSize: CGSize? = nil               // its size before Sill's first fit (WindowRestore's `original`)
    var asksMade = 0
    var lastAsk: (target: CGSize, at: CGSize, moved: Bool)? = nil
    var log: [String] = []
    var seen: [String: Int] = [:]

    init(seed: UInt64) {
        self.seed = seed
        rng = RNG(s: seed)
        let minSizes = [S(200, 150), S(700, 450), S(1100, 760), S(300, 200)]
        let m = minSizes[rng.int(minSizes.count)]
        let w = max(m.width, CGFloat(300 + rng.int(1200))), h = max(m.height, CGFloat(200 + rng.int(700)))
        app = App(minSize: m, fixed: rng.chance(0.15), size: S(w, h))
        fitWindows = rng.chance(0.7)
    }

    mutating func note(_ s: String) { seen[s, default: 0] += 1 }

    /// StreamCoordinator.fitToViewport around the real rule: the fit, the 2 pt compare, the memory, the
    /// write (WindowSizer.resize), and what is remembered.
    mutating func fitToViewport() {
        guard let f = FitPolicy.fit(panel: panel, scale: scale, fitWindows: fitWindows) else { return }
        let current = app.size
        guard FitPolicy.needsResize(current: current, target: f.size) else { return }
        guard asks.shouldAsk(window: window, target: f.size, current: current) else {
            // Skipped: the same ask left this window short, where it is now, and nothing changed since.
            check(lastAsk.map { !FitPolicy.needsResize(current: $0.target, target: f.size) && !FitPolicy.needsResize(current: $0.at, target: current) } == true,
                  "model seed \(seed): a fit skipped though the last ask did not leave the window here; \(log.suffix(6))")
            // Within the 2 pt every compare allows (Accessibility and the window server round differently).
            check(app.takes(f.size).map { !FitPolicy.needsResize(current: current, target: $0) } ?? true,
                  "model seed \(seed): a skipped fit would have moved the window from \(current) to \(String(describing: app.takes(f.size))); \(log.suffix(6))")
            note("not asked again")
            return
        }
        asksMade += 1
        let after = app.takes(f.size) ?? current
        if !app.fixed && !app.fullScreen {
            // WindowSizer.resize returned a fit: WindowRestore records it (the first keeps the frame before).
            if !fitted { ownSize = current }
            fitted = true
            app.size = after
        }
        if f.reason == .byDefault { note("asked by default") } else { note("asked for Aa") }
        asks.asked(window: window, target: f.size, after: after)
        let moved = FitPolicy.moved(from: current, to: after)
        lastAsk = (f.size, after, moved)
        note(moved ? "fit moved the window" : (app.fixed ? "fit refused" : (app.fullScreen ? "fit: full screen" : "fit at its minimum")))
    }

    /// Where the window should be now, if a fit applies and its app can take it: at the size asked, or
    /// at its minimum.
    func expectedSize() -> CGSize? {
        guard let f = FitPolicy.fit(panel: panel, scale: scale, fitWindows: fitWindows), let took = app.takes(f.size) else { return nil }
        return took
    }

    mutating func step() {
        switch rng.int(100) {
        case 0..<20:
            let panels = [S(1000, 710), S(710, 1000), S(1133, 744), S(386, 241), S(424, 265), S(377, 340), S(669, 418), S(1366, 960)]
            panel = panels[rng.int(panels.count)]
            log.append("viewport \(panel!)")
            fitToViewport()
        case 20..<40:
            // Every change in this model fits at once, as the coordinator does (a viewport, Aa, the setting,
            // a restart after the person resized the window or it left full screen, a pick), so the same
            // viewport sent again finds nothing new: it never asks, whatever the last ask came to.
            log.append("the same viewport again (the pointer showed or hid)")
            let before = asksMade
            fitToViewport()
            check(asksMade == before, "model seed \(seed): the same viewport sent again asked again; \(log.suffix(6))")
            note("re-sent")
        case 40..<50:
            let scales: [Double?] = [nil, 0.5, 0.75, 1, 1.25, 1.5]
            scale = scales[rng.int(scales.count)]
            log.append("Aa \(scale.map { "\($0)" } ?? "unset")")
            fitToViewport()
        case 50..<58:
            fitWindows.toggle()
            log.append("the setting \(fitWindows ? "on" : "off")")
            // StreamCoordinator.applyFitSetting.
            switch FitPolicy.afterSettingChange(fitWindows: fitWindows, scale: scale, fitted: fitted) {
            case .fitNow: note("setting on: fitted now"); fitToViewport()
            case .putBack:
                // restoreFits: back to its own size (whole: every change on the Mac was fitted again
                // here; window-restore's check has the other ways back), left as it is in full screen.
                note("setting off: put back")
                if !app.fullScreen, let own = ownSize { app.size = own }
                fitted = false
                ownSize = nil
            case .nothing: note("setting changed: nothing")
            }
        case 58..<68:
            guard !app.fullScreen, !app.fixed else { return }
            app.size = S(max(app.minSize.width, CGFloat(300 + rng.int(1200))), max(app.minSize.height, CGFloat(200 + rng.int(700))))
            log.append("the person resized it to \(app.size)")
            note("person resized")
            // The catalog's resize check restarts the stream, and the restart fits it again.
            fitToViewport()
        case 68..<74:
            if app.fullScreen {
                app.fullScreen = false; app.size = app.beforeFullScreen; log.append("full screen off")
            } else {
                app.beforeFullScreen = app.size; app.fullScreen = true; app.size = App.display; log.append("full screen on")
            }
            note("full screen toggled")
            fitToViewport()                        // the restart at its new size
        case 74..<82:
            log.append("restart (a rate change, the encoder)")
            fitToViewport()
        case 82..<88:
            log.append("picked again")
            asks = FitPolicy.Asks()                 // select's bringForward
            lastAsk = nil
            note("picked again")
            fitToViewport()
        case 88..<92:
            window += 1                             // another window picked: same app kind, its own size
            app.size = S(max(app.minSize.width, CGFloat(300 + rng.int(1200))), max(app.minSize.height, CGFloat(200 + rng.int(700))))
            app.fullScreen = false
            fitted = false
            ownSize = nil
            asks = FitPolicy.Asks()
            lastAsk = nil
            log.append("another window \(window)")
            fitToViewport()
        default:
            break
        }
        // After every step: where a fit applies and the app can take it, the window is there (at the size
        // asked, or at its minimum); a window that cannot be resized or is in full screen keeps its size.
        if let want = expectedSize() {
            check(!FitPolicy.needsResize(current: app.size, target: want),
                  "model seed \(seed): window at \(app.size), a fit applies (\(String(describing: FitPolicy.fit(panel: panel, scale: scale, fitWindows: fitWindows)))) and its app takes \(want); \(log.suffix(6))")
        }
    }
}

let sessions = 5_000
var globalSeen: [String: Int] = [:]
var totalAsks = 0
for n in 0..<sessions {
    var s = Session(seed: UInt64(n) &* 6151 &+ 3)
    for _ in 0..<(20 + s.rng.int(80)) { s.step() }
    totalAsks += s.asksMade
    for (k, v) in s.seen { globalSeen[k, default: 0] += v }
}
let needed = ["asked by default", "asked for Aa", "fit moved the window", "fit refused", "fit: full screen", "fit at its minimum",
              "not asked again", "setting on: fitted now", "setting off: put back", "setting changed: nothing", "person resized",
              "full screen toggled", "picked again", "re-sent"]
for k in needed { check((globalSeen[k] ?? 0) > 0, "model: never came up: \(k)") }
print("fit-policy: the model, \(sessions) sessions, \(totalAsks) asks: " + needed.map { "\($0) \(globalSeen[$0] ?? 0)" }.joined(separator: ", "))

if failures == 0 {
    print("fit-policy: all \(passes) checks passed")
    exit(0)
} else {
    print("fit-policy: \(failures) of \(passes + failures) checks FAILED")
    exit(1)
}
