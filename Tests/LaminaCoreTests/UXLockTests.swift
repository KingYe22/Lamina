import XCTest
@testable import LaminaCore

final class UXLockTests: XCTestCase {
    func testDistanceAndMoveLabelsUseDocumentUnits() {
        XCTAssertEqual(ToolBehaviors.distanceLabel(points: 1, unit: .mm), "D: 0.35 mm")
        XCTAssertEqual(ToolBehaviors.distanceLabel(points: 72, unit: .mm), "D: 25.40 mm")
        let moved = ToolBehaviors.moveDeltaLines(dx: 72, dy: -36, unit: .mm)
        XCTAssertEqual(moved.dx, "dX: 25.40 mm")
        XCTAssertEqual(moved.dy, "dY: -12.70 mm")
        XCTAssertEqual(ToolBehaviors.moveDeltaLines(dx: 10, dy: 0, unit: .pt).dx, "dX: 10.00 pt")
    }

    func testDockSnapMeetsAtZeroInsideEightAndIgnoresNine() {
        XCTAssertEqual(DockSnap.threshold, 8)
        let host = DockFrame(x: 0, y: 0, width: 500, height: 400)
        let other = DockFrame(x: 100, y: 50, width: 80, height: 40)
        let near = DockFrame(x: 186, y: 50, width: 40, height: 30)
        let hit = DockSnap.magnet(frame: near, others: [other], host: host)
        XCTAssertEqual(hit.frame.x, 180, accuracy: 0.001)
        XCTAssertEqual(hit.frame.y, 50, accuracy: 0.001)
        XCTAssertEqual(hit.frame.x - other.maxX, 0, accuracy: 0.001)
        XCTAssertFalse(hit.guides.isEmpty)

        let far = DockFrame(x: 189, y: 120, width: 40, height: 30)
        let miss = DockSnap.magnet(frame: far, others: [other], host: host)
        XCTAssertEqual(miss.frame.x, 189, accuracy: 0.001)
        XCTAssertTrue(miss.guides.isEmpty)

        let edge = DockFrame(x: 8, y: 8, width: 40, height: 30)
        let docked = DockSnap.magnet(frame: edge, others: [], host: host)
        XCTAssertEqual(docked.frame.x, 0, accuracy: 0.001)
        XCTAssertEqual(docked.frame.y, 0, accuracy: 0.001)

        let outside = DockFrame(x: 9, y: 40, width: 40, height: 30)
        let free = DockSnap.magnet(frame: outside, others: [], host: host)
        XCTAssertEqual(free.frame.x, 9, accuracy: 0.001)
    }

    func testRightShoulderSnapsFlushInsideEightAndIgnoresNine() {
        XCTAssertEqual(DockSnap.guideHex, 0x0072EF)
        let host = DockFrame(x: 0, y: 0, width: 1000, height: 700)
        let near = DockFrame(x: 1000 - 180 - 6, y: 80, width: 180, height: 120)
        let hit = DockSnap.magnet(frame: near, others: [], host: host)
        XCTAssertEqual(hit.frame.maxX, host.maxX, accuracy: 0.001)
        XCTAssertEqual(host.maxX - hit.frame.maxX, 0, accuracy: 0.001)
        XCTAssertTrue(hit.guides.contains { guide in
            if case .vertical(let x) = guide.axis { return abs(x - host.maxX) < 0.001 }
            return false
        })

        let edge = DockFrame(x: 1000 - 180 - 8, y: 80, width: 180, height: 120)
        let atLimit = DockSnap.magnet(frame: edge, others: [], host: host)
        XCTAssertEqual(atLimit.frame.maxX, host.maxX, accuracy: 0.001)

        let far = DockFrame(x: 1000 - 180 - 9, y: 80, width: 180, height: 120)
        let miss = DockSnap.magnet(frame: far, others: [], host: host)
        XCTAssertEqual(miss.frame.x, far.x, accuracy: 0.001)
        XCTAssertTrue(miss.guides.isEmpty)
    }

    func testGenerativeEntryLeavesPanelsAndStrokeAlone() {
        let model = EditorModel()
        model.openPanels = ["属性", "图层", "外观", "对齐", "描边"]
        let width = model.currentStroke?.width
        let selection = model.selection
        model.presentGenerative()
        XCTAssertTrue(model.generativeOpen)
        XCTAssertEqual(model.openPanels, ["属性", "图层", "外观", "对齐", "描边"])
        XCTAssertEqual(model.currentStroke?.width, width)
        XCTAssertEqual(model.selection, selection)
        XCTAssertEqual(model.status, "生成式")
    }

    func testPenHotSpotIsTheNibTipNotTheCenter() {
        XCTAssertEqual(PenHotSpot.width, 32)
        XCTAssertEqual(PenHotSpot.height, 32)
        XCTAssertEqual(PenCursorBitmap.tipX, 1, accuracy: 1e-9)
        XCTAssertEqual(PenCursorBitmap.tipY, 1, accuracy: 1e-9)
        XCTAssertEqual(PenHotSpot.x, 1)
        XCTAssertEqual(PenHotSpot.y, 1)
        XCTAssertFalse(PenHotSpot.isCenter)
        XCTAssertEqual(PenHotSpot.cursorX, PenCursorBitmap.tipX, accuracy: 1e-9)
        XCTAssertEqual(PenHotSpot.cursorY, PenCursorBitmap.tipY, accuracy: 1e-9)
        let one = PenCursorBitmap.measureTip(scale: 1)
        let two = PenCursorBitmap.measureTip(scale: 2)
        print("tipError_logical 1x=\(one.absolute) dx=\(one.dx) dy=\(one.dy) 2x=\(two.absolute) dx=\(two.dx) dy=\(two.dy)")
        XCTAssertLessThanOrEqual(one.absolute, 1.5)
        XCTAssertLessThanOrEqual(two.absolute, 1.5)
        XCTAssertEqual(one.absolute, 0, accuracy: 1e-9)
        XCTAssertEqual(two.absolute, 0, accuracy: 1e-9)
        XCTAssertEqual(PenHotSpot.tipError, 0, accuracy: 1e-9)
        XCTAssertEqual(one.ulX, PenHotSpot.cursorX, accuracy: 1e-9)
        XCTAssertEqual(one.ulY, PenHotSpot.cursorY, accuracy: 1e-9)
        XCTAssertEqual(two.ulX, PenHotSpot.cursorX, accuracy: 1e-9)
        XCTAssertEqual(two.ulY, PenHotSpot.cursorY, accuracy: 1e-9)
        XCTAssertNotEqual(PenHotSpot.x, PenHotSpot.width / 2)
        XCTAssertNotEqual(PenHotSpot.y, PenHotSpot.height / 2)
    }

