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

    /// The drag path FloatPanel.trackDrag and the toolbar grip both call.
    /// Numbers are the 2026-11-09 Illustrator capture (y down).
    func testMeasuredDockFollowsThePointerUntilRelease() {
        let scene = illustratorScene(toolbar: true)
        let floating = DockFrame(x: -900, y: 200, width: 487, height: 167)
        var drag = PanelDragPath(
            wasDocked: false,
            origin: floating,
            startPointer: Vec2(-800, 420),
            floatingWidth: floating.width,
            floatingHeight: floating.height
        )
        let outside = drag.step(pointer: Vec2(-500, 420), scene: scene, up: false)
        XCTAssertTrue(outside.following)
        XCTAssertEqual(outside.chrome, .none)
        XCTAssertFalse(outside.ghost)
        XCTAssertEqual(outside.frame.width, 487, accuracy: 0.001)
        XCTAssertEqual(outside.target, .stay)

        let properties = scene.columns[0].frame
        for x in [-410.0, -405, -400, -395, -390, -386, -384] {
            let hit = drag.step(pointer: Vec2(x, 420), scene: scene, up: false)
            guard case .bar(let bar, let tint) = hit.chrome else {
                return XCTFail("pointer \(x) should light the right bar")
            }
            XCTAssertEqual(bar.maxX, properties.minX, accuracy: 0.001)
            XCTAssertEqual(bar.width, IllustratorDock.barThickness, accuracy: 0.001)
            XCTAssertEqual(bar.minY, properties.minY, accuracy: 0.001)
            XCTAssertEqual(bar.height, properties.height, accuracy: 0.001)
            XCTAssertEqual(tint?.minX ?? -9999, properties.minX - IllustratorDock.rightOuter, accuracy: 0.001)
            XCTAssertTrue(hit.ghost)
            XCTAssertEqual(hit.frame.x, floating.x + (x - (-800)), accuracy: 0.001)
            XCTAssertEqual(hit.frame.width, floating.width, accuracy: 0.001)
            XCTAssertNotEqual(hit.frame.minX, properties.minX, accuracy: 0.001)
        }
        for x in [-413.0, -415, -420, -383, -382, -380, -370, -250, -80, -66] {
            let miss = drag.step(pointer: Vec2(x, 420), scene: scene, up: false)
            XCTAssertEqual(miss.chrome, .none, "pointer \(x)")
            XCTAssertFalse(miss.ghost, "pointer \(x)")
        }

        let before = scene.columns[0].frame
        let dropped = drag.step(pointer: Vec2(-398, 430), scene: scene, up: true)
        guard case .newColumn(let beside, let place, let width, let height) = dropped.target else {
            return XCTFail("release in the hot zone inserts a column, got \(dropped.target)")
        }
        XCTAssertEqual(beside, "properties")
        XCTAssertEqual(place, .before)
        XCTAssertEqual(width, 487, accuracy: 0.001)
        XCTAssertEqual(height, 167, accuracy: 0.001)
        let inserted = IllustratorDock.insertedFrame(scene: scene, target: dropped.target)
        XCTAssertEqual(inserted?.maxX ?? 0, before.minX, accuracy: 0.001)
        XCTAssertEqual(inserted?.minY ?? 0, before.minY, accuracy: 0.001)
        XCTAssertEqual(inserted?.width ?? 0, 487, accuracy: 0.001)
        XCTAssertEqual(scene.columns[0].frame, before)
    }

    func testMeasuredGroupZonesUseThePointerAndHysteresis() {
        let scene = illustratorScene(toolbar: true)
        var drag = PanelDragPath(
            wasDocked: false,
            origin: DockFrame(x: -900, y: 200, width: 487, height: 167),
            startPointer: Vec2(-800, 420),
            floatingWidth: 487,
            floatingHeight: 167
        )
        XCTAssertEqual(drag.step(pointer: Vec2(-300, 96), scene: scene, up: false).chrome, .none)
        for y in [99.0, 102, 105, 111] {
            guard case .line = drag.step(pointer: Vec2(-300, y), scene: scene, up: false).chrome else {
                return XCTFail("y \(y) from above is the top line")
            }
        }
        guard case .outline = drag.step(pointer: Vec2(-300, 114), scene: scene, up: false).chrome else {
            return XCTFail("tab bar is an outline")
        }
        guard case .outline = drag.step(pointer: Vec2(-300, 141), scene: scene, up: false).chrome else {
            return XCTFail("tab bar plus 2 pt")
        }
        // Approached from the tab zone, y = 108 stays an outline.
        guard case .outline = drag.step(pointer: Vec2(-300, 108), scene: scene, up: false).chrome else {
            return XCTFail("hysteresis from below")
        }
        XCTAssertEqual(drag.step(pointer: Vec2(-300, 420), scene: scene, up: false).chrome, .none)
        XCTAssertEqual(drag.step(pointer: Vec2(-300, 800), scene: scene, up: false).chrome, .none)
        guard case .line = drag.step(pointer: Vec2(-300, 803), scene: scene, up: false).chrome else {
            return XCTFail("bottom band")
        }
        let below = drag.step(pointer: Vec2(-300, 836), scene: scene, up: true)
        guard case .stack(_, let above) = below.target else { return XCTFail(String(describing: below.target)) }
        XCTAssertFalse(above)

        var fromAbove = PanelDragPath(
            wasDocked: false,
            origin: DockFrame(x: -900, y: 80, width: 487, height: 167),
            startPointer: Vec2(-800, 90),
            floatingWidth: 487,
            floatingHeight: 167
        )
        _ = fromAbove.step(pointer: Vec2(-300, 99), scene: scene, up: false)
        guard case .line = fromAbove.step(pointer: Vec2(-300, 108), scene: scene, up: false).chrome else {
            return XCTFail("hysteresis from above")
        }
        let joined = fromAbove.step(pointer: Vec2(-300, 120), scene: scene, up: true)
        guard case .join = joined.target else { return XCTFail(String(describing: joined.target)) }
    }

    func testMeasuredUndockStaysPutThroughSevenAndFollowsAtFifteen() {
        let scene = illustratorScene(toolbar: true)
        let slot = scene.groups[0].frame
        var drag = PanelDragPath(
            wasDocked: true,
            origin: slot,
            startPointer: Vec2(-600, 122),
            floatingWidth: 487,
            floatingHeight: 167,
            originGroupID: "properties"
        )
        for travel in [1.4, 3.6, 7.3] {
            let step = drag.step(pointer: Vec2(-600 - travel, 122), scene: scene, up: false)
            XCTAssertFalse(step.following, "travel \(travel)")
            XCTAssertEqual(step.frame, slot)
            XCTAssertEqual(step.chrome, .none)
            XCTAssertFalse(step.ghost)
            XCTAssertEqual(step.target, .stay)
        }
        let away = drag.step(pointer: Vec2(-600 - 15.5, 122), scene: scene, up: false)
        XCTAssertTrue(away.following)
        XCTAssertFalse(away.ghost, "no indicator, so the panel stays opaque")
        XCTAssertEqual(away.frame.x, slot.x - 15.5, accuracy: 0.001)
        XCTAssertEqual(away.frame.width, 487, accuracy: 0.001)

        var back = PanelDragPath(
            wasDocked: true,
            origin: slot,
            startPointer: Vec2(-600, 122),
            floatingWidth: 487,
            floatingHeight: 167,
            originGroupID: "properties"
        )
        let overSlot = back.step(pointer: Vec2(-300, 200), scene: sceneWithVacatedSlot(), up: false)
        XCTAssertTrue(overSlot.ghost)
        guard case .outline = overSlot.chrome else { return XCTFail("re-drop outline") }
        let restored = back.step(pointer: Vec2(-300, 200), scene: sceneWithVacatedSlot(), up: true)
        guard case .restore = restored.target else { return XCTFail(String(describing: restored.target)) }

        let floated = drag.step(pointer: Vec2(-1000, 450), scene: scene, up: true)
        XCTAssertEqual(floated.target, .float)
    }

    func testMeasuredLeftZonesAndToolbarRedock() {
        let docked = illustratorScene(toolbar: true)
        var panel = PanelDragPath(
            wasDocked: false,
            origin: DockFrame(x: -1100, y: 300, width: 487, height: 167),
            startPointer: Vec2(-1100, 450),
            floatingWidth: 487,
            floatingHeight: 167
        )
        for x in [-1235.0, -1225] {
            guard case .bar(let bar, let tint) = panel.step(pointer: Vec2(x, 450), scene: docked, up: false).chrome else {
                return XCTFail("toolbar-right \(x)")
            }
            XCTAssertNil(tint)
            XCTAssertEqual(bar.minX, -1240, accuracy: 0.001)
            XCTAssertEqual(bar.width, 6, accuracy: 0.001)
        }
        XCTAssertEqual(panel.step(pointer: Vec2(-1200, 450), scene: docked, up: false).chrome, .none)
        var occupied = docked
        occupied.columns.append(DockColumnBox(
            id: "left",
            frame: DockFrame(x: -1331, y: 90, width: 40, height: 747),
            side: .left
        ))
        XCTAssertEqual(panel.step(pointer: Vec2(-1328, 450), scene: occupied, up: false).chrome, .none)
        XCTAssertEqual(panel.step(pointer: Vec2(-1242, 450), scene: docked, up: false).chrome, .none)
        XCTAssertEqual(panel.step(pointer: Vec2(-1315, 450), scene: docked, up: false).chrome, .none)
        XCTAssertEqual(panel.step(pointer: Vec2(-1334, 450), scene: docked, up: false).chrome, .none)
        for x in [-1328.0, -1322] {
            guard case .bar(let bar, _) = panel.step(pointer: Vec2(x, 450), scene: docked, up: false).chrome else {
                return XCTFail("window edge \(x)")
            }
            XCTAssertEqual(bar.minX, -1331, accuracy: 0.001)
            XCTAssertEqual(bar.width, 6, accuracy: 0.001)
        }
        let besideToolbar = panel.step(pointer: Vec2(-1225, 450), scene: docked, up: true)
        let inserted = IllustratorDock.insertedFrame(scene: docked, target: besideToolbar.target)
        XCTAssertEqual(inserted?.minX ?? 0, -1240, accuracy: 0.001)
        XCTAssertEqual(inserted?.width ?? 0, 487, accuracy: 0.001)

        let bare = illustratorScene(toolbar: false)
        var toolbar = PanelDragPath(
            wasDocked: true,
            draggingToolbar: true,
            origin: DockFrame(x: -1200, y: 90, width: 102, height: 874),
            startPointer: Vec2(-1288, 110),
            floatingWidth: 102,
            floatingHeight: 874,
            toolbarWidth: 91
        )
        for x in [-1329.0, -1312] {
            guard case .bar(let bar, _) = toolbar.step(pointer: Vec2(x, 305), scene: bare, up: false).chrome else {
                return XCTFail("bare edge \(x)")
            }
            XCTAssertEqual(bar.minX, -1331, accuracy: 0.001)
            XCTAssertEqual(bar.width, 6, accuracy: 0.001)
        }
        XCTAssertEqual(toolbar.step(pointer: Vec2(-1300, 305), scene: bare, up: false).chrome, .none)
        XCTAssertEqual(toolbar.step(pointer: Vec2(-1333, 305), scene: bare, up: false).chrome, .none)
        let redock = toolbar.step(pointer: Vec2(-1325, 305), scene: bare, up: true)
        XCTAssertEqual(redock.target, .redockToolbar(.left))
        let home = IllustratorDock.toolbarColumn(scene: bare, side: .left, width: 91)
        XCTAssertEqual(home?.minX ?? 0, -1331, accuracy: 0.001)
        XCTAssertEqual(home?.width ?? 0, 91, accuracy: 0.001)

        guard case .bar(let rightBar, _) = toolbar.step(pointer: Vec2(-400, 420), scene: bare, up: false).chrome else {
            return XCTFail("floating toolbar uses the right zone")
        }
        XCTAssertEqual(rightBar.maxX, -381, accuracy: 0.001)
        XCTAssertEqual(toolbar.step(pointer: Vec2(-415, 420), scene: bare, up: false).chrome, .none)
        XCTAssertEqual(toolbar.step(pointer: Vec2(-383, 420), scene: bare, up: false).chrome, .none)
        let parked = IllustratorDock.toolbarColumn(scene: bare, side: .right, width: 91)
        XCTAssertEqual(parked?.maxX ?? 0, -381, accuracy: 0.001)
        XCTAssertEqual(bare.columns[0].frame.minX, -381, accuracy: 0.001)
    }

    func testCollapseRestoresTheExpandedHeightAndResizeDoesNotResetFloaters() {
        XCTAssertEqual(PanelCollapse.height(collapsed: true, expanded: 243, title: 22), 22, accuracy: 0.001)
        XCTAssertEqual(PanelCollapse.height(collapsed: false, expanded: 243, title: 22), 243, accuracy: 0.001)
        XCTAssertNotEqual(PanelCollapse.height(collapsed: false, expanded: 243, title: 22), 312, accuracy: 0.001)
        XCTAssertFalse(FloatingPlacement.resetsFrames(alreadyPlaced: true))
        XCTAssertTrue(FloatingPlacement.resetsFrames(alreadyPlaced: false))
    }

    func testPenCloseHitIsSixScreenPointsAndTheViewFlagWins() {
        let zoom = 0.5188
        let anchor = Vec2(100, 80)
        let pan = Vec2(10, 20)
        let viewH = 600.0
        let anchorView = PenCloseHit.viewPoint(document: anchor, viewHeight: viewH, pan: pan, zoom: zoom)
        let nearView = Vec2(anchorView.x + 5, anchorView.y - 2)
        XCTAssertTrue(PenCloseHit.screen(pointer: nearView, anchor: anchorView))
        let nearDoc = PenCloseHit.documentPoint(viewX: nearView.x, viewY: nearView.y, viewHeight: viewH, pan: pan, zoom: zoom)
        XCTAssertLessThanOrEqual(nearDoc.distance(to: anchor) * zoom, 6.01)
        let farView = Vec2(anchorView.x + 7, anchorView.y)
        XCTAssertFalse(PenCloseHit.screen(pointer: farView, anchor: anchorView))
        let roundTrip = PenCloseHit.viewPoint(
            document: PenCloseHit.documentPoint(viewX: 180, viewY: 240, viewHeight: viewH, pan: pan, zoom: zoom),
            viewHeight: viewH, pan: pan, zoom: zoom
        )
        XCTAssertEqual(roundTrip.x, 180, accuracy: 0.001)
        XCTAssertEqual(roundTrip.y, 240, accuracy: 0.001)

        let model = EditorModel()
        model.smartGuides = true
        model.zoom = zoom
        model.tool = .pen
        model.document.guides.append(Guide(axis: .vertical, position: 400))
        for point in [anchor, Vec2(220, 80), Vec2(160, 200)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        let missed = Vec2(anchor.x + 40, anchor.y + 40)
        XCTAssertFalse(ToolBehaviors.hitsPenClose(nodes: model.penNodes, point: missed, zoom: zoom))
        model.pointerDown(at: missed, shift: false, option: false, command: false, closeHit: true)
        model.pointerDrag(to: Vec2(anchor.x + 30, anchor.y), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(anchor.x + 30, anchor.y), shift: false, option: false, command: false)
        XCTAssertTrue(model.penNodes.isEmpty)
        guard case .path(let closed) = model.document.flatItems().last else { return XCTFail("闭合") }
        XCTAssertTrue(closed.path.closed)
        XCTAssertEqual(closed.path.nodes.count, 3)
        XCTAssertNotNil(closed.path.nodes[0].outHandle)
    }

    func testDraggingOnePanelOutOfARightColumnKeepsTheOthersDocked() {
        let column = DockColumnSpec(id: "right", place: .before, width: 313)
        let members = [
            DockMember(id: "appearance", columnID: "right", order: 0, height: 243),
            DockMember(id: "pathfinder", columnID: "right", order: 1, height: 180),
            DockMember(id: "stroke", columnID: "right", order: 2, height: 442),
        ]
        let parked = arrange(members: members, columns: [column])
        XCTAssertEqual(parked.columns.map(\.id), ["right"])
        XCTAssertEqual(parked.properties.width, 312, accuracy: 0.001)
        XCTAssertEqual(parked.properties.x, 1470 - 312, accuracy: 0.001)
        XCTAssertGreaterThan(parked.properties.height, 100)
        XCTAssertEqual(parked.propertiesContent, parked.properties)
        assertSpan(parked, windowWidth: 1470, toolbar: 0)
        assertNoDockOverlap(parked)

        var dragging = members
        dragging[1].dragging = true
        let during = arrange(members: dragging, columns: [column])
        XCTAssertEqual(during.columns.map(\.id), ["right"])
        XCTAssertEqual(during.columns[0].width, 313, accuracy: 0.001)
        XCTAssertNil(during.memberFrames["pathfinder"])
        XCTAssertGreaterThan(during.memberFrames["appearance"]?.height ?? 0, 1)
        XCTAssertGreaterThan(during.memberFrames["stroke"]?.height ?? 0, 1)
        XCTAssertEqual(during.memberFrames["appearance"]?.maxY ?? 0, parked.memberFrames["appearance"]?.maxY ?? -1, accuracy: 0.001)
        // The panel under the pointer leaves the stack. The panel below it moves up.
        XCTAssertEqual(during.memberFrames["stroke"]?.maxY ?? 0, during.memberFrames["appearance"]?.y ?? -1, accuracy: 0.001)
        XCTAssertEqual(during.properties, parked.properties)
        XCTAssertEqual(during.canvas, parked.canvas)
        XCTAssertEqual(during.status, parked.status)
        assertSpan(during, windowWidth: 1470, toolbar: 0)
        assertNoDockOverlap(during)

        let released = arrange(members: members, columns: [column])
        XCTAssertEqual(released.memberFrames, parked.memberFrames)
        XCTAssertEqual(released.columns, parked.columns)
        XCTAssertEqual(released.canvas, parked.canvas)
        XCTAssertEqual(released.properties, parked.properties)
    }

    func testDockedFramesDoNotOverlapAndCanvasMatchesTheColumns() {
        let columns = [
            DockColumnSpec(id: "align", place: .before, width: 313),
            DockColumnSpec(id: "appearance", place: .before, width: 302),
        ]
        let members = [
            DockMember(id: "align", columnID: "align", order: 0, height: 283),
            DockMember(id: "appearance", columnID: "appearance", order: 0, height: 243),
        ]
        // 1470 − 302 − 313 − 312 = 543. That is the status edge in the 0.4.8 screenshot
        // once those two columns are really there, with the toolbar undocked.
        let laid = arrange(window: (1470, 1904), members: members, columns: columns)
        assertSpan(laid, windowWidth: 1470, toolbar: 0)
        XCTAssertEqual(laid.status.maxX, 543, accuracy: 0.001)
        XCTAssertEqual(laid.canvas.width, 543, accuracy: 0.001)
        XCTAssertEqual(laid.properties.x, 1470 - 312, accuracy: 0.001)
        XCTAssertEqual(laid.properties.width, 312, accuracy: 0.001)
        assertNoDockOverlap(laid)
        XCTAssertFalse(laid.properties.overlaps(laid.canvas))
        XCTAssertFalse(laid.properties.overlaps(laid.status))

        let classic = arrange(window: (1033, 970), toolbarLeft: true, members: [], columns: [])
        assertSpan(classic, windowWidth: 1033, toolbar: 81)
        XCTAssertEqual(classic.canvas, DockBox(x: 81, y: 20, width: 640, height: 805))
        XCTAssertEqual(classic.status, DockBox(x: 81, y: 0, width: 640, height: 20))
        XCTAssertEqual(classic.properties, DockBox(x: 721, y: 20, width: 312, height: 841))

        // A committed new column keeps the measured floating width. It is not invented mid-drag.
        let dropped = arrange(
            window: (1092, 970),
            toolbarLeft: true,
            members: [DockMember(id: "pathfinder", columnID: "new", order: 0, height: 167)],
            columns: [DockColumnSpec(id: "new", place: .before, width: 487)]
        )
        assertSpan(dropped, windowWidth: 1092, toolbar: 81)
        XCTAssertEqual(dropped.canvas.width, 212, accuracy: 0.001)
        XCTAssertEqual(dropped.status.maxX, 293, accuracy: 0.001)
        XCTAssertEqual(dropped.properties.x, 1092 - 312, accuracy: 0.001)
        XCTAssertEqual(dropped.properties.width, 312, accuracy: 0.001)
    }

    func testPathfinderAndStrokeDragOutAndBackRestoresTheLayout() {
        let column = DockColumnSpec(id: "right", place: .before, width: 313)
        let members = [
            DockMember(id: "pathfinder", columnID: "right", order: 0, height: 180),
            DockMember(id: "stroke", columnID: "right", order: 1, height: 442),
        ]
        let parked = arrange(members: members, columns: [column])

        var pathfinderOut = members
        pathfinderOut[0].dragging = true
        let pathfinderDragging = arrange(members: pathfinderOut, columns: [column])
        XCTAssertEqual(pathfinderDragging.columns.map(\.id), ["right"])
        XCTAssertNil(pathfinderDragging.memberFrames["pathfinder"])
        XCTAssertGreaterThan(pathfinderDragging.memberFrames["stroke"]?.height ?? 0, 1)
        XCTAssertEqual(pathfinderDragging.canvas, parked.canvas)
        XCTAssertEqual(pathfinderDragging.properties, parked.properties)
        assertNoDockOverlap(pathfinderDragging)
        let pathfinderBack = arrange(members: members, columns: [column])
        XCTAssertEqual(pathfinderBack, parked)

        var strokeOut = members
        strokeOut[1].dragging = true
        let strokeDragging = arrange(members: strokeOut, columns: [column])
        XCTAssertEqual(strokeDragging.columns.map(\.id), ["right"])
        XCTAssertNil(strokeDragging.memberFrames["stroke"])
        XCTAssertGreaterThan(strokeDragging.memberFrames["pathfinder"]?.height ?? 0, 1)
        XCTAssertEqual(strokeDragging.memberFrames["pathfinder"], parked.memberFrames["pathfinder"])
        XCTAssertEqual(strokeDragging.canvas, parked.canvas)
        let strokeBack = arrange(members: members, columns: [column])
        XCTAssertEqual(strokeBack, parked)

        // The pointer carries the floating height. Coming back uses the slot height.
        XCTAssertEqual(
            DockLayout.heightOnRelease(target: .restore(group: "pathfinder"), slotHeight: 180, carriedHeight: 167),
            180,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DockLayout.heightOnRelease(target: .restore(group: "stroke"), slotHeight: 442, carriedHeight: 167),
            442,
            accuracy: 0.001
        )
        XCTAssertEqual(
            DockLayout.heightOnRelease(target: .float, slotHeight: 442, carriedHeight: 167),
            167,
            accuracy: 0.001
        )
    }

    func testWindowResizeKeepsDockedColumnsConsistent() {
        let column = DockColumnSpec(id: "right", place: .before, width: 313)
        let members = [
            DockMember(id: "pathfinder", columnID: "right", order: 0, height: 180),
            DockMember(id: "stroke", columnID: "right", order: 1, height: 442),
        ]
        let before = arrange(window: (1200, 970), toolbarLeft: true, members: members, columns: [column])
        let after = arrange(window: (1380, 970), toolbarLeft: true, members: members, columns: [column])
        XCTAssertEqual(after.columns, before.columns)
        XCTAssertEqual(after.canvas.width, before.canvas.width + 180, accuracy: 0.001)
        XCTAssertEqual(after.status.width, after.canvas.width, accuracy: 0.001)
        XCTAssertEqual(after.properties.x, before.properties.x + 180, accuracy: 0.001)
        XCTAssertEqual(after.properties.width, before.properties.width, accuracy: 0.001)
        XCTAssertEqual(after.properties.width, 312, accuracy: 0.001)
        XCTAssertEqual(after.memberFrames["stroke"]?.x ?? 0, (before.memberFrames["stroke"]?.x ?? 0) + 180, accuracy: 0.001)
        XCTAssertEqual(after.memberFrames["stroke"]?.width ?? 0, before.memberFrames["stroke"]?.width ?? -1, accuracy: 0.001)
        XCTAssertEqual(after.memberFrames["pathfinder"]?.y ?? 0, before.memberFrames["pathfinder"]?.y ?? -1, accuracy: 0.001)
        assertSpan(before, windowWidth: 1200, toolbar: 81)
        assertSpan(after, windowWidth: 1380, toolbar: 81)
        assertNoDockOverlap(before)
        assertNoDockOverlap(after)
        XCTAssertFalse(FloatingPlacement.resetsFrames(alreadyPlaced: true))
    }

    func testColumnIsRemovedOnlyWhenItIsTrulyEmpty() {
        let column = DockColumnSpec(id: "right", place: .before, width: 313)
        let dragging = DockMember(id: "stroke", columnID: "right", order: 0, height: 442, dragging: true)
        let during = arrange(members: [dragging], columns: [column])
        XCTAssertEqual(during.columns.map(\.id), ["right"])
        XCTAssertNil(during.memberFrames["stroke"])
        XCTAssertEqual(during.propertiesContent, during.properties)

        var embedded = dragging
        embedded.dragging = false
        embedded.embedded = true
        let held = arrange(members: [embedded], columns: [column])
        XCTAssertEqual(held.columns.map(\.id), ["right"])
        XCTAssertNil(held.memberFrames["stroke"])

        var gone = dragging
        gone.dragging = false
        gone.columnID = nil
        let removed = arrange(members: [gone], columns: [column])
        XCTAssertTrue(removed.columns.isEmpty)
        XCTAssertEqual(removed.canvas.width, during.canvas.width + 313, accuracy: 0.001)
        XCTAssertEqual(removed.properties, during.properties)
        assertSpan(removed, windowWidth: 1470, toolbar: 0)

        var hidden = dragging
        hidden.dragging = false
        hidden.hidden = true
        XCTAssertTrue(arrange(members: [hidden], columns: [column]).columns.isEmpty)
    }

    func testDraggingInsidePropertiesDoesNotCollapseTheColumn() {
        let parked = arrange(members: [
            DockMember(id: "pathfinder", columnID: "properties", order: 0, height: 180),
            DockMember(id: "stroke", columnID: "properties", order: 1, height: 200),
        ], columns: [])
        var dragging = [
            DockMember(id: "pathfinder", columnID: "properties", order: 0, height: 180, dragging: true),
            DockMember(id: "stroke", columnID: "properties", order: 1, height: 200),
        ]
        let during = arrange(members: dragging, columns: [])
        XCTAssertEqual(during.properties, parked.properties)
        XCTAssertGreaterThan(during.properties.height, 100)
        XCTAssertEqual(during.propertiesContent.height, parked.properties.height - 200, accuracy: 0.001)
        XCTAssertNil(during.memberFrames["pathfinder"])
        XCTAssertGreaterThan(during.memberFrames["stroke"]?.height ?? 0, 1)
        XCTAssertEqual(during.canvas, parked.canvas)
        assertNoDockOverlap(during)

        dragging[0].dragging = false
        dragging[0].columnID = nil
        let alone = arrange(members: [dragging[0]], columns: [])
        XCTAssertEqual(alone.propertiesContent, alone.properties)
        XCTAssertEqual(alone.properties, parked.properties)
    }

    func testFloatingLayerStaysAboveDockedPanels() {
        XCTAssertGreaterThan(
            DockLayer.layer(columnID: nil, dragging: false),
            DockLayer.layer(columnID: "right", dragging: false)
        )
        XCTAssertGreaterThan(
            DockLayer.layer(columnID: "right", dragging: true),
            DockLayer.layer(columnID: "right", dragging: false)
        )
        XCTAssertEqual(DockLayer.layer(columnID: "properties", dragging: false), .docked)
        XCTAssertEqual(DockLayer.layer(columnID: "right", dragging: false), .docked)
    }

    private func arrange(
        window: (Double, Double) = (1470, 1904),
        toolbarLeft: Bool = false,
        toolbarRight: Bool = false,
        members: [DockMember],
        columns: [DockColumnSpec]
    ) -> DockLayoutResult {
        DockLayout.solve(DockLayoutInput(
            windowWidth: window.0,
            windowHeight: window.1,
            titleBand: 28,
            documentTabHeight: 28,
            statusHeight: 20,
            chromeInset: 89,
            dockLift: 36,
            toolWidth: 81,
            dockWidth: 312,
            toolbarLeft: toolbarLeft,
            toolbarRight: toolbarRight,
            columns: columns,
            members: members
        ))
    }

    private func assertSpan(
        _ result: DockLayoutResult,
        windowWidth: Double,
        toolbar: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let columns = result.columns.reduce(0) { $0 + $1.width }
        let span = DockLayout.spanWidth(windowWidth: windowWidth, toolbar: toolbar, columns: columns, dock: 312)
        XCTAssertEqual(result.canvas.width, span, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(result.status.width, span, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(result.status.x, result.canvas.x, accuracy: 0.001, file: file, line: line)
        XCTAssertGreaterThan(span, 0, file: file, line: line)
    }

    private func assertNoDockOverlap(
        _ result: DockLayoutResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frames = result.memberFrames.sorted { $0.key < $1.key }
        for (index, entry) in frames.enumerated() {
            XCTAssertFalse(entry.value.overlaps(result.canvas), "\(entry.key) covers the canvas", file: file, line: line)
            XCTAssertFalse(entry.value.overlaps(result.status), "\(entry.key) covers the status bar", file: file, line: line)
            XCTAssertFalse(entry.value.overlaps(result.propertiesContent), "\(entry.key) covers 属性", file: file, line: line)
            if entry.value.maxX <= result.properties.x + 0.05 {
                XCTAssertFalse(entry.value.overlaps(result.properties), "\(entry.key) covers the properties column", file: file, line: line)
            }
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(entry.value.overlaps(other.value), "\(entry.key) overlaps \(other.key)", file: file, line: line)
            }
        }
    }

    func testTabAndGroupPickupMatchesColumnUndock() {
        let scene = illustratorScene(toolbar: true)
        let origin = DockFrame(x: -900, y: 200, width: 313, height: 283)
        for wasDocked in [true, false] {
            var drag = PanelDragPath(
                wasDocked: wasDocked,
                origin: origin,
                startPointer: Vec2(-700, 220),
                floatingWidth: origin.width,
                floatingHeight: origin.height
            )
            let still = drag.step(pointer: Vec2(-700 - 7, 220), scene: scene, up: false)
            XCTAssertFalse(still.following, "wasDocked \(wasDocked) at 7 pt")
            XCTAssertEqual(still.frame, origin)
            XCTAssertEqual(still.target, .stay)
            let gone = drag.step(pointer: Vec2(-700 - 10.4, 220), scene: scene, up: false)
            XCTAssertTrue(gone.following, "wasDocked \(wasDocked) at 10.4 pt")
            XCTAssertEqual(gone.frame.x, origin.x - 10.4, accuracy: 0.001)
        }
    }

    func testRemainingGroupKeepsContentWidthAndClips() {
        let fit = PanelContentFit.size(tabs: ["变换", "对齐"])
        XCTAssertEqual(fit.width, PanelContentFit.alignWidth, accuracy: 0.001)
        XCTAssertEqual(fit.height, PanelContentFit.alignHeight, accuracy: 0.001)
        XCTAssertGreaterThan(fit.width, 200)
        let labelWidth = 148.0
        XCTAssertFalse(PanelContentFit.staysInside(contentMaxX: fit.width, frameWidth: labelWidth, clipsToBounds: false))
        XCTAssertTrue(PanelContentFit.staysInside(contentMaxX: fit.width, frameWidth: labelWidth, clipsToBounds: true))
        XCTAssertTrue(PanelContentFit.staysInside(contentMaxX: fit.width, frameWidth: fit.width, clipsToBounds: true))
        XCTAssertEqual(PanelContentFit.size(tabs: ["路径查找器"]).width, PanelContentFit.alignWidth, accuracy: 0.001)
        XCTAssertEqual(PanelContentFit.size(tabs: ["描边", "透明度"]).width, PanelContentFit.strokeWidth, accuracy: 0.001)
    }

    func testFloatingTabJoinsAGroupTabBarWithAnOutline() {
        var scene = illustratorScene(toolbar: true)
        let group = DockGroupBox(
            id: "align",
            frame: DockFrame(x: -700, y: 200, width: 313, height: 283),
            tabHeight: 34,
            columnID: ""
        )
        scene.groups.append(group)
        var drag = PanelDragPath(
            wasDocked: false,
            origin: DockFrame(x: -980, y: 420, width: 180, height: 140),
            startPointer: Vec2(-900, 480),
            floatingWidth: 180,
            floatingHeight: 140
        )
        let pointer = Vec2(group.frame.x + 40, group.frame.minY + 16)
        let held = drag.step(pointer: pointer, scene: scene, up: false)
        guard case .outline(let outline) = held.chrome else {
            return XCTFail("tab bar shows the group outline, got \(held.chrome)")
        }
        XCTAssertEqual(outline, group.frame)
        XCTAssertTrue(held.ghost)
        let dropped = drag.step(pointer: pointer, scene: scene, up: true)
        guard case .join(let id) = dropped.target else { return XCTFail(String(describing: dropped.target)) }
        XCTAssertEqual(id, "align")
    }

    func testBothAxesResizeKeepsTheColumnAndFloatingScreenPosition() {
        let members = [
            DockMember(id: "stroke", columnID: "right", order: 0, height: 442),
        ]
        let column = DockColumnSpec(id: "right", place: .before, width: 313)
        for size in [(1400.0, 900.0), (800.0, 900.0), (1400.0, 970.0), (1033.0, 880.0)] {
            let solved = arrange(window: size, toolbarLeft: true, members: members, columns: [column])
            XCTAssertEqual(solved.properties.width, 312, accuracy: 0.001, "\(size)")
            XCTAssertEqual(solved.properties.x, size.0 - 312, accuracy: 0.001, "\(size)")
            XCTAssertGreaterThan(solved.properties.height, 100, "\(size)")
            XCTAssertEqual(solved.columns.map(\.id), ["right"], "\(size)")
            XCTAssertGreaterThan(solved.memberFrames["stroke"]?.height ?? 0, 1, "\(size)")
        }
        let panel = DockBox(x: 120, y: 640, width: 302, height: 243)
        let window = DockBox(x: 0, y: 0, width: 1400, height: 900)
        let held = FloatingScreen.reposition(
            panelInWindow: panel,
            oldWindowOrigin: (0, 100),
            newWindowOrigin: (0, 100),
            windowBounds: window
        )
        XCTAssertEqual(held.x, panel.x, accuracy: 0.001)
        XCTAssertEqual(held.y, panel.y, accuracy: 0.001)
        XCTAssertEqual(held.height, panel.height, accuracy: 0.001)
        let slid = FloatingScreen.reposition(
            panelInWindow: DockBox(x: 200, y: 180, width: 302, height: 243),
            oldWindowOrigin: (40, 200),
            newWindowOrigin: (40, 140),
            windowBounds: DockBox(x: 0, y: 0, width: 1200, height: 1000)
        )
        XCTAssertEqual(slid.x, 200, accuracy: 0.001)
        XCTAssertEqual(slid.y, 240, accuracy: 0.001)
        let local = PropertiesChrome.localX(cropX: 652)
        XCTAssertGreaterThanOrEqual(local, 0)
        XCTAssertLessThan(local, PropertiesChrome.designDockWidth)
        let slidOff = 652.0 - (1400.0 - 312.0 - 81.0)
        XCTAssertLessThan(slidOff, 0)
        XCTAssertGreaterThan(abs(local - slidOff), 1)
        let centering = FloatingScreen.holdDecision(
            alreadySettled: false, windowVisible: true, frameFitsScreen: false, windowFrameChanged: true
        )
        XCTAssertFalse(centering.settled)
        XCTAssertFalse(centering.move, "centering a too-large window is not a user resize")
        let fitted = FloatingScreen.holdDecision(
            alreadySettled: false, windowVisible: true, frameFitsScreen: true, windowFrameChanged: true
        )
        XCTAssertTrue(fitted.settled)
        XCTAssertFalse(fitted.move, "the first frame that fits is recorded without moving panels")
        let idle = FloatingScreen.holdDecision(
            alreadySettled: true, windowVisible: true, frameFitsScreen: true, windowFrameChanged: false
        )
        XCTAssertFalse(idle.move)
        let resized = FloatingScreen.holdDecision(
            alreadySettled: true, windowVisible: true, frameFitsScreen: true, windowFrameChanged: true
        )
        XCTAssertTrue(resized.move)
    }

    func testStatusItemsDoNotOverlapWhenTheCanvasNarrows() {
        let wide = StatusBarLayout.place(barWidth: 640, hintWidth: 280, trailingWidth: 180)
        XCTAssertFalse(wide.overlaps)
        XCTAssertEqual(wide.hintWidth, 280, accuracy: 0.001)
        XCTAssertEqual(wide.trailingX, 640 - 12 - 180, accuracy: 0.001)
        let narrow = StatusBarLayout.place(barWidth: 212, hintWidth: 280, trailingWidth: 180)
        XCTAssertFalse(narrow.overlaps)
        XCTAssertLessThan(narrow.hintWidth, 280)
        XCTAssertLessThanOrEqual(narrow.hintX + narrow.hintWidth, narrow.trailingX + 0.001)
        XCTAssertGreaterThan(narrow.trailingWidth, 1)
    }

    func testPenEndsOnEscapeToolSwitchAndDeselectAndClearDeletes() {
        let model = EditorModel()
        model.smartGuides = false
        model.tool = .pen
        for point in [Vec2.zero, Vec2(40, 0)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        XCTAssertEqual(model.penNodes.count, 2)
        model.endPenFromEscape()
        XCTAssertTrue(model.penNodes.isEmpty)
        XCTAssertEqual(model.document.flatItems().count, 1)

        model.perform("取消选择")
        model.tool = .pen
        model.pointerDown(at: .zero, shift: false, option: false, command: false)
        model.pointerUp(at: .zero, shift: false, option: false, command: false)
        XCTAssertEqual(model.penNodes.count, 1)
        XCTAssertEqual(model.document.flatItems().count, 1, "an unselected endpoint starts a new path")

        model.pointerDown(at: Vec2(16, 12), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(16, 12), shift: false, option: false, command: false)
        XCTAssertEqual(model.penNodes.count, 2)
        model.tool = .selection
        XCTAssertTrue(model.penNodes.isEmpty)
        XCTAssertEqual(model.document.flatItems().count, 2)

        model.tool = .pen
        model.pointerDown(at: Vec2(80, 80), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(80, 80), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(100, 80), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(100, 80), shift: false, option: false, command: false)
        model.perform("取消选择")
        XCTAssertTrue(model.penNodes.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)

        model.perform("全选")
        XCTAssertFalse(model.selection.isEmpty)
        model.perform("清除")
        XCTAssertTrue(model.document.flatItems().isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertTrue(model.penNodes.isEmpty)
    }

    func testDockBarIsFlushAndUsesTheSampledBlue() {
        let column = DockFrame(x: -381, y: 90, width: 314, height: 747)
        let chrome = IllustratorDock.rightChrome(column: column)
        XCTAssertEqual(chrome.bar.maxX, column.minX, accuracy: 0.001)
        XCTAssertEqual(chrome.bar.width, IllustratorDock.barThickness, accuracy: 0.001)
        XCTAssertEqual(IllustratorDock.barHex, 0x2C62CB)
        let parts = IllustratorDock.barDeviceComponents()
        XCTAssertEqual(parts.r, 44.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(parts.g, 98.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(parts.b, 203.0 / 255, accuracy: 0.0001)
        XCTAssertTrue(IllustratorDock.rightHot(edge: column.minX, pointerX: -410))
        XCTAssertFalse(IllustratorDock.rightHot(edge: column.minX, pointerX: -413))
        XCTAssertTrue(IllustratorDock.rightHot(edge: column.minX, pointerX: -384))
        XCTAssertFalse(IllustratorDock.rightHot(edge: column.minX, pointerX: -383))
    }

    /// Height shrinks with the window's top fixed, so the origin rises by the
    /// same delta. 描边 on the bottom keeps its screen position. It is not
    /// pinned to the host bottom (that lift was exactly −70 and −90 pt).
    func testBottomFloaterKeepsItsScreenPositionWhenTheWindowShrinks() {
        let stroke = DockBox(x: 322, y: 20, width: 313, height: 442)
        let window900 = DockBox(x: 0, y: 0, width: 1033, height: 900)
        let by70 = FloatingScreen.reposition(
            panelInWindow: stroke,
            oldWindowOrigin: (763, 115),
            newWindowOrigin: (763, 185),
            windowBounds: window900
        )
        XCTAssertEqual(by70.y, 20 - 70, accuracy: 0.001)
        XCTAssertEqual(by70.x, stroke.x, accuracy: 0.001)
        XCTAssertEqual(by70.y + 185, stroke.y + 115, accuracy: 0.001, "screen y is unchanged")
        let by90 = FloatingScreen.reposition(
            panelInWindow: stroke,
            oldWindowOrigin: (763, 115),
            newWindowOrigin: (763, 205),
            windowBounds: DockBox(x: 0, y: 0, width: 1033, height: 880)
        )
        XCTAssertEqual(by90.y, 20 - 90, accuracy: 0.001)
        XCTAssertEqual(by90.y + 205, stroke.y + 115, accuracy: 0.001)

        let top = DockBox(x: 100, y: 542, width: 302, height: 243)
        let topHeld = FloatingScreen.reposition(
            panelInWindow: top,
            oldWindowOrigin: (763, 115),
            newWindowOrigin: (763, 185),
            windowBounds: window900
        )
        XCTAssertEqual(topHeld.y, 542 - 70, accuracy: 0.001)
        XCTAssertEqual(topHeld.x, top.x, accuracy: 0.001)

        let hanging = FloatingScreen.reposition(
            panelInWindow: DockBox(x: 10, y: -30, width: 100, height: 80),
            oldWindowOrigin: (0, 0),
            newWindowOrigin: (0, 0),
            windowBounds: DockBox(x: 0, y: 0, width: 1033, height: 700)
        )
        XCTAssertEqual(hanging.y, -30, accuracy: 0.001)
        let escaped = FloatingScreen.reposition(
            panelInWindow: DockBox(x: 10, y: 900, width: 100, height: 80),
            oldWindowOrigin: (0, 0),
            newWindowOrigin: (0, 0),
            windowBounds: DockBox(x: 0, y: 0, width: 1033, height: 700)
        )
        XCTAssertEqual(escaped.y, 700 - 80, accuracy: 0.001)
    }

    /// Toolbar-right and window-edge bars use the same device blue as the right bar.
    func testLeftDockBarsUseTheRightBarsDeviceBlue() {
        let scene = illustratorScene(toolbar: true)
        var drag = PanelDragPath(
            wasDocked: false,
            origin: DockFrame(x: -1100, y: 300, width: 487, height: 167),
            startPointer: Vec2(-1100, 450),
            floatingWidth: 487,
            floatingHeight: 167
        )
        guard case .bar(let beside, let besideTint) = drag.step(pointer: Vec2(-1235, 450), scene: scene, up: false).chrome else {
            return XCTFail("toolbar-right bar")
        }
        XCTAssertNil(besideTint)
        guard case .bar(let edge, let edgeTint) = drag.step(pointer: Vec2(-1328, 450), scene: scene, up: false).chrome else {
            return XCTFail("window-edge bar")
        }
        XCTAssertNil(edgeTint)
        guard case .bar(let right, _) = drag.step(pointer: Vec2(-400, 420), scene: scene, up: false).chrome else {
            return XCTFail("right bar")
        }
        XCTAssertEqual(beside.width, right.width, accuracy: 0.001)
        XCTAssertEqual(edge.width, right.width, accuracy: 0.001)
        XCTAssertEqual(beside.width, IllustratorDock.barThickness, accuracy: 0.001)
        let paint = DockBarPaint.device(alpha: 1)
        XCTAssertEqual(paint, DockBarPaint.device(alpha: 1))
        XCTAssertEqual(paint.red, 44.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(paint.green, 98.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(paint.blue, 203.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(paint.alpha, 1, accuracy: 1e-12)
        XCTAssertEqual(IllustratorDock.barHex, 0x2C62CB)
        XCTAssertNotEqual(IllustratorDock.barHex, 0x3D62C5)
    }

    /// 15.5 pt over the vacated slot follows opaque. 31 pt is the ghost sample.
    /// 12.4 pt is the retest point that must stay opaque. Follow still starts after 7.3.
    func testColumnUndockStaysOpaqueAtFifteenAndGhostsAtThirtyOne() {
        let scene = sceneWithVacatedSlot()
        let slot = scene.groups[0].frame
        let start = Vec2(slot.x + slot.width / 2, slot.minY + 20)
        func step(_ travel: Double) -> DockPlacement {
            var path = PanelDragPath(
                wasDocked: true,
                origin: slot,
                startPointer: start,
                floatingWidth: slot.width,
                floatingHeight: slot.height,
                originGroupID: "properties"
            )
            return path.step(pointer: Vec2(start.x - travel, start.y), scene: scene, up: false)
        }
        let early = step(12.4)
        XCTAssertTrue(early.following)
        XCTAssertFalse(early.ghost)
        guard case .outline = early.chrome else { return XCTFail("12.4 is still over the slot") }
        let solid = step(15.5)
        XCTAssertTrue(solid.following)
        XCTAssertFalse(solid.ghost)
        guard case .outline = solid.chrome else { return XCTFail("15.5 follows opaque over the slot") }
        XCTAssertEqual(solid.frame.x, slot.x - 15.5, accuracy: 0.001)
        let ghost = step(31)
        XCTAssertTrue(ghost.following)
        XCTAssertTrue(ghost.ghost)
        guard case .outline = ghost.chrome else { return XCTFail("31 ghosts over the slot") }
        XCTAssertEqual(IllustratorDock.undockGhost, 31, accuracy: 0.001)
        XCTAssertEqual(IllustratorDock.undockStationary, 7.3, accuracy: 0.001)
    }

    /// Key code 53 with an empty character string, and cancelOperation, both end an open path.
    func testEscapeEndsThePenFromKeyDownOrCancelOperation() {
        XCTAssertEqual(PenEscape.keyCode, 53)
        XCTAssertFalse(PenEscape.endsOpenPath(
            keyCode: 0,
            charactersEmpty: true,
            cancelOperation: false,
            toolIsPen: true,
            hasOpenNodes: true
        ))
        XCTAssertTrue(PenEscape.endsOpenPath(
            keyCode: PenEscape.keyCode,
            charactersEmpty: true,
            cancelOperation: false,
            toolIsPen: true,
            hasOpenNodes: true
        ))
        XCTAssertTrue(PenEscape.endsOpenPath(
            keyCode: PenEscape.keyCode,
            charactersEmpty: false,
            cancelOperation: false,
            toolIsPen: true,
            hasOpenNodes: false
        ))
        XCTAssertTrue(PenEscape.endsOpenPath(
            keyCode: 0,
            charactersEmpty: true,
            cancelOperation: true,
            toolIsPen: false,
            hasOpenNodes: true
        ))
        XCTAssertFalse(PenEscape.endsOpenPath(
            keyCode: PenEscape.keyCode,
            charactersEmpty: true,
            cancelOperation: true,
            toolIsPen: false,
            hasOpenNodes: false
        ))

        let model = EditorModel()
        model.smartGuides = false
        model.tool = .pen
        for point in [Vec2.zero, Vec2(30, 0)] {
            model.pointerDown(at: point, shift: false, option: false, command: false)
            model.pointerUp(at: point, shift: false, option: false, command: false)
        }
        XCTAssertEqual(model.penNodes.count, 2)
        XCTAssertTrue(PenEscape.endsOpenPath(
            keyCode: PenEscape.keyCode,
            charactersEmpty: true,
            cancelOperation: false,
            toolIsPen: model.tool == .pen,
            hasOpenNodes: !model.penNodes.isEmpty
        ))
        model.endPenFromEscape()
        XCTAssertTrue(model.penNodes.isEmpty)
        XCTAssertEqual(model.document.flatItems().count, 1)

        model.pointerDown(at: Vec2(8, 8), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(8, 8), shift: false, option: false, command: false)
        XCTAssertEqual(model.penNodes.count, 1)
        XCTAssertTrue(PenEscape.endsOpenPath(
            keyCode: 0,
            charactersEmpty: true,
            cancelOperation: true,
            toolIsPen: model.tool == .pen,
            hasOpenNodes: !model.penNodes.isEmpty
        ))
        model.endPenFromEscape()
        XCTAssertTrue(model.penNodes.isEmpty)
    }

    private func illustratorScene(toolbar: Bool) -> DockWorkspace {
        let host = DockFrame(x: -1331, y: 44, width: 1264, height: 793)
        let column = DockColumnBox(
            id: "properties",
            frame: DockFrame(x: -381, y: 90, width: 314, height: 747),
            side: .right
        )
        let group = DockGroupBox(
            id: "properties",
            frame: DockFrame(x: -381, y: 105, width: 314, height: 732),
            tabHeight: 34,
            columnID: "properties"
        )
        let bar: DockFrame? = toolbar ? DockFrame(x: -1331, y: 90, width: 91, height: 747) : nil
        return DockWorkspace(host: host, toolbar: bar, columns: [column], groups: [group])
    }

    private func sceneWithVacatedSlot() -> DockWorkspace {
        var scene = illustratorScene(toolbar: true)
        scene.groups[0].vacated = true
        return scene
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
