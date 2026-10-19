import AppKit
import ScreenCaptureKit
import CoreMedia

// TEST ONLY (Tests/capture-fit/run.sh; README.md). What ScreenCaptureKit's `scalesToFit` changes in the
// host's WindowCapture (closed PR #149 by nacben, whose test this extends; issue #70): on two displays of
// its own, each made with the host's VirtualDisplay wrapper (the private CGVirtualDisplay API, as
// `SillHost --virtual-display-selftest` makes one) and holding one white window of its own and nothing
// else of this Mac's: a 1× display, as an external display at 1×, and a 2× one, as a Retina display.
// The window, and the display itself, are captured as the host asks: at their points (Standard), at
// twice them (Retina: twice a 1× display's pixels, a 2× display's own), and the window at four times its
// points on the 2× display (twice its pixels, as Retina asks of a 1× display). Each first frame's luma
// is sampled at nine points over the window. White must reach the right and the bottom: before the fix
// (`run.sh --rev REV`, main before this change), a source asked for more pixels than it has sits in the
// frame's top-left corner with black around it, as #149 found. Then the window drawn with one-pixel lines
// at its own pixels and at half, whose frames, saved with CAPTURE_FIT_FRAMES=DIR, compare.py compares
// between two runs (main's and this build's: the same, but for a downscale's level or two of noise).
//
// Never another app's window, never input, never the hardware encoder (nothing is encoded), never this
// Mac's own displays' content: the displays are captured only while they show the check's window. The
// displays are gone when it exits (and with the process if it dies); it exits by itself after 90 s.

/// WindowCapture's statistics, without the host's.
final class Stats {
    static let shared = Stats()
    func bump(_ name: String) {}
}

/// A pattern of one-pixel lines (at the display's scale), so any resampling shows in the frame's hash.
final class PatternView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor.black.setFill()
        let px = 1 / (window?.backingScaleFactor ?? 1)
        var x: CGFloat = 0
        while x < bounds.width { NSRect(x: x, y: 0, width: px, height: bounds.height).fill(); x += 3 * px }
        var y: CGFloat = 0
        while y < bounds.height { NSRect(x: 0, y: y, width: bounds.width, height: px).fill(); y += 5 * px }
    }
}

/// The first frame's luma plane, hashed (FNV-1a over every row's visible bytes).
final class FrameHash {
    private let lock = NSLock()
    private var value: (UInt64, Int, Int)?
    /// The luma plane itself, for CAPTURE_FIT_FRAMES (a PGM per frame, to compare two builds' frames).
    private(set) var luma = Data()
    func record(_ pixels: CVPixelBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard value == nil else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0), height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var h: UInt64 = 0xcbf29ce484222325
        var plane = Data(capacity: width * height)
        for row in 0..<height {
            for col in 0..<width { h = (h ^ UInt64(bytes[row * stride + col])) &* 0x100000001b3 }
            plane.append(UnsafeBufferPointer(start: bytes + row * stride, count: width))
        }
        value = (h, width, height)
        luma = plane
    }
    func read() -> (UInt64, Int, Int)? { lock.lock(); defer { lock.unlock() }; return value }
}

