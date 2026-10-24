import Foundation
import CoreGraphics
import ScreenCaptureKit
import StreamProtocol

/// The extended display (kind 33): a second screen of the Mac at the device's size, beside the Mac's
/// own, streamed whole. The person drags windows onto it on the Mac, or with the device's pointer,
/// as onto any display; when it goes (another source picked, the last device leaving, Sill quitting)
/// macOS moves its windows back to the Mac's screens.
///
/// One `CGVirtualDisplay` (VirtualDisplay.swift), HiDPI, apart from `--virtual-display`'s stage:
/// the same vendor (so Sill's own windows never open on it: `StreamCoordinator.isSillVirtualDisplay`)
/// with a serial of its own, so macOS remembers where the person arranged it in System Settings ›
/// Displays separately from the stage's. Sill leaves that arrangement to macOS: a new display goes
/// beside the main one, and one the person moved stays where they put it.
///
/// Main actor. Needs the AppKit loop, as every virtual display does (VirtualDisplay.swift).
@MainActor
final class ExtendedScreen {
    private(set) var display: VirtualDisplay?
    private(set) var scDisplay: SCDisplay?
    /// Called when the window server takes the display away by itself.
    var onLost: (() -> Void)?
    private var generation = 0

    enum Failure: Error, CustomStringConvertible {
        case neverOnline, notListedBySCK
        var description: String {
            switch self {
            case .neverOnline: return "the display never came online"
            case .notListedBySCK: return "ScreenCaptureKit never listed the display"
            }
        }
    }

    static let serialNum: UInt32 = 2
    static let minSize = CGSize(width: 640, height: 480)
    static let maxSide: CGFloat = 4096   // VirtualDisplay's 8192 px at 2×

    /// The display in global points while it exists (input and the pointer land there).
    var frame: CGRect? {
        guard let d = display, d.isAlive else { return nil }
        let b = d.bounds
        return b.width > 0 ? b : nil
    }

    /// The display's size for a device's panel, in Mac points: the panel divided by its text scale
    /// (Aa; none counts as 1×), so the Mac's text shows on the device at about the size the scale
    /// asks, within 640×480 and 4096 on a side. No viewport yet: 1280×800. Pure.
    static func size(for v: Viewport?) -> CGSize {
        guard let v, v.width > 0, v.height > 0 else { return CGSize(width: 1280, height: 800) }
        let s = (v.scale ?? 1) > 0 ? (v.scale ?? 1) : 1
        let w = (v.width / s).rounded(), h = (v.height / s).rounded()
        return CGSize(width: min(max(w, minSize.width), maxSide), height: min(max(h, minSize.height), maxSide))
    }

    /// Whether the display is up at this size and rate already.
    func matches(size: CGSize, refreshHz: Int) -> Bool {
        guard let d = display, d.isAlive, scDisplay != nil else { return false }
        return d.widthPt == Int(size.width) && d.heightPt == Int(size.height) && Int(d.refreshHz) == refreshHz
    }

    /// Makes the display at `size` (Mac points, 2×) and `refreshHz`, or keeps the one there if it
    /// already is. A new size recreates it: macOS moves what was on it to the Mac's screens for the
    /// moment in between. Throws when it cannot be made or ScreenCaptureKit never lists it.
    func prepare(size: CGSize, refreshHz: Int) async throws {
        if matches(size: size, refreshHz: refreshHz) { return }
        release()
        let t0 = Date()
        let d = try VirtualDisplay(name: "Sill Extended", widthPt: Int(size.width), heightPt: Int(size.height), scale: 2,
                                   refreshHz: Double(refreshHz), vendorID: VirtualStage.vendorID,
                                   productID: VirtualStage.productID, serialNum: Self.serialNum)
        generation += 1
        let gen = generation
        display = d
        d.onTerminated = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen, self.display != nil else { return }
                print("Extended display: the window server removed it.")
                self.release()
                self.onLost?()
            }
        }
        let online = await d.waitUntilOnline(timeout: 3)
        guard d.bounds.width > 0 else { release(); throw Failure.neverOnline }
        if !online {
            print("Extended display is online but not at \(d.widthPt)×\(d.heightPt) @2×: backing \(d.pixelSize.width)×\(d.pixelSize.height) px.")
        }
        // ScreenCaptureKit lists a new display a little after CoreGraphics does (VirtualStage's wait).
        let t1 = Date()
        var listed: SCDisplay?
        while Date().timeIntervalSince(t1) < 3 {
            let remaining = max(0.2, 3 - Date().timeIntervalSince(t1))
            if let c = await WindowCatalog.shareableContent(excludingDesktopWindows: true, onScreenWindowsOnly: true, timeout: remaining),
               let found = c.displays.first(where: { $0.displayID == d.displayID }) { listed = found; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let listed, display === d else { release(); throw Failure.notListedBySCK }
        scDisplay = listed
        let b = d.bounds
        print("Extended display \(d.widthPt)×\(d.heightPt) pt @2× id \(d.displayID) at (\(Int(b.minX)),\(Int(b.minY))), "
              + "\(Int(refreshHz)) Hz: ready in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    }

    /// Removes the display, if there is one. macOS moves its windows to the Mac's screens.
    func release() {
        guard let d = display else { return }
        display = nil
        scDisplay = nil
        let id = d.displayID
        d.destroy()
        print("Removed the extended display \(id)")
    }
}
