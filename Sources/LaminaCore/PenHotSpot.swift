import Foundation

/// Pen-tool cursor tip, measured on `PenCursorBitmap`.
///
/// `x` and `y` are the tip pixel from the bitmap's top-left. NSCursor's hotspot
/// is that same point from the lower-left (`cursorX`, `cursorY`). It is the nib
/// tip, not the center of the 32×32 image.
public enum PenHotSpot {
    public static let width = PenCursorBitmap.width
    public static let height = PenCursorBitmap.height
    public static var x: Int { PenCursorBitmap.tipPixel.x }
    public static var y: Int { PenCursorBitmap.tipPixel.y }
    public static var cursorX: Double { PenCursorBitmap.hotspotX }
    public static var cursorY: Double { PenCursorBitmap.hotspotY }
    public static var tipError: Double { PenCursorBitmap.tipError }

    public static var isCenter: Bool {
        x == width / 2 && y == height / 2
    }
}
