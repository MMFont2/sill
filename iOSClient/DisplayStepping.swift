import Foundation
import StreamProtocol

/// The Desktop button on a Mac with several displays (issue #91; docs/display-stepping-plan.md, the
/// device's rules): which display the Desktop shows, what a tap picks, and what the button says. With
/// fewer than two displays listed (a Mac with one, or one from before that lists none) the button is
/// exactly today's: "Desktop", "Show the full Mac desktop", and a pick that names no display. Pure
/// (Foundation and StreamProtocol), so Tests/checks/display-stepping compiles it with the host's
/// DesktopDisplays. StreamClient keeps the Mac's list and this device's own pick (`desktopFace`,
/// `tapDesktop`); the three bars draw the face.
enum DisplayStepping {
    /// The displays the button steps through (rule 1): the Mac's list in its order (the main display
    /// first, then those to its right, then those to its left), a duplicate ID dropped, when it holds
    /// two or more; else none, and the button is today's.
    static func steps(_ displays: [DisplayInfo]?) -> [DisplayInfo] {
        var seen = Set<UInt32>()
        let unique = (displays ?? []).filter { seen.insert($0.id).inserted }
        return unique.count >= 2 ? unique : []
    }

    /// Which of `steps` the Desktop shows, as an index; nil without steps (rule 2): this device's own
    /// pick while it stands (`asked`), else the Mac's word (`desktop`, the list's `desktopDisplay`),
    /// else the main display, else the first. One that is not listed counts as none.
    static func shown(_ steps: [DisplayInfo], desktop: UInt32?, asked: UInt32?) -> Int? {
        guard !steps.isEmpty else { return nil }
        if let asked, let i = steps.firstIndex(where: { $0.id == asked }) { return i }
        if let desktop, let i = steps.firstIndex(where: { $0.id == desktop }) { return i }
        return steps.firstIndex(where: { $0.main == true }) ?? 0
    }

    /// The display a pick of the Desktop names (rule 3), nil for today's pick (no steps): while the
    /// Desktop streams (a tap on its button), the next after the one shown, from the last back round to
    /// the first; otherwise (a tap from a window or from nothing, and this device's own requests: rule
    /// 7) the one shown, as the label says.
    static func pick(_ steps: [DisplayInfo], shown: Int?, desktopStreams: Bool) -> UInt32? {
        guard !steps.isEmpty else { return nil }
        let at = min(max(shown ?? 0, 0), steps.count - 1)
        return steps[desktopStreams ? (at + 1) % steps.count : at].id
    }

    /// What the button shows and says (rules 4 and 5).
    struct Face: Equatable {
        /// Under the symbol: "Desktop", or which display of how many, "1 of 2".
        var label: String
        /// VoiceOver's: "Show the full Mac desktop", or "Desktop, Built-in Retina Display, 1 of 2".
        var accessibilityLabel: String
        /// What a tap does, with steps: "Shows the next display, LG UltraFine." while the Desktop
        /// streams, "Shows this display’s desktop." otherwise; none without.
        var hint: String?
        /// A phone's Large Content Viewer (row 1 at the accessibility text sizes): "Desktop", or
        /// "Desktop, 1 of 2".
        var largeTitle: String
    }

    /// The button as it has always been, with fewer than two displays.
    static let plain = Face(label: "Desktop", accessibilityLabel: "Show the full Mac desktop", hint: nil, largeTitle: "Desktop")

    static func face(_ steps: [DisplayInfo], shown: Int?, desktopStreams: Bool) -> Face {
        guard !steps.isEmpty, let shown, steps.indices.contains(shown) else { return plain }
        let position = "\(shown + 1) of \(steps.count)"
        let hint: String
        if desktopStreams {
            let next = (shown + 1) % steps.count
            hint = "Shows the next display, \(name(steps[next], at: next))."
        } else {
            hint = "Shows this display’s desktop."
        }
        return Face(label: position, accessibilityLabel: "Desktop, \(name(steps[shown], at: shown)), \(position)",
                    hint: hint, largeTitle: "Desktop, \(position)")
    }

    /// A display's name as the button says it: the Mac's, cleaned as any text from the Mac (SafeText);
    /// "Display 2" for one that has none.
    static func name(_ display: DisplayInfo, at index: Int) -> String {
        let clean = SafeText.label(display.name)
        return clean.isEmpty ? "Display \(index + 1)" : clean
    }

    // MARK: A pick that stands (rule 6)

    /// How long this device's pick shows before the Mac's word does: max(3 s, 4 × the worst recent round
    /// trip), so a pick from afar is not taken back before the Mac's list can name it.
    static func askHold(rttMs: Int?) -> Double { max(3, 4 * Double(max(rttMs ?? 0, 0)) / 1000) }

    /// Whether this device's pick of `asked`, made at `askedAt`, still stands over the Mac's list: not
    /// once the list names it (the Mac took it), once it is no longer among the steps, or once `hold`
    /// has passed (the pick was lost, or another device picked after it).
    static func askStands(_ asked: UInt32, askedAt: Double, now: Double, hold: Double, steps: [DisplayInfo], desktop: UInt32?) -> Bool {
        guard desktop != asked, steps.contains(where: { $0.id == asked }) else { return false }
        return now - askedAt < hold
    }
}