    func testPenBitmapIsSolidBlackNibWithSlitAndNewPathMark() {
        let plain = PenCursorBitmap.rgba(state: .pen, newPath: false)
        let starred = PenCursorBitmap.rgba(state: .pen, newPath: true)
        let caret = PenCursorBitmap.rgba(state: .convert, newPath: false)
        XCTAssertEqual(plain.count, 32 * 32 * 4)
        XCTAssertEqual(PenCursorBitmap.rgba(state: .pen, newPath: false, scale: 2).count, 64 * 64 * 4)

        let tip = pixel(plain, PenHotSpot.x, PenHotSpot.y)
        XCTAssertGreaterThan(tip.a, 200, cursorGrid(plain))
        XCTAssertLessThan(tip.r, 48, "tip pixel is black ink, got \(tip)\n\(cursorGrid(plain))")
        XCTAssertEqual(foremost(plain)?.x, PenHotSpot.x, cursorGrid(plain))
        XCTAssertEqual(foremost(plain)?.y, PenHotSpot.y, cursorGrid(plain))
        XCTAssertLessThan(pixel(plain, PenHotSpot.x - 1, PenHotSpot.y - 1).a, 16, cursorGrid(plain))
        XCTAssertEqual(foremost(caret)?.x, PenHotSpot.x, cursorGrid(caret))
        XCTAssertEqual(foremost(caret)?.y, PenHotSpot.y, cursorGrid(caret))

        XCTAssertGreaterThan(blackCount(plain), 40, cursorGrid(plain))
        let slit = interiorWhite(plain)
        XCTAssertGreaterThanOrEqual(slit, 4, "white slit inside the nib\n\(cursorGrid(plain))")
        XCTAssertLessThan(exteriorWhite(plain), 8, "no sticker outline\n\(cursorGrid(plain))")

        XCTAssertGreaterThan(cornerOpaque(starred), cornerOpaque(plain) + 10, cursorGrid(starred))
        XCTAssertLessThan(cornerOpaque(plain), 8, cursorGrid(plain))
        XCTAssertNotEqual(
            PenCursorBitmap.rgba(state: .add, newPath: false),
            PenCursorBitmap.rgba(state: .delete, newPath: false)
        )
    }

    func testPropertiesShoulderDocksOnApproachAndNotWhileResting() {
        let host = DockFrame(x: 0, y: 0, width: 952, height: 800)
        let shoulder = DockFrame(x: 640, y: 0, width: 312, height: 800)
        let width = 180.0
        let nearMax = shoulder.minX - 6
        let near = DockFrame(x: nearMax - width, y: 6, width: width, height: 120)

        let moving = DockSnap.magnet(
            frame: near, others: [], host: host, shoulder: shoulder, dragStartMaxX: near.maxX - 3
        )
        XCTAssertEqual(moving.frame.maxX, shoulder.maxX, accuracy: 0.001)
        XCTAssertEqual(moving.frame.x, shoulder.minX, accuracy: 0.001)
        XCTAssertEqual(moving.frame.width, shoulder.width, accuracy: 0.001)
        XCTAssertEqual(moving.frame.y, 0, accuracy: 0.001)
        XCTAssertGreaterThan(abs(moving.frame.x - near.x), DockSnap.threshold)
        XCTAssertTrue(moving.guides.contains { guide in
            if case .vertical(let x) = guide.axis { return abs(x - shoulder.maxX) < 0.001 }
            return false
        })

        let parked = DockFrame(x: near.x, y: 40, width: width, height: 120)
        let jitter = DockSnap.magnet(
            frame: parked, others: [], host: host, shoulder: shoulder, dragStartMaxX: parked.maxX - 1
        )
        XCTAssertEqual(jitter.frame.x, parked.x, accuracy: 0.001)

        let resting = DockSnap.magnet(
            frame: parked, others: [], host: host, shoulder: shoulder, dragStartMaxX: parked.maxX
        )
        XCTAssertEqual(resting.frame.x, parked.x, accuracy: 0.001)
        XCTAssertTrue(resting.guides.isEmpty)

        let farMax = shoulder.minX - 9
        let far = DockFrame(x: farMax - width, y: 40, width: width, height: 120)
        let miss = DockSnap.magnet(
            frame: far, others: [], host: host, shoulder: shoulder, dragStartMaxX: far.maxX - 3
        )
        XCTAssertEqual(miss.frame.x, far.x, accuracy: 0.001)

        let overlap = DockFrame(x: shoulder.minX - width + 20, y: 40, width: width, height: 120)
        let held = DockSnap.magnet(
            frame: overlap, others: [], host: host, shoulder: shoulder, dragStartMaxX: overlap.maxX + 10
        )
        XCTAssertEqual(held.frame.maxX, shoulder.maxX, accuracy: 0.001)

        let distant = DockFrame(x: 10, y: 40, width: width, height: 120)
        let pointed = DockSnap.magnet(
            frame: distant, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(shoulder.minX + 20, 100), dragStartMaxX: distant.maxX
        )
        XCTAssertEqual(pointed.frame.maxX, shoulder.maxX, accuracy: 0.001)
        let outside = DockSnap.magnet(
            frame: distant, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(shoulder.minX - 9, 100), dragStartMaxX: distant.maxX
        )
        XCTAssertEqual(outside.frame.x, distant.x, accuracy: 0.001)
    }

