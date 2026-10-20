import AppKit
import LaminaCore

enum Theme {
    /// Window chrome, a mid gray rather than near-black.
    static let window = NSColor(srgbRed: 0.345, green: 0.345, blue: 0.345, alpha: 1)
    /// Canvas surround, about #535353.
    static let pasteboard = NSColor(srgbRed: 0x53 / 255, green: 0x53 / 255, blue: 0x53 / 255, alpha: 1)
    /// Panels, about #323232.
    static let panel = NSColor(srgbRed: 0x32 / 255, green: 0x32 / 255, blue: 0x32 / 255, alpha: 1)
    static let chrome = window
    static let raised = NSColor(srgbRed: 0.27, green: 0.27, blue: 0.27, alpha: 1)
    static let line = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
    static let text = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)
    static let dim = NSColor(srgbRed: 0.74, green: 0.74, blue: 0.74, alpha: 1)
    static let accent = NSColor(srgbRed: 0.078, green: 0.451, blue: 0.902, alpha: 1)
    static let artboard = NSColor.white
    static let guide = NSColor(srgbRed: 0.18, green: 0.78, blue: 0.84, alpha: 1)
    static let homeBlue = NSColor(srgbRed: 0.08, green: 0.40, blue: 0.84, alpha: 1)
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
