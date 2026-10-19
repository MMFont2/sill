import Foundation
import CoreGraphics
import StreamProtocol

/// Which of the Mac's displays the Desktop shows (issue #91; docs/display-stepping-plan.md): the
/// displays a device's Desktop button steps through, in their order; the one a Desktop pick streams;
/// the host's lines about it; and, TEST ONLY, the test patterns a synthetic host lists instead
/// (SILL_TEST_DISPLAYS). Pure (Foundation, CoreGraphics and StreamProtocol), so
/// Tests/checks/display-stepping compiles it with the device's DisplayStepping. The coordinator
/// keeps the Desktop's display (`StreamCoordinator.desktopDisplayID`) and the catalog reads the
/// displays (`WindowCatalog.desktopDisplays`).
enum DesktopDisplays {
    /// One display as the catalog reads it, or a synthetic host's test pattern.
    struct Display: Equatable {
        var id: UInt32
        var name: String
        /// Its frame in global points, the main display's top-left at 0,0 and y down (CGDisplayBounds').
        var frame: CGRect
        var isMain: Bool
        /// One of Sill's own virtual displays (VirtualStage.vendorID): never a Desktop (the plan's rule 8).
        var isSill: Bool = false
    }

    /// The displays a Desktop button steps through, in order (the plan's rule 1): never Sill's own; the
    /// main display first; then the displays whose left edge is at or right of the main one's, left to
    /// right; then the rest, left to right (where two share a left edge, the higher first, then by ID).
    /// So a tap moves one display to the right, and from the rightmost round to the leftmost. A
    /// duplicate ID keeps its first. With no main display among them (macOS always has one), the first
    /// stands in for it.
    static func ordered(_ displays: [Display]) -> [Display] {
        var seen = Set<UInt32>()
        let own = displays.filter { !$0.isSill && seen.insert($0.id).inserted }
        guard let main = own.first(where: { $0.isMain }) ?? own.first else { return [] }
        let rest = own.filter { $0.id != main.id }
        func reading(_ a: Display, _ b: Display) -> Bool {
            if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
            if a.frame.minY != b.frame.minY { return a.frame.minY < b.frame.minY }
            return a.id < b.id
        }
        let right = rest.filter { $0.frame.minX >= main.frame.minX }.sorted(by: reading)
        let left = rest.filter { $0.frame.minX < main.frame.minX }.sorted(by: reading)
        return [main] + right + left
    }

    /// The display a Desktop pick of `asked` streams (the plan's rule 2): that one if listed, else the
    /// main one, else the first; nil when none is listed. A pick without a display (every device
    /// before issue #91) asks for none.
    static func resolve(_ asked: UInt32?, in listed: [Display]) -> Display? {
        if let asked, let d = listed.first(where: { $0.id == asked }) { return d }
        return listed.first(where: { $0.isMain }) ?? listed.first
    }

    /// The window list's `displays`: each display listed, its size in points, `main` only on the main one.
    static func infos(_ listed: [Display]) -> [DisplayInfo] {
        listed.map { DisplayInfo(id: $0.id, name: $0.name, width: Double($0.frame.width), height: Double($0.frame.height),
                                 main: $0.isMain ? true : nil) }
    }

    /// "LG UltraFine (2 of 2)": which display the stream's line names (the plan's rule 6); nil with one
    /// display or fewer, whose line stays as it always was.
    static func which(_ d: Display, in listed: [Display]) -> String? {
        guard listed.count > 1, let i = listed.firstIndex(where: { $0.id == d.id }) else { return nil }
        return "\(d.name) (\(i + 1) of \(listed.count))"
    }

    /// A Desktop pick named a display that is not listed: gone meanwhile, or never this Mac's (rule 2).
    static func missingLine(asked: UInt32, instead: Display?, in listed: [Display]) -> String {
        "Desktop: display \(asked) is not connected; " + streaming(instead, in: listed) + "."
    }

    /// The display the Desktop streamed went away while it streamed: unplugged, or a lid closed under a
    /// monitor (rule 5).
    static func goneLine(_ gone: Display, instead: Display?, in listed: [Display]) -> String {
        "Desktop: \(gone.name) is gone; " + streaming(instead, in: listed) + (instead.map { $0.isMain ? ", instead." : " instead." } ?? ".")
    }

    /// What streams instead: "streaming Built-in Retina Display (1 of 2), the main display".
    private static func streaming(_ d: Display?, in listed: [Display]) -> String {
        guard let d else { return "no other display is listed" }
        return "streaming \(which(d, in: listed) ?? d.name)" + (d.isMain ? ", the main display" : "")
    }

    /// A display's name in the list: macOS's (NSScreen's localizedName), cleaned as any text a device
    /// shows (SafeText); for one NSScreen does not know yet (the CLI has no AppKit loop to learn of a
    /// display plugged in since it started), "Built-in Display" or "Display".
    static func name(_ localized: String?, builtIn: Bool) -> String {
        let clean = SafeText.label(localized ?? "")
        if !clean.isEmpty { return clean }
        return builtIn ? "Built-in Display" : "Display"
    }

    // MARK: TEST ONLY: a synthetic host's displays (SILL_TEST_DISPLAYS)

    /// `SILL_TEST_DISPLAYS=N` (2 to 4): a synthetic host's Desktop is N test patterns; `N@S`: the last of
    /// them goes away S seconds after the host starts, as an unplugged display. Nil when unset, and for
    /// anything else (the host then says it ignored it).
    struct TestSpec: Equatable {
        var count: Int
        var goneAfter: Double?
    }

    static func testSpec(_ raw: String?) -> TestSpec? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, let count = Int(parts[0]), (2...testSizes.count).contains(count) else { return nil }
        guard parts.count == 2 else { return TestSpec(count: count, goneAfter: nil) }
        guard let seconds = Double(parts[1]), seconds.isFinite, seconds >= 0 else { return nil }
        return TestSpec(count: count, goneAfter: seconds)
    }

    /// The test patterns' sizes in points: the first is the one test pattern every synthetic host has
    /// always streamed (1512×949), then 1440×900, 1280×800 and 1920×1080.
    static let testSizes: [CGSize] = [CGSize(width: 1512, height: 949), CGSize(width: 1440, height: 900),
                                      CGSize(width: 1280, height: 800), CGSize(width: 1920, height: 1080)]

    /// A synthetic host's displays: "Test Pattern" (the main one, ID 1), then "Test Pattern 2" to 4 (IDs
    /// 2 to 4) side by side to its right, as `ordered` lists them. One without the variable.
    static func testDisplays(count: Int) -> [Display] {
        var x: CGFloat = 0
        return (0 ..< max(1, min(count, testSizes.count))).map { i in
            let size = testSizes[i]
            defer { x += size.width }
            return Display(id: UInt32(i + 1), name: i == 0 ? "Test Pattern" : "Test Pattern \(i + 1)",
                           frame: CGRect(origin: CGPoint(x: x, y: 0), size: size), isMain: i == 0)
        }
    }
}
