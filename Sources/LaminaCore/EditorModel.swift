import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class EditorModel {
    public var document: LaminaDocument
    public var selection: [UUID] = []
    public var selectedAnchors: Set<UUID> = []
    public var tool: Tool = .selection
    public var activeAttrIsFill = true
    public var currentFill: Paint? = .solid(.white)
    public var currentStroke: StrokeStyle? = StrokeStyle()
    public var zoom: Double = 1
    public var pan: Vec2 = .zero
    public var viewportSize = Vec2(1200, 800)
    public var outline = false
    public var gpuPreview = true
    public var overprintPreview = false
    public var pixelPreview = false
    public var showEdges = true
    public var showArtboards = true
    public var showBoundingBox = true
    public var transparencyGrid = false
    public var showRulers = false
    public var artboardRulers = false
    public var showGuides = true
    public var lockGuides = false
    public var smartGuides = true
    public var showPerspective = false
    public var showGrid = false
    public var snapGrid = false
    public var snapPoint = false
    public var screenMode = 0
    public var drawMode = 0
    public var openPanels: Set<String> = ["属性", "图层"]
    public var status = "就绪"
    public var nudge: Double = 1
    public var editingText: UUID?
    public var showHiddenCharacters = false
    public var lastEffect: LiveEffect?
    public var polygonSides = 6
    public var starPoints = 5
    public var starInner = 0.38
    public var cornerRadius: Double = 12
    public var workspace = "基本功能"
    public var toolbarAdvanced = true
    public var clipboard: [ArtItem] = []
    public var savedSelection: [UUID] = []
    public var lastSelection: [UUID] = []
    public var spiralTurns: Double = 4
    public var gridRows = 4
    public var gridColumns = 4
    public var blendSteps = 6
    public var perspectivePlane = 1
    public var chartKind: ChartKind = .column
    public var brush: BrushDefinition? = .calligraphic(angle: 0.4, roundness: 0.35)
    public var brushLibrary: [BrushPreset] = BrushLibrary.defaults
    public var widthProfile: WidthProfile = .uniform
    public var fidelity = 2.5
    public var smoothness = 0.0
    public var blobDiameter = 16.0
    public var eraserDiameter = 16.0
    public var wandTolerance = 0.0
    public var wandFill = true
    public var warpKind: WarpToolKind = .warp
    public var warpDiameter = 90.0
    public var warpIntensity = 0.7
    public var symbolKind: SymbolToolKind = .sprayer
    public var symbolDiameter = 48.0
    public var puppetPins: [Vec2] = []
    public var penCursor: PenCursor = .pen
    public var rubberBand = true
    public var showAnchors = true
    public var showHandles = true
    public var autoAddDelete = true
    public var brushEditSelection = false
    public var spaceHeld = false
    public var viewRotation = 0.0
    public var perspectiveGrid = PerspectiveGrid(board: Rect2(x: 0, y: 0, width: 800, height: 600))
    public var glyphNudge: [UUID: Vec2] = [:]
    public var arcSweep = Double.pi
    public var flareRays = 8
    public var polarDivisions = 8
    public var measure = MeasureReading(distance: 0, dx: 0, dy: 0, angle: 0)
    /// When set, parameter commands open `pendingDialog` instead of applying defaults.
    public var dialogsEnabled = false
    public var pendingDialog: DialogRequest?
    public var dialogValues: [String: String] = [:]
    public var keymap = UserKeymap()
    public var fileURL: String?
    public var savedSnapshot: Data?
    /// App shell handles file dialogs, quit, and other commands that need AppKit.
    /// Return true to consume the action.
    public var actionHandler: ((String) -> Bool)?

    public private(set) var canUndo = false
    public private(set) var canRedo = false
    public var penNodes: [PathNode] = []
    public var penClosed = false
    public var hover = Vec2.zero
    public enum InteractionHint: Equatable {
        case none
        case marquee(Rect2)
        case lasso([Vec2])
    }
    public private(set) var interactionHint: InteractionHint = .none

    private var undoStack: [Data] = []
    private var redoStack: [Data] = []
    private var drag: Drag?
    private var moveSnapshot: Data?
    private var moveOrigin = Vec2.zero
    private var createOrigin = Vec2.zero
    private var lasso: [Vec2] = []
    private let undoLimit = 40
    private var penSource: UUID?
    private var penAnchorOrigin = Vec2.zero
    private var strokeSamples: [StrokeSample] = []
    private var gestureOrigin = Vec2.zero

    private enum Drag {
        case marquee(Vec2)
        case move
        case scale(Handle, Rect2)
        case create
        case lasso
        case anchor(item: UUID, node: UUID)
        case artboard(UUID)
        case rotate(Vec2)
        case gradient
        case pen
        case distort(Handle, Rect2)
        case warp
        case reshape
        case puppet
        case width(UUID)
        case convert(item: UUID, node: UUID, handle: Bool)
        case pan
    }

    public enum Handle: String { case nw, n, ne, e, se, s, sw, w, rotate }

    public init(document: LaminaDocument = .blank()) {
        self.document = document
        self.savedSnapshot = try? JSONEncoder.lamina.encode(document)
    }

    // MARK: History

    public func beginChange() {
        if let data = try? JSONEncoder.lamina.encode(document) {
            undoStack.append(data)
            if undoStack.count > undoLimit { undoStack.removeFirst() }
            redoStack.removeAll()
            canUndo = true
            canRedo = false
        }
    }

    public func undo() {
        guard let data = undoStack.popLast(), let doc = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: data) else {
            status = "没有可还原的操作"
            return
        }
        if let current = try? JSONEncoder.lamina.encode(document) { redoStack.append(current) }
        document = doc
        selection = selection.filter { document.containsItem($0) }
        canUndo = !undoStack.isEmpty
        canRedo = true
        status = "还原"
    }

    public func redo() {
        guard let data = redoStack.popLast(), let doc = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: data) else {
            status = "没有可重做的操作"
            return
        }
        if let current = try? JSONEncoder.lamina.encode(document) { undoStack.append(current) }
        document = doc
        canRedo = !redoStack.isEmpty
        canUndo = true
        status = "重做"
    }

    // MARK: Pointer

    public func pointerDown(at p: Vec2, shift: Bool, option: Bool, command: Bool, space: Bool = false, stylus: StylusSample = .mouse, clickCount: Int = 1) {
        hover = snapped(p)
        let p = hover
        gestureOrigin = p
        if space || spaceHeld {
            moveOrigin = p
            createOrigin = pan
            drag = .pan
            status = "抓手"
            return
        }
        switch tool {
        case .selection:
            if showBoundingBox, let handle = hitHandle(at: p) {
                beginChange()
                moveSnapshot = try? JSONEncoder.lamina.encode(document)
                moveOrigin = p
                drag = .scale(handle, selectionBounds() ?? .zero)
                return
            }
            if let id = topHit(p) {
                if shift {
                    toggle(id)
                } else if !selection.contains(id) {
                    selection = [id]
                    selectedAnchors = []
                }
                beginChange()
                moveSnapshot = try? JSONEncoder.lamina.encode(document)
                moveOrigin = p
                drag = .move
            } else {
                if !shift { selection = []; selectedAnchors = [] }
                drag = .marquee(p)
                interactionHint = .marquee(Rect2(x: p.x, y: p.y, width: 0, height: 0))
            }
        case .directSelection:
            directSelection(at: p, shift: shift)
        case .groupSelection:
            groupSelect(at: p, shift: shift)
        case .magicWand:
            magicWand(at: p, subtract: option, add: shift)
        case .lasso:
            lasso = [p]
            drag = .lasso
            interactionHint = .lasso(lasso)
        case .pen:
            if command {
                directSelection(at: p, shift: shift)
                return
            }
            penDown(p, option: option, shift: shift)
        case .curvature:
            curvatureDown(p, clickCount: clickCount)
        case .addAnchor:
            addAnchor(at: p)
        case .deleteAnchor:
            deleteAnchor(at: p)
        case .convertAnchor:
            convertAnchor(at: p)
        case .text, .areaText, .verticalText, .touchType:
            beginChange()
            if tool == .touchType, let id = topHit(p) {
                selection = [id]
                glyphNudge[id, default: .zero] += Vec2(option ? -1 : 1, 0)
                status = "修饰文字"
                drag = nil
                return
            }
            let item = makeText(at: p, area: tool == .areaText || tool == .verticalText ? Rect2(x: p.x, y: p.y, width: 1, height: 1) : nil, vertical: tool == .verticalText)
            insertNew(item)
            editingText = tool == .touchType ? nil : item.id
            createOrigin = p
            drag = (tool == .areaText || tool == .verticalText) ? .create : nil
        case .pathText:
            attachPathText()
        case .line, .rectangle, .roundedRectangle, .ellipse, .polygon, .star, .flare, .artboard, .slice, .arc, .spiral, .rectGrid, .polarGrid:
            if tool == .artboard, let index = document.artboards.firstIndex(where: { $0.rect.contains(p) }) {
                document.activeArtboard = index
                moveOrigin = p
                drag = .artboard(document.artboards[index].id)
                status = document.artboards[index].name
                break
            }
            createOrigin = p
            drag = .create
        case .brush, .blobBrush, .pencil, .shaper, .eraser, .knife, .smooth, .pathEraser, .joinTool:
            if tool == .brush, brushEditSelection, extendBrush(at: p) { drag = .create; return }
            penNodes = [PathNode.corner(p)]
            strokeSamples = [sample(stylus, at: p)]
            drag = .create
        case .hand:
            moveOrigin = p
            createOrigin = pan
            drag = .move
        case .zoom:
            createOrigin = p
            drag = .marquee(p)
            interactionHint = .marquee(Rect2(x: p.x, y: p.y, width: 0, height: 0))
        case .rotate, .reflect, .scale, .shear:
            beginTransform(at: p, copy: option)
            drag = .rotate(selectionBounds()?.center ?? p)
        case .freeTransform:
            beginTransform(at: p, copy: option)
            if command, let box = selectionBounds(), let handle = hitHandle(at: p) {
                drag = .distort(handle, box)
            } else if showBoundingBox, let handle = hitHandle(at: p), let box = selectionBounds() {
                drag = .scale(handle, box)
            } else if topHit(p) != nil {
                drag = .move
            } else {
                drag = .rotate(selectionBounds()?.center ?? p)
            }
        case .gradient:
            beginChange()
            moveOrigin = p
            drag = .gradient
        case .eyedropper:
            eyedrop(at: p, style: option)
        case .scissors:
            splitAt(p)
        case .shapeBuilder:
            penNodes = [PathNode.corner(p)]
            lasso = [p]
            drag = .lasso
        case .width:
            beginWidth(at: p, option: option)
        case .blend:
            if let id = topHit(p) {
                if !selection.contains(id) { selection.append(id) }
                if selection.count >= 2 { perform("混合对象") }
                else { status = "混合：再点一个对象" }
            }
        case .symbolSprayer:
            spraySymbol(at: p)
        case .columnGraph:
            createOrigin = p
            drag = .create
        case .mesh:
            insertMesh(at: p)
        case .livePaintBucket:
            paintBucket(at: p)
        case .livePaintSelection:
            selectLivePaintFace(at: p)
        case .perspectiveGrid:
            showPerspective = true
            syncPerspective()
            moveOrigin = p
            drag = .warp
            status = "透视网格"
        case .perspectiveSelection:
            if let id = topHit(p) {
                selection = [id]
                beginChange()
                moveSnapshot = try? JSONEncoder.lamina.encode(document)
                moveOrigin = p
                drag = .move
            }
            status = "透视平面 \(perspectivePlane)"
        case .measure:
            createOrigin = p
            moveOrigin = p
            drag = .create
            status = "度量"
        case .warp:
            beginChange()
            moveSnapshot = try? JSONEncoder.lamina.encode(document)
            moveOrigin = p
            drag = .warp
        case .reshape:
            beginChange()
            moveSnapshot = try? JSONEncoder.lamina.encode(document)
            moveOrigin = p
            drag = .reshape
        case .puppet:
            beginChange()
            moveSnapshot = try? JSONEncoder.lamina.encode(document)
            moveOrigin = p
            if let index = puppetPins.indices.min(by: { puppetPins[$0].distance(to: p) < puppetPins[$1].distance(to: p) }),
               puppetPins[index].distance(to: p) < 8 / zoom {
                drag = .puppet
            } else {
                puppetPins.append(p)
                drag = puppetPins.count >= 2 ? .puppet : nil
                status = "牵线 \(puppetPins.count) 个针脚"
            }
        case .rotateView:
            moveOrigin = p
            drag = .rotate(viewportSize * 0.5)
        }
    }

    public func pointerDrag(to p: Vec2, shift: Bool, option: Bool, command: Bool, space: Bool = false, stylus: StylusSample = .mouse) {
        hover = p
        guard let drag else { return }
        switch drag {
        case .pan:
            pan = createOrigin - (p - moveOrigin)
            status = "抓手"
            return
        case .move:
            if tool == .hand {
                pan = createOrigin - (p - moveOrigin)
                return
            }
            if tool == .perspectiveSelection {
                applyPlaneMove(to: p)
            } else {
                applyMove(to: p, copy: option)
            }
        case .marquee(let origin):
            interactionHint = .marquee(Rect2(
                min: Vec2(min(origin.x, p.x), min(origin.y, p.y)),
                max: Vec2(max(origin.x, p.x), max(origin.y, p.y))
            ))
        case .scale(let handle, let original):
            applyScale(handle: handle, original: original, to: p, shift: shift, option: option)
        case .create:
            if tool == .brush || tool == .pencil || tool == .blobBrush || tool == .shaper || tool == .eraser || tool == .knife || tool == .smooth || tool == .pathEraser || tool == .joinTool {
                if penNodes.last?.anchor.distance(to: p) ?? 0 > 1.5 {
                    penNodes.append(.corner(p))
                    strokeSamples.append(sample(stylus, at: p))
                }
            }
        case .pen:
            if tool == .curvature { dragCurvature(to: p) }
            else { penDrag(to: p, shift: shift, option: option, space: space) }
        case .distort(let handle, let original):
            applyDistort(handle: handle, original: original, to: p)
        case .warp:
            if tool == .perspectiveGrid { dragVanishing(to: p) }
            else { applyWarp(to: p) }
        case .reshape:
            applyReshape(to: p)
        case .puppet:
            applyPuppet(to: p)
        case .width:
            updateWidth(to: p, option: option)
        case .convert(let item, let node, let handle):
            dragConvert(item: item, node: node, to: p, breaking: handle || option)
        case .lasso:
            lasso.append(p)
            if tool == .shapeBuilder { penNodes.append(.corner(p)) }
            interactionHint = .lasso(lasso)
        case .anchor(let item, let node):
            moveAnchor(item: item, node: node, to: p, shift: shift)
        case .artboard(let id):
            if let idx = document.artboards.firstIndex(where: { $0.id == id }) {
                let delta = p - moveOrigin
                document.artboards[idx].rect.x += delta.x
                document.artboards[idx].rect.y += delta.y
                moveOrigin = p
            }
        case .rotate(let center):
            if tool == .rotateView {
                viewRotation = ToolBehaviors.rotateAngle(center: center, from: moveOrigin, to: p, shift: shift)
                status = String(format: "旋转视图 %.0f°", viewRotation * 180 / Double.pi)
            } else {
                applyRotateLike(center: center, to: p, shift: shift, option: option)
            }
        case .gradient:
            applyGradient(from: moveOrigin, to: p, shift: shift)
        }
    }

    public func pointerUp(at p: Vec2, shift: Bool, option: Bool, command: Bool, space: Bool = false, stylus: StylusSample = .mouse) {
        hover = p
        let kind = drag
        drag = nil
        interactionHint = .none
        switch kind {
        case .marquee(let origin):
            if tool == .zoom {
                finishZoom(from: origin, to: p, out: option)
                break
            }
            let rect = Rect2(min: Vec2(min(origin.x, p.x), min(origin.y, p.y)), max: Vec2(max(origin.x, p.x), max(origin.y, p.y)))
            let hits = items(in: rect, fullyInside: false)
            // "拖动选框时按 E" selects only fully enclosed objects. `command` here stands in for that modifier when tests pass it; the view passes the E flag separately via `shift` already used. Fully-inside is requested with `option` during marquee.
            let chosen = option ? items(in: rect, fullyInside: true) : hits
            if shift {
                for id in chosen where !selection.contains(id) { selection.append(id) }
            } else if rect.width > 2 || rect.height > 2 {
                selection = chosen
            }
        case .create:
            commitCreate(to: p, shift: shift, option: option)
        case .lasso:
            if tool == .shapeBuilder {
                shapeBuild(stroke: penNodes.map(\.anchor), subtract: option)
                penNodes = []
                lasso = []
                break
            }
            let ring = lasso
            let hits = document.layers.flatMap(\.items).filter { item in
                let anchors = pathAnchors(item)
                return ToolBehaviors.lassoHits(anchors: anchors, center: ItemGeometry.bounds(item).center, ring: ring)
            }.map(\.id)
            selection = hits
            lasso = []
        case .convert(let item, let node, let handle):
            if !handle, gestureOrigin.distance(to: p) < 3 { toggleConvert(item: item, node: node) }
            status = "锚点"
        case .pan:
            status = "抓手"
        case .move, .scale, .anchor, .rotate, .gradient, .artboard, .pen, .distort, .warp, .reshape, .puppet, .width:
            status = tool == .pen ? "钢笔 \(penNodes.count) 点" : "已变换"
        case .none:
            break
        }
    }

    public func keyDown(chord: KeyChord) -> Bool {
        if let tool = toolMatching(chord), editingText == nil, chord.modifiers.subtracting(.shift).isEmpty {
            self.tool = tool
            status = tool.title
            return true
        }
        if let entry = Keymap.preferredEntry(for: chord, editingText: editingText != nil) {
            if Keymap.toolForTitle[entry.title] != nil, editingText != nil { return false }
            perform(entry.action)
            return true
        }
        if chord.modifiers.isEmpty, chord.key == .return, editingText == nil {
            requestToolOptions()
            return true
        }
        if chord.modifiers.isEmpty, case .character(let c) = chord.key, editingText != nil {
            appendText(String(c))
            return true
        }
        return false
    }

    public func toolMatching(_ chord: KeyChord) -> Tool? {
        for (title, tool) in Keymap.toolForTitle {
            if Keymap.chords(forTitle: title).contains(chord) { return tool }
        }
        return nil
    }

    // MARK: Commands

    @discardableResult
    public func perform(_ action: String) -> Bool {
        if dialogsEnabled, dialogValues.isEmpty, let request = DialogCatalog.request(for: action) {
            pendingDialog = request
            status = request.title
            return true
        }
        defer { dialogValues = [:] }
        if let actionHandler, actionHandler(action) { return true }
        switch action {
        case "工具选项": applyToolOptions()
        case "还原": undo()
        case "重做": redo()
        case "创建文档", "在不打开“新建文档”对话框的情况下创建文档":
            newDocument(size: Vec2(800, 600))
        case "从模板创建文档":
            newDocument(size: Vec2(595, 842), title: "模板-A4")
        case "退出应用程序":
            status = "退出"
        case "全选", "选择全部对象":
            selection = document.layers.flatMap { $0.items.map(\.id) }
            status = "已选择 \(selection.count) 个对象"
        case "取消选择":
            lastSelection = selection
            selection = []
            selectedAnchors = []
        case "重新选择":
            selection = lastSelection.filter { document.containsItem($0) }
        case "选择现用画板中的图稿":
            let board = document.currentArtboard.rect
            selection = document.layers.flatMap(\.items).filter { ItemGeometry.bounds($0).intersects(board) }.map(\.id)
        case "反向选择":
            let all = Set(document.layers.flatMap { $0.items.map(\.id) })
            selection = Array(all.subtracting(selection))
        case "剪切":
            copySelection(); deleteSelection(recordUndo: true)
        case "复制":
            copySelection()
        case "粘贴":
            paste(offset: Vec2(12, 12), place: .above)
        case "贴在前面":
            paste(offset: .zero, place: .above)
        case "贴在后面":
            paste(offset: .zero, place: .below)
        case "原位粘贴", "在现用画板上就地粘贴":
            paste(offset: .zero, place: .inPlace)
        case "粘贴到所有画板上":
            pasteOnAllArtboards()
        case "清除":
            deleteSelection(recordUndo: true)
        case "编组选定图稿":
            groupSelection()
        case "取消选定图稿编组":
            ungroupSelection()
        case "锁定所选对象":
            setLock(true)
        case "解锁所选对象":
            unlockAll()
        case "隐藏所选对象":
            setHidden(true)
        case "显示所有所选对象":
            unhideAll()
        case "将所选对象前移": arrange(1)
        case "将所选对象移到前面": arrange(.max)
        case "将所选对象后移": arrange(-1)
        case "将所选对象移到后面": arrange(.min)
        case "创建剪切蒙版": makeClip()
        case "释放剪切蒙版": releaseClip()
        case "创建复合路径": makeCompound()
        case "释放复合路径": releaseCompound()
        case "连接两个或更多路径": joinSelection()
        case "平均两个或更多路径": averageSelection()
        case "轮廓化描边": outlineStroke()
        case "偏移路径": offsetPaths(field("distance", 10))
        case "简化": simplifySelection(tolerance: field("tolerance", 1.5))
        case "扩展", "扩展外观", "扩展形状": expandSelection()
        case "将变换重新应用于对象": transformAgain()
        case "重置定界框": resetBounds()
        case "水平左对齐", "水平居中对齐", "水平右对齐", "垂直顶对齐", "垂直居中对齐", "垂直底对齐":
            align(action)
        case "混合对象": makeBlend()
        case "完成向混合添加对象": releaseBlend()
        case "创建轮廓": createOutlines()
        case "放大": zoom = min(64, zoom * 1.25); status = "\(Int(zoom * 100))%"
        case "缩小": zoom = max(0.02, zoom / 1.25); status = "\(Int(zoom * 100))%"
        case "放大 100%", "实际大小": zoom = 1; status = "100%"
        case "画板适合窗口大小", "适合窗口中的可成像区域": fitArtboard()
        case "在窗口中查看所有画板": fitAll()
        case "在文档的轮廓和 GPU 预览之间切换":
            outline.toggle(); status = outline ? "轮廓" : "预览"
        case "在文档的 GPU 和 CPU 预览之间切换":
            gpuPreview.toggle(); status = gpuPreview ? "GPU 预览" : "CPU 预览"
        case "在“叠印预览”模式下查看文档": overprintPreview.toggle()
        case "在“像素预览”模式下查看文档": pixelPreview.toggle()
        case "隐藏边缘": showEdges.toggle()
        case "显示/隐藏画板": showArtboards.toggle()
        case "隐藏定界框": showBoundingBox.toggle()
        case "显示透明网格": transparencyGrid.toggle()
        case "显示标尺": showRulers.toggle()
        case "显示/隐藏画板标尺": artboardRulers.toggle(); showRulers = true
        case "隐藏参考线": showGuides.toggle()
        case "锁定参考线": lockGuides.toggle()
        case "建立参考线": makeGuides()
        case "释放参考线": releaseGuides()
        case "显示/隐藏智能参考线": smartGuides.toggle()
        case "显示/隐藏透视网格", "透视网格": showPerspective.toggle()
        case "显示网格": showGrid.toggle()
        case "对齐网格": snapGrid.toggle()
        case "对齐点": snapPoint.toggle()
        case "在填色和描边之间转换":
            activeAttrIsFill.toggle(); status = activeAttrIsFill ? "填色" : "描边"
        case "把填色和描边设置为默认":
            currentFill = .solid(.white); currentStroke = StrokeStyle(); activeAttrIsFill = true
        case "互换填色和描边": swapFillStroke()
        case "选择渐变填色模式":
            currentFill = .linear(.blackWhite); activeAttrIsFill = true; applyPaintToSelection()
        case "选择颜色填充模式":
            if currentFill == nil || isGradient(currentFill) { currentFill = .solid(.black) }
            activeAttrIsFill = true; applyPaintToSelection()
        case "选择无描边/填充模式":
            if activeAttrIsFill { currentFill = nil } else { currentStroke = nil }
            applyPaintToSelection()
        case "颜色模式 RGB": document.colorMode = .rgb
        case "颜色模式 CMYK": document.colorMode = .cmyk
        case "反相颜色": mapColors { $0.inverted() }
        case "转换为灰度": mapColors { $0.grayscale() }
        case "调整饱和度": mapColors { $0.withSaturation(1.4) }
        case "新建画板": addArtboard()
        case "画板适合图稿": fitArtboardToArtwork()
        case "重新排列画板": arrangeArtboards()
        case "添加图层": addLayer(dialog: false)
        case "在打开“新建图层”对话框时添加图层": addLayer(dialog: true)
        case "路径查找器 联集": boolean(.unite)
        case "路径查找器 相减": boolean(.minusFront)
        case "路径查找器 交集": boolean(.intersect)
        case "路径查找器 差集": boolean(.exclude)
        case "将上一个路径查找器效果应用于选定对象": boolean(.unite)
        case "效果 投影": applyEffect(.dropShadow(dx: field("dx", 4), dy: field("dy", 4), blur: field("blur", 6), color: RGBA(r: 0, g: 0, b: 0, a: 0.4)))
        case "效果 内发光": applyEffect(.innerGlow(blur: field("blur", 8), color: RGBA(hex: "#FFFFFF")))
        case "效果 外发光": applyEffect(.outerGlow(blur: field("blur", 10), color: RGBA(hex: "#1473E6")))
        case "效果 圆角": applyEffect(.roundCorners(radius: field("radius", cornerRadius)))
        case "效果 羽化": applyEffect(.feather(radius: field("radius", 8)))
        case "效果 涂抹": applyEffect(.scribble)
        case "效果 凸出": extrudeSelection(depth: field("depth", 16))
        case "效果 绕转": revolveSelection(angle: field("angle", 360))
        case "效果 膨胀": inflateSelection(amount: field("amount", 12))
        case "将上一个效果应用于选定对象":
            if let lastEffect { applyEffect(lastEffect) }
        case "通过调整效果对话框中的值，将上一个效果应用于选定对象":
            status = "上一个效果"
            openPanels.insert("外观")
        case "显示隐藏字符": showHiddenCharacters.toggle()
        case "加粗": toggleText { $0.bold.toggle() }
        case "斜体": toggleText { $0.italic.toggle() }
        case "下划线": toggleText { $0.underline.toggle() }
        case "拼写检查": spellcheck()
        case "查找和替换": findReplace()
        case "调用帮助", "墨线帮助": status = "墨线帮助"
        case "关于墨线": status = "墨线 0.1"
        case "关于快捷键来源": status = "快捷键表来自 Adobe Illustrator 公开帮助文档"
        case "键盘快捷键说明", "打开“键盘快捷键”对话框": status = "键盘快捷键"; openPanels.insert("键盘快捷键")
        case "打开“偏好设置”对话框": status = "首选项"; openPanels.insert("首选项")
        case "打开“颜色设置”对话框": status = "颜色设置"; openPanels.insert("颜色设置")
        case "打开“文档设置”对话框": status = "文档设置"; openPanels.insert("文档设置")
        case "打开“文件信息”对话框": status = "文件信息"; openPanels.insert("文件信息")
        case "打开“存储为”对话框", "存储对文档所做的更改", "存储文档的副本", "打开文档", "关闭文档窗口", "打印", "将文件置入文档", "打包文档", "打开“导出为多种屏幕所用格式”对话框", "导出为", "打开“存储为 Web 所用格式”对话框", "恢复":
            status = action
        case "工作区 基本功能", "工作区 传统基本功能", "工作区 排版", "工作区 绘画", "工作区 描摹", "工作区 重置":
            workspace = action.replacingOccurrences(of: "工作区 ", with: "")
            if action.contains("基本") { openPanels = ["属性", "图层"] }
            status = "工作区 \(workspace)"
        case "工具栏 基本": toolbarAdvanced = false
        case "工具栏 高级": toolbarAdvanced = true
        case "显示/隐藏色板": togglePanel("色板")
        case "显示/隐藏画板面板": togglePanel("画板")
        case "显示/隐藏资源导出": togglePanel("资源导出")
        case "显示/隐藏 AI": togglePanel("AI")
        case "旋转对话框": rotateSelection(field("degrees", 30) * Double.pi / 180)
        case "对称对话框":
            if textField("axis", "h") == "v" { reflectSelection(vertical: true) } else { reflectSelection(vertical: false) }
        case "缩放对话框": scaleSelection(field("percent", 110) / 100)
        case "倾斜对话框": shearSelection(field("shear", 20) / 100)
        case "打开“分别变换”对话框":
            scaleSelection(field("percent", 105) / 100)
            if field("degrees", 0) != 0 { rotateSelection(field("degrees", 0) * Double.pi / 180) }
        case "移动对象": nudgeSelection(Vec2(field("dx", nudge * 10), field("dy", 0)))
        case "相同填充颜色": selectSameFill()
        case "相同描边颜色": selectSameStroke()
        case "相同描边宽度": selectSameStrokeWidth()
        case "相同不透明度": selectSameOpacity()
        case "选择文本对象":
            selection = allItems().compactMap { if case .text(let t) = $0 { return t.id } else { return nil } }
        case "选择同图层":
            if let id = selection.first, let layer = document.layerID(containing: id) {
                selection = document.layers.first { $0.id == layer }?.items.map(\.id) ?? []
            }
        case "选择方向手柄": status = "方向手柄"
        case "选择剪切蒙版":
            selection = allItems().compactMap { if case .clip(let c) = $0 { return c.id } else { return nil } }
        case "存储所选对象":
            savedSelection = selection; status = "已存储所选对象"
        case "选择当前所选对象上方的对象": selectSibling(1)
        case "选择当前所选对象下方的对象": selectSibling(-1)
        case "建立图案": makeSymbol()
        case "编辑图案": status = "编辑图案"; openPanels.insert("色板")
        case "使用变形封套扭曲对象": warpSelection("弧形", bend: 0.6)
        case "使用网格作为封套形状来扭曲对象": warpSelection("鱼眼", bend: 0.4)
        case "使用其他对象作为封套形状来扭曲对象": clipToTop()
        case "释放封套": ungroupSelection()
        case "进行实时上色（使用油漆桶工具时）": makeLivePaint()
        case "释放实时上色": releaseLivePaint()
        case "图像描摹": traceSelection(preset: TracePreset.named(textField("preset", TracePreset.blackAndWhiteLogo.name)))
        case "栅格化": rasterizeSelection(ppi: field("ppi", document.rasterPPI))
        case "文档栅格效果设置":
            document.rasterPPI = field("ppi", document.rasterPPI)
            status = "栅格效果 \(Int(document.rasterPPI)) ppi"
            openPanels.insert("文档栅格效果设置")
        case "区域文字选项":
            let leading = field("leading", 0)
            toggleText { $0.leading = leading }
            status = "区域文字选项"
        case "查找/替换字体":
            let font = textField("font", "Helvetica")
            toggleText { $0.fontName = font }
            status = "字体 \(font)"
        case "转为路径文字": convertToPathText()
        case "转为直排路径文字": toggleText { $0.kind = .path }
        case "混合选项":
            blendSteps = max(1, Int(field("steps", Double(blendSteps))))
            status = "混合步数 \(blendSteps)"
        case "切换到上次使用的选择工具（选择工具、直接选择工具或编组选择工具）":
            cycleSelectionTool()
        case "在多种绘图模式之间切换":
            drawMode = (drawMode + 1) % 3
            status = ["正常绘制", "在后面绘制", "在内部绘制"][drawMode]
        case "在屏幕模式之间切换：正常屏幕模式、带菜单栏的全屏模式、全屏模式":
            screenMode = (screenMode + 1) % 3
            status = ["正常屏幕", "带菜单栏的全屏", "全屏"][screenMode]
        case "退出画板工具模式", "退出全屏模式":
            if tool == .artboard { tool = .selection }
            if screenMode != 0 { screenMode = 0 }
        case "显示/隐藏所有面板":
            if openPanels.isEmpty { openPanels = ["属性", "图层"] } else { openPanels = [] }
        case "显示/隐藏所有面板（“工具”面板和“控制”面板除外）":
            openPanels = openPanels.isEmpty ? ["属性"] : []
        default:
            if action.hasPrefix("显示/隐藏") || action.hasPrefix("打开") {
                let panel = panelName(from: action)
                togglePanel(panel)
                return true
            }
            if action.hasPrefix("字体 ") {
                let name = String(action.dropFirst(3))
                toggleText { $0.fontName = name }
                return true
            }
            if action.hasPrefix("字号 ") {
                if let size = Double(action.dropFirst(3).replacingOccurrences(of: " pt", with: "")) {
                    toggleText { $0.fontSize = size }
                }
                return true
            }
            if action.hasPrefix("变形 ") {
                warpSelection(String(action.dropFirst(3)), bend: field("bend", 0.5))
                return true
            }
            if action.hasPrefix("扭曲 ") {
                warpSelection(String(action.dropFirst(3)), bend: field("bend", 8))
                return true
            }
            if action.hasPrefix("图表 ") {
                let name = String(action.dropFirst(3))
                chartKind = ChartKind.allCases.first { $0.title == name } ?? ChartKind(rawValue: name) ?? .column
                tool = .columnGraph
                status = chartKind.title
                return true
            }
            if action.hasPrefix("效果 ") {
                let name = String(action.dropFirst("效果 ".count))
                applyEffect(.distort(kind: name, amount: field("amount", 8)))
                status = action
                return true
            }
            if action.hasPrefix("SVG滤镜") {
                status = action
                return true
            }
            if action.hasPrefix("转换为") {
                convertShape(action)
                return true
            }
            if action.hasPrefix("插入") {
                insertGlyph(action)
                return true
            }
            status = action
            return true
        }
        return true
    }

    public func togglePanel(_ name: String) {
        if openPanels.contains(name) { openPanels.remove(name) } else { openPanels.insert(name) }
        status = name
    }

    public func newDocument(size: Vec2, title: String = "未标题-1", colorMode: ColorMode = .rgb, units: UnitKind = .pt, artboardCount: Int = 1, rasterPPI: Double = 72, zoomTo: Double? = nil) {
        var doc = LaminaDocument.blank(title: title, size: size)
        doc.colorMode = colorMode
        doc.units = units
        doc.rasterPPI = rasterPPI
        if artboardCount > 1 {
            let gap = 40.0
            doc.artboards = (0..<artboardCount).map { index in
                Artboard(name: "画板 \(index + 1)", rect: Rect2(x: Double(index) * (size.x + gap), y: 0, width: size.x, height: size.y))
            }
            doc.activeArtboard = 0
        }
        document = doc
        selection = []
        undoStack = []
        redoStack = []
        canUndo = false
        canRedo = false
        fileURL = nil
        savedSnapshot = try? JSONEncoder.lamina.encode(document)
        if let zoomTo {
            zoom = zoomTo
            let board = document.currentArtboard.rect
            pan = Vec2(board.midX - viewportSize.x / zoom / 2, board.midY - viewportSize.y / zoom / 2)
        }
        status = "新建文档"
    }

    public func replaceDocument(_ doc: LaminaDocument) {
        document = doc
        selection = []
        undoStack = []
        redoStack = []
        canUndo = false
        canRedo = false
        savedSnapshot = try? JSONEncoder.lamina.encode(doc)
    }

    public func markSaved() {
        savedSnapshot = try? JSONEncoder.lamina.encode(document)
    }

    public var isDirty: Bool {
        guard let savedSnapshot, let now = try? JSONEncoder.lamina.encode(document) else { return true }
        return now != savedSnapshot
    }

    public func fitArtboard() {
        let b = document.currentArtboard.rect
        guard b.width > 1, b.height > 1 else { return }
        let margin = 48.0
        zoom = min((viewportSize.x - margin) / b.width, (viewportSize.y - margin) / b.height)
        zoom = max(0.02, zoom)
        pan = Vec2(b.midX - viewportSize.x / zoom / 2, b.midY - viewportSize.y / zoom / 2)
        status = "适合画板 \(Int(zoom * 100))%"
    }

    public func fitAll() {
        let box = document.artboards.map(\.rect).reduce(Rect2.zero) { $0.isEmpty ? $1 : $0.union($1) }
        guard box.width > 1 else { return }
        zoom = min(viewportSize.x / box.width, viewportSize.y / box.height) * 0.9
        pan = Vec2(box.midX - viewportSize.x / zoom / 2, box.midY - viewportSize.y / zoom / 2)
    }

    public func selectionBounds() -> Rect2? {
        let boxes = selection.compactMap { document.item(id: $0) }.map { ItemGeometry.bounds($0) }.filter { !$0.isEmpty }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    public func applyFill(_ paint: Paint?) {
        currentFill = paint
        activeAttrIsFill = true
        applyPaintToSelection()
    }

    public func applyStroke(_ stroke: StrokeStyle?) {
        currentStroke = stroke
        activeAttrIsFill = false
        applyPaintToSelection()
    }

    public func addFillLayer() {
        beginChange()
        let paint = currentFill ?? .solid(.black)
        for id in selection {
            _ = document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                object.appearance.additionalFills.append(paint)
                item = .path(object)
            }
        }
        status = "添加填色"
    }

    public func addStrokeLayer() {
        beginChange()
        var stroke = currentStroke ?? StrokeStyle()
        stroke.brush = brush
        stroke.profile = widthProfile
        for id in selection {
            _ = document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                object.appearance.additionalStrokes.append(stroke)
                item = .path(object)
            }
        }
        status = "添加描边"
    }

    public func setBrush(_ next: BrushDefinition) {
        brush = next
        beginChange()
        for id in selection {
            _ = document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                var stroke = object.appearance.stroke ?? currentStroke ?? StrokeStyle()
                stroke.brush = next
                object.appearance.stroke = stroke
                item = .path(object)
            }
        }
        status = "画笔"
    }

    public func setWidthProfile(_ profile: WidthProfile) {
        widthProfile = profile
        beginChange()
        for id in selection {
            _ = document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                var stroke = object.appearance.stroke ?? currentStroke ?? StrokeStyle()
                stroke.profile = profile
                object.appearance.stroke = stroke
                item = .path(object)
            }
        }
        status = "宽度配置"
    }

    public func toggleOverprint(fill: Bool) {
        beginChange()
        for id in selection {
            _ = document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                if fill { object.appearance.overprintFill.toggle() }
                else { object.appearance.overprintStroke.toggle() }
                item = .path(object)
            }
        }
        status = fill ? "叠印填色" : "叠印描边"
    }

    public func insertSVG(_ svg: String) throws {
        let imported = try SVGCodec.read(svg)
        beginChange()
        let items = imported.layers.flatMap(\.items)
        for item in items { insertNew(item) }
        selection = items.map(\.id)
        status = "已插入 SVG"
    }

    public func addPalette(_ rows: [(name: String, hex: String)]) {
        beginChange()
        for row in rows {
            document.swatches.append(Swatch(name: row.name, paint: .solid(RGBA(hex: row.hex))))
        }
        status = "已添加 \(rows.count) 个色板"
    }

    public func setNudge(_ value: Double) { nudge = value }

    // MARK: Creation

    private func commitCreate(to p: Vec2, shift: Bool, option: Bool) {
        if tool == .hand { return }
        if tool == .measure {
            measure = ToolBehaviors.measure(from: createOrigin, to: p)
            status = String(format: "距离 %.1f  Δx %.1f  Δy %.1f  %.0f°", measure.distance, measure.dx, measure.dy, measure.angle)
            return
        }
        if tool == .brush || tool == .pencil || tool == .blobBrush || tool == .shaper || tool == .eraser || tool == .knife || tool == .smooth || tool == .pathEraser || tool == .joinTool {
            if penNodes.last?.anchor.distance(to: p) ?? 0 > 1.5 {
                penNodes.append(.corner(p))
            }
            finishFreehand(erase: tool == .eraser || tool == .knife)
            return
        }
        var a = createOrigin
        var b = p
        if shift {
            let dx = b.x - a.x, dy = b.y - a.y
            let side = max(abs(dx), abs(dy))
            b = Vec2(a.x + side * (dx < 0 ? -1 : 1), a.y + side * (dy < 0 ? -1 : 1))
        }
        if option {
            let c = a
            a = Vec2(c.x - (b.x - c.x), c.y - (b.y - c.y))
        }
        let rect = Rect2(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        guard rect.width > 0.5 || rect.height > 0.5 || tool == .line else { return }
        beginChange()
        switch tool {
        case .rectangle:
            if showPerspective { insertProjected(rect, name: "矩形") }
            else { insertNew(.path(styled(PathObject(name: "矩形", path: PathBuilder.rectangle(rect))))) }
        case .roundedRectangle:
            insertNew(.path(styled(PathObject(name: "圆角矩形", path: PathBuilder.roundedRect(rect, radius: cornerRadius)))))
        case .ellipse:
            insertNew(.path(styled(PathObject(name: "椭圆", path: PathBuilder.ellipse(rect)))))
        case .polygon:
            let radius = max(rect.width, rect.height) / 2
            insertNew(.path(styled(PathObject(name: "多边形", path: PathBuilder.polygon(center: rect.center, radius: radius, sides: polygonSides)))))
        case .star:
            let radius = max(rect.width, rect.height) / 2
            insertNew(.path(styled(PathObject(name: "星形", path: PathBuilder.star(center: rect.center, radius: max(radius, 4), points: starPoints, innerRatio: starInner)))))
        case .flare:
            let radius = max(rect.width, rect.height) / 2
            let children = ToolBehaviors.flare(center: rect.center, radius: max(radius, 8), rays: flareRays).map { path -> ArtItem in
                .path(styled(PathObject(name: "光晕", path: path, appearance: Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle()))))
            }
            insertNew(.group(GroupObject(name: "光晕", children: children)))
        case .line:
            let end = shift ? ToolBehaviors.constrain45(p, from: createOrigin) : p
            insertNew(.path(styled(PathObject(name: "直线", path: PathBuilder.line(createOrigin, end), appearance: Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle())))))
        case .arc:
            let sweep = shift ? Double.pi / 2 : arcSweep
            insertNew(.path(styled(PathObject(name: "弧形", path: ToolBehaviors.arcPath(rect: rect, sweep: sweep), appearance: Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle())))))
        case .spiral:
            insertNew(.path(styled(PathObject(name: "螺旋线", path: PathBuilder.spiral(center: rect.center, startRadius: 4, endRadius: max(rect.width, rect.height) / 2, turns: spiralTurns), appearance: Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle())))))
        case .rectGrid:
            let paths = PathBuilder.rectGrid(rect, rows: gridRows, columns: gridColumns)
            let children = paths.map { ArtItem.path(styled(PathObject(name: "网格线", path: $0, appearance: Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle())))) }
            insertNew(.group(GroupObject(name: "矩形网格", children: children)))
        case .polarGrid:
            let paths = ToolBehaviors.polarGrid(rect, rings: gridRows, divisions: polarDivisions)
            let children = paths.map { ArtItem.path(styled(PathObject(name: "极坐标网格", path: $0, appearance: Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle())))) }
            insertNew(.group(GroupObject(name: "极坐标网格", children: children)))
        case .artboard:
            let board = Artboard(name: "画板 \(document.artboards.count + 1)", rect: rect)
            document.artboards.append(board)
            document.activeArtboard = document.artboards.count - 1
            status = board.name
        case .slice:
            document.slices.append(SliceRect(rect: rect))
        case .areaText, .verticalText:
            if case .text(var text) = document.item(id: editingText ?? UUID()) {
                text.kind = .area
                text.frame = rect
                let id = text.id
                document.updateItem(id) { $0 = .text(text) }
            }
        case .columnGraph:
            if showPerspective {
                insertProjected(rect, name: chartKind.title)
            } else {
                insertNew(.graph(ChartBuilder.object(kind: chartKind, frame: rect)))
            }
        default:
            break
        }
    }

    private func styled(_ object: PathObject) -> PathObject {
        var object = object
        object.appearance.fill = currentFill
        object.appearance.stroke = currentStroke
        return object
    }

    private func makeText(at p: Vec2, area: Rect2?, vertical: Bool = false) -> ArtItem {
        var text = TextObject(origin: p, fontSize: 24, appearance: Appearance(fill: currentFill ?? .solid(.black), stroke: nil))
        if vertical {
            text.name = "直排文字"
            text.string = "直排文字"
            text.leading = -text.fontSize
        }
        if let area {
            text.kind = .area
            text.frame = area
            if !vertical { text.string = "区域文字" }
        }
        return .text(text)
    }

    private func insertNew(_ item: ArtItem) {
        let index: Int? = drawMode == 1 ? 0 : nil
        document.insert(item, index: index)
        if drawMode == 2, let clipID = selection.first, let clip = document.item(id: clipID) {
            _ = document.removeItem(item.id)
            let group = ClipObject(clipper: clip, contents: [item])
            _ = document.removeItem(clipID)
            document.insert(.clip(group))
            selection = [group.id]
            return
        }
        selection = [item.id]
    }

    private func finishFreehand(erase: Bool) {
        let raw = penNodes.map(\.anchor)
        guard raw.count > 1 else { penNodes = []; strokeSamples = []; return }
        if tool == .smooth {
            beginChange()
            smoothAlong(raw)
            penNodes = []; strokeSamples = []
            return
        }
        if tool == .pathEraser {
            beginChange()
            eraseSpan(raw)
            penNodes = []; strokeSamples = []
            return
        }
        if tool == .joinTool {
            beginChange()
            joinAlong(raw)
            penNodes = []; strokeSamples = []
            return
        }
        if tool == .eraser {
            beginChange()
            cutWithRibbon(raw, knife: false)
            penNodes = []; strokeSamples = []
            status = "橡皮擦"
            return
        }
        if tool == .knife {
            beginChange()
            cutWithRibbon(raw, knife: true)
            penNodes = []; strokeSamples = []
            status = "刻刀"
            return
        }
        beginChange()
        if tool == .shaper, scribbleDelete(raw) {
            penNodes = []; strokeSamples = []
            return
        }
        let fitted = FreehandFit.fit(raw, fidelity: fidelity, smoothness: smoothness, closed: tool == .blobBrush)
        if tool == .shaper, let kind = ToolBehaviors.recognize(raw) {
            let box = Rect2.enclosing(raw)
            let path = kind == .ellipse ? PathBuilder.ellipse(box) : PathBuilder.rectangle(box)
            insertNew(.path(styled(PathObject(name: kind.label, path: path))))
            penNodes = []; strokeSamples = []
            return
        }
        if tool == .blobBrush {
            insertBlob(fitted)
            penNodes = []; strokeSamples = []
            return
        }
        var appearance = Appearance(fill: nil, stroke: currentStroke ?? StrokeStyle())
        if tool == .brush, var stroke = appearance.stroke {
            stroke.width = max(4, stroke.width)
            stroke.brush = brush
            stroke.profile = widthProfile
            stroke.samples = strokeSamples
            appearance.stroke = stroke
            appearance.fill = nil
        }
        if penSource != nil {
            _ = penSource
        }
        insertNew(.path(PathObject(name: tool.title, path: fitted, appearance: appearance)))
        penNodes = []
        strokeSamples = []
        penSource = nil
    }

    private func penDown(_ p: Vec2, option: Bool, shift: Bool) {
        var point = p
        if shift, let last = penNodes.last {
            point = ToolBehaviors.constrain45(point, from: last.anchor)
        }
        let slop = 8 / zoom
        if let first = penNodes.first, penNodes.count >= 3, first.anchor.distance(to: point) <= slop {
            beginChange()
            let path = PathItem(nodes: penNodes, closed: true, shape: .free)
            insertNew(.path(styled(PathObject(name: "路径", path: path))))
            penNodes = []
            penCursor = .close
            penSource = nil
            drag = nil
            return
        }
        if penNodes.count >= 2, let other = openEndpoint(near: point, excluding: penSource) {
            var nodes = penNodes
            nodes.append(.corner(other.point))
            beginChange()
            if let source = penSource { _ = document.removeItem(source) }
            _ = document.removeItem(other.item)
            let path = PathItem(nodes: nodes, closed: false, shape: .free)
            insertNew(.path(styled(PathObject(name: "路径", path: path))))
            penNodes = []
            penCursor = .join
            penSource = nil
            drag = nil
            return
        }
        if penNodes.isEmpty, let end = openEndpoint(near: point, excluding: nil) {
            beginChange()
            if case .path(let object) = document.item(id: end.item) {
                penNodes = object.path.nodes
                if end.atStart == false { penNodes.reverse() }
                penSource = end.item
                _ = document.removeItem(end.item)
                penCursor = .continuePath
                penAnchorOrigin = penNodes.last?.anchor ?? point
                drag = .pen
                status = "继续路径"
                return
            }
        }
        if penNodes.isEmpty, autoAddDelete, editAnchorUnderPen(at: point) {
            return
        }
        var node = PathNode.corner(point)
        if option { node.corner = .corner }
        penNodes.append(node)
        penAnchorOrigin = point
        penCursor = ToolBehaviors.penCursor(nodes: penNodes, hover: point, zoom: zoom, nearAnchor: false, nearSegment: false, nearForeignEnd: false)
        drag = .pen
        status = "钢笔 \(penNodes.count) 点"
    }

    public func penDrag(to p: Vec2, shift: Bool = false, option: Bool = false, space: Bool = false) {
        guard !penNodes.isEmpty else { return }
        let last = penNodes.count - 1
        if space || spaceHeld {
            let moved = penAnchorOrigin + (p - gestureOrigin)
            let delta = moved - penNodes[last].anchor
            penNodes[last].anchor = moved
            if let h = penNodes[last].inHandle { penNodes[last].inHandle = h + delta }
            if let h = penNodes[last].outHandle { penNodes[last].outHandle = h + delta }
            return
        }
        let placed = ToolBehaviors.placeHandle(anchor: penNodes[last].anchor, drag: p, shift: shift, option: option)
        penNodes[last].outHandle = placed.outHandle
        penNodes[last].inHandle = placed.inHandle
        penNodes[last].corner = option ? .corner : .smooth
    }

    public func finishPen() {
        guard penNodes.count >= 2 else { penNodes = []; return }
        beginChange()
        let path = PathItem(nodes: penNodes, closed: penClosed, shape: .free)
        insertNew(.path(styled(PathObject(name: "路径", path: path))))
        penNodes = []
    }

    private func curvatureDown(_ p: Vec2, clickCount: Int) {
        if clickCount >= 2, let index = penNodes.indices.min(by: { penNodes[$0].anchor.distance(to: p) < penNodes[$1].anchor.distance(to: p) }),
           penNodes[index].anchor.distance(to: p) < 8 / zoom {
            penNodes = ToolBehaviors.curvature(penNodes, toggle: index)
            status = "曲率角点"
            return
        }
        penNodes.append(.corner(p))
        penNodes = ToolBehaviors.curvature(penNodes, toggle: nil)
        drag = .pen
        status = "曲率 \(penNodes.count) 点"
    }

    private func addAnchor(at p: Vec2) {
        guard let id = selection.first, case .path(var object) = document.item(id: id), let hit = Bezier.project(object.path, point: p) else {
            status = "请选择路径"
            return
        }
        beginChange()
        object.path = Bezier.split(object.path, segment: hit.index, t: hit.t)
        document.updateItem(id) { $0 = .path(object) }
    }

    private func deleteAnchor(at p: Vec2) {
        guard let hit = hitAnchor(p) else { return }
        beginChange()
        document.updateItem(hit.item) { item in
            if case .path(var object) = item {
                object.path = Bezier.deleteNode(object.path, nodeID: hit.node)
                item = .path(object)
            }
        }
    }

    private func convertAnchor(at p: Vec2) {
        if let handle = hitHandlePoint(p) {
            beginChange()
            moveSnapshot = try? JSONEncoder.lamina.encode(document)
            drag = .convert(item: handle.item, node: handle.node, handle: true)
            return
        }
        guard let hit = hitAnchor(p) else { return }
        beginChange()
        moveSnapshot = try? JSONEncoder.lamina.encode(document)
        moveOrigin = p
        drag = .convert(item: hit.item, node: hit.node, handle: false)
    }

    // MARK: Selection helpers

    private func topHit(_ p: Vec2) -> UUID? {
        for layer in document.layers.reversed() where layer.visible && !layer.locked {
            for item in layer.items.reversed() where !item.hidden && !item.locked {
                if ItemGeometry.hit(item, point: p, tolerance: 5 / zoom) != nil || ItemGeometry.bounds(item).contains(p, inset: 4 / zoom) {
                    return item.id
                }
            }
        }
        return nil
    }

    private func toggle(_ id: UUID) {
        if let idx = selection.firstIndex(of: id) { selection.remove(at: idx) } else { selection.append(id) }
    }

    private func items(in rect: Rect2, fullyInside: Bool) -> [UUID] {
        document.layers.flatMap(\.items).filter { item in
            let b = ItemGeometry.bounds(item)
            if fullyInside {
                return rect.contains(Vec2(b.minX, b.minY)) && rect.contains(Vec2(b.maxX, b.maxY))
            }
            return b.intersects(rect)
        }.map(\.id)
    }

    public func hitHandle(at p: Vec2) -> Handle? {
        guard let box = selectionBounds() else { return nil }
        let points: [(Handle, Vec2)] = [
            (.nw, Vec2(box.minX, box.minY)), (.n, Vec2(box.midX, box.minY)), (.ne, Vec2(box.maxX, box.minY)),
            (.e, Vec2(box.maxX, box.midY)), (.se, Vec2(box.maxX, box.maxY)), (.s, Vec2(box.midX, box.maxY)),
            (.sw, Vec2(box.minX, box.maxY)), (.w, Vec2(box.minX, box.midY))
        ]
        let tol = 6 / zoom
        return points.first { $0.1.distance(to: p) <= tol }?.0
    }

    private func hitAnchor(_ p: Vec2) -> (item: UUID, node: UUID)? {
        let tol = 6 / zoom
        for item in allItems().reversed() {
            if case .path(let object) = item {
                let local = object.transform.inverted?.apply(p) ?? p
                for node in object.path.nodes where node.anchor.distance(to: local) <= tol {
                    return (object.id, node.id)
                }
            }
        }
        return nil
    }

    private func allItems() -> [ArtItem] { document.flatItems() }

    private func groupSelect(at p: Vec2, shift: Bool) {
        guard let leaf = ItemGeometryHit.leaf(in: document, at: p) else { return }
        if selection.contains(leaf), let parent = document.parentID(of: leaf) {
            selection = [parent]
        } else {
            selection = [leaf]
        }
        if shift, let id = selection.first { toggle(id) }
    }

    private func magicWand(at p: Vec2, subtract: Bool, add: Bool) {
        guard let id = ItemGeometryHit.leaf(in: document, at: p), let item = document.item(id: id) else { return }
        let sample = fillColor(item)
        let matches = allItems().filter { other in
            guard let color = fillColor(other), let sample else { return fillHex(other) == fillHex(item) }
            return ToolBehaviors.colorDistance(color, sample) <= wandTolerance + 0.0001
        }.map(\.id)
        if subtract {
            selection.removeAll { matches.contains($0) }
        } else if add {
            for id in matches where !selection.contains(id) { selection.append(id) }
        } else {
            selection = matches
        }
    }

    private func fillHex(_ item: ArtItem) -> String {
        switch item {
        case .path(let o): return o.appearance.fill?.solidColor?.hex ?? ""
        case .text(let o): return o.appearance.fill?.solidColor?.hex ?? ""
        case .compound(let o): return o.appearance.fill?.solidColor?.hex ?? ""
        default: return ""
        }
    }

    // MARK: Transforms

    private func applyMove(to p: Vec2, copy: Bool) {
        guard let snapshot = moveSnapshot, let original = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        let delta = p - moveOrigin
        if copy {
            document = original
            let clones = selection.compactMap { id -> ArtItem? in
                guard var item = original.item(id: id) else { return nil }
                item = retarget(item)
                var t = item.transform
                t.tx += delta.x; t.ty += delta.y
                item.setTransform(t)
                return item
            }
            for clone in clones { document.insert(clone) }
            selection = clones.map(\.id)
            moveSnapshot = try? JSONEncoder.lamina.encode(document)
            moveOrigin = p
            return
        }
        document = original
        for id in selection {
            document.updateItem(id) { item in
                var t = item.transform
                t.tx += delta.x
                t.ty += delta.y
                item.setTransform(t)
            }
        }
    }

    private func retarget(_ item: ArtItem) -> ArtItem {
        switch item {
        case .path(var o): o.id = UUID(); return .path(o)
        case .text(var o): o.id = UUID(); return .text(o)
        case .group(var o):
            o.id = UUID()
            o.children = o.children.map(retarget)
            return .group(o)
        case .compound(var o): o.id = UUID(); return .compound(o)
        case .clip(var o):
            o.id = UUID()
            o.clipper = retarget(o.clipper)
            o.contents = o.contents.map(retarget)
            return .clip(o)
        case .placed(var o): o.id = UUID(); return .placed(o)
        case .mesh(var o): o.id = UUID(); return .mesh(o)
        case .graph(var o): o.id = UUID(); return .graph(o)
        }
    }

    private func applyScale(handle: Handle, original: Rect2, to p: Vec2, shift: Bool, option: Bool) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        let anchor = option ? original.center : opposite(of: handle, in: original)
        var scaleX = 1.0, scaleY = 1.0
        switch handle {
        case .e, .w:
            scaleX = safeScale(p.x - anchor.x, original.width * (handle == .w ? -0.5 : 0.5) == 0 ? (handle == .e ? original.maxX - anchor.x : original.minX - anchor.x) : 1)
            let originX = handle == .e ? original.maxX : original.minX
            scaleX = (p.x - anchor.x) / ((originX - anchor.x) == 0 ? 1 : (originX - anchor.x))
            scaleY = shift ? scaleX : 1
        case .n, .s:
            let originY = handle == .s ? original.maxY : original.minY
            scaleY = (p.y - anchor.y) / ((originY - anchor.y) == 0 ? 1 : (originY - anchor.y))
            scaleX = shift ? scaleY : 1
        default:
            let origin = cornerPoint(handle, original)
            scaleX = (p.x - anchor.x) / ((origin.x - anchor.x) == 0 ? 1 : (origin.x - anchor.x))
            scaleY = (p.y - anchor.y) / ((origin.y - anchor.y) == 0 ? 1 : (origin.y - anchor.y))
            if shift {
                let u = max(abs(scaleX), abs(scaleY))
                scaleX = u * (scaleX < 0 ? -1 : 1)
                scaleY = u * (scaleY < 0 ? -1 : 1)
            }
        }
        _ = safeScale
        let xform = Affine.scale(scaleX, scaleY, around: anchor)
        for id in selection {
            document.updateItem(id) { item in
                item.setTransform(xform.concatenated(item.transform))
            }
        }
    }

    private func safeScale(_ a: Double, _ b: Double) -> Double { b == 0 ? 1 : a / b }

    private func opposite(of handle: Handle, in rect: Rect2) -> Vec2 {
        switch handle {
        case .nw: return Vec2(rect.maxX, rect.maxY)
        case .n: return Vec2(rect.midX, rect.maxY)
        case .ne: return Vec2(rect.minX, rect.maxY)
        case .e: return Vec2(rect.minX, rect.midY)
        case .se: return Vec2(rect.minX, rect.minY)
        case .s: return Vec2(rect.midX, rect.minY)
        case .sw: return Vec2(rect.maxX, rect.minY)
        case .w: return Vec2(rect.maxX, rect.midY)
        case .rotate: return rect.center
        }
    }

    private func cornerPoint(_ handle: Handle, _ rect: Rect2) -> Vec2 {
        switch handle {
        case .nw: return Vec2(rect.minX, rect.minY)
        case .ne: return Vec2(rect.maxX, rect.minY)
        case .se: return Vec2(rect.maxX, rect.maxY)
        case .sw: return Vec2(rect.minX, rect.maxY)
        default: return rect.center
        }
    }

    private func moveAnchor(item: UUID, node: UUID, to p: Vec2, shift: Bool) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        let delta = p - moveOrigin
        let ids = selectedAnchors.isEmpty ? [node] : selectedAnchors
        document.updateItem(item) { art in
            guard case .path(var object) = art else { return }
            for i in object.path.nodes.indices where ids.contains(object.path.nodes[i].id) {
                object.path.nodes[i].anchor += delta
                if let h = object.path.nodes[i].inHandle { object.path.nodes[i].inHandle = h + delta }
                if let h = object.path.nodes[i].outHandle { object.path.nodes[i].outHandle = h + delta }
            }
            object.path.shape = .free
            art = .path(object)
        }
    }

    private func applyRotateLike(center: Vec2, to p: Vec2, shift: Bool, option: Bool) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        let xform: Affine
        switch tool {
        case .scale:
            let factors = ToolBehaviors.scaleFactors(center: center, from: moveOrigin, to: p, shift: shift)
            xform = Affine.scale(factors.0, factors.1, around: center)
        case .reflect:
            xform = ToolBehaviors.reflection(axisStart: center, axisEnd: p)
        case .shear:
            let dx = (p.x - moveOrigin.x) / 80
            let dy = shift ? 0 : (p.y - moveOrigin.y) / 80
            xform = Affine.skew(x: dx, y: dy, around: center)
        default:
            xform = Affine.rotation(ToolBehaviors.rotateAngle(center: center, from: moveOrigin, to: p, shift: shift), around: center)
        }
        _ = option
        for id in selection {
            document.updateItem(id) { item in
                item.setTransform(xform.concatenated(item.transform))
            }
        }
    }

    private func applyGradient(from a: Vec2, to b: Vec2, shift: Bool) {
        guard let box = selectionBounds(), box.width > 0, box.height > 0 else { return }
        let existing = selectedGradient()
        let paint = ToolBehaviors.gradient(existing: existing, from: a, to: b, box: box, shift: shift)
        let radial = selection.contains { id in
            if case .path(let o) = document.item(id: id), case .radial = o.appearance.fill { return true }
            return false
        }
        currentFill = radial ? .radial(paint) : .linear(paint)
        applyPaintToSelection()
    }

    private var lastTransform = Affine.identity

    private func rotateSelection(_ radians: Double) {
        guard let center = selectionBounds()?.center else { return }
        beginChange()
        let xform = Affine.rotation(radians, around: center)
        lastTransform = xform
        for id in selection { document.updateItem(id) { $0.setTransform(xform.concatenated($0.transform)) } }
    }

    private func scaleSelection(_ factor: Double) {
        guard let center = selectionBounds()?.center else { return }
        beginChange()
        let xform = Affine.scale(factor, factor, around: center)
        lastTransform = xform
        for id in selection { document.updateItem(id) { $0.setTransform(xform.concatenated($0.transform)) } }
    }

    private func reflectSelection(vertical: Bool = false) {
        guard let center = selectionBounds()?.center else { return }
        beginChange()
        let xform = vertical ? Affine.scale(1, -1, around: center) : Affine.scale(-1, 1, around: center)
        lastTransform = xform
        for id in selection { document.updateItem(id) { $0.setTransform(xform.concatenated($0.transform)) } }
    }

    private func shearSelection(_ amount: Double) {
        guard let center = selectionBounds()?.center else { return }
        beginChange()
        let xform = Affine.skew(x: amount, y: 0, around: center)
        lastTransform = xform
        for id in selection { document.updateItem(id) { $0.setTransform(xform.concatenated($0.transform)) } }
    }

    private func nudgeSelection(_ delta: Vec2) {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                var t = item.transform
                t.tx += delta.x; t.ty += delta.y
                item.setTransform(t)
            }
        }
    }

    private func transformAgain() {
        beginChange()
        for id in selection { document.updateItem(id) { $0.setTransform(lastTransform.concatenated($0.transform)) } }
    }

    private func resetBounds() {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                let box = Bezier.bounds(object.path)
                guard box.width > 0, box.height > 0 else { return }
                for i in object.path.nodes.indices {
                    object.path.nodes[i].anchor = Vec2(object.path.nodes[i].anchor.x - box.x, object.path.nodes[i].anchor.y - box.y)
                    if let h = object.path.nodes[i].inHandle { object.path.nodes[i].inHandle = h - Vec2(box.x, box.y) }
                    if let h = object.path.nodes[i].outHandle { object.path.nodes[i].outHandle = h - Vec2(box.x, box.y) }
                }
                var t = object.transform
                t.tx += box.x; t.ty += box.y
                object.transform = t
                item = .path(object)
            }
        }
    }

    // MARK: Arrange, paint, path ops

    private func arrange(_ direction: Int) {
        guard let id = selection.first, let layerID = document.layerID(containing: id), let li = document.layers.firstIndex(where: { $0.id == layerID }) else { return }
        beginChange()
        var items = document.layers[li].items
        let selected = items.filter { selection.contains($0.id) }
        items.removeAll { selection.contains($0.id) }
        let insertAt: Int
        if direction == .max { insertAt = items.count }
        else if direction == .min { insertAt = 0 }
        else if direction > 0 { insertAt = min(items.count, (items.count)) }
        else { insertAt = max(0, 0) }
        // Place relative to remaining stack: front is the end.
        if direction == .max {
            items.append(contentsOf: selected)
        } else if direction == .min {
            items.insert(contentsOf: selected, at: 0)
        } else if direction > 0 {
            items.append(contentsOf: selected)
        } else {
            items.insert(contentsOf: selected, at: 0)
        }
        _ = insertAt
        document.layers[li].items = items
    }

    private func align(_ action: String) {
        let boxes = selection.compactMap { id -> (UUID, Rect2)? in
            guard let item = document.item(id: id) else { return nil }
            return (id, ItemGeometry.bounds(item))
        }
        guard boxes.count >= 2 else { return }
        let union = boxes.map(\.1).reduce(boxes[0].1) { $0.union($1) }
        beginChange()
        for (id, box) in boxes {
            var dx = 0.0, dy = 0.0
            switch action {
            case "水平左对齐": dx = union.minX - box.minX
            case "水平居中对齐": dx = union.midX - box.midX
            case "水平右对齐": dx = union.maxX - box.maxX
            case "垂直顶对齐": dy = union.minY - box.minY
            case "垂直居中对齐": dy = union.midY - box.midY
            case "垂直底对齐": dy = union.maxY - box.maxY
            default: break
            }
            document.updateItem(id) { item in
                var t = item.transform
                t.tx += dx; t.ty += dy
                item.setTransform(t)
            }
        }
    }

    private func applyPaintToSelection() {
        guard !selection.isEmpty else { return }
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                switch item {
                case .path(var o):
                    if activeAttrIsFill { o.appearance.fill = currentFill } else { o.appearance.stroke = currentStroke }
                    item = .path(o)
                case .text(var o):
                    if activeAttrIsFill { o.appearance.fill = currentFill } else { o.appearance.stroke = currentStroke }
                    item = .text(o)
                case .compound(var o):
                    if activeAttrIsFill { o.appearance.fill = currentFill } else { o.appearance.stroke = currentStroke }
                    item = .compound(o)
                default: break
                }
            }
        }
    }

    private func swapFillStroke() {
        let fill = currentFill
        let strokePaint = currentStroke?.paint
        currentFill = strokePaint
        if let fill {
            if currentStroke == nil { currentStroke = StrokeStyle(paint: fill) }
            else { currentStroke?.paint = fill }
        } else {
            currentStroke = nil
        }
        applyPaintToSelection()
    }

    private func isGradient(_ paint: Paint?) -> Bool {
        switch paint {
        case .linear, .radial: return true
        default: return false
        }
    }

    private func mapColors(_ f: (RGBA) -> RGBA) {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                switch item {
                case .path(var o):
                    o.appearance.fill = o.appearance.fill?.mapColor(f)
                    if var stroke = o.appearance.stroke {
                        stroke.paint = stroke.paint.mapColor(f)
                        o.appearance.stroke = stroke
                    }
                    item = .path(o)
                case .text(var o):
                    o.appearance.fill = o.appearance.fill?.mapColor(f)
                    item = .text(o)
                default: break
                }
            }
        }
    }

    private func copySelection() {
        clipboard = selection.compactMap { document.item(id: $0) }
        status = "已复制 \(clipboard.count)"
    }

    private func paste(offset: Vec2, place: PastePlace) {
        guard !clipboard.isEmpty else { return }
        beginChange()
        let clones = clipboard.map { item -> ArtItem in
            var copy = retarget(item)
            var t = copy.transform
            t.tx += offset.x; t.ty += offset.y
            copy.setTransform(t)
            return copy
        }
        for clone in clones {
            switch place {
            case .above, .inPlace: document.insert(clone)
            case .below: document.insert(clone, index: 0)
            }
        }
        selection = clones.map(\.id)
    }

    private enum PastePlace { case above, below, inPlace }

    private func pasteOnAllArtboards() {
        guard !clipboard.isEmpty, let source = document.artboards.first else { return }
        beginChange()
        var ids: [UUID] = []
        for board in document.artboards {
            let delta = Vec2(board.rect.x - source.rect.x, board.rect.y - source.rect.y)
            for item in clipboard {
                var copy = retarget(item)
                var t = copy.transform
                t.tx += delta.x; t.ty += delta.y
                copy.setTransform(t)
                document.insert(copy)
                ids.append(copy.id)
            }
        }
        selection = ids
    }

    public func deleteSelection(recordUndo: Bool) {
        if recordUndo { beginChange() }
        for id in selection { _ = document.removeItem(id) }
        selection = []
    }

    private func groupSelection() {
        let items = selection.compactMap { document.item(id: $0) }
        guard items.count >= 2 else { status = "请选择多个对象"; return }
        beginChange()
        for id in selection { _ = document.removeItem(id) }
        let group = GroupObject(name: "组", children: items)
        document.insert(.group(group))
        selection = [group.id]
    }

    private func ungroupSelection() {
        beginChange()
        var created: [UUID] = []
        for id in selection {
            guard case .group(let group) = document.item(id: id) else { continue }
            _ = document.removeItem(id)
            for child in group.children {
                var copy = child
                copy.setTransform(group.transform.concatenated(child.transform))
                document.insert(copy)
                created.append(copy.id)
            }
        }
        if !created.isEmpty { selection = created }
    }

    private func setLock(_ locked: Bool) {
        beginChange()
        for id in selection { document.updateItem(id) { $0.setLocked(locked) } }
        if locked { selection = [] }
    }

    private func unlockAll() {
        beginChange()
        for item in allItems() where item.locked {
            document.updateItem(item.id) { $0.setLocked(false) }
        }
    }

    private func setHidden(_ hidden: Bool) {
        beginChange()
        for id in selection { document.updateItem(id) { $0.setHidden(hidden) } }
        if hidden { selection = [] }
    }

    private func unhideAll() {
        beginChange()
        for item in document.flatItems(includingHidden: true) where item.hidden {
            document.updateItem(item.id) { $0.setHidden(false) }
        }
    }

    private func makeClip() {
        guard selection.count >= 2 else { status = "请选择蒙版和内容"; return }
        let items = selection.compactMap { document.item(id: $0) }
        beginChange()
        for id in selection { _ = document.removeItem(id) }
        let clipper = items.last!
        let contents = Array(items.dropLast())
        let clip = ClipObject(clipper: clipper, contents: contents)
        document.insert(.clip(clip))
        selection = [clip.id]
    }

    private func releaseClip() {
        beginChange()
        var created: [UUID] = []
        for id in selection {
            guard case .clip(let clip) = document.item(id: id) else { continue }
            _ = document.removeItem(id)
            document.insert(clip.clipper)
            created.append(clip.clipper.id)
            for child in clip.contents {
                document.insert(child)
                created.append(child.id)
            }
        }
        selection = created
    }

    private func makeCompound() {
        let paths: [PathItem] = selection.compactMap {
            if case .path(let o) = document.item(id: $0) { return o.path }
            return nil
        }
        guard paths.count >= 2 else { return }
        let appearance = (document.item(id: selection[0]).flatMap { if case .path(let o) = $0 { return o.appearance } else { return nil } }) ?? .default
        beginChange()
        for id in selection { _ = document.removeItem(id) }
        let compound = CompoundObject(paths: paths, appearance: appearance)
        document.insert(.compound(compound))
        selection = [compound.id]
    }

    private func releaseCompound() {
        beginChange()
        var created: [UUID] = []
        for id in selection {
            guard case .compound(let c) = document.item(id: id) else { continue }
            _ = document.removeItem(id)
            for path in c.paths {
                let object = PathObject(path: path, appearance: c.appearance, transform: c.transform)
                document.insert(.path(object))
                created.append(object.id)
            }
        }
        selection = created
    }

    private func joinSelection() {
        let paths: [PathItem] = selection.compactMap { if case .path(let o) = document.item(id: $0) { return o.path } else { return nil } }
        guard let joined = PathOps.join(paths) else { status = "没有可连接的开放路径"; return }
        beginChange()
        for id in selection { _ = document.removeItem(id) }
        let object = styled(PathObject(name: "路径", path: joined))
        document.insert(.path(object))
        selection = [object.id]
    }

    private func averageSelection() {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path = PathOps.average(o.path, nodeIDs: selectedAnchors.isEmpty ? nil : selectedAnchors)
                    item = .path(o)
                }
            }
        }
    }

    private func outlineStroke() {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(let o) = item else { return }
                let ring = Bezier.flatten(o.path)
                let width = o.appearance.stroke?.width ?? 1
                let outline = PathOps.outlineStroke(ring, width: width, closed: o.path.closed)
                let path = PathItem(nodes: outline.map { .corner($0) }, closed: true, shape: .free)
                var appearance = o.appearance
                appearance.fill = o.appearance.stroke?.paint ?? .solid(.black)
                appearance.stroke = nil
                item = .path(PathObject(id: o.id, name: o.name, path: path, appearance: appearance, transform: o.transform))
            }
        }
    }

    private func offsetPaths(_ distance: Double) {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var o) = item else { return }
                let ring = Bezier.flatten(o.path)
                let moved = PathOps.offset(ring, distance: distance)
                o.path = PathItem(nodes: moved.map { .corner($0) }, closed: true, shape: .free)
                item = .path(o)
            }
        }
    }

    private func simplifySelection(tolerance: Double = 1.5) {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path = PathOps.simplify(o.path, tolerance: tolerance)
                    item = .path(o)
                }
            }
        }
    }

    private func expandSelection() {
        beginChange()
        let ids = selection
        var created: [UUID] = []
        for id in ids {
            guard case .path(let object) = document.item(id: id) else { continue }
            if object.appearance.stroke?.brush != nil, let stroke = object.appearance.stroke {
                let baked = BrushEngine.expand(path: object.path, stroke: stroke)
                if !baked.isEmpty {
                    _ = document.removeItem(id)
                    let group = GroupObject(name: "扩展外观", children: baked)
                    document.insert(.group(group))
                    created.append(group.id)
                    continue
                }
            }
            if !object.widths.isEmpty || object.appearance.stroke?.profile != .uniform, let stroke = object.appearance.stroke {
                let outline = WidthStroke.outline(path: object.path, widths: object.widths, profile: stroke.profile, base: stroke.width)
                var appearance = object.appearance
                appearance.fill = stroke.paint
                appearance.stroke = nil
                appearance.effects = []
                let baked = PathObject(name: "扩展外观", path: outline, appearance: appearance, transform: object.transform)
                _ = document.removeItem(id)
                document.insert(.path(baked))
                created.append(baked.id)
                continue
            }
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path.shape = .free
                    o.appearance.effects = []
                    item = .path(o)
                }
            }
            created.append(id)
        }
        selection = created
        status = "已扩展"
    }

    private func boolean(_ op: BooleanOp) {
        let paths = selection.compactMap { id -> PathObject? in
            if case .path(let o) = document.item(id: id) { return o }
            return nil
        }
        guard paths.count >= 2 else { status = "请选择两个路径"; return }
        let a = Bezier.flatten(paths[0].path).map { paths[0].transform.apply($0) }
        let b = Bezier.flatten(paths[1].path).map { paths[1].transform.apply($0) }
        let rings = Pathfinder.apply(op, subject: a, clip: b)
        beginChange()
        for id in selection { _ = document.removeItem(id) }
        var ids: [UUID] = []
        for ring in rings where ring.count >= 3 {
            let path = PathItem(nodes: ring.map { .corner($0) }, closed: true, shape: .free)
            let object = PathObject(name: "路径查找器", path: path, appearance: paths[0].appearance)
            document.insert(.path(object))
            ids.append(object.id)
        }
        selection = ids
        status = "路径查找器"
    }

    private func applyEffect(_ effect: LiveEffect) {
        beginChange()
        lastEffect = effect
        for id in selection {
            document.updateItem(id) { item in
                switch item {
                case .path(var o):
                    o.appearance.effects.append(effect)
                    if case .roundCorners(let radius) = effect, case .rectangle = o.path.shape {
                        let box = Bezier.bounds(o.path)
                        o.path = PathBuilder.roundedRect(box, radius: radius)
                    }
                    if case .warp(let kind, let bend) = effect {
                        o.path = PathOps.warp(o.path, kind: kind, bend: bend)
                    }
                    item = .path(o)
                default: break
                }
            }
        }
    }

    private func warpSelection(_ kind: String, bend: Double) {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path = PathOps.warp(o.path, kind: kind, bend: bend)
                    item = .path(o)
                }
            }
        }
        lastEffect = .warp(kind: kind, bend: bend)
    }

    private func clipToTop() { makeClip() }

    private func makeSymbol() {
        guard let id = selection.first, var item = document.item(id: id) else { return }
        beginChange()
        if case .group(var g) = item {
            g.isSymbol = true
            item = .group(g)
            document.updateItem(id) { $0 = item }
        } else {
            let group = GroupObject(name: "图案", children: [item], isSymbol: true)
            _ = document.removeItem(id)
            document.insert(.group(group))
            selection = [group.id]
        }
    }

    private func makeLivePaint() {
        let paths = selection.compactMap { id -> PathObject? in
            if case .path(let object) = document.item(id: id) { return object }
            return nil
        }
        guard !paths.isEmpty else { return }
        beginChange()
        for id in selection { _ = document.removeItem(id) }
        let group = LivePaint.group(paths: paths, gap: max(0, field("gap", 2)))
        document.insert(.group(group))
        selection = [group.id]
        tool = .livePaintBucket
        status = "实时上色 \(group.children.count) 个面"
    }

    private func releaseLivePaint() {
        ungroupSelection()
    }

    private func makeBlend() {
        let items = selection.compactMap { document.item(id: $0) }
        guard items.count >= 2 else { return }
        guard case .path(let a) = items[0], case .path(let b) = items[1] else { return }
        beginChange()
        var children: [ArtItem] = []
        let steps = max(2, blendSteps)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            var path = a.path
            for n in path.nodes.indices {
                let other = b.path.nodes[min(n, b.path.nodes.count - 1)].anchor
                path.nodes[n].anchor = path.nodes[n].anchor + (other - path.nodes[n].anchor) * t
            }
            var appearance = a.appearance
            if let c1 = a.appearance.fill?.solidColor, let c2 = b.appearance.fill?.solidColor {
                appearance.fill = .solid(c1.mixed(with: c2, t: t))
            }
            children.append(.path(PathObject(name: "混合", path: path, appearance: appearance)))
        }
        for id in selection { _ = document.removeItem(id) }
        let group = GroupObject(name: "混合", children: children)
        document.insert(.group(group))
        selection = [group.id]
    }

    private func releaseBlend() { ungroupSelection() }

    private func createOutlines() {
        beginChange()
        var created: [UUID] = []
        for id in selection {
            guard case .text(let text) = document.item(id: id) else { continue }
            _ = document.removeItem(id)
            let glyphs = GlyphOutline.outlines(for: text)
            let children = glyphs.map { path in
                ArtItem.path(PathObject(name: "字形", path: path, appearance: text.appearance))
            }
            let group = GroupObject(name: "轮廓", children: children)
            document.insert(.group(group))
            created.append(group.id)
        }
        if !created.isEmpty { selection = created; status = "创建轮廓" }
    }

    private func addArtboard() {
        beginChange()
        let last = document.artboards.last?.rect ?? Rect2(x: 0, y: 0, width: 800, height: 600)
        let rect = Rect2(x: last.maxX + 40, y: last.y, width: last.width, height: last.height)
        document.artboards.append(Artboard(name: "画板 \(document.artboards.count + 1)", rect: rect))
        document.activeArtboard = document.artboards.count - 1
    }

    private func fitArtboardToArtwork() {
        let box = document.layers.flatMap(\.items).map { ItemGeometry.bounds($0) }.reduce(Rect2.zero) { $0.isEmpty ? $1 : $0.union($1) }
        guard !box.isEmpty, document.artboards.indices.contains(document.activeArtboard) else { return }
        beginChange()
        document.artboards[document.activeArtboard].rect = box.expanded(20)
    }

    private func arrangeArtboards() {
        beginChange()
        var x = 0.0
        for i in document.artboards.indices {
            document.artboards[i].rect.x = x
            document.artboards[i].rect.y = 0
            x += document.artboards[i].rect.width + 40
        }
    }

    private func addLayer(dialog: Bool) {
        beginChange()
        let layer = Layer(name: "图层 \(document.layers.count + 1)", colorHex: ["#1473E6", "#E34850", "#2D9D78", "#E68619"][document.layers.count % 4])
        document.layers.append(layer)
        document.activeLayer = document.layers.count - 1
        status = dialog ? "新建图层" : layer.name
        openPanels.insert("图层")
    }

    private func makeGuides() {
        guard let box = selectionBounds() else { return }
        beginChange()
        document.guides.append(Guide(axis: .horizontal, position: box.midY))
        document.guides.append(Guide(axis: .vertical, position: box.midX))
    }

    private func releaseGuides() {
        beginChange()
        document.guides.removeAll()
    }

    private func selectSibling(_ step: Int) {
        guard let id = selection.first, let layerID = document.layerID(containing: id), let layer = document.layers.first(where: { $0.id == layerID }), let idx = layer.items.firstIndex(where: { $0.id == id }) else { return }
        let next = idx + step
        if layer.items.indices.contains(next) { selection = [layer.items[next].id] }
    }

    private func selectSameFill() {
        guard let id = selection.first, let item = document.item(id: id) else { return }
        let hex = fillHex(item)
        selection = allItems().filter { fillHex($0) == hex }.map(\.id)
    }

    private func selectSameStroke() {
        selectSameFill()
    }

    private func selectSameStrokeWidth() {
        guard let id = selection.first, case .path(let o) = document.item(id: id) else { return }
        let w = o.appearance.stroke?.width
        selection = allItems().compactMap {
            if case .path(let p) = $0, p.appearance.stroke?.width == w { return p.id }
            return nil
        }
    }

    private func selectSameOpacity() {
        guard let id = selection.first, case .path(let o) = document.item(id: id) else { return }
        let op = o.appearance.opacity
        selection = allItems().compactMap {
            if case .path(let p) = $0, abs(p.appearance.opacity - op) < 0.001 { return p.id }
            return nil
        }
    }

    private func eyedrop(at p: Vec2, style: Bool) {
        guard let id = ItemGeometryHit.leaf(in: document, at: p), let item = document.item(id: id) else { return }
        if style {
            selection = [id]
            applyFill(currentFill)
            if let stroke = currentStroke { applyStroke(stroke) }
            status = "吸管应用"
            return
        }
        switch item {
        case .path(let o):
            currentFill = o.appearance.fill
            currentStroke = o.appearance.stroke
        case .text(let o):
            currentFill = o.appearance.fill
        default: break
        }
        status = "吸管"
    }

    private func splitAt(_ p: Vec2) {
        guard let id = ItemGeometryHit.leaf(in: document, at: p), case .path(let object) = document.item(id: id), let hit = Bezier.project(object.path, point: p) else { return }
        let pieces = ToolBehaviors.scissors(object.path, segment: hit.index, t: hit.t)
        guard !pieces.isEmpty else { return }
        beginChange()
        _ = document.removeItem(id)
        var ids: [UUID] = []
        for piece in pieces {
            let copy = PathObject(name: object.name, path: piece, appearance: object.appearance, transform: object.transform)
            document.insert(.path(copy))
            ids.append(copy.id)
        }
        selection = ids
        status = pieces.count > 1 ? "剪刀已分开" : "剪刀"
    }

    private func smoothSelection() {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path.nodes = Bezier.smooth(o.path.nodes, closed: o.path.closed)
                    item = .path(o)
                }
            }
        }
    }

    private func shapeBuild(stroke: [Vec2], subtract: Bool) {
        let paths = selection.compactMap { id -> PathItem? in
            if case .path(let o) = document.item(id: id) { return o.path }
            return nil
        }
        let faces = ToolBehaviors.shapeFaces(paths: paths, stroke: stroke, subtract: subtract)
        guard !faces.isEmpty else { status = "形状生成器没有切到面"; return }
        beginChange()
        let appearance = selection.compactMap { id -> Appearance? in
            if case .path(let o) = document.item(id: id) { return o.appearance }
            return nil
        }.first ?? Appearance()
        for id in selection { _ = document.removeItem(id) }
        var ids: [UUID] = []
        for face in faces {
            let object = PathObject(name: "形状生成器", path: face, appearance: appearance)
            document.insert(.path(object))
            ids.append(object.id)
        }
        selection = ids
        status = subtract ? "形状生成器删除" : "形状生成器"
    }

    private func beginWidth(at p: Vec2, option: Bool) {
        guard let id = selection.first else { status = "请选择路径"; return }
        beginChange()
        var created = false
        document.updateItem(id) { item in
            guard case .path(var o) = item else { return }
            let sides = ToolBehaviors.widthSides(path: o.path, at: 0.5, point: p, total: max(1, (o.appearance.stroke?.width ?? 8) / 2), option: option)
            o.widths.append(WidthPoint(t: sides.2, left: sides.0, right: sides.1))
            item = .path(o)
            created = true
        }
        if created { drag = .width(id) }
        status = "宽度点"
    }

    private func spraySymbol(at p: Vec2) {
        guard let id = selection.first, let item = document.item(id: id) else { status = "请先选择符号"; return }
        let tint = currentFill?.solidColor ?? .black
        let existing = allItems().compactMap { art -> Vec2? in
            art.name == "符号实例" ? ItemGeometry.bounds(art).center : nil
        }
        let plan = ToolBehaviors.symbolInstances(kind: symbolKind, at: p, diameter: symbolDiameter, existing: existing, tint: tint)
        beginChange()
        if symbolKind == .sprayer {
            for place in plan.places {
                var copy = retarget(item)
                copy.setTransform(.translation(place.x, place.y))
                if case .path(var o) = copy { o.name = "符号实例"; copy = .path(o) }
                if case .group(var o) = copy { o.name = "符号实例"; copy = .group(o) }
                document.insert(copy)
            }
            status = "符号喷枪 \(plan.places.count)"
            return
        }
        for artID in allItems().map(\.id) {
            document.updateItem(artID) { art in
                guard art.name == "符号实例" else { return }
                let center = ItemGeometry.bounds(art).center
                if center.distance(to: p) > symbolDiameter { return }
                switch symbolKind {
                case .shifter, .scruncher:
                    let next = plan.moved.min { $0.distance(to: center) < $1.distance(to: center) } ?? center
                    var t = art.transform
                    t.tx += next.x - center.x
                    t.ty += next.y - center.y
                    art.setTransform(t)
                case .sizer:
                    art.setTransform(Affine.scale(plan.scale, plan.scale, around: center).concatenated(art.transform))
                case .spinner:
                    art.setTransform(Affine.rotation(plan.rotation, around: center).concatenated(art.transform))
                case .stainer:
                    if let color = plan.color, case .path(var o) = art {
                        o.appearance.fill = .solid(color)
                        art = .path(o)
                    }
                case .screener:
                    if let opacity = plan.opacity, case .path(var o) = art {
                        o.appearance.opacity = opacity
                        art = .path(o)
                    }
                case .styler:
                    if case .path(var o) = art {
                        o.appearance.stroke = currentStroke
                        art = .path(o)
                    }
                case .sprayer:
                    break
                }
            }
        }
        status = symbolKind.title
    }

    private func insertMesh(at p: Vec2) {
        if let id = topHit(p), case .mesh(let mesh) = document.item(id: id) {
            beginChange()
            let next = ToolBehaviors.subdivideMesh(mesh)
            document.updateItem(id) { $0 = .mesh(next) }
            selection = [id]
            status = "网格 \(next.columns)×\(next.rows)"
            return
        }
        beginChange()
        let colors = (0..<16).map { i in RGBA(r: Double(i % 4) / 3, g: Double(i / 4) / 3, b: 0.6) }
        let mesh = MeshObject(columns: 4, rows: 4, origin: p, cell: Vec2(20, 20), colors: colors)
        document.insert(.mesh(mesh))
        selection = [mesh.id]
    }

    private func paintBucket(at p: Vec2) {
        for layer in document.layers.reversed() where layer.visible {
            for item in layer.items.reversed() {
                if case .group(let group) = item, group.isLivePaint {
                    let color = currentFill ?? .solid(.black)
                    let painted = LivePaint.paint(group, at: p, color: color)
                    if painted != group {
                        beginChange()
                        document.updateItem(group.id) { $0 = .group(painted) }
                        status = "实时上色"
                        return
                    }
                }
            }
        }
        guard let id = ItemGeometryHit.leaf(in: document, at: p) else { return }
        selection = [id]
        activeAttrIsFill = true
        applyPaintToSelection()
    }

    private func attachPathText() {
        guard let id = selection.first, case .path(let path) = document.item(id: id) else {
            status = "请先选择路径"
            return
        }
        beginChange()
        var text = TextObject(kind: .path, string: "路径文字", origin: path.path.nodes.first?.anchor ?? .zero, onPath: path.path)
        text.appearance.fill = .solid(.black)
        document.insert(.text(text))
        selection = [text.id]
    }

    private func convertToPathText() { attachPathText() }

    private func traceSelection(preset: TracePreset) {
        let placed = selection.compactMap { id -> PlacedObject? in
            if case .placed(let object) = document.item(id: id) { return object }
            return nil
        }
        guard let image = placed.first, let data = Data(base64Encoded: image.dataBase64) else {
            status = "图像描摹需要置入的 PNG"
            return
        }
        let traced = ImageTrace.trace(png: data, preset: preset)
        guard !traced.isEmpty else {
            status = "没有描出路径"
            return
        }
        beginChange()
        let shift = Affine.translation(image.frame.x, image.frame.y)
        let scale = Affine.scale(image.frame.width / max(1, Double(PNGCodec.decode(data)?.width ?? 1)), image.frame.height / max(1, Double(PNGCodec.decode(data)?.height ?? 1)))
        let children = traced.map { object -> ArtItem in
            var copy = object
            copy.path.nodes = copy.path.nodes.map { node in
                var moved = node
                moved.anchor = shift.apply(scale.apply(node.anchor))
                if let h = node.inHandle { moved.inHandle = shift.apply(scale.apply(h)) }
                if let h = node.outHandle { moved.outHandle = shift.apply(scale.apply(h)) }
                return moved
            }
            return .path(copy)
        }
        let group = GroupObject(name: "描摹", children: children)
        document.insert(.group(group))
        selection = [group.id]
        status = "图像描摹 \(preset.name)"
    }

    private func convertShape(_ action: String) {
        beginChange()
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var o) = item else { return }
                let box = Bezier.bounds(o.path)
                if action.contains("椭圆") { o.path = PathBuilder.ellipse(box) }
                else if action.contains("圆角") { o.path = PathBuilder.roundedRect(box, radius: cornerRadius) }
                else { o.path = PathBuilder.rectangle(box) }
                item = .path(o)
            }
        }
    }

    private func toggleText(_ body: (inout TextObject) -> Void) {
        beginChange()
        let ids = selection.isEmpty ? [editingText].compactMap { $0 } : selection
        for id in ids {
            document.updateItem(id) { item in
                if case .text(var text) = item {
                    body(&text)
                    item = .text(text)
                }
            }
        }
    }

    private func appendText(_ string: String) {
        guard let id = editingText else { return }
        document.updateItem(id) { item in
            if case .text(var text) = item {
                text.string += string
                item = .text(text)
            }
        }
    }

    private func insertGlyph(_ action: String) {
        let map = [
            "插入字间中点": "·", "插入版权符号": "©", "插入省略号": "…", "插入段落符号": "¶",
            "插入分节符": "§", "插入商标符号": "™", "插入注册商标符号": "®",
            "插入全角破折号": "—", "插入半角破折号": "–", "插入自由连字符": "­",
            "插入左双引号": "“", "插入右双引号": "”", "插入左单引号": "‘", "插入右单引号": "’",
            "插入全角空格": "\u{3000}", "插入半角空格": " ", "插入窄间隔": "\u{2009}"
        ]
        if let glyph = map[action] { appendText(glyph) }
        else { status = action }
    }

    private func cycleSelectionTool() {
        switch tool {
        case .selection: tool = .directSelection
        case .directSelection: tool = .groupSelection
        default: tool = .selection
        }
    }

    public func requestToolOptions() {
        let diameter = tool == .blobBrush ? blobDiameter : tool == .eraser ? eraserDiameter : tool == .warp ? warpDiameter : symbolDiameter
        pendingDialog = ToolBehaviors.optionsDialog(tool: tool, fidelity: fidelity, smoothness: smoothness, diameter: diameter, tolerance: wandTolerance)
        status = pendingDialog?.title ?? tool.title
    }

    private func applyToolOptions() {
        fidelity = field("fidelity", fidelity)
        smoothness = field("smoothness", smoothness)
        let diameter = field("diameter", blobDiameter)
        blobDiameter = diameter
        eraserDiameter = diameter
        warpDiameter = diameter
        symbolDiameter = diameter
        wandTolerance = field("tolerance", wandTolerance)
        status = "已应用\(tool.title)选项"
    }

    private func snapped(_ point: Vec2) -> Vec2 {
        guard smartGuides || snapGrid || snapPoint else { return point }
        let anchors = snapPoint || smartGuides ? allItems().flatMap(pathAnchors) : []
        var guides = showGuides && !lockGuides && smartGuides ? document.guides : []
        if smartGuides {
            let board = document.currentArtboard.rect
            guides.append(Guide(axis: .vertical, position: board.minX))
            guides.append(Guide(axis: .vertical, position: board.maxX))
            guides.append(Guide(axis: .horizontal, position: board.minY))
            guides.append(Guide(axis: .horizontal, position: board.maxY))
        }
        return ToolBehaviors.snap(point, anchors: anchors, guides: guides, grid: snapGrid ? 8 : nil, tolerance: 6 / zoom)
    }

    private func sample(_ stylus: StylusSample, at point: Vec2) -> StrokeSample {
        var copy = stylus.stroke
        copy.point = point
        return copy
    }

    private func directSelection(at p: Vec2, shift: Bool) {
        if let anchor = hitAnchor(p) {
            if shift { selectedAnchors.formSymmetricDifference([anchor.node]) } else { selectedAnchors = [anchor.node] }
            selection = [anchor.item]
            beginChange()
            moveSnapshot = try? JSONEncoder.lamina.encode(document)
            moveOrigin = p
            drag = .anchor(item: anchor.item, node: anchor.node)
        } else if let id = ItemGeometryHit.leaf(in: document, at: p) {
            selection = [id]
            drag = .marquee(p)
            interactionHint = .marquee(Rect2(x: p.x, y: p.y, width: 0, height: 0))
        } else {
            if !shift { selection = []; selectedAnchors = [] }
            drag = .marquee(p)
            interactionHint = .marquee(Rect2(x: p.x, y: p.y, width: 0, height: 0))
        }
    }

    private func pathAnchors(_ item: ArtItem) -> [Vec2] {
        switch item {
        case .path(let o): return o.path.nodes.map { o.transform.apply($0.anchor) }
        case .group(let o): return o.children.flatMap(pathAnchors)
        default: return []
        }
    }

    private func fillColor(_ item: ArtItem) -> RGBA? {
        switch item {
        case .path(let o): return o.appearance.fill?.solidColor
        case .text(let o): return o.appearance.fill?.solidColor
        case .compound(let o): return o.appearance.fill?.solidColor
        default: return nil
        }
    }

    private func openEndpoint(near p: Vec2, excluding: UUID?) -> (item: UUID, point: Vec2, atStart: Bool)? {
        let slop = 8 / zoom
        for item in allItems().reversed() {
            if item.id == excluding { continue }
            guard case .path(let object) = item, !object.path.closed, object.path.nodes.count >= 2 else { continue }
            if let first = object.path.nodes.first, object.transform.apply(first.anchor).distance(to: p) <= slop {
                return (object.id, first.anchor, true)
            }
            if let last = object.path.nodes.last, object.transform.apply(last.anchor).distance(to: p) <= slop {
                return (object.id, last.anchor, false)
            }
        }
        return nil
    }

    private func editAnchorUnderPen(at p: Vec2) -> Bool {
        guard let id = selection.first, case .path(let object) = document.item(id: id) else { return false }
        if let hit = hitAnchor(p), hit.item == id {
            beginChange()
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path = Bezier.deleteNode(o.path, nodeID: hit.node)
                    item = .path(o)
                }
            }
            penCursor = .delete
            status = "删除锚点"
            return true
        }
        if let hit = Bezier.project(object.path, point: p), hit.point.distance(to: p) < 6 / zoom {
            beginChange()
            document.updateItem(id) { item in
                if case .path(var o) = item {
                    o.path = Bezier.split(o.path, segment: hit.index, t: hit.t)
                    item = .path(o)
                }
            }
            penCursor = .add
            status = "添加锚点"
            return true
        }
        return false
    }

    private func extendBrush(at p: Vec2) -> Bool {
        guard let id = selection.first, case .path(let object) = document.item(id: id), !object.path.closed,
              let last = object.path.nodes.last?.anchor, last.distance(to: p) < 12 / zoom else { return false }
        penNodes = object.path.nodes
        strokeSamples = object.appearance.stroke?.samples ?? []
        penSource = id
        _ = document.removeItem(id)
        return true
    }

    private func dragCurvature(to p: Vec2) {
        guard !penNodes.isEmpty else { return }
        penNodes[penNodes.count - 1].anchor = p
        penNodes = ToolBehaviors.curvature(penNodes, toggle: nil)
    }

    private func toggleConvert(item: UUID, node: UUID) {
        document.updateItem(item) { art in
            guard case .path(var object) = art, let index = object.path.nodes.firstIndex(where: { $0.id == node }) else { return }
            object.path.nodes[index] = ToolBehaviors.convert(node: object.path.nodes[index], drag: nil, breakHandle: false)
            object.path.shape = .free
            art = .path(object)
        }
    }

    private func dragConvert(item: UUID, node: UUID, to p: Vec2, breaking: Bool) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        document.updateItem(item) { art in
            guard case .path(var object) = art, let index = object.path.nodes.firstIndex(where: { $0.id == node }) else { return }
            object.path.nodes[index] = ToolBehaviors.convert(node: object.path.nodes[index], drag: p, breakHandle: breaking)
            object.path.shape = .free
            art = .path(object)
        }
    }

    private func hitHandlePoint(_ p: Vec2) -> (item: UUID, node: UUID)? {
        let tol = 6 / zoom
        for item in allItems().reversed() {
            guard case .path(let object) = item else { continue }
            for node in object.path.nodes {
                if let h = node.inHandle, h.distance(to: p) <= tol { return (object.id, node.id) }
                if let h = node.outHandle, h.distance(to: p) <= tol { return (object.id, node.id) }
            }
        }
        return nil
    }

    private func beginTransform(at p: Vec2, copy: Bool) {
        if copy {
            let clones = selection.compactMap { id -> ArtItem? in
                guard var item = document.item(id: id) else { return nil }
                item = retarget(item)
                return item
            }
            for clone in clones { document.insert(clone) }
            selection = clones.map(\.id)
        }
        beginChange()
        moveSnapshot = try? JSONEncoder.lamina.encode(document)
        moveOrigin = p
    }

    private func applyDistort(handle: Handle, original: Rect2, to p: Vec2) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                let local = object.path.nodes.map { object.transform.apply($0.anchor) }
                let moved = ToolBehaviors.bilinear(local, from: original, corner: handle, to: p)
                for i in object.path.nodes.indices {
                    object.path.nodes[i].anchor = moved[i]
                    object.path.nodes[i].inHandle = nil
                    object.path.nodes[i].outHandle = nil
                }
                object.transform = .identity
                object.path.shape = .free
                item = .path(object)
            }
        }
    }

    private func applyWarp(to p: Vec2) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                let local = object.path.nodes.map { object.transform.apply($0.anchor) }
                let moved = ToolBehaviors.warp(local, origin: moveOrigin, current: p, kind: warpKind, radius: warpDiameter, intensity: warpIntensity)
                for i in object.path.nodes.indices { object.path.nodes[i].anchor = moved[i] }
                object.transform = .identity
                object.path.shape = .free
                item = .path(object)
            }
        }
    }

    private func applyReshape(to p: Vec2) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                let local = object.path.nodes.map { object.transform.apply($0.anchor) }
                let moved = ToolBehaviors.reshape(local, origin: moveOrigin, delta: p - moveOrigin, radius: warpDiameter)
                for i in object.path.nodes.indices { object.path.nodes[i].anchor = moved[i] }
                object.transform = .identity
                object.path.shape = .free
                item = .path(object)
            }
        }
    }

    private func applyPuppet(to p: Vec2) {
        guard puppetPins.count >= 2, let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        guard let nearest = puppetPins.indices.min(by: { puppetPins[$0].distance(to: moveOrigin) < puppetPins[$1].distance(to: moveOrigin) }) else { return }
        var moved = puppetPins
        moved[nearest] = p
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var object) = item else { return }
                let local = object.path.nodes.map { object.transform.apply($0.anchor) }
                let next = ToolBehaviors.puppet(local, rest: puppetPins, moved: moved)
                for i in object.path.nodes.indices { object.path.nodes[i].anchor = next[i] }
                object.transform = .identity
                object.path.shape = .free
                item = .path(object)
            }
        }
    }

    private func updateWidth(to p: Vec2, option: Bool) {
        guard case .width(let id) = drag, case .path(var object) = document.item(id: id), let last = object.widths.indices.last else { return }
        let sides = ToolBehaviors.widthSides(path: object.path, at: object.widths[last].t, point: p, total: object.widths[last].left, option: option)
        object.widths[last].left = sides.0
        object.widths[last].right = sides.1
        document.updateItem(id) { $0 = .path(object) }
    }

    private func dragVanishing(to p: Vec2) {
        syncPerspective()
        let left = perspectiveGrid.leftVanishing.distance(to: moveOrigin)
        let right = perspectiveGrid.rightVanishing.distance(to: moveOrigin)
        if left <= right { perspectiveGrid.leftVanishing = p } else { perspectiveGrid.rightVanishing = p }
        showPerspective = true
        status = "消失点"
    }

    private func syncPerspective() {
        let plane: PerspectivePlane
        switch perspectivePlane {
        case 0: plane = .left
        case 2: plane = .right
        default: plane = .floor
        }
        perspectiveGrid.board = document.currentArtboard.rect
        perspectiveGrid.plane = plane
    }

    private func applyPlaneMove(to p: Vec2) {
        guard let snapshot = moveSnapshot, let base = try? JSONDecoder.lamina.decode(LaminaDocument.self, from: snapshot) else { return }
        document = base
        syncPerspective()
        let delta = ToolBehaviors.planeDelta(perspectiveGrid, from: moveOrigin, to: p)
        for id in selection {
            document.updateItem(id) { item in
                var t = item.transform
                t.tx += delta.x
                t.ty += delta.y
                item.setTransform(t)
            }
        }
    }

    private func selectedGradient() -> GradientPaint? {
        for id in selection {
            if case .path(let o) = document.item(id: id) {
                if case .linear(let g) = o.appearance.fill { return g }
                if case .radial(let g) = o.appearance.fill { return g }
            }
        }
        return nil
    }

    private func selectLivePaintFace(at p: Vec2) {
        for item in allItems().reversed() {
            guard case .group(let group) = item, group.isLivePaint else { continue }
            for child in group.children.reversed() {
                if case .path(let path) = child, Math2.polygonContains(p, ring: path.path.nodes.map(\.anchor)) {
                    selection = [path.id]
                    status = "实时上色选区"
                    return
                }
            }
        }
        if let id = ItemGeometryHit.leaf(in: document, at: p) { selection = [id] }
    }

    private func finishZoom(from origin: Vec2, to p: Vec2, out: Bool) {
        let rect = Rect2(min: Vec2(min(origin.x, p.x), min(origin.y, p.y)), max: Vec2(max(origin.x, p.x), max(origin.y, p.y)))
        if rect.width < 3 && rect.height < 3 {
            zoom = out ? max(0.02, zoom / 1.25) : min(64, zoom * 1.25)
        } else if rect.width > 1, rect.height > 1 {
            let zx = viewportSize.x / rect.width
            let zy = viewportSize.y / rect.height
            zoom = min(64, max(0.02, min(zx, zy)))
            pan = rect.origin
        }
        status = "缩放 \(Int(zoom * 100))%"
    }

    private func smoothAlong(_ stroke: [Vec2]) {
        for id in selection {
            document.updateItem(id) { item in
                guard case .path(var o) = item else { return }
                o.path.nodes = ToolBehaviors.smooth(nodes: o.path.nodes, near: stroke, radius: max(8, eraserDiameter), closed: o.path.closed)
                item = .path(o)
            }
        }
        status = "平滑"
    }

    private func eraseSpan(_ stroke: [Vec2]) {
        var created: [UUID] = []
        for id in selection {
            guard case .path(let object) = document.item(id: id) else { continue }
            let parts = ToolBehaviors.eraseSpan(object.path, stroke: stroke, radius: max(6, eraserDiameter * 0.5))
            _ = document.removeItem(id)
            for part in parts {
                let copy = PathObject(name: object.name, path: part, appearance: object.appearance, transform: object.transform)
                document.insert(.path(copy))
                created.append(copy.id)
            }
        }
        selection = created
        status = "路径橡皮擦"
    }

    private func joinAlong(_ stroke: [Vec2]) {
        let paths = selection.compactMap { id -> PathItem? in
            if case .path(let o) = document.item(id: id) { return o.path }
            return nil
        }
        guard let joined = ToolBehaviors.joinUnder(stroke: stroke, paths: paths, radius: 10) else {
            status = "没有可连接的开放路径"
            return
        }
        for id in selection { _ = document.removeItem(id) }
        let object = styled(PathObject(name: "路径", path: joined))
        document.insert(.path(object))
        selection = [object.id]
        status = "连接"
    }

    private func cutWithRibbon(_ stroke: [Vec2], knife: Bool) {
        var created: [UUID] = []
        let targets = allItems().compactMap { item -> (UUID, PathObject)? in
            if case .path(let o) = item { return (o.id, o) }
            return nil
        }
        if knife {
            for (_, object) in targets {
                let parts = ToolBehaviors.knife(object.path, stroke: stroke)
                if parts.count < 2 { continue }
                _ = document.removeItem(object.id)
                for part in parts {
                    let copy = PathObject(name: object.name, path: part, appearance: object.appearance, transform: object.transform)
                    document.insert(.path(copy))
                    created.append(copy.id)
                }
            }
            selection = created
            return
        }
        let ribbon = ToolBehaviors.eraserRibbon(stroke, diameter: eraserDiameter)
        for (_, object) in targets {
            let flat = object.path.nodes.map { object.transform.apply($0.anchor) }
            guard flat.count >= 3 else { continue }
            let box = Rect2.enclosing(flat)
            let strokeBox = Rect2.enclosing(stroke).expanded(eraserDiameter)
            if !box.intersects(strokeBox) { continue }
            let parts = ToolBehaviors.erase(flat, ribbon: ribbon)
            if parts.count == 1, parts[0].count == flat.count { continue }
            _ = document.removeItem(object.id)
            for ring in parts where ring.count >= 3 {
                let copy = PathObject(name: object.name, path: PathItem(nodes: ring.map { .corner($0) }, closed: true, shape: .free), appearance: object.appearance)
                document.insert(.path(copy))
                created.append(copy.id)
            }
        }
        selection = created
    }

    private func scribbleDelete(_ stroke: [Vec2]) -> Bool {
        let victims = allItems().filter { item in
            let center = ItemGeometry.bounds(item).center
            return stroke.contains { $0.distance(to: center) < 8 }
        }
        guard !victims.isEmpty, stroke.count > 6 else { return false }
        for item in victims { _ = document.removeItem(item.id) }
        status = "形状工具删除"
        return true
    }

    private func insertBlob(_ path: PathItem) {
        var stroke = StrokeStyle(width: blobDiameter, brush: .calligraphic(angle: 0, roundness: 1, diameter: blobDiameter), samples: strokeSamples)
        stroke.paint = currentFill ?? .solid(.black)
        let ribbons = BrushEngine.expand(path: path, stroke: stroke)
        guard let first = ribbons.first, case .path(let ribbon) = first else { return }
        var ring = ribbon.path.nodes.map(\.anchor)
        for item in allItems() {
            guard case .path(let object) = item, object.appearance.fill?.solidColor?.hex == (currentFill?.solidColor?.hex ?? "") else { continue }
            let other = Bezier.flatten(object.path)
            let united = Pathfinder.apply(.unite, subject: ring, clip: other)
            if let merged = united.max(by: { shoelace($0) < shoelace($1) }) {
                _ = document.removeItem(object.id)
                ring = merged
            }
        }
        let object = PathObject(name: "斑点", path: PathItem(nodes: ring.map { .corner($0) }, closed: true, shape: .free), appearance: Appearance(fill: currentFill, stroke: nil))
        document.insert(.path(object))
        selection = [object.id]
    }

    private func shoelace(_ ring: [Vec2]) -> Double {
        guard ring.count >= 3 else { return 0 }
        var area = 0.0
        for i in ring.indices {
            let j = (i + 1) % ring.count
            area += ring[i].x * ring[j].y - ring[j].x * ring[i].y
        }
        return abs(area) * 0.5
    }

    public func commitDialog(_ values: [String: String]) {
        guard let request = pendingDialog else { return }
        pendingDialog = nil
        dialogValues = values
        let saved = dialogsEnabled
        dialogsEnabled = false
        _ = perform(request.action)
        dialogsEnabled = saved
    }

    public func cancelDialog() { pendingDialog = nil }

    private func field(_ key: String, _ fallback: Double) -> Double {
        if let raw = dialogValues[key], let value = Double(raw) { return value }
        return fallback
    }

    private func textField(_ key: String, _ fallback: String) -> String {
        let raw = dialogValues[key] ?? ""
        return raw.isEmpty ? fallback : raw
    }

    private func insertProjected(_ rect: Rect2, name: String) {
        syncPerspective()
        insertNew(.path(styled(PathObject(name: name, path: perspectiveGrid.project(rect)))))
        status = "透视平面"
    }

    private func extrudeSelection(depth: Double) {
        replacePaths { Solid3D.extrude($0.path, color: $0.appearance.fill?.solidColor ?? RGBA(hex: "#1473E6"), depth: depth) }
        status = "凸出"
    }

    private func revolveSelection(angle: Double) {
        let steps = max(6, Int(angle / 30))
        replacePaths { Solid3D.revolve($0.path, color: $0.appearance.fill?.solidColor ?? RGBA(hex: "#1473E6"), steps: steps) }
        status = "绕转"
    }

    private func inflateSelection(amount: Double) {
        replacePaths { Solid3D.inflate($0.path, color: $0.appearance.fill?.solidColor ?? RGBA(hex: "#1473E6"), amount: amount) }
        status = "膨胀"
    }

    private func replacePaths(_ body: (PathObject) -> [ArtItem]) {
        let ids = selection
        beginChange()
        var created: [UUID] = []
        for id in ids {
            guard case .path(let object) = document.item(id: id) else { continue }
            let faces = body(object)
            guard !faces.isEmpty else { continue }
            _ = document.removeItem(id)
            var group = GroupObject(name: "三维", children: faces)
            group.transform = object.transform
            document.insert(.group(group))
            created.append(group.id)
        }
        if !created.isEmpty { selection = created }
    }

    private func rasterizeSelection(ppi: Double) {
        let ids = selection
        guard !ids.isEmpty else { status = "栅格化"; return }
        beginChange()
        var created: [UUID] = []
        for id in ids {
            guard let item = document.item(id: id) else { continue }
            let points: [Vec2]
            let fill: RGBA
            switch item {
            case .path(let object):
                points = Bezier.flatten(object.path).map { object.transform.apply($0) }
                fill = object.appearance.fill?.solidColor ?? .black
            default:
                let box = ItemGeometry.bounds(item)
                points = [Vec2(box.minX, box.minY), Vec2(box.maxX, box.minY), Vec2(box.maxX, box.maxY), Vec2(box.minX, box.maxY)]
                fill = RGBA(r: 0.5, g: 0.5, b: 0.5)
            }
            let buffer = EffectEngine.rasterize(points: points, fill: fill, ppi: ppi)
            let box = Rect2.enclosing(points).expanded(8)
            let placed = PlacedObject(name: "栅格", kind: "image", frame: box, dataBase64: buffer.png().base64EncodedString())
            _ = document.removeItem(id)
            document.insert(.placed(placed))
            created.append(placed.id)
        }
        selection = created
        status = "栅格化 \(Int(ppi)) ppi"
    }

    private func findReplace() {
        let find = textField("find", "")
        guard !find.isEmpty else { status = "查找和替换"; return }
        let replace = dialogValues["replace"] ?? ""
        toggleText { $0.string = $0.string.replacingOccurrences(of: find, with: replace) }
        status = "已替换"
    }

    private func spellcheck() {
        let words = selection.compactMap { id -> String? in
            if case .text(let text) = document.item(id: id) { return text.string }
            return nil
        }.joined(separator: " ")
        let known: Set<String> = ["the", "and", "墨线", "hello"]
        let misses = words.split(whereSeparator: { !$0.isLetter }).map(String.init).filter { word in
            word.allSatisfy { $0.isASCII } && word.count > 2 && !known.contains(word.lowercased())
        }
        status = misses.isEmpty ? "拼写检查通过" : "可疑：\(misses.prefix(6).joined(separator: "、"))"
    }

    private func panelName(from action: String) -> String {
        let known = ["属性", "图层", "颜色", "画笔", "描边", "渐变", "信息", "透明度", "外观", "对齐", "变换", "路径查找器", "符号", "图形样式", "字符", "段落", "制表符", "OpenType", "色板", "画板"]
        for name in known where action.contains(name) { return name }
        return action
    }
}

enum ItemGeometryHit {
    static func leaf(in document: LaminaDocument, at p: Vec2) -> UUID? {
        for layer in document.layers.reversed() where layer.visible && !layer.locked {
            for item in layer.items.reversed() {
                if let id = ItemGeometry.hit(item, point: p, tolerance: 5) { return id }
            }
        }
        return nil
    }
}