/// The first frame's luma at nine points of `region` (fractions of the frame: x, y, width, height).
final class FirstFrame {
    private let lock = NSLock()
    private var values: [UInt8]?
    private var size: (Int, Int) = (0, 0)
    let region: CGRect
    init(region: CGRect) { self.region = region }
    func record(_ pixels: CVPixelBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard values == nil else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0), height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        size = (width, height)
        values = [0.1, 0.5, 0.9].flatMap { fy in
            [0.1, 0.5, 0.9].map { fx -> UInt8 in
                let x = Int(Double(width - 1) * (region.minX + region.width * fx))
                let y = Int(Double(height - 1) * (region.minY + region.height * fy))
                return bytes[y * stride + x]
            }
        }
    }
    func read() -> (values: [UInt8], size: (Int, Int))? {
        lock.lock(); defer { lock.unlock() }
        return values.map { ($0, size) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { print("FAIL: still running after 90 s"); exit(1) }

/// One capture, as StreamCoordinator.startPipeline makes it: the real WindowCapture, the size asked.
@MainActor
func capture(_ filter: SCContentFilter, width: Int, height: Int, region: CGRect) async throws -> (values: [UInt8], size: (Int, Int))? {
    let c = WindowCapture()
    let frame = FirstFrame(region: region)
    c.onFrame = { pixels, _ in frame.record(pixels) }
    try await c.start(filter: filter, width: width, height: height, fps: 30, showsCursor: false)
    for _ in 0..<60 {
        if frame.read() != nil { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    await c.stop()
    return frame.read()
}

Task { @MainActor in
    var failures = 0
    func judge(_ what: String, _ result: (values: [UInt8], size: (Int, Int))?, white: Bool = true) {
        guard let r = result else { print("FAIL: \(what): no frame"); failures += 1; return }
        let passed = r.values.allSatisfy { $0 > 200 }
        print("\(passed ? "ok" : "FAIL"): \(what), \(r.size.0)×\(r.size.1) px, luma \(r.values)")
        if !passed { failures += 1 }
    }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
    for scale in [1, 2] {
        // A display of its own, 1000×700 pt, with Sill's virtual display's identity (VirtualStage's),
        // so this Mac remembers no new display. Sill.app makes one only with its Virtual Display on.
        let display: VirtualDisplay
        do {
            display = try VirtualDisplay(name: "Sill capture check", widthPt: 1000, heightPt: 700, scale: scale, refreshHz: 60,
                                         vendorID: 0x5111, productID: 0x0001, serialNum: 1)
        } catch {
            print("FAIL: no \(scale)× display: \(error)"); failures += 1; continue
        }
        let online = await display.waitUntilOnline(timeout: 5)
        let b = display.bounds
        print("\(scale)× display \(display.displayID): \(Int(b.width))×\(Int(b.height)) pt at (\(Int(b.minX)),\(Int(b.minY))), "
              + "\(display.pixelSize.width)×\(display.pixelSize.height) px\(online ? "" : " (not at the mode asked)")")
        // The window: 800×500 pt, 100 pt in from the display's top-left corner, white, borderless.
        let wr = CGRect(x: b.minX + 100, y: b.minY + 100, width: 800, height: 500)
        let window = NSWindow(contentRect: NSRect(x: wr.minX, y: primaryHeight - wr.maxY, width: wr.width, height: wr.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.isReleasedWhenClosed = false
        window.title = "Sill capture check \(scale)x"
        window.orderFrontRegardless()
        do {
            try await Task.sleep(for: .milliseconds(600))    // the window server commits the window and the display
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }),
                  let scDisplay = content.displays.first(where: { $0.displayID == display.displayID }) else {
                throw NSError(domain: "CaptureFit", code: 1, userInfo: [NSLocalizedDescriptionKey: "the window or the display is not in the capture list"])
            }
            let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
            let windowFilter = SCContentFilter(desktopIndependentWindow: own)
            // The window as the host captures it in regular mode: its points × the capture scale.
            judge("\(scale)× display, the window at its points (Standard)", try await capture(windowFilter, width: 800, height: 500, region: whole))
            judge("\(scale)× display, the window at twice its points (Retina)", try await capture(windowFilter, width: 1600, height: 1000, region: whole))
            if scale == 2 {
                judge("2× display, the window at four times its points (twice its pixels)", try await capture(windowFilter, width: 3200, height: 2000, region: whole))
            }
            // The display as the Desktop: its points × the capture scale; the window's part of it sampled.
            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let inWindow = CGRect(x: 0.1 + 0.08 * 0.8, y: 100.0 / 700 + 0.08 * (500.0 / 700), width: 0.8 * 0.84, height: (500.0 / 700) * 0.84)
            judge("\(scale)× display, the Desktop at its points (Standard)", try await capture(filter, width: 1000, height: 700, region: inWindow))
            judge("\(scale)× display, the Desktop at twice its points (Retina)", try await capture(filter, width: 2000, height: 1400, region: inWindow))
        } catch {
            print("FAIL: \(scale)× display: \(error)"); failures += 1
        }
        // The same window drawn with one-pixel lines, at its own pixels and at half: no resampling (the
        // first) and a downscale (the second), Standard on a Retina display. The first's hash is the same
        // for this build and main's (`--rev`) when scalesToFit changed nothing there. A downscale differs
        // by a luma level or two even between two runs of one build (the GPU's scaler), so its frames are
        // compared by compare.py, saved with CAPTURE_FIT_FRAMES=DIR.
        let pattern = PatternView(frame: NSRect(x: 0, y: 0, width: wr.width, height: wr.height))
        window.contentView = pattern
        pattern.needsDisplay = true
        do {
            try await Task.sleep(for: .milliseconds(500))
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            if let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) {
                let filter = SCContentFilter(desktopIndependentWindow: own)
                for (what, w, h) in [("its own pixels", 800 * scale, 500 * scale), ("half of them", 400 * scale, 250 * scale)] {
                    let c = WindowCapture()
                    let hash = FrameHash()
                    c.onFrame = { pixels, _ in hash.record(pixels) }
                    try await c.start(filter: filter, width: w, height: h, fps: 30, showsCursor: false)
                    for _ in 0..<60 { if hash.read() != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                    await c.stop()
                    if let (v, fw, fh) = hash.read() {
                        print("hash: \(scale)× display, the patterned window at \(what), \(fw)×\(fh) px: \(String(v, radix: 16))")
                        if let dir = ProcessInfo.processInfo.environment["CAPTURE_FIT_FRAMES"] {
                            let file = URL(fileURLWithPath: dir).appendingPathComponent("pattern-\(scale)x-\(fw)x\(fh).pgm")
                            try? (Data("P5\n\(fw) \(fh)\n255\n".utf8) + hash.luma).write(to: file)
                        }
                    } else {
                        print("FAIL: \(scale)× display, the patterned window at \(what): no frame"); failures += 1
                    }
                }
            } else {
                print("FAIL: \(scale)× display: the patterned window is not in the capture list"); failures += 1
            }
        } catch {
            print("FAIL: \(scale)× display, the patterned window: \(error)"); failures += 1
        }
        window.orderOut(nil)
        window.close()
        display.destroy()
        try? await Task.sleep(for: .milliseconds(400))      // the display goes before the next one comes
    }
    print("capture-fit: \(failures == 0 ? "all passed" : "\(failures) FAILED")")
    exit(failures == 0 ? 0 : 1)
}
app.run()