    /// Drag 外观 and 对齐 into the blue-guide zone, then release at the raw
    /// (unsnapped) origin. The panel must join the shoulder column.
    func testAppearanceAndAlignReleaseIntoTheRightShoulder() {
        let host = DockFrame(x: 0, y: 0, width: 952, height: 800)
        let shoulder = DockFrame(x: 640, y: 0, width: 312, height: 800)

        let appearance = DockFrame(x: 19, y: 520, width: 302, height: 243)
        let approachX = shoulder.minX - 6 - appearance.width
        var appearanceDrag = DockGesture(floating: appearance)
        let approach = DockFrame(x: approachX, y: appearance.y, width: appearance.width, height: appearance.height)
        let hold = appearanceDrag.step(
            proposed: approach, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(approach.x + 40, approach.y + 10),
            dragStartMaxX: appearance.maxX, up: false
        )
        XCTAssertTrue(appearanceDrag.shoulderArmed)
        XCTAssertEqual(hold.frame.x, shoulder.minX, accuracy: 0.001)
        XCTAssertEqual(hold.frame.width, shoulder.width, accuracy: 0.001)
        XCTAssertEqual(hold.frame.maxX, shoulder.maxX, accuracy: 0.001)
        XCTAssertTrue(hold.guides.contains { guide in
            if case .vertical(let x) = guide.axis { return abs(x - shoulder.maxX) < 0.001 }
            return false
        })
        let released = appearanceDrag.step(
            proposed: approach, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(approach.x + 40, approach.y + 10),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertTrue(released.docked)
        XCTAssertTrue(released.guides.isEmpty)
        XCTAssertEqual(released.frame.x, shoulder.minX, accuracy: 0.001)
        XCTAssertEqual(released.frame.width, shoulder.width, accuracy: 0.001)
        XCTAssertEqual(released.frame.maxX, host.maxX, accuracy: 0.001)

        // Pointer is already in the column while the panel is still hundreds of
        // points short of the edge — the guide is on, so mouse-up joins the dock.
        let center = DockFrame(x: 200, y: 400, width: appearance.width, height: appearance.height)
        XCTAssertGreaterThan(shoulder.maxX - center.maxX, 200)
        var pointerDrag = DockGesture(floating: appearance)
        let aimed = pointerDrag.step(
            proposed: center, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(shoulder.minX + 24, 420),
            dragStartMaxX: appearance.maxX, up: false
        )
        XCTAssertTrue(pointerDrag.shoulderArmed)
        XCTAssertEqual(aimed.frame.x, shoulder.minX, accuracy: 0.001)
        let dropped = pointerDrag.step(
            proposed: center, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(shoulder.minX + 24, 420),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertTrue(dropped.docked)
        XCTAssertEqual(dropped.frame.x, shoulder.minX, accuracy: 0.001)
        XCTAssertEqual(dropped.frame.width, shoulder.width, accuracy: 0.001)

        let align = DockFrame(x: 280, y: 480, width: 313, height: 283)
        var alignDrag = DockGesture(floating: align)
        let alignNear = DockFrame(x: shoulder.minX - 4 - align.width, y: align.y, width: align.width, height: align.height)
        _ = alignDrag.step(
            proposed: alignNear, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(alignNear.maxX - 8, alignNear.y + 12),
            dragStartMaxX: align.maxX, up: false
        )
        let alignUp = alignDrag.step(
            proposed: alignNear, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(alignNear.maxX - 8, alignNear.y + 12),
            dragStartMaxX: align.maxX, up: true
        )
        XCTAssertTrue(alignUp.docked)
        XCTAssertEqual(alignUp.frame.x, shoulder.minX, accuracy: 0.001)
        XCTAssertEqual(alignUp.frame.width, shoulder.width, accuracy: 0.001)
        XCTAssertEqual(alignUp.frame.maxX, shoulder.maxX, accuracy: 0.001)

        // Leaving the zone turns the guide off; mouse-up keeps the floating frame.
        var leave = DockGesture(floating: appearance)
        _ = leave.step(
            proposed: approach, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(approach.x + 20, approach.y + 10),
            dragStartMaxX: appearance.maxX, up: false
        )
        XCTAssertTrue(leave.shoulderArmed)
        let away = DockFrame(x: 30, y: 400, width: appearance.width, height: appearance.height)
        let backedOut = leave.step(
            proposed: away, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(80, 420),
            dragStartMaxX: appearance.maxX, up: false
        )
        XCTAssertFalse(leave.shoulderArmed)
        XCTAssertFalse(backedOut.docked)
        XCTAssertEqual(backedOut.frame.width, appearance.width, accuracy: 0.001)
        let left = leave.step(
            proposed: away, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(80, 420),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertFalse(leave.shoulderArmed)
        XCTAssertFalse(left.docked)
        XCTAssertEqual(left.frame.x, away.x, accuracy: 0.001)
        XCTAssertEqual(left.frame.width, appearance.width, accuracy: 0.001)

        // Mouse-up itself is far outside the column: do not dock on a stale latch.
        var releaseFar = DockGesture(floating: appearance)
        _ = releaseFar.step(
            proposed: approach, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(approach.x + 20, approach.y + 10),
            dragStartMaxX: appearance.maxX, up: false
        )
        let jumped = releaseFar.step(
            proposed: away, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(80, 420),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertFalse(releaseFar.shoulderArmed)
        XCTAssertFalse(jumped.docked)
        XCTAssertEqual(jumped.frame.x, away.x, accuracy: 0.001)

        // Release a few points outside the 8 pt zone still joins, because the guide was lit.
        var flicker = DockGesture(floating: appearance)
        _ = flicker.step(
            proposed: approach, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(approach.x + 20, approach.y + 10),
            dragStartMaxX: appearance.maxX, up: false
        )
        let almost = DockFrame(
            x: shoulder.minX - 12 - appearance.width, y: appearance.y,
            width: appearance.width, height: appearance.height
        )
        let flickUp = flicker.step(
            proposed: almost, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(almost.x + 24, almost.y + 8),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertTrue(flickUp.docked)
        XCTAssertEqual(flickUp.frame.x, shoulder.minX, accuracy: 0.001)
        XCTAssertEqual(flickUp.frame.width, shoulder.width, accuracy: 0.001)
    }

    func testPenHoverCursorFollowsThePointerWithoutClobberingTheClickCursor() {
        let fresh = EditorModel()
        fresh.tool = .pen
        fresh.pointerMove(to: Vec2(12, 4))
        XCTAssertEqual(fresh.penHoverCursor, .pen)
        XCTAssertTrue(fresh.penNewPathMark)
        XCTAssertEqual(fresh.penCursor, .pen)

        fresh.pointerDown(at: .zero, shift: false, option: false, command: false)
        fresh.pointerUp(at: .zero, shift: false, option: false, command: false)
        fresh.pointerDown(at: Vec2(40, 0), shift: false, option: false, command: false)
        fresh.pointerUp(at: Vec2(40, 0), shift: false, option: false, command: false)
        fresh.finishPen()
        let clicked = fresh.penCursor
        fresh.pointerMove(to: Vec2(40, 0))
        XCTAssertEqual(fresh.penHoverCursor, .continuePath)
        XCTAssertEqual(fresh.penCursor, clicked)
        XCTAssertFalse(fresh.penNewPathMark && fresh.penHoverCursor == .pen)
        fresh.pointerMove(to: Vec2(200, 200))
        XCTAssertEqual(fresh.penHoverCursor, .pen)
        XCTAssertTrue(fresh.penNewPathMark)

        let closing = EditorModel()
        closing.tool = .pen
        closing.pointerDown(at: .zero, shift: false, option: false, command: false)
        closing.pointerUp(at: .zero, shift: false, option: false, command: false)
        closing.pointerDown(at: Vec2(30, 0), shift: false, option: false, command: false)
        closing.pointerUp(at: Vec2(30, 0), shift: false, option: false, command: false)
        closing.pointerDown(at: Vec2(30, 30), shift: false, option: false, command: false)
        closing.pointerUp(at: Vec2(30, 30), shift: false, option: false, command: false)
        XCTAssertEqual(closing.penCursor, .pen)
        closing.pointerMove(to: Vec2(1, 0))
        XCTAssertEqual(closing.penHoverCursor, .close)
        XCTAssertEqual(closing.penCursor, .pen)

        let editing = EditorModel()
        editing.tool = .rectangle
        editing.pointerDown(at: .zero, shift: false, option: false, command: false)
        editing.pointerDrag(to: Vec2(40, 20), shift: false, option: false, command: false)
        editing.pointerUp(at: Vec2(40, 20), shift: false, option: false, command: false)
        editing.tool = .pen
        editing.autoAddDelete = true
        editing.pointerMove(to: Vec2(20, 0))
        XCTAssertEqual(editing.penHoverCursor, .add)
        editing.pointerMove(to: .zero)
        XCTAssertEqual(editing.penHoverCursor, .delete)
        XCTAssertEqual(editing.penCursor, .pen)
    }

    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let offset = (y * 32 + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
    }

    private func foremost(_ bytes: [UInt8]) -> (x: Int, y: Int)? {
        var best: (x: Int, y: Int, score: Int)?
        for y in 0..<32 {
            for x in 0..<32 {
                if pixel(bytes, x, y).a <= 16 { continue }
                let score = x + y
                if let current = best, score >= current.score { continue }
                best = (x, y, score)
            }
        }
        return best.map { ($0.x, $0.y) }
    }

    private func blackCount(_ bytes: [UInt8]) -> Int {
        var count = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let sample = pixel(bytes, x, y)
                if sample.a > 200, sample.r < 48 { count += 1 }
            }
        }
        return count
    }

    /// White pixels whose four neighbors are opaque: the nib slit, not an outline.
    private func interiorWhite(_ bytes: [UInt8]) -> Int {
        var count = 0
        for y in 1..<31 {
            for x in 1..<31 {
                let sample = pixel(bytes, x, y)
                guard sample.a > 200, sample.r > 200 else { continue }
                let around = [pixel(bytes, x - 1, y), pixel(bytes, x + 1, y), pixel(bytes, x, y - 1), pixel(bytes, x, y + 1)]
                if around.allSatisfy({ $0.a > 200 }) { count += 1 }
            }
        }
        return count
    }

    /// White pixels that touch transparency. A sticker outline lives here.
    private func exteriorWhite(_ bytes: [UInt8]) -> Int {
        var count = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let sample = pixel(bytes, x, y)
                guard sample.a > 200, sample.r > 200 else { continue }
                var exposed = false
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx
                    let ny = y + dy
                    if nx < 0 || ny < 0 || nx >= 32 || ny >= 32 || pixel(bytes, nx, ny).a < 16 {
                        exposed = true
                    }
                }
                if exposed { count += 1 }
            }
        }
        return count
    }

