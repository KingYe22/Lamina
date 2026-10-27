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
        XCTAssertEqual(PenHotSpot.x, 0)
        XCTAssertEqual(PenHotSpot.y, 25)
        XCTAssertFalse(PenHotSpot.isCenter)
        XCTAssertEqual(PenHotSpot.cursorX, 0, accuracy: 0.001)
        XCTAssertEqual(PenHotSpot.cursorY, 7, accuracy: 0.001)
        XCTAssertNotEqual(PenHotSpot.cursorX, 16)
        XCTAssertNotEqual(PenHotSpot.cursorY, 16)
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
