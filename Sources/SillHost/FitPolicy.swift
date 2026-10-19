import Foundation
import CoreGraphics

/// When Sill fits a window it streams to a device, and to which size (issue #70;
/// docs/fit-by-default-plan.md). Pure: the device's panel, its Aa scale and the Mac's setting in, a
/// size out. StreamCoordinator's `fitToViewport` asks it, WindowSizer.resize makes the fit, and
/// WindowRestore records it, so the window goes back to its own frame when it stops streaming (issue
/// #57). `Tests/checks/fit-policy` checks this file alone; the window-restore check's model and the
/// restore probe compile it too.
///
/// In regular mode (Virtual Display off) Sill resizes the window it streams, through Accessibility,
/// to the device's panel at a text scale: device points per Mac point. Aa sets the scale on the
/// device, and until Aa is first used the device sends none. Before this change no scale meant
/// "leave the window alone", so a window streamed at its Mac size, shrunk into the panel or small in
/// the middle of it with black around it, while Aa read 1× (issue #70). Now, while Fit windows to the
/// device's screen is on (`HostConfig.fitWindows`, on by default), no scale counts as Aa's 1×: the
/// window takes the panel's size in Mac points, larger or smaller than it was, within what its app
/// allows, and its text keeps the size it has on the Mac. Off, no scale leaves the window alone, as
/// before. A scale from Aa counts whatever the setting. The virtual display sizes its window itself
/// (VirtualStage.windowSize, which has always counted no scale as 1×).
enum FitPolicy {
    /// The scale a fit takes when the device sends none (Aa unset) and the setting is on: Aa's 1×.
    static let defaultScale = 1.0

    /// The scales a fit takes: Aa's steps (0.5× to 1.5×) with room on both sides. Anything else is no
    /// device's Aa, and the window is left alone.
    static let scales: ClosedRange<Double> = 0.25...4

    /// The longest side a fit asks for, in Mac points: past any display, so past any device's panel at
    /// a scale above. A longer one is no device's viewport, and the window is left alone.
    static let maxSide: CGFloat = 16_384

    /// Who asked for the fit.
    enum Reason: Equatable {
        /// The device's Aa.
        case textScale
        /// Fit windows to the device's screen, with Aa unset.
        case byDefault
    }

    /// A fit: the window's size in Mac points, the scale it was worked out at and why.
    struct Fit: Equatable {
        var size: CGSize
        var scale: Double
        var reason: Reason
    }

    /// The fit for a window that streams in regular mode: the device's panel (device points; nil
    /// before any viewport), its Aa scale (nil until Aa is first used) and the Mac's setting. Nil:
    /// leave the window alone (no panel yet or an empty one, a scale outside `scales`, no scale with
    /// the setting off, a side that rounds to nothing or passes `maxSide` at its scale).
    static func fit(panel: CGSize?, scale: Double?, fitWindows: Bool) -> Fit? {
        guard let panel else { return nil }      // an empty panel rounds to nothing (`size`)
        let s: Double
        let reason: Reason
        if let scale {
            guard scales.contains(scale) else { return nil }
            s = scale
            reason = .textScale
        } else {
            guard fitWindows else { return nil }
            s = defaultScale
            reason = .byDefault
        }
        guard let size = size(panel: panel, scale: s) else { return nil }
        return Fit(size: size, scale: s, reason: reason)
    }

    /// The panel at `scale`, in whole Mac points (as the virtual display's window is worked out);
    /// nil when a side rounds to nothing, passes `maxSide` or is not a number.
    static func size(panel: CGSize, scale: Double) -> CGSize? {
        let w = (panel.width / scale).rounded(), h = (panel.height / scale).rounded()
        guard w >= 1, h >= 1, w <= maxSide, h <= maxSide else { return nil }
        return CGSize(width: w, height: h)
    }

    /// How far a window may be from the size asked and count as there: Accessibility and the window
    /// server round differently (WindowRestore.tolerance is the same 2 pt).
    static let tolerance: CGFloat = 2

    /// The window is not at `target` yet: more than `tolerance` off on either side.
    static func needsResize(current: CGSize, target: CGSize) -> Bool {
        abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance
    }

    /// A fit changed the window's size: a point or more on either side. Less is an app that refused,
    /// sits at its minimum or has not answered yet: nothing for the stream to restart for.
    static func moved(from before: CGSize, to after: CGSize) -> Bool {
        abs(after.width - before.width) >= 1 || abs(after.height - before.height) >= 1
    }

