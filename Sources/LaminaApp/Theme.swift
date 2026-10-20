import AppKit
import LaminaCore

enum Theme {
    static let pasteboard = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    static let chrome = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    static let panel = NSColor(srgbRed: 0.14, green: 0.14, blue: 0.15, alpha: 1)
    static let raised = NSColor(srgbRed: 0.22, green: 0.22, blue: 0.24, alpha: 1)
    static let line = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    static let text = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    static let dim = NSColor(srgbRed: 0.64, green: 0.64, blue: 0.67, alpha: 1)
    static let accent = NSColor(srgbRed: 0.078, green: 0.451, blue: 0.902, alpha: 1)
    static let artboard = NSColor.white
    static let guide = NSColor(srgbRed: 0.18, green: 0.78, blue: 0.84, alpha: 1)
}

extension CGPoint {
    init(x: Double, y: Double) {
        self.init(x: CGFloat(x), y: CGFloat(y))
    }
}

extension CGRect {
    init(x: Double, y: Double, width: Double, height: Double) {
        self.init(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }
}

extension CGContext {
    func setLineWidth(_ width: Double) {
        setLineWidth(CGFloat(width))
    }
}

extension RGBA {
    /// Display conversion. Authored CMYK goes through the generic CMYK space (ColorSync) into sRGB.
    var cgColor: CGColor {
        if let source = cmykSource {
            let device = CGColor(genericCMYKCyan: CGFloat(source.c), magenta: CGFloat(source.m), yellow: CGFloat(source.y), black: CGFloat(source.k), alpha: CGFloat(a))
            if let srgb = CGColorSpace(name: CGColorSpace.sRGB),
               let converted = device.converted(to: srgb, intent: .relativeColorimetric, options: nil) {
                return converted
            }
        }
        return CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var nsColor: NSColor {
        if let source = cmykSource {
            let device = NSColor(deviceCyan: CGFloat(source.c), magenta: CGFloat(source.m), yellow: CGFloat(source.y), black: CGFloat(source.k), alpha: CGFloat(a))
            return device.usingColorSpace(.sRGB) ?? NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
