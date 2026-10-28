import Foundation

/// Pen-tool cursor tip, measured on `PenCursorBitmap`.
///
/// `x` and `y` are the tip pixel. `cursorX` and `cursorY` are the NSCursor hotspot
/// in the same top-left, y-down space (the nib corner, not the image center, and
/// not `height - y`). v0.4.1's lower-left conversion put the drawn tip ~19.5 pt
/// above the click on a Retina Mac.
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
