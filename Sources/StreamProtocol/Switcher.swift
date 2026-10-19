import Foundation

/// What the host streams. The client decides; the host only ever streams one source.
public enum StreamSource: Codable, Hashable {
    case none
    case window(UInt32)   // CGWindowID, stable for the life of the window
    case desktop          // one of the Mac's displays, whole: the main one, or the one a pick names
                          // (SourcePick, WindowList.desktopDisplay; issue #91)
}

/// A pick (kind 6): the source, and for the Desktop which of the Mac's displays (`DisplayInfo.id`,
/// issue #91; docs/display-stepping-plan.md). On the wire it is `StreamSource`'s JSON with the
/// display inside the Desktop's object, `{"desktop":{"display":69733632}}`; without a display it is
/// exactly `StreamSource`'s, `{"desktop":{}}`. A host from before reads it as `StreamSource` and gets
/// the Desktop (the synthesized decoder ignores keys it does not know in the Desktop's object). A
/// device sends a display only to a host whose window list lists two or more displays; a display on
/// another source is never written and is ignored when read, and one that is not a number reads as
/// none.
public struct SourcePick: Codable, Hashable {
    public var source: StreamSource
    /// The display the Desktop should show; nil: the main one (every device before issue #91).
    public var display: UInt32?

    public init(_ source: StreamSource, display: UInt32? = nil) {
        self.source = source
        self.display = source == .desktop ? display : nil
    }

    /// StreamSource's own keys, written by hand only for a Desktop that names its display.
    private enum SourceKeys: String, CodingKey { case none, window, desktop }
    private enum DesktopKeys: String, CodingKey { case display }

    public init(from decoder: Decoder) throws {
        source = try StreamSource(from: decoder)
        guard source == .desktop,
              let desktop = try? decoder.container(keyedBy: SourceKeys.self).nestedContainer(keyedBy: DesktopKeys.self, forKey: .desktop)
        else { display = nil; return }
        display = (try? desktop.decodeIfPresent(UInt32.self, forKey: .display)) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        guard source == .desktop, let display else { try source.encode(to: encoder); return }
        var container = encoder.container(keyedBy: SourceKeys.self)
        var desktop = container.nestedContainer(keyedBy: DesktopKeys.self, forKey: .desktop)
        try desktop.encode(display, forKey: .display)
    }
}

/// One of the Mac's displays, as a device steps the Desktop through them (issue #91;
/// docs/display-stepping-plan.md). The shape pull request #66 gave its own (kind 40 there), so the
/// two reconcile in code alone: `id` the display's CGDirectDisplayID, `name` macOS's for it
/// (NSScreen's localizedName: "Built-in Retina Display", "LG UltraFine"), `width` and `height` its
/// size in points (Double: a later host's fractional size never fails a device's decoding of the
/// whole list), `main` true for the display with the menu bar.
public struct DisplayInfo: Codable, Hashable, Sendable {
    public var id: UInt32
    public var name: String
    public var width: Double
    public var height: Double
    public var main: Bool?
    public init(id: UInt32, name: String, width: Double, height: Double, main: Bool? = nil) {
        self.id = id; self.name = name; self.width = width; self.height = height; self.main = main
    }
}

/// One on-screen Mac window, as the client sees it. WindowList order is stable: first seen first.
public struct WindowInfo: Codable, Hashable, Identifiable {
    public var id: UInt32
    public var title: String
    public var appName: String
    public var bundleID: String
    public var width: Int      // points
    public var height: Int

    public init(id: UInt32, title: String, appName: String, bundleID: String, width: Int, height: Int) {
        self.id = id; self.title = title; self.appName = appName; self.bundleID = bundleID
        self.width = width; self.height = height
    }
}

/// An installed app, for the drawer's "All apps" section.
public struct AppInfo: Codable, Hashable, Identifiable {
    public var id: String { bundleID }
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) { self.name = name; self.bundleID = bundleID }
}

