import Foundation

/// How long a window's thumbnail is touched and held before its lights (close, minimize, full screen)
/// show and it can be dragged to a new place (issue #113, docs/thumbnail-hold-plan.md). A setting of
/// this device's own, in the Settings panel's This iPad (or iPhone) group: from 1 to 5 s in half
/// seconds, 1 s unless changed (it was a fixed 1.5 s, with nothing on screen until the lights came).
/// Stored as `Sill.thumbnailHold`, never sent to the Mac.
///
/// WindowStrip reads it for every thumbnail of every bar (sideways, an iPad's portrait window bar, a
/// phone's row 2), and the press shows from touch-down (`look`): the thumbnail darkens at once and,
/// unless Reduce Motion is on, shrinks a little over the hold, so the person sees that the press took
/// and how long is left. The drag's own rules (12 pt before the hold is a scroll, 8 pt after it lifts
/// the thumbnail) are not this type's and do not change.
///
/// Pure: Foundation only, checked in Tests/checks/thumbnail-hold.
enum ThumbnailHold {
    /// The UserDefaults key (`@AppStorage` in WindowStrip and the Settings panel). DEBUG harness:
    /// `-Sill.thumbnailHold <seconds>` for one run.
    static let key = "Sill.thumbnailHold"
    /// The hold's lengths a person may choose, in seconds.
    static let range: ClosedRange<Double> = 1...5
    /// The stepper's step: half a second.
    static let step = 0.5
    /// Unless changed: shorter than the 1.5 s of before.
    static let standard = 1.0
    /// The fixed hold before this setting (issue #113's 1.5 s).
    static let before = 1.5

    /// Every length the stepper offers: 1, 1.5, … 5.
    static var choices: [Double] {
        let count = Int(((range.upperBound - range.lowerBound) / step).rounded())
        return (0...count).map { range.lowerBound + Double($0) * step }
    }

    /// A length as the hold takes it: nothing usable (not a number, infinite) is the standard 1 s; one
    /// outside the range is its nearest end; one between steps the nearest half second (a quarter
    /// rounds up).
    static func seconds(_ value: Double) -> Double {
        guard value.isFinite else { return standard }
        let kept = min(max(value, range.lowerBound), range.upperBound)
        return range.lowerBound + ((kept - range.lowerBound) / step).rounded(.toNearestOrAwayFromZero) * step
    }

    /// What a stored value means, whatever UserDefaults hands back: a number (a Double, an Int or a
    /// Bool, each an NSNumber there), or a string as a launch argument gives it
    /// (`-Sill.thumbnailHold 2.5`). Nothing stored, or nothing that reads as a number, is the standard
    /// 1 s.
    static func seconds(stored: Any?) -> Double {
        switch stored {
        case let n as NSNumber: return seconds(n.doubleValue)
        case let s as String:
            guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return standard }
            return seconds(d)
        default: return standard
        }
    }

    // MARK: The press's look

    /// How a thumbnail looks while it is pressed: a black veil over its picture (`dim`, the opacity),
    /// and its scale. From touch-down until the hold fires or the press ends (a lift, a scroll).
    struct Look: Equatable {
        var dim: Double
        var scale: Double
    }

    /// The veil's opacity while pressed: the picture darkens as a Home Screen icon does.
    static let pressedDim = 0.22
    /// The scale a press shrinks to by the end of the hold. Under Reduce Motion nothing shrinks.
    static let pressedScale = 0.95
    /// The veil comes in over this (an ease-out), so a swipe that turns into a scroll barely shows it.
    static let veilIn = 0.08
    /// A press that ends without the hold (a tap, a scroll) goes back over this (an ease-out).
    static let release = 0.15

    /// What a thumbnail shows: pressed or not, with Reduce Motion or not.
    static func look(pressed: Bool, reduceMotion: Bool) -> Look {
        guard pressed else { return Look(dim: 0, scale: 1) }
        return Look(dim: pressedDim, scale: reduceMotion ? 1 : pressedScale)
    }

    /// How long the press takes to reach its smallest: the whole hold, so the shrink ends as the lights
    /// show (an ease-out from touch-down would be done long before a 5 s hold).
    static func shrinkDuration(hold: Double) -> Double { seconds(hold) }

    // MARK: Words

    /// The row's title in the Settings panel.
    static let title = "Hold to Show Window Controls"
    /// The row's label for VoiceOver ("Hold to show window controls, 1 second").
    static let spokenTitle = "Hold to show window controls"

    /// "1", "1.5", "5": a length without a trailing ".0".
    static func number(_ value: Double) -> String {
        let s = seconds(value)
        return s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s)
    }

    /// The row's value beside the stepper: "1 s", "1.5 s".
    static func valueText(_ value: Double) -> String { "\(number(value)) s" }

    /// The value as VoiceOver says it: "1 second", "1.5 seconds", "2 seconds".
    static func spokenValue(_ value: Double) -> String {
        let s = seconds(value)
        return "\(number(s)) \(s == 1 ? "second" : "seconds")"
    }

    /// Under the row: what the length is for. The words are the tour's ("Touch and hold a window to
    /// close, minimize or go full screen. Keep holding and drag to move it."), so the two agree.
    static let footnote = "How long you touch and hold a window’s thumbnail before Close, Minimize and Full Screen show and you can drag it to a new place. A thumbnail darkens as soon as you touch it."
}
