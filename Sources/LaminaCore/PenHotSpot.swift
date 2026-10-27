import Foundation

/// Pen-tool cursor tip. The bitmap origin for this spec is the top-left.
/// NSCursor measures its hotspot from the lower-left, so `cursorY` converts the same pixel.
public enum PenHotSpot {
    public static let width = 32
    public static let height = 32
    /// Nib tip, in pixels from the bitmap's top-left. Not the icon center.
    public static let x = 0
    public static let y = 25

    public static var cursorX: Double { Double(x) }
    /// AppKit hotspot y for the tip pixel above.
    public static var cursorY: Double { Double(height - y) }

    public static var isCenter: Bool {
        x == width / 2 && y == height / 2
    }
}
