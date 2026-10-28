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
        XCTAssertEqual(PenCursorBitmap.tipX, 3.5, accuracy: 1e-9)
        XCTAssertEqual(PenCursorBitmap.tipY, 5.5, accuracy: 1e-9)
        XCTAssertEqual(PenHotSpot.x, 3)
        XCTAssertEqual(PenHotSpot.y, 5)
        XCTAssertFalse(PenHotSpot.isCenter)
        XCTAssertEqual(PenHotSpot.cursorX, 3.5, accuracy: 1e-9)
        XCTAssertEqual(PenHotSpot.cursorY, 26.5, accuracy: 1e-9)
        XCTAssertEqual(PenHotSpot.tipError, 0, accuracy: 1e-9)
        let backX = PenHotSpot.cursorX
        let backY = Double(PenHotSpot.height) - PenHotSpot.cursorY
        XCTAssertEqual(backX, PenCursorBitmap.tipX, accuracy: 1e-9)
        XCTAssertEqual(backY, PenCursorBitmap.tipY, accuracy: 1e-9)
        XCTAssertNotEqual(PenHotSpot.x, PenHotSpot.width / 2)
        XCTAssertNotEqual(PenHotSpot.y, PenHotSpot.height / 2)
    }

    func testPenBitmapIsBlackNibWithWhiteTipAndNewPathMark() {
        let plain = PenCursorBitmap.rgba(state: .pen, newPath: false)
        let starred = PenCursorBitmap.rgba(state: .pen, newPath: true)
        let caret = PenCursorBitmap.rgba(state: .convert, newPath: false)
        XCTAssertEqual(plain.count, 32 * 32 * 4)
        XCTAssertEqual(PenCursorBitmap.rgba(state: .pen, newPath: false, scale: 2).count, 64 * 64 * 4)

        let tip = pixel(plain, 3, 5)
        XCTAssertGreaterThan(tip.a, 200, cursorGrid(plain))
        XCTAssertGreaterThan(tip.r, 200)
        XCTAssertEqual(foremost(plain).map { $0.x + $0.y }, 3 + 5, cursorGrid(plain))
        XCTAssertEqual(foremost(plain)?.x, 3)
        XCTAssertEqual(foremost(plain)?.y, 5)
        XCTAssertLessThan(pixel(plain, 2, 4).a, 16, cursorGrid(plain))
        XCTAssertEqual(foremost(caret)?.x, PenHotSpot.x, cursorGrid(caret))
        XCTAssertEqual(foremost(caret)?.y, PenHotSpot.y, cursorGrid(caret))

        let body = blackCentroid(plain)
        let sample = pixel(plain, body.x, body.y)
        XCTAssertGreaterThan(sample.a, 200, cursorGrid(plain))
        XCTAssertLessThan(sample.r, 48, "body should be black, got \(sample) at \(body)")
        let spread = outlineSpread(plain)
        XCTAssertGreaterThan(spread.white, spread.black, "white outline \(spread.white) should sit outside black \(spread.black)\n\(cursorGrid(plain))")

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

    private func blackCentroid(_ bytes: [UInt8]) -> (x: Int, y: Int) {
        var sx = 0
        var sy = 0
        var count = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let sample = pixel(bytes, x, y)
                if sample.a > 200, sample.r < 48 {
                    sx += x
                    sy += y
                    count += 1
                }
            }
        }
        guard count > 0 else { return (0, 0) }
        return (sx / count, sy / count)
    }

    private func outlineSpread(_ bytes: [UInt8]) -> (black: Double, white: Double) {
        var bx: [Double] = []
        var by: [Double] = []
        var wx: [Double] = []
        var wy: [Double] = []
        for y in 0..<32 {
            for x in 0..<32 {
                let sample = pixel(bytes, x, y)
                if sample.a > 200, sample.r < 48 {
                    bx.append(Double(x))
                    by.append(Double(y))
                }
            }
        }
        let cx = bx.reduce(0, +) / Double(max(bx.count, 1))
        let cy = by.reduce(0, +) / Double(max(by.count, 1))
        for y in 0..<32 {
            for x in 0..<32 {
                let sample = pixel(bytes, x, y)
                guard sample.a > 200, sample.r > 200 else { continue }
                let clear = neighborClear(bytes, x, y)
                if clear {
                    wx.append(Double(x))
                    wy.append(Double(y))
                }
            }
        }
        func mean(_ xs: [Double], _ ys: [Double]) -> Double {
            guard !xs.isEmpty else { return 0 }
            return zip(xs, ys).reduce(0.0) { partial, point in
                let dx = point.0 - cx
                let dy = point.1 - cy
                return partial + (dx * dx + dy * dy).squareRoot()
            } / Double(xs.count)
        }
        return (mean(bx, by), mean(wx, wy))
    }

    private func neighborClear(_ bytes: [UInt8], _ x: Int, _ y: Int) -> Bool {
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let nx = x + dx
            let ny = y + dy
            if nx < 0 || ny < 0 || nx >= 32 || ny >= 32 { return true }
            if pixel(bytes, nx, ny).a < 16 { return true }
        }
        return false
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
}