    // MARK: Not asking again for nothing

    /// The last fit that left its window short of the size asked: an app at its minimum or snapping to
    /// a grid, a window that cannot be resized or is in full screen, an app that did not answer,
    /// Accessibility off. The same size asked again from where it ended leaves it there again, and
    /// asking costs Accessibility's calls on the main actor (up to a second each for an app that does
    /// not answer) and, for a refusal or full screen, a line in the log each time; and a device sends
    /// its viewport again whenever its pointer shows or hides. So the same window is not asked for the
    /// same size again while it is where that ask left it. The person at the Mac resizing it, the window
    /// leaving full screen, its app taking the size late, another size asked (a rotation, Aa), another
    /// window, or a pick (the coordinator starts afresh: a busy app may answer now) all ask again. One
    /// window streams at a time, so one is remembered.
    struct Asks: Equatable {
        struct Short: Equatable {
            var window: CGWindowID
            var asked: CGSize
            /// Where the ask left it.
            var at: CGSize
        }
        private(set) var short: Short?

        init() {}

        /// Whether to ask `window`, now at `current`, for `target`.
        func shouldAsk(window: CGWindowID, target: CGSize, current: CGSize) -> Bool {
            guard let s = short, s.window == window else { return true }
            return FitPolicy.needsResize(current: s.asked, target: target) || FitPolicy.needsResize(current: s.at, target: current)
        }

        /// What an ask came to: the window is at `after` (where it was when nothing was written:
        /// refused, full screen, no Accessibility window). Remembered when short of `target`, forgotten
        /// when there.
        mutating func asked(window: CGWindowID, target: CGSize, after: CGSize) {
            short = FitPolicy.needsResize(current: after, target: target) ? Short(window: window, asked: target, at: after) : nil
        }
    }

    // MARK: The setting changed while a window streams

    /// What a change of Fit windows to the device's screen does to the window streaming in regular mode.
    enum Change: Equatable {
        /// On: the window is fitted now, at 1×.
        case fitNow
        /// Off: the window Sill fitted only because of the setting goes back to its own frame now
        /// (WindowRestore's rules: moved, resized and full screen as at any stop).
        case putBack
        case nothing
    }

    /// The setting is now `fitWindows`; the device's Aa scale is `scale` (nil: unset); Sill has a fit
    /// on record for the window (`fitted`). A scale from Aa keeps its fit, or its lack of one, either way.
    static func afterSettingChange(fitWindows: Bool, scale: Double?, fitted: Bool) -> Change {
        if scale != nil { return .nothing }
        if fitWindows { return .fitNow }
        return fitted ? .putBack : .nothing
    }

    // MARK: What the device is told

    /// Kind 16's `stream.fitsPanel` (RunningStream): the Mac sizes the streamed window to the device's
    /// panel, so a device whose picture's pane would otherwise follow the picture's shape (the iPhone Duo
    /// open flat, DuoPosture.paneAspect) keeps its own, and a window's minimum size cannot shrink that
    /// pane step by step. A window on the virtual display, or one in regular mode that a fit applies to
    /// (Aa's or the setting's; its app refusing or clamping the size all the same: the Mac keeps asking
    /// for the panel). Never the Desktop.
    static func fitsPanel(window: Bool, onVirtualDisplay: Bool, fit: Fit?) -> Bool {
        window && (onVirtualDisplay || fit != nil)
    }

    // MARK: The log

    /// The line for a fit that resized the window: "Resized Safari to 1000×710 pt (asked 1000×710 for a
    /// 1000×710 panel at 1.5×)" for Aa's scale, as it has always read; "… at 1×, by default)" for the
    /// setting's.
    static func resizedLine(app: String, took: CGSize, fit: Fit, panel: CGSize) -> String {
        let at = fit.reason == .byDefault ? "1×, by default" : "\(fit.scale)×"
        return "Resized \(app) to \(Int(took.width))×\(Int(took.height)) pt (asked \(Int(fit.size.width))×\(Int(fit.size.height)) "
            + "for a \(Int(panel.width))×\(Int(panel.height)) panel at \(at))"
    }

    /// The one line the setting adds at launch, and only while it is off (SillHost --no-fit, or
    /// Sill.app's switch off): the default path prints what it always printed.
    static let offLine = "Fit windows to the device's screen is off: a picked window keeps its size until the device sets one with Aa."
}