    private func cornerOpaque(_ bytes: [UInt8]) -> Int {
        var count = 0
        for y in 22..<32 {
            for x in 22..<32 where pixel(bytes, x, y).a > 16 {
                count += 1
            }
        }
        return count
    }

    private func cursorGrid(_ bytes: [UInt8]) -> String {
        (0..<32).map { y in
            (0..<32).map { x in
                let sample = pixel(bytes, x, y)
                if sample.a < 16 { return " " }
                if sample.r > 200 { return "w" }
                if sample.r < 48 { return "k" }
                return "."
            }.joined()
        }.joined(separator: "\n")
    }

    func testPenChromeDistanceAnchorAndNewPath() {
        let model = EditorModel()
        model.document.units = .mm
        model.tool = .pen
        model.pointerMove(to: Vec2(12, 4))
        XCTAssertTrue(model.penNewPathMark)
        XCTAssertEqual(model.penDistance, "")
        XCTAssertFalse(model.penAnchorLabel)

        model.pointerDown(at: .zero, shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(72, 0), shift: false, option: false, command: false)
        XCTAssertFalse(model.penRubberLive)
        XCTAssertEqual(model.penDistance, "D: 25.40 mm")
        XCTAssertFalse(model.penNewPathMark)
        model.pointerUp(at: Vec2(72, 0), shift: false, option: false, command: false)
        XCTAssertTrue(model.penRubberLive)
        XCTAssertEqual(model.penDistance, "D: 25.40 mm")

        model.pointerMove(to: Vec2(10, 1), shift: true)
        XCTAssertEqual(model.hover.y, 0, accuracy: 0.01)
        XCTAssertTrue(model.penDistance.hasPrefix("D: "))

        model.tool = .rectangle
        model.pointerDown(at: .zero, shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(40, 20), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(40, 20), shift: false, option: false, command: false)
        model.tool = .pen
        model.penNodes = []
        model.pointerMove(to: .zero)
        XCTAssertTrue(model.penAnchorLabel)
        XCTAssertTrue(model.penNewPathMark)
        model.pointerMove(to: Vec2(20, 10))
        XCTAssertFalse(model.penAnchorLabel)
    }

