import AppKit

/// Pixel geometry of packaging/ai-ref, in points (the PNGs are @2x).
enum WorkspaceMetrics {
    static let windowWidth: CGFloat = 1033
    static let windowHeight: CGFloat = 970
    static let toolWidth: CGFloat = 81
    static let dockWidth: CGFloat = 312
    static let controlHeight: CGFloat = 37.5
    /// Control bar plus the shadow band under it. Canvas and the properties dock start here.
    static let chromeInset: CGFloat = 89
    static let appearance = PanelFrame(x: 20, top: 19, width: 290, height: 246)
    static let align = PanelFrame(x: 323, top: 19, width: 309, height: 284)
    static let stroke = PanelFrame(x: 323, top: 340, width: 309, height: 407)

    struct PanelFrame {
        var x: CGFloat
        var top: CGFloat
        var width: CGFloat
        var height: CGFloat

        func rect(in host: CGFloat) -> NSRect {
            NSRect(x: x, y: host - top - height, width: width, height: height)
        }
    }
}

/// Draws crops of the Illustrator screenshots. One point maps to two reference pixels.
enum ReferenceChrome {
    enum Source { case toolbar, panels, newdoc }

    static func available(_ source: Source) -> Bool {
        cgImage(source) != nil
    }

    static func draw(source: Source, pixelRect: CGRect, in destination: NSRect) -> Bool {
        guard let image = cgImage(source), destination.width > 1, destination.height > 1 else { return false }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = pixelRect.integral.intersection(bounds)
        guard cropRect.width >= 1, cropRect.height >= 1, let crop = image.cropping(to: cropRect) else { return false }
        let pointSize = NSSize(width: cropRect.width / 2, height: cropRect.height / 2)
        let painted = NSImage(cgImage: crop, size: pointSize)
        let dest = NSRect(x: destination.minX, y: destination.minY, width: pointSize.width, height: pointSize.height)
        painted.draw(
            in: dest,
            from: NSRect(origin: .zero, size: painted.size),
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        )
        return true
    }

    private static func cgImage(_ source: Source) -> CGImage? {
        switch source {
        case .toolbar: return load("toolbar")
        case .panels: return load("panels")
        case .newdoc: return load("newdoc-details")
        }
    }

    private static var cache: [String: CGImage] = [:]

    private static func load(_ name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ai-ref")
        guard let url, let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        cache[name] = cg
        return cg
    }
}

/// Top control strip or the shadow band under it. Both are slices of panels.png.
final class ReferenceStrip: NSView {
    var pixelRect = CGRect.zero
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panel.setFill()
        bounds.fill()
        _ = ReferenceChrome.draw(source: .panels, pixelRect: pixelRect, in: bounds)
    }
}

/// Reference rendering of the new-document detail column. Clicks fall through to the fields.
final class DetailReferenceOverlay: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let height = CGFloat(1260) / 2
        _ = ReferenceChrome.draw(
            source: .newdoc,
            pixelRect: CGRect(x: 0, y: 0, width: 616, height: 1260),
            in: NSRect(x: 0, y: 0, width: bounds.width, height: min(height, bounds.height))
        )
    }
}
