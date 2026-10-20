import AppKit
import LaminaCore

enum Theme {
    static func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// PingFang SC, the system face used by the Chinese Illustrator UI.
    static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let name: String
        switch weight {
        case .bold, .semibold: name = "PingFangSC-Semibold"
        case .medium: name = "PingFangSC-Medium"
        default: name = "PingFangSC-Regular"
        }
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Workspace chrome sampled from the Illustrator toolbar (#535353).
    static let window = color(0x535353)
    /// Pasteboard behind the artboard, sampled from the panel screenshot.
    static let pasteboard = color(0x606060)
    /// Toolbar, floating panels, and the properties dock.
    static let panel = color(0x535353)
    static let chrome = window
    /// New-document column, sampled from newdoc-details.png.
    static let dialog = color(0x323232)
    /// Depressed fields. New-document inputs sample to about #1C1C1C.
    static let field = color(0x1C1C1C)
    static let raised = color(0x3A3A3A)
    /// Dividers.
    static let line = color(0x6A6A6A)
    static let fieldBorder = color(0x737373)
    /// Primary text.
    static let text = color(0xE8E8E8)
    /// Labels and unselected tabs.
    static let dim = color(0xB0B0B0)
    /// Group titles.
    static let heading = color(0xD0D0D0)
    /// Tool icons, sampled from the toolbar line art.
    static let icon = color(0xC1C1C1)
    /// Secondary button stroke.
    static let secondaryStroke = color(0x909090)
    /// Generative-AI blue sampled from the toolbar button.
    static let accent = color(0x1673E6)
    static let accentHover = color(0x0059C2)
    static let accentDown = color(0x004DA3)
    static let focus = color(0x54A3F6)
    static let artboard = NSColor.white
    static let guide = NSColor(srgbRed: 0.18, green: 0.78, blue: 0.84, alpha: 1)
    static let homeBlue = accent
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