public struct WindowList: Codable {
    public var macName: String
    public var windows: [WindowInfo]
    public var active: StreamSource
    /// Random, picked once per launch of the host and the same in every list to every device: two
    /// connections whose lists carry the same one reach the same running host. A name cannot tell
    /// that (two Macs can share one, and mDNS renames neither when they share no link), and a
    /// device moving its session from AWDL to the network must not land on another Mac. Optional:
    /// nil from a host older than 2026-09-24, and an older device ignores the key.
    public var launchID: String?
    /// The host's version: Sill.app's CFBundleShortVersionString ("0.4.0"); nil from SillHost (no
    /// bundle) and from hosts before 2026-09-25. For later devices: which Mac to update, and to what
    /// (docs/update-notice-plan.md §14).
    public var hostVersion: String?
    /// The host's SillProtocol.current; nil from hosts before 2026-09-25, which speak 1. The JSON key
    /// is "protocol".
    public var `protocol`: Int?
    /// Which trackpad gestures this host takes (kind 28, Gesture.swift): 1 is the six of
    /// `TrackpadGesture.names`, each turned into the Mac's own shortcut. Nil from every host before
    /// 2026-09-27, to which a device sends no kind 28. A later generation of gestures says 2 and
    /// goes only to a host that says so.
    public var gestures: Int?
    /// What this host takes and sends of the clipboard (kind 32, Clipboard.swift): 1 is text
    /// (`ClipboardPolicy.generation`). Nil from every host before 2026-10-14, and from one whose Share
    /// clipboard with devices is off: a device sends no kind 32 to either. A later generation
    /// (images) says 2, and a device sends images only to a host that says so. An Int, as `gestures`:
    /// pull request #66's `Bool` (never released) does not decode here and becomes an Int as it
    /// rebases.
    public var clipboard: Int?
    /// The Mac's displays, the main one first, then those to its right and then those to its left,
    /// each left to right (never Sill's own virtual display): what a device's Desktop button steps
    /// through (issue #91; docs/display-stepping-plan.md). Nil from every host before 2026-10-20
    /// (whose Desktop is the display macOS lists first), and from one that cannot read its displays;
    /// a device sends a display in its Desktop pick only to a host that lists two or more.
    public var displays: [DisplayInfo]?
    /// The display the Desktop shows: the one it streams while it streams, else the one it streamed
    /// last (the last Desktop pick's), else the main one. Nil with `displays`.
    public var desktopDisplay: UInt32?

    public init(macName: String, windows: [WindowInfo], active: StreamSource, launchID: String? = nil,
                hostVersion: String? = nil, protocol: Int? = nil, gestures: Int? = nil, clipboard: Int? = nil,
                displays: [DisplayInfo]? = nil, desktopDisplay: UInt32? = nil) {
        self.macName = macName; self.windows = windows; self.active = active; self.launchID = launchID
        self.hostVersion = hostVersion; self.protocol = `protocol`; self.gestures = gestures
        self.clipboard = clipboard
        self.displays = displays; self.desktopDisplay = desktopDisplay
    }
}

public struct LaunchApp: Codable {
    public var bundleID: String
    public init(bundleID: String) { self.bundleID = bundleID }
}

/// Client → host: what the bar's long-press menu asks of a window, the three traffic lights.
public struct WindowCommand: Codable {
    public enum Action: String, Codable { case close, minimize, fullScreen }
    public var id: UInt32
    public var action: Action
    public init(id: UInt32, action: Action) { self.id = id; self.action = action }
}

/// JSON payloads. Everything here is small and infrequent; frames never go through JSON.
public enum Wire {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

/// Binary image payloads: a key, then the image bytes.
public enum ImageBlob {
    /// windowID(4, BE) + JPEG
    public static func encodeThumbnail(windowID: UInt32, jpeg: Data) -> Data {
        var d = Data(capacity: 4 + jpeg.count)
        d.appendBigEndian(windowID)
        d.append(jpeg)
        return d
    }
    public static func decodeThumbnail(_ d: Data) -> (windowID: UInt32, jpeg: Data)? {
        guard d.count > 4 else { return nil }
        return (d.readBigEndian(UInt32.self, at: 0), d.subdata(in: (d.startIndex + 4)..<d.endIndex))
    }

    /// bundleIDLength(2, BE) + bundleID UTF-8 + PNG
    public static func encodeIcon(bundleID: String, png: Data) -> Data {
        let id = Data(bundleID.utf8)
        var d = Data(capacity: 2 + id.count + png.count)
        d.appendBigEndian(UInt16(id.count))
        d.append(id)
        d.append(png)
        return d
    }
    public static func decodeIcon(_ d: Data) -> (bundleID: String, png: Data)? {
        guard d.count > 2 else { return nil }
        let len = Int(d.readBigEndian(UInt16.self, at: 0))
        guard d.count > 2 + len else { return nil }
        let idStart = d.startIndex + 2
        guard let id = String(data: d.subdata(in: idStart..<(idStart + len)), encoding: .utf8) else { return nil }
        return (id, d.subdata(in: (idStart + len)..<d.endIndex))
    }
}