    func testObjectMoveReadoutIsSeparateFromPenDistance() {
        let model = EditorModel()
        model.document.units = .mm
        model.tool = .rectangle
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(80, 60), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(80, 60), shift: false, option: false, command: false)
        model.tool = .selection
        model.pointerDown(at: Vec2(40, 30), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(40 + 72, 30 - 36), shift: false, option: false, command: false)
        XCTAssertEqual(model.moveDX, "dX: 25.40 mm")
        XCTAssertEqual(model.moveDY, "dY: -12.70 mm")
        XCTAssertEqual(model.penDistance, "")
        XCTAssertFalse(model.liveLabel.contains("dX:"))
        model.pointerUp(at: Vec2(40 + 72, 30 - 36), shift: false, option: false, command: false)
        XCTAssertEqual(model.moveDX, "")
        XCTAssertEqual(model.moveDY, "")
    }

    func testZoomRectAndBrushCursorsMatchIllustratorArtwork() {
        XCTAssertEqual(ToolCursors.kind(for: .zoom), .zoomIn)
        XCTAssertEqual(ToolCursors.kind(for: .rectangle), .precision)
        XCTAssertEqual(ToolCursors.kind(for: .ellipse), .precision)
        XCTAssertEqual(ToolCursors.kind(for: .line), .precision)
        XCTAssertEqual(ToolCursors.kind(for: .brush), .brush)
        XCTAssertNil(ToolCursors.kind(for: .selection))
        XCTAssertNil(ToolCursors.kind(for: .pen))
        XCTAssertEqual(ToolCursorBitmap.zoomHotspot, ToolCursorHotspot(x: 11.5, y: 11.5))
        XCTAssertEqual(ToolCursorBitmap.precisionHotspot, ToolCursorHotspot(x: 16, y: 16))
        XCTAssertEqual(ToolCursorBitmap.brushHotspot, ToolCursorHotspot(x: 5, y: 23))

        let zoom = ToolCursorBitmap.rgba(kind: .zoomIn)
        let zoomOut = ToolCursorBitmap.rgba(kind: .zoomOut)
        XCTAssertEqual(zoom.count, 32 * 32 * 4)
        XCTAssertEqual(ToolCursorBitmap.rgba(kind: .zoomIn, scale: 2).count, 64 * 64 * 4)
        XCTAssertNotEqual(zoom, zoomOut)
        let plus = pixel(zoom, 11, 11)
        XCTAssertGreaterThan(plus.a, 200, cursorGrid(zoom))
        XCTAssertLessThan(plus.r, 48, cursorGrid(zoom))
        let stem = pixel(zoom, 11, 8)
        XCTAssertLessThan(stem.r, 48, "plus stem\n\(cursorGrid(zoom))")
        let minus = pixel(zoomOut, 11, 8)
        XCTAssertGreaterThan(minus.r, 200, "minus leaves the stem white\n\(cursorGrid(zoomOut))")
        let lens = pixel(zoom, 14, 14)
        XCTAssertGreaterThan(lens.r, 200, "white lens\n\(cursorGrid(zoom))")
        let ring = pixel(zoom, 17, 11)
        XCTAssertLessThan(ring.r, 48, "black rim\n\(cursorGrid(zoom))")
        let rim = pixel(zoom, 19, 11)
        XCTAssertGreaterThan(rim.r, 200, "white outer edge\n\(cursorGrid(zoom))")
        let handle = pixel(zoom, 22, 22)
        XCTAssertLessThan(handle.r, 48, "handle\n\(cursorGrid(zoom))")
        XCTAssertLessThan(pixel(zoom, 2, 11).a, 16, "not a full-span cross\n\(cursorGrid(zoom))")
        XCTAssertLessThan(pixel(zoom, 11, 2).a, 16, cursorGrid(zoom))
        XCTAssertLessThan(pixel(zoom, 0, 0).a, 16, cursorGrid(zoom))
        XCTAssertLessThan(pixel(zoom, 31, 31).a, 16, cursorGrid(zoom))
        XCTAssertGreaterThan(exteriorWhite(zoom), 8, "magnifier has a white outline\n\(cursorGrid(zoom))")

        let cross = ToolCursorBitmap.rgba(kind: .precision)
        XCTAssertLessThan(pixel(cross, 16, 16).a, 16, "center gap\n\(cursorGrid(cross))")
        XCTAssertLessThan(pixel(cross, 15, 16).a, 16, cursorGrid(cross))
        XCTAssertLessThan(pixel(cross, 16, 15).a, 16, cursorGrid(cross))
        XCTAssertLessThan(pixel(cross, 15, 15).a, 16, cursorGrid(cross))
        for point in [(7, 16), (24, 16), (16, 7), (16, 24)] {
            let sample = pixel(cross, point.0, point.1)
            XCTAssertGreaterThan(sample.a, 200, "arm \(point)\n\(cursorGrid(cross))")
            XCTAssertLessThan(sample.r, 48, cursorGrid(cross))
        }
        XCTAssertEqual(pixel(cross, 7, 16).a, pixel(cross, 24, 16).a)
        XCTAssertEqual(pixel(cross, 16, 7).a, pixel(cross, 16, 24).a)
        XCTAssertLessThan(pixel(cross, 1, 1).a, 16, "not an arrow\n\(cursorGrid(cross))")
        XCTAssertLessThan(pixel(cross, 0, 0).a, 16, cursorGrid(cross))
        XCTAssertGreaterThan(exteriorWhite(cross), 8, "cross has a white outline\n\(cursorGrid(cross))")

        let brush = ToolCursorBitmap.rgba(kind: .brush, mark: false)
        let marked = ToolCursorBitmap.rgba(kind: .brush, mark: true)
        let tip = pixel(brush, 5, 23)
        XCTAssertGreaterThan(tip.a, 200, cursorGrid(brush))
        XCTAssertLessThan(tip.r, 48, "tip is black\n\(cursorGrid(brush))")
        let body = pixel(brush, 20, 10)
        XCTAssertGreaterThan(body.a, 200, "brush body\n\(cursorGrid(brush))")
        XCTAssertLessThan(body.r, 48, cursorGrid(brush))
        XCTAssertEqual(opaque(brush, x: 22..<32, y: 22..<32), 0, "plain brush has no corner mark\n\(cursorGrid(brush))")
        XCTAssertGreaterThan(opaque(marked, x: 22..<32, y: 22..<32), 10, "new stroke asterisk\n\(cursorGrid(marked))")
        XCTAssertGreaterThan(exteriorWhite(brush), 8, "brush has a white outline\n\(cursorGrid(brush))")
    }

    func testEmptyDocumentPaintIsWhiteFillAndBlackStroke() {
        let model = EditorModel()
        XCTAssertEqual(model.currentFill, .solid(.white))
        XCTAssertEqual(model.currentStroke?.paint, .solid(.black))
        XCTAssertEqual(model.currentStroke?.width, 1)
        XCTAssertEqual(Appearance.documentDefault, LaminaDocument.defaultAppearance)
        XCTAssertEqual(Appearance.default.fill, .solid(.white))
        XCTAssertEqual(Appearance.default.stroke?.paint, .solid(.black))
        XCTAssertTrue(model.activeAttrIsFill)

        model.currentFill = nil
        model.currentStroke = nil
        model.activeAttrIsFill = false
        model.newDocument(size: Vec2(200, 200))
        XCTAssertEqual(model.currentFill, .solid(.white))
        XCTAssertEqual(model.currentStroke?.paint, .solid(.black))
        XCTAssertEqual(model.currentStroke?.width, 1)
        XCTAssertTrue(model.activeAttrIsFill)

        model.currentFill = .solid(.black)
        model.currentStroke = nil
        XCTAssertTrue(model.perform("把填色和描边设置为默认"))
        XCTAssertEqual(model.currentFill, .solid(.white))
        XCTAssertEqual(model.currentStroke?.paint, .solid(.black))
        XCTAssertEqual(model.currentStroke?.width, 1)
    }

    /// Appearance, toolbar wells, and the selection share one paint store.
    /// The old split left Appearance on black fill / no stroke while the wells followed D and Shift+X.
    func testAppearanceMatchesWellsAndSelectionAfterDefaultAndSwap() {
        let model = EditorModel()
        let defaults = Appearance.documentDefault
        assertSharedPaint(model, fill: defaults.fill, stroke: defaults.stroke, name: "未选择对象")
        let stale = Appearance(fill: .solid(.black), stroke: nil)
        XCTAssertNotEqual(model.appearanceAttributes.fill, stale.fill)
        XCTAssertNotEqual(model.appearanceAttributes.stroke, stale.stroke)

        let rect = PathObject(
            name: "矩形",
            path: PathBuilder.rectangle(Rect2(x: 10, y: 12, width: 80, height: 40)),
            appearance: Appearance(fill: .solid(.white), stroke: StrokeStyle(paint: .solid(.black), width: 1))
        )
        model.document.insert(.path(rect))
        model.selection = [rect.id]
        assertSharedPaint(model, fill: .solid(.white), stroke: StrokeStyle(paint: .solid(.black), width: 1), name: "矩形")
        guard case .path(let drawn) = model.document.item(id: rect.id) else {
            return XCTFail("矩形")
        }
        XCTAssertEqual(drawn.appearance.fill, model.appearanceAttributes.fill)
        XCTAssertEqual(drawn.appearance.stroke, model.appearanceAttributes.stroke)
        XCTAssertNotEqual(drawn.appearance.fill, .solid(.black))
        XCTAssertNotNil(drawn.appearance.stroke)

        let stalePath = PathObject(
            name: "路径",
            path: PathBuilder.rectangle(Rect2(x: 120, y: 12, width: 40, height: 30)),
            appearance: stale
        )
        model.document.insert(.path(stalePath))
        model.selection = [stalePath.id]
        XCTAssertEqual(model.appearanceAttributes.targetName, "路径")
        XCTAssertEqual(model.appearanceAttributes.fill, stale.fill)
        XCTAssertEqual(model.appearanceAttributes.stroke, stale.stroke)
        XCTAssertEqual(model.currentFill, model.appearanceAttributes.fill)
        XCTAssertEqual(model.currentStroke, model.appearanceAttributes.stroke)

        XCTAssertTrue(model.perform("把填色和描边设置为默认"))
        assertSharedPaint(model, fill: defaults.fill, stroke: defaults.stroke, name: "路径")
        guard case .path(let reset) = model.document.item(id: stalePath.id) else {
            return XCTFail("默认")
        }
        XCTAssertEqual(reset.appearance.fill, model.appearanceAttributes.fill)
        XCTAssertEqual(reset.appearance.stroke, model.appearanceAttributes.stroke)

        XCTAssertTrue(model.perform("互换填色和描边"))
        guard case .path(let swapped) = model.document.item(id: stalePath.id) else {
            return XCTFail("互换")
        }
        XCTAssertEqual(model.appearanceAttributes.fill, .solid(.black))
        XCTAssertEqual(model.appearanceAttributes.stroke?.paint, .solid(.white))
        XCTAssertEqual(model.appearanceAttributes.stroke?.width, 1)
        XCTAssertEqual(swapped.appearance.fill, model.appearanceAttributes.fill)
        XCTAssertEqual(swapped.appearance.stroke, model.appearanceAttributes.stroke)
        XCTAssertEqual(model.currentFill, model.appearanceAttributes.fill)
        XCTAssertEqual(model.currentStroke, model.appearanceAttributes.stroke)

        model.selection = []
        XCTAssertEqual(model.appearanceAttributes.targetName, "未选择对象")
        XCTAssertEqual(model.appearanceAttributes.fill, .solid(.black))
        XCTAssertEqual(model.appearanceAttributes.stroke?.paint, .solid(.white))
        XCTAssertEqual(model.currentFill, model.appearanceAttributes.fill)
        XCTAssertEqual(model.currentStroke, model.appearanceAttributes.stroke)

        model.tool = .rectangle
        model.pointerDown(at: Vec2(200, 40), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(260, 90), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(260, 90), shift: false, option: false, command: false)
        guard let freshID = model.selection.first, case .path(let fresh) = model.document.item(id: freshID) else {
            return XCTFail("新矩形")
        }
        XCTAssertEqual(fresh.name, "矩形")
        XCTAssertEqual(fresh.appearance.fill, model.appearanceAttributes.fill)
        XCTAssertEqual(fresh.appearance.stroke, model.appearanceAttributes.stroke)
        XCTAssertEqual(fresh.appearance.fill, .solid(.black))
        XCTAssertEqual(fresh.appearance.stroke?.paint, .solid(.white))
        XCTAssertEqual(model.currentFill, model.appearanceAttributes.fill)
        XCTAssertEqual(model.currentStroke, model.appearanceAttributes.stroke)
    }

    private func assertSharedPaint(_ model: EditorModel, fill: Paint?, stroke: StrokeStyle?, name: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = model.appearanceAttributes
        XCTAssertEqual(shown.targetName, name, file: file, line: line)
        XCTAssertEqual(shown.fill, fill, file: file, line: line)
        XCTAssertEqual(shown.stroke, stroke, file: file, line: line)
        XCTAssertEqual(model.currentFill, shown.fill, file: file, line: line)
        XCTAssertEqual(model.currentStroke, shown.stroke, file: file, line: line)
        guard let id = model.selection.first, let appearance = model.document.item(id: id)?.paintAppearance else { return }
        XCTAssertEqual(appearance.fill, shown.fill, file: file, line: line)
        XCTAssertEqual(appearance.stroke, shown.stroke, file: file, line: line)
    }

    func testBrushDragPreviewsInkWhileRectangleStaysGeometric() {
        let model = EditorModel()
        model.tool = .brush
        model.pointerDown(at: Vec2(10, 40), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(160, 70), shift: false, option: false, command: false)
        XCTAssertEqual(model.livePaths.count, 1)
        XCTAssertFalse(model.livePaths[0].closed)
        XCTAssertGreaterThanOrEqual(model.livePaths[0].nodes.count, 2)
        XCTAssertFalse(model.liveInk.isEmpty)
        guard case .path(let ink) = model.liveInk[0] else {
            return XCTFail("brush preview is a filled path")
        }
        XCTAssertTrue(ink.path.closed)
        XCTAssertNil(ink.appearance.stroke)
        XCTAssertEqual(ink.appearance.fill, .solid(.black))
        XCTAssertGreaterThan(ink.path.nodes.count, model.livePaths[0].nodes.count + 4)
        let spine = Bezier.bounds(model.livePaths[0])
        let ribbon = ItemGeometry.bounds(model.liveInk[0])
        let growth = (ribbon.width - spine.width) + (ribbon.height - spine.height)
        XCTAssertGreaterThan(growth, 2, "ink is thicker than the centerline, growth \(growth)")
        let length = polylineLength(model.livePaths[0].nodes)
        let area = polygonArea(ink.path.nodes.map(\.anchor))
        XCTAssertGreaterThan(length, 1)
        XCTAssertGreaterThan(area / length, 7, "default brush ribbon is about 8 pt, area/length \(area / length)")
        guard case .calligraphic(let nib) = model.brush else {
            return XCTFail("default brush is calligraphic")
        }
        XCTAssertGreaterThanOrEqual(nib.diameter.minimum, 8)
        XCTAssertGreaterThanOrEqual(nib.roundness.minimum, 0.95)
        model.pointerDrag(to: Vec2(200, 90), shift: false, option: false, command: false)
        XCTAssertFalse(model.liveInk.isEmpty, "ink stays up through the middle of the drag")
        model.pointerUp(at: Vec2(200, 90), shift: false, option: false, command: false)
        XCTAssertTrue(model.liveInk.isEmpty)
        guard case .path(let painted) = model.document.layers.flatMap(\.items).last else {
            return XCTFail("committed brush")
        }
        guard case .calligraphic(let committed) = painted.appearance.stroke?.brush else {
            return XCTFail("committed stroke keeps the brush")
        }
        XCTAssertGreaterThanOrEqual(committed.diameter.minimum, 8)
        XCTAssertGreaterThanOrEqual(committed.roundness.minimum, 0.95)
        XCTAssertGreaterThanOrEqual(painted.appearance.stroke?.width ?? 0, 8)
        XCTAssertNil(painted.appearance.fill)
        XCTAssertTrue(model.livePaths.isEmpty)

        model.tool = .rectangle
        model.pointerDown(at: Vec2(12, 18), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(90, 60), shift: false, option: false, command: false)
        XCTAssertTrue(model.liveInk.isEmpty)
        XCTAssertEqual(model.livePaths.count, 1)
        XCTAssertTrue(model.livePaths[0].closed)
        XCTAssertEqual(model.livePaths[0].nodes.count, 4)
        model.pointerUp(at: Vec2(90, 60), shift: false, option: false, command: false)
        XCTAssertTrue(model.livePaths.isEmpty)
        XCTAssertTrue(model.liveInk.isEmpty)
    }

    func testToolbarContentInsetsAreEightAndMatched() {
        XCTAssertEqual(ToolbarChrome.contentInset, 8)
        XCTAssertEqual(ToolbarChrome.insetTolerance, 1)
        for width in [70.0, 77.0, 81.0, 90.0] {
            let insets = ToolbarChrome.insets(stripWidth: width)
            XCTAssertEqual(insets.left, 8, accuracy: 0.001)
            XCTAssertEqual(insets.right, 8, accuracy: 0.001)
            XCTAssertLessThanOrEqual(abs(insets.left - insets.right), ToolbarChrome.insetTolerance)
            XCTAssertEqual(ToolbarChrome.placedX(ToolbarChrome.tracedContentMinX, stripWidth: width), 8, accuracy: 0.001)
            XCTAssertEqual(width - ToolbarChrome.placedX(ToolbarChrome.tracedContentMaxX, stripWidth: width), 8, accuracy: 0.001)
        }
    }

    func testSelectedWellIs22AndCenteredInTheSlot() {
        let slot = DockFrame(x: 10, y: 4, width: 30, height: 24)
        let well = ToolbarChrome.selectedWell(slot: slot)
        XCTAssertEqual(well.width, 22, accuracy: 0.001)
        XCTAssertEqual(well.x + well.width / 2, slot.x + slot.width / 2, accuracy: 0.001)
        XCTAssertEqual(well.y, slot.y, accuracy: 0.001)
        XCTAssertEqual(well.height, slot.height, accuracy: 0.001)
    }

    func testGripHitIsAtLeast22PointsTallAndFullWidth() {
        let hit = ToolbarChrome.gripHitRect(stripWidth: 81, gripCenterY: 67.5)
        XCTAssertGreaterThanOrEqual(hit.height, 22)
        XCTAssertEqual(hit.height, ToolbarChrome.gripHitHeight, accuracy: 0.001)
        XCTAssertEqual(hit.x, 0, accuracy: 0.001)
        XCTAssertEqual(hit.width, 81, accuracy: 0.001)
        XCTAssertEqual(hit.y, 56.5, accuracy: 0.001)
        XCTAssertEqual(ToolbarChrome.gripVisualHeight, 11, accuracy: 0.001)
        XCTAssertEqual(ToolbarChrome.undockTravel, 12, accuracy: 0.001)
    }

    func testToolbarCollapseRowSitsOnTheTopEdge() {
        let collapse = ToolbarChrome.collapseRow
        XCTAssertLessThanOrEqual(collapse.minY, 2, "no dead band above <<")
        XCTAssertGreaterThanOrEqual(collapse.height, 16)
        XCTAssertLessThanOrEqual(collapse.height, 20)
        XCTAssertEqual(ToolbarChrome.contentOffsetY, -ToolbarChrome.tracedCollapseTop, accuracy: 0.001)

        let grip = ToolbarChrome.gripVisualFrame
        XCTAssertGreaterThanOrEqual(grip.height, 10)
        XCTAssertLessThanOrEqual(grip.height, 12)
        XCTAssertGreaterThanOrEqual(grip.minY, collapse.maxY - 0.001)

        let hit = ToolbarChrome.gripHitRect(stripWidth: ToolbarChrome.stripWidth, gripCenterY: ToolbarChrome.gripCenterY)
        XCTAssertGreaterThanOrEqual(hit.height, 22)
        XCTAssertEqual(hit.x, 0, accuracy: 0.001)
        XCTAssertEqual(hit.width, ToolbarChrome.stripWidth, accuracy: 0.001)
        let selectionTop = ToolbarChrome.viewY(ToolbarChrome.tracedSelectionMinY)
        XCTAssertGreaterThan(selectionTop, grip.maxY)
        XCTAssertLessThan(hit.maxY, selectionTop, "tool icons are outside the undock hit")
        XCTAssertEqual(ToolbarChrome.gripCenterY, 23.5, accuracy: 0.001)
    }

    func testGripStaysDockedUnderTwelveAndUndocksAtTwelve() {
        var drag = ToolbarGripDrag(start: .zero, docked: true)
        XCTAssertFalse(drag.step(pointer: Vec2(11.9, 0)))
        XCTAssertFalse(drag.floating)
        XCTAssertTrue(drag.step(pointer: Vec2(12, 0)))
        XCTAssertTrue(drag.floating)

        var diagonal = ToolbarGripDrag(start: .zero, docked: true)
        XCTAssertFalse(diagonal.step(pointer: Vec2(8, 8)))
        XCTAssertTrue(diagonal.step(pointer: Vec2(9, 9)))

        var floating = ToolbarGripDrag(start: Vec2(3, 3), docked: false)
        XCTAssertTrue(floating.step(pointer: Vec2(3, 3)))
    }

    func testToolbarRedockUsesEightPointEdges() {
        let hostMaxX = 1000.0
        XCTAssertEqual(ToolbarSnap.edge(panelMinX: 8, panelMaxX: 89, hostMinX: 0, hostMaxX: hostMaxX), .left)
        XCTAssertEqual(ToolbarSnap.edge(panelMinX: 9, panelMaxX: 90, hostMinX: 0, hostMaxX: hostMaxX), .none)
        XCTAssertEqual(ToolbarSnap.edge(panelMinX: hostMaxX - 8 - 81, panelMaxX: hostMaxX - 8, hostMinX: 0, hostMaxX: hostMaxX), .right)
        XCTAssertEqual(ToolbarSnap.edge(panelMinX: hostMaxX - 9 - 81, panelMaxX: hostMaxX - 9, hostMinX: 0, hostMaxX: hostMaxX), .none)
        XCTAssertEqual(DockSnap.guideThickness, 2, accuracy: 0.001)
    }

    func testPanelTitleAndBottomGripBothDrag() {
        let width = 302.0
        let height = 243.0
        XCTAssertEqual(PanelChromeHit.region(x: 40, y: 8, width: width, height: height, titleHeight: 22), .move)
        XCTAssertEqual(PanelChromeHit.region(x: width / 2, y: height - 4, width: width, height: height, titleHeight: 22), .move)
        XCTAssertEqual(PanelChromeHit.region(x: 10, y: height - 4, width: width, height: height, titleHeight: 22), .resize)
        XCTAssertEqual(PanelChromeHit.region(x: width / 2, y: height / 2, width: width, height: height, titleHeight: 22), .content)
    }

    func testAppearanceAndAlignReleaseIntoTheLeftEdge() {
        let host = DockFrame(x: 0, y: 0, width: 952, height: 800)
        let shoulder = DockFrame(x: 640, y: 0, width: 312, height: 800)
        let appearance = DockFrame(x: 19, y: 520, width: 302, height: 243)
        let near = DockFrame(x: 6, y: appearance.y, width: appearance.width, height: appearance.height)
        var drag = DockGesture(floating: appearance)
        let hold = drag.step(
            proposed: near, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(near.x + 40, near.y + 10),
            dragStartMaxX: appearance.maxX, up: false
        )
        XCTAssertTrue(drag.leftArmed)
        XCTAssertFalse(drag.shoulderArmed)
        XCTAssertEqual(hold.anchor, .left)
        XCTAssertTrue(hold.docked)
        XCTAssertEqual(hold.frame.x, 0, accuracy: 0.001)
        XCTAssertEqual(hold.frame.width, appearance.width, accuracy: 0.001)
        XCTAssertEqual(host.minX - hold.frame.minX, 0, accuracy: 0.001)
        XCTAssertTrue(hold.guides.contains { guide in
            if case .vertical(let x) = guide.axis { return abs(x - host.minX) < 0.001 }
            return false
        })
        let released = drag.step(
            proposed: near, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(near.x + 40, near.y + 10),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertEqual(released.anchor, .left)
        XCTAssertTrue(released.docked)
        XCTAssertTrue(released.guides.isEmpty)
        XCTAssertEqual(released.frame.x, 0, accuracy: 0.001)
        XCTAssertEqual(released.frame.width, appearance.width, accuracy: 0.001)

        let outside = DockFrame(x: 9, y: appearance.y, width: appearance.width, height: appearance.height)
        var miss = DockGesture(floating: appearance)
        let free = miss.step(
            proposed: outside, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(outside.x + 20, outside.y + 8),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertEqual(free.anchor, .none)
        XCTAssertFalse(free.docked)
        XCTAssertEqual(free.frame.x, 9, accuracy: 0.001)

        let align = DockFrame(x: 4, y: 500, width: 313, height: 283)
        var stacked = DockGesture(floating: align)
        let joined = stacked.step(
            proposed: align, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(align.x + 30, align.y + 12),
            dragStartMaxX: align.maxX,
            leftOccupied: [released.frame],
            up: true
        )
        XCTAssertEqual(joined.anchor, .left)
        XCTAssertEqual(joined.frame.x, 0, accuracy: 0.001)
        XCTAssertEqual(joined.frame.width, align.width, accuracy: 0.001)
        XCTAssertLessThan(joined.frame.maxY, released.frame.minY + 0.001)

        var flicker = DockGesture(floating: appearance)
        _ = flicker.step(
            proposed: near, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(near.x + 12, near.y + 8),
            dragStartMaxX: appearance.maxX, up: false
        )
        let almost = DockFrame(x: 14, y: appearance.y, width: appearance.width, height: appearance.height)
        let flickUp = flicker.step(
            proposed: almost, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(almost.x + 16, almost.y + 8),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertEqual(flickUp.anchor, .left)
        XCTAssertEqual(flickUp.frame.x, 0, accuracy: 0.001)

        var jumped = DockGesture(floating: appearance)
        _ = jumped.step(
            proposed: near, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(near.x + 12, near.y + 8),
            dragStartMaxX: appearance.maxX, up: false
        )
        let far = DockFrame(x: 20, y: appearance.y, width: appearance.width, height: appearance.height)
        let cleared = jumped.step(
            proposed: far, others: [], host: host, shoulder: shoulder,
            pointer: Vec2(far.x + 16, far.y + 8),
            dragStartMaxX: appearance.maxX, up: true
        )
        XCTAssertEqual(cleared.anchor, .none)
        XCTAssertFalse(cleared.docked)
        XCTAssertEqual(cleared.frame.x, 20, accuracy: 0.001)
    }

    func testTitlebarDoubleClickZoomsAndSingleClickDoesNot() {
        XCTAssertTrue(TitlebarZoom.shouldZoom(clickCount: 2, inTitleChrome: true, onInteractiveControl: false))
        XCTAssertFalse(TitlebarZoom.shouldZoom(clickCount: 1, inTitleChrome: true, onInteractiveControl: false))
        XCTAssertFalse(TitlebarZoom.shouldZoom(clickCount: 2, inTitleChrome: true, onInteractiveControl: true))
        XCTAssertFalse(TitlebarZoom.shouldZoom(clickCount: 2, inTitleChrome: false, onInteractiveControl: false))
    }

    func testClosedPenPathStaysEditable() {
        let model = EditorModel()
        model.smartGuides = false
        model.tool = .pen
        for point in [Vec2(0, 0), Vec2(40, 0), Vec2(20, 30), Vec2(0, 0)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        let items = model.document.flatItems()
        XCTAssertEqual(items.count, 1)
        guard case .path(let closed) = items[0] else { return XCTFail("闭合后应是普通路径") }
        XCTAssertTrue(closed.path.closed)
        XCTAssertFalse(closed.locked)
        XCTAssertEqual(closed.name, "路径")
        XCTAssertEqual(model.selection, [closed.id])
        XCTAssertFalse(items.contains {
            if case .compound = $0 { return true }
            return false
        })

        model.tool = .directSelection
        let before = closed.path.nodes[1].anchor
        model.pointerDown(at: before, shift: false, option: false, command: false)
        let dragged = Vec2(before.x + 15, before.y - 10)
        model.pointerDrag(to: dragged, shift: false, option: false, command: false)
        model.pointerUp(at: dragged, shift: false, option: false, command: false)
        guard case .path(let edited) = model.document.item(id: closed.id) else { return XCTFail("锚点") }
        XCTAssertEqual(edited.path.nodes[1].anchor.x, before.x + 15, accuracy: 0.01)
        XCTAssertEqual(edited.path.nodes[1].anchor.y, before.y - 10, accuracy: 0.01)
        XCTAssertTrue(edited.path.closed)
        XCTAssertFalse(edited.locked)

        model.tool = .selection
        guard let box = model.selectionBounds() else { return XCTFail("定界框") }
        let se = Vec2(box.maxX, box.maxY)
        XCTAssertEqual(model.hitHandle(at: se), .se)
        let widthBefore = box.width
        model.pointerDown(at: se, shift: false, option: false, command: false)
        let scaledTo = Vec2(se.x + 20, se.y + 20)
        model.pointerDrag(to: scaledTo, shift: false, option: false, command: false)
        model.pointerUp(at: scaledTo, shift: false, option: false, command: false)
        guard let scaled = model.selectionBounds() else { return XCTFail("缩放") }
        XCTAssertGreaterThan(scaled.width, widthBefore + 5)
        guard case .path(let still) = model.document.item(id: closed.id) else { return XCTFail("仍是路径") }
        XCTAssertTrue(still.path.closed)
        XCTAssertFalse(still.locked)
    }

    /// A click a few points off the first anchor must close. On main, smart guides
    /// snap that click onto a nearby guide and the path stays open, while the
    /// magenta 「锚点」 affordance is already showing.
    func testPenClosesWhenClickIsNearTheFirstAnchor() {
        let model = EditorModel()
        model.tool = .pen
        XCTAssertTrue(model.smartGuides)
        model.document.guides.append(Guide(axis: .vertical, position: 109))
        for point in [Vec2(100, 100), Vec2(160, 100), Vec2(130, 40)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        let near = Vec2(104, 100)
        model.pointerMove(to: near)
        XCTAssertEqual(model.penHoverCursor, .close)
        XCTAssertTrue(model.penAnchorLabel)
        model.pointerDown(at: near, shift: false, option: false, command: false)
        model.pointerUp(at: near, shift: false, option: false, command: false)

        XCTAssertTrue(model.penNodes.isEmpty, "close ends the pen session")
        let items = model.document.flatItems()
        XCTAssertEqual(items.count, 1)
        guard case .path(let closed) = items[0] else { return XCTFail("闭合后应是普通路径") }
        XCTAssertTrue(closed.path.closed)
        XCTAssertEqual(closed.path.nodes.count, 3)
        XCTAssertEqual(closed.path.nodes[0].anchor.x, 100, accuracy: 0.01)
        XCTAssertEqual(closed.path.nodes[0].anchor.y, 100, accuracy: 0.01)
        XCTAssertFalse(items.contains { if case .compound = $0 { return true }; return false })

        model.pointerMove(to: Vec2(400, 400))
        XCTAssertEqual(model.penHoverCursor, .pen)
        XCTAssertTrue(model.penNewPathMark)
    }

    func testPenClosesATwoAnchorPathInsideSixPoints() {
        let model = EditorModel()
        model.smartGuides = false
        model.tool = .pen
        model.pointerDown(at: .zero, shift: false, option: false, command: false)
        model.pointerUp(at: .zero, shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(40, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(40, 0), shift: false, option: false, command: false)
        let near = Vec2(5, 0)
        XCTAssertEqual(ToolBehaviors.penCloseSlop, 6, accuracy: 0.001)
        model.pointerMove(to: near)
        XCTAssertEqual(model.penHoverCursor, .close)
        XCTAssertTrue(model.penAnchorLabel)
        model.pointerDown(at: near, shift: false, option: false, command: false)
        model.pointerUp(at: near, shift: false, option: false, command: false)
        XCTAssertTrue(model.penNodes.isEmpty)
        guard case .path(let closed) = model.document.flatItems().last else { return XCTFail("闭合") }
        XCTAssertTrue(closed.path.closed)
        XCTAssertEqual(closed.path.nodes.count, 2)

        let outside = EditorModel()
        outside.smartGuides = false
        outside.tool = .pen
        for point in [Vec2.zero, Vec2(40, 0), Vec2(20, 30)] {
            outside.pointerDown(at: point, shift: false, option: false, command: false)
            outside.pointerUp(at: point, shift: false, option: false, command: false)
        }
        outside.pointerMove(to: Vec2(7, 0))
        XCTAssertEqual(outside.penHoverCursor, .pen)
        XCTAssertFalse(outside.penAnchorLabel)
        outside.pointerDown(at: Vec2(7, 0), shift: false, option: false, command: false)
        outside.pointerUp(at: Vec2(7, 0), shift: false, option: false, command: false)
        XCTAssertEqual(outside.penNodes.count, 4)
        XCTAssertTrue(outside.document.flatItems().isEmpty)
    }

    func testPenCloseDragPullsTheFirstHandlesThenCloses() {
        let model = EditorModel()
        model.smartGuides = false
        model.tool = .pen
        for point in [Vec2.zero, Vec2(40, 0), Vec2(20, 30)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        model.pointerDown(at: Vec2(1, 0), shift: false, option: false, command: false)
        model.pointerDrag(to: Vec2(24, 0), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(24, 0), shift: false, option: false, command: false)
        XCTAssertTrue(model.penNodes.isEmpty)
        guard case .path(let closed) = model.document.flatItems().last else { return XCTFail("闭合") }
        XCTAssertTrue(closed.path.closed)
        XCTAssertEqual(closed.path.nodes.count, 3)
        guard let handle = closed.path.nodes[0].outHandle else { return XCTFail("首点手柄") }
        XCTAssertEqual(handle.x, 24, accuracy: 0.01)
        XCTAssertEqual(handle.y, 0, accuracy: 0.01)
        XCTAssertFalse(model.document.flatItems().contains { if case .compound = $0 { return true }; return false })
    }

    private func polylineLength(_ nodes: [PathNode]) -> Double {
        guard nodes.count >= 2 else { return 0 }
        var length = 0.0
        for index in 1..<nodes.count {
            length += nodes[index].anchor.distance(to: nodes[index - 1].anchor)
        }
        return length
    }

    private func polygonArea(_ points: [Vec2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) * 0.5
    }

    private func opaque(_ bytes: [UInt8], x: Range<Int>, y: Range<Int>) -> Int {
        var count = 0
        for yy in y {
            for xx in x where pixel(bytes, xx, yy).a > 16 {
                count += 1
            }
        }
        return count
    }
}
