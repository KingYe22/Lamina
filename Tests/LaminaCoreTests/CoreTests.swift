import XCTest
@testable import LaminaCore

final class ShortcutTests: XCTestCase {
    func testEveryAdobeRowIsMapped() {
        let text = ShortcutSource.load()
        XCTAssertTrue(text.contains("Command + Z"), "shortcut source missing")
        let rows = ShortcutTableParser.parse(text)
        XCTAssertEqual(rows.count, 390, rows.prefix(5).map(\.title).joined(separator: " | "))
        XCTAssertEqual(rows.first?.title, "还原")
        XCTAssertEqual(rows.first?.macRaw, "Command + Z")
        XCTAssertEqual(rows.last?.title, "显示/隐藏“符号”面板")
        XCTAssertEqual(rows.last?.macRaw, "Shift + Command + F11")
        XCTAssertEqual(Keymap.entries.count, rows.count)
        for row in rows {
            let mapped = Keymap.entries.first { $0.index == row.index }
            XCTAssertEqual(mapped?.title, row.title)
            XCTAssertEqual(mapped?.macRaw, row.macRaw)
            XCTAssertEqual(mapped?.chords, row.chords)
        }
    }

    func testCanonicalChords() {
        func chord(_ title: String) -> KeyChord? {
            Keymap.entry(title: title)?.chords.first
        }
        XCTAssertEqual(chord("还原"), KeyChord(modifiers: .command, key: .character("z")))
        XCTAssertEqual(chord("重做"), KeyChord(modifiers: [.shift, .command], key: .character("z")))
        XCTAssertEqual(chord("创建文档"), KeyChord(modifiers: .command, key: .character("n")))
        XCTAssertEqual(chord("从模板创建文档"), KeyChord(modifiers: [.shift, .command], key: .character("n")))
        XCTAssertEqual(chord("打开文档"), KeyChord(modifiers: .command, key: .character("o")))
        XCTAssertEqual(chord("存储对文档所做的更改"), KeyChord(modifiers: .command, key: .character("s")))
        XCTAssertEqual(chord("打开“存储为”对话框"), KeyChord(modifiers: [.shift, .command], key: .character("s")))
        XCTAssertEqual(chord("存储文档的副本"), KeyChord(modifiers: [.option, .command], key: .character("s")))
        XCTAssertEqual(chord("粘贴到所有画板上"), KeyChord(modifiers: [.option, .shift, .command], key: .character("v")))
        XCTAssertEqual(chord("打开“键盘快捷键”对话框"), KeyChord(modifiers: [.option, .shift, .command], key: .character("k")))
        XCTAssertEqual(chord("打开“偏好设置”对话框"), KeyChord(modifiers: .command, key: .character("k")))
        XCTAssertEqual(chord("选择工具"), KeyChord(modifiers: [], key: .character("v")))
        XCTAssertEqual(chord("直接选择工具"), KeyChord(modifiers: [], key: .character("a")))
        XCTAssertEqual(chord("钢笔工具"), KeyChord(modifiers: [], key: .character("p")))
        XCTAssertEqual(chord("曲率工具"), KeyChord(modifiers: .shift, key: .tilde))
        XCTAssertEqual(chord("添加锚点工具"), KeyChord(modifiers: [], key: .plus))
        XCTAssertEqual(chord("删除锚点工具"), KeyChord(modifiers: [], key: .minus))
        XCTAssertEqual(chord("直线段工具"), KeyChord(modifiers: [], key: .backslash))
        XCTAssertEqual(chord("矩形工具"), KeyChord(modifiers: [], key: .character("m")))
        XCTAssertEqual(chord("椭圆工具"), KeyChord(modifiers: [], key: .character("l")))
        XCTAssertEqual(chord("抓手工具"), KeyChord(modifiers: [], key: .character("h")))
        XCTAssertEqual(chord("缩放工具"), KeyChord(modifiers: [], key: .character("z")))
        XCTAssertEqual(chord("画板工具"), KeyChord(modifiers: .shift, key: .character("o")))
        XCTAssertEqual(chord("全选"), KeyChord(modifiers: .command, key: .character("a")))
        XCTAssertEqual(chord("编组选定图稿"), KeyChord(modifiers: .command, key: .character("g")))
        XCTAssertEqual(chord("创建剪切蒙版"), KeyChord(modifiers: .command, key: .character("7")))
        XCTAssertEqual(chord("创建复合路径"), KeyChord(modifiers: .command, key: .character("8")))
        XCTAssertEqual(chord("放大"), KeyChord(modifiers: .command, key: .equal))
        XCTAssertEqual(chord("缩小"), KeyChord(modifiers: .command, key: .minus))
        XCTAssertEqual(chord("在填色和描边之间转换"), KeyChord(modifiers: [], key: .character("x")))
        XCTAssertEqual(chord("把填色和描边设置为默认"), KeyChord(modifiers: [], key: .character("d")))
        XCTAssertEqual(chord("互换填色和描边"), KeyChord(modifiers: .shift, key: .character("x")))
        XCTAssertEqual(chord("选择渐变填色模式"), KeyChord(modifiers: [], key: .greaterThan))
        XCTAssertEqual(chord("选择颜色填充模式"), KeyChord(modifiers: [], key: .lessThan))
        XCTAssertEqual(chord("选择无描边/填充模式"), KeyChord(modifiers: [], key: .slash))
        XCTAssertEqual(chord("显示/隐藏“图层”面板"), KeyChord(modifiers: [], key: .function(7)))
        XCTAssertEqual(chord("显示/隐藏“属性”面板"), KeyChord(modifiers: .command, key: .function(11)))
        XCTAssertEqual(chord("显示/隐藏“路径查找器”面板"), KeyChord(modifiers: [.shift, .command], key: .function(9)))
        XCTAssertEqual(chord("恢复"), KeyChord(modifiers: [], key: .function(12)))
        XCTAssertEqual(chord("退出应用程序"), KeyChord(modifiers: .command, key: .character("q")))
        let font = Keymap.entry(title: "增加或减小字体大小")
        XCTAssertTrue(font?.chords.contains(KeyChord(modifiers: [.command, .shift], key: .period)) == true)
        XCTAssertTrue(font?.chords.contains(KeyChord(modifiers: [.command, .shift], key: .comma)) == true)
        let arrows = Keymap.entry(title: "以用户定义的增量移动选区")
        XCTAssertEqual(Set(arrows?.chords.map(\.key) ?? []), Set([.left, .right, .up, .down]))
        XCTAssertEqual(Keymap.entries.filter { $0.chords.isEmpty }.count > 0, true)
        XCTAssertEqual(Keymap.toolForTitle.count >= 40, true)
    }

    func testMenuSpecLabelsAndAccelerators() {
        let required = [
            "文件", "新建", "从模板新建", "打开", "最近打开的文件", "关闭", "存储", "存储为", "存储副本", "恢复",
            "置入", "导出", "导出为多种屏幕所用格式", "导出为…", "存储为Web所用格式", "打包", "文档设置", "文档颜色模式",
            "文件信息", "打印",
            "编辑", "还原", "重做", "剪切", "复制", "粘贴", "贴在前面", "贴在后面", "就地粘贴", "在所有画板上粘贴",
            "清除", "查找和替换", "拼写检查", "编辑颜色", "颜色设置", "键盘快捷键",
            "对象", "变换", "再次变换", "移动", "旋转", "对称", "缩放", "倾斜", "分别变换", "重置定界框",
            "排列", "置于顶层", "前移一层", "后移一层", "置于底层", "对齐", "编组", "取消编组",
            "锁定", "全部解锁", "隐藏", "显示全部", "扩展", "扩展外观", "栅格化", "路径", "连接", "平均",
            "轮廓化描边", "偏移路径", "简化", "形状", "图案", "混合", "封套扭曲", "实时上色", "图像描摹",
            "剪切蒙版", "复合路径", "画板",
            "文字", "字体", "大小", "区域文字选项", "路径文字", "创建轮廓", "查找/替换字体", "显示隐藏字符",
            "选择", "全部", "现用画板上的全部对象", "取消选择", "重新选择", "反向", "上方的下一个对象", "下方的下一个对象",
            "相同", "对象", "存储所选对象",
            "效果", "应用上一个效果", "上一个效果", "文档栅格效果设置", "3D和材质", "SVG滤镜", "变形", "扭曲和变换",
            "路径查找器", "转换为形状", "风格化", "投影", "内发光", "外发光", "圆角", "羽化", "涂抹",
            "视图", "轮廓", "GPU预览", "叠印预览", "像素预览", "放大", "缩小", "画板适合窗口大小", "全部适合窗口大小",
            "实际大小", "隐藏边缘", "隐藏画板", "隐藏定界框", "显示透明度网格", "标尺", "显示标尺", "更改为画板标尺",
            "参考线", "隐藏参考线", "锁定参考线", "建立参考线", "释放参考线", "智能参考线", "透视网格", "显示网格",
            "对齐网格", "对齐点",
            "窗口", "工作区", "基本功能", "传统基本功能", "属性", "图层", "颜色", "画笔", "描边", "渐变", "信息",
            "透明度", "外观", "对齐", "变换", "符号", "图形样式", "字符", "段落", "制表符", "OpenType", "色板",
            "资源导出", "工具栏", "高级",
            "帮助"
        ]
        let titles = Set(MenuCatalog.flattened().map(\.title))
        for name in required {
            XCTAssertTrue(titles.contains(name), "missing menu \(name)")
        }
        func chord(_ path: [String]) -> KeyChord? {
            guard let node = MenuCatalog.bar.first(where: { _ in true })?.find(path: path) ?? MenuCatalog.fileMenu.find(path: path) else {
                return MenuCatalog.flattened().first { $0.title == path.last }?.explicit
            }
            return MenuCatalog.menuChord(for: node)
        }
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "新建" }!), KeyChord(modifiers: .command, key: .character("n")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "存储" }!), KeyChord(modifiers: .command, key: .character("s")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "还原" }!), KeyChord(modifiers: .command, key: .character("z")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "编组" }!), KeyChord(modifiers: .command, key: .character("g")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "画板适合窗口大小" }!), KeyChord(modifiers: .command, key: .character("0")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "隐藏边缘" }!), KeyChord(modifiers: .command, key: .character("h")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "显示标尺" }!), KeyChord(modifiers: .command, key: .character("r")))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "下方的下一个对象" }!), KeyChord(modifiers: [.option, .command], key: .leftBracket))
        XCTAssertEqual(MenuCatalog.menuChord(for: MenuCatalog.flattened().first { $0.title == "图层" && $0.action.contains("图层") }!), KeyChord(modifiers: [], key: .function(7)))
        _ = chord
    }
}

final class KYSTests: XCTestCase {
    func testImportExportTextAndKYS() {
        let text = """
        集: 工作室
        创建文档\tCommand+N
        选择工具\tV
        还原\tCommand+Z
        """
        let set = ShortcutSetImporter.parse(text)
        XCTAssertEqual(set.name, "工作室")
        XCTAssertEqual(set.overrides.count, 3)
        XCTAssertEqual(set.overrides[0].chord, KeyChord(modifiers: .command, key: .character("n")))
        XCTAssertEqual(set.overrides[1].chord, KeyChord(modifiers: [], key: .character("v")))

        let kys = """
        /version 1
        /name [夜间]
        /command [编组选定图稿] /shortcut [Command+G]
        /tool [选择工具] /shortcut [V]
        """
        let imported = ShortcutSetImporter.parse(kys)
        XCTAssertEqual(imported.name, "夜间")
        XCTAssertEqual(imported.overrides.count, 2)
        let map = UserKeymap()
        map.apply(imported)
        XCTAssertEqual(map.chord(for: "编组选定图稿"), KeyChord(modifiers: .command, key: .character("g")))
        let exported = ShortcutSetImporter.exportText(name: "墨线")
        XCTAssertTrue(exported.contains("还原"))
        XCTAssertTrue(ShortcutSetImporter.parse(exported).overrides.count > 100)
    }
}

final class PathfinderTests: XCTestCase {
    func testRectangleBoolean() {
        let a = [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100), Vec2(0, 100)]
        let b = [Vec2(50, 50), Vec2(150, 50), Vec2(150, 150), Vec2(50, 150)]
        let union = Pathfinder.apply(.unite, subject: a, clip: b)
        let (unionBox, unionArea) = Pathfinder.boundsArea(union)
        XCTAssertEqual(unionBox.minX, 0, accuracy: 0.05)
        XCTAssertEqual(unionBox.minY, 0, accuracy: 0.05)
        XCTAssertEqual(unionBox.maxX, 150, accuracy: 0.05)
        XCTAssertEqual(unionBox.maxY, 150, accuracy: 0.05)
        XCTAssertEqual(unionArea, 17500, accuracy: 1)

        let inter = Pathfinder.apply(.intersect, subject: a, clip: b)
        let (interBox, interArea) = Pathfinder.boundsArea(inter)
        XCTAssertEqual(interBox.minX, 50, accuracy: 0.05)
        XCTAssertEqual(interBox.minY, 50, accuracy: 0.05)
        XCTAssertEqual(interBox.maxX, 100, accuracy: 0.05)
        XCTAssertEqual(interBox.maxY, 100, accuracy: 0.05)
        XCTAssertEqual(interArea, 2500, accuracy: 1)

        let diff = Pathfinder.apply(.minusFront, subject: a, clip: b)
        let (_, diffArea) = Pathfinder.boundsArea(diff)
        XCTAssertEqual(diffArea, 7500, accuracy: 1)
    }
}

final class SVGRoundTripTests: XCTestCase {
    func testShapesTextGradientGroup() throws {
        var doc = LaminaDocument.blank(title: "往返", size: Vec2(640, 480))
        doc.artboards.append(Artboard(name: "画板 2", rect: Rect2(x: 700, y: 0, width: 200, height: 200)))
        let rect = PathObject(name: "矩形", path: PathBuilder.rectangle(Rect2(x: 20, y: 30, width: 100, height: 40)))
        let oval = PathObject(name: "椭圆", path: PathBuilder.ellipse(Rect2(x: 150, y: 40, width: 80, height: 50)), appearance: Appearance(fill: .linear(.blackWhite), stroke: StrokeStyle(width: 2)))
        let star = PathObject(name: "星形", path: PathBuilder.star(center: Vec2(300, 80), radius: 30, points: 5, innerRatio: 0.4), appearance: Appearance(fill: .solid(RGBA(hex: "#E34850")), stroke: nil))
        var curve = PathBuilder.line(Vec2(10, 200), Vec2(80, 220))
        curve.nodes[0].outHandle = Vec2(30, 160)
        curve.nodes[1].inHandle = Vec2(60, 250)
        curve.shape = .free
        let path = PathObject(name: "曲线", path: curve, appearance: Appearance(fill: nil, stroke: StrokeStyle(paint: .solid(RGBA(hex: "#1473E6")), width: 3)))
        let text = TextObject(name: "标题", string: "墨线", origin: Vec2(40, 180), fontName: "PingFang SC", fontSize: 28)
        let child = PathObject(name: "子项", path: PathBuilder.rectangle(Rect2(x: 0, y: 0, width: 10, height: 10)))
        let group = GroupObject(name: "组", children: [.path(child)])
        doc.layers[0].items = [.path(rect), .path(oval), .path(star), .path(path), .text(text), .group(group)]
        let svg = SVGCodec.write(doc)
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("linearGradient"))
        XCTAssertTrue(svg.contains("墨线"))
        let back = try SVGCodec.read(svg)
        XCTAssertEqual(back.title, "往返")
        XCTAssertEqual(back.artboards.count, 2)
        XCTAssertEqual(back.artboards[0].rect.width, 640, accuracy: 0.01)
        XCTAssertEqual(back.layers.count, 1)
        XCTAssertEqual(back.layers[0].items.count, 6)
        guard case .path(let r2) = back.layers[0].items[0] else { return XCTFail("rect") }
        XCTAssertEqual(r2.id, rect.id)
        XCTAssertEqual(r2.path.nodes.count, 4)
        XCTAssertEqual(r2.path.nodes[2].anchor.x, 120, accuracy: 0.02)
        XCTAssertEqual(r2.path.nodes[2].anchor.y, 70, accuracy: 0.02)
        guard case .path(let e2) = back.layers[0].items[1] else { return XCTFail("ellipse") }
        if case .linear(let g) = e2.appearance.fill {
            XCTAssertEqual(g.stops.count, 2)
        } else {
            XCTFail("expected linear gradient")
        }
        guard case .text(let t2) = back.layers[0].items[4] else { return XCTFail("text") }
        XCTAssertEqual(t2.string, "墨线")
        XCTAssertEqual(t2.fontSize, 28, accuracy: 0.01)
        guard case .group(let g2) = back.layers[0].items[5] else { return XCTFail("group") }
        XCTAssertEqual(g2.children.count, 1)
        guard case .path(let curveBack) = back.layers[0].items[3] else { return XCTFail("curve") }
        XCTAssertEqual(curveBack.path.nodes[0].outHandle?.x ?? -1, 30, accuracy: 0.05)
    }
}

final class AIRoundTripTests: XCTestCase {
    func testNativeJSONSurvivesPDF() throws {
        var doc = LaminaDocument.blank(title: "档案", size: Vec2(400, 300))
        doc.colorMode = .cmyk
        doc.rasterPPI = 150
        doc.guides = [Guide(axis: .vertical, position: 40)]
        let rect = PathObject(name: "矩形", path: PathBuilder.rectangle(Rect2(x: 10, y: 12, width: 80, height: 40)), appearance: Appearance(fill: .solid(RGBA(hex: "#112233")), stroke: StrokeStyle(width: 2)))
        let text = TextObject(string: "Hello 墨线", origin: Vec2(20, 80), fontSize: 18)
        let group = GroupObject(name: "组", children: [.path(PathObject(path: PathBuilder.ellipse(Rect2(x: 5, y: 5, width: 20, height: 10))))])
        doc.layers[0].items = [.path(rect), .text(text), .group(group)]
        doc.swatches.append(Swatch(name: "品牌", paint: .solid(RGBA(hex: "#ABCDEF"))))
        let data = try AIFile.data(from: doc)
        let header = String(data: data.prefix(5), encoding: .ascii)
        XCTAssertEqual(header, "%PDF-")
        XCTAssertTrue(data.range(of: Data("%%EOF".utf8)) != nil)
        let back = try AIFile.document(from: data)
        XCTAssertEqual(back, doc)
        XCTAssertEqual(back.layers[0].items.count, 3)
        XCTAssertEqual(back.colorMode, .cmyk)
        XCTAssertEqual(back.guides.count, 1)
    }
}

final class EditorTests: XCTestCase {
    func testDrawSelectMoveUndoGroupClipCompound() {
        let model = EditorModel()
        model.tool = .rectangle
        model.pointerDown(at: Vec2(10, 10), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(110, 60), shift: false, option: false, command: false)
        model.tool = .ellipse
        model.pointerDown(at: Vec2(40, 30), shift: false, option: false, command: false)
        model.pointerUp(at: Vec2(90, 80), shift: false, option: false, command: false)
        XCTAssertEqual(model.document.layers[0].items.count, 2)
        model.perform("全选")
        XCTAssertEqual(model.selection.count, 2)
        let before = ItemGeometry.bounds(model.document.item(id: model.selection[0])!)
        model.tool = .selection
        model.pointerDown(at: before.center, shift: false, option: false, command: false)
        model.pointerDrag(to: before.center + Vec2(15, 5), shift: false, option: false, command: false)
        model.pointerUp(at: before.center + Vec2(15, 5), shift: false, option: false, command: false)
        let after = ItemGeometry.bounds(model.document.item(id: model.selection[0])!)
        XCTAssertEqual(after.minX, before.minX + 15, accuracy: 0.01)
        model.undo()
        let undone = ItemGeometry.bounds(model.document.item(id: model.selection[0])!)
        XCTAssertEqual(undone.minX, before.minX, accuracy: 0.01)
        model.redo()
        model.perform("全选")
        model.perform("编组选定图稿")
        XCTAssertEqual(model.document.layers[0].items.count, 1)
        if case .group(let g) = model.document.layers[0].items[0] {
            XCTAssertEqual(g.children.count, 2)
        } else {
            XCTFail("group")
        }
        model.undo()
        model.perform("全选")
        model.perform("创建复合路径")
        if case .compound = model.document.layers[0].items.last {
        } else { XCTFail("compound") }
        model.perform("释放复合路径")
        XCTAssertGreaterThanOrEqual(model.document.layers[0].items.count, 2)
        model.perform("全选")
        model.perform("创建剪切蒙版")
        if case .clip = model.document.layers[0].items.last {} else { XCTFail("clip") }
        model.perform("路径查找器 联集")
        model.keyDown(chord: KeyChord(modifiers: [], key: .character("v")))
        XCTAssertEqual(model.tool, .selection)
        model.keyDown(chord: KeyChord(modifiers: .command, key: .character("a")))
        XCTAssertFalse(model.selection.isEmpty)
        model.perform("在填色和描边之间转换")
        XCTAssertFalse(model.activeAttrIsFill)
        model.perform("选择无描边/填充模式")
        model.perform("添加图层")
        XCTAssertEqual(model.document.layers.count, 2)
        model.perform("新建画板")
        XCTAssertEqual(model.document.artboards.count, 2)
    }

    func testPenAndTextAndAIParse() throws {
        let model = EditorModel()
        model.tool = .pen
        model.pointerDown(at: Vec2(0, 0), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(20, 0), shift: false, option: false, command: false)
        model.pointerDown(at: Vec2(20, 20), shift: false, option: false, command: false)
        model.finishPen()
        XCTAssertEqual(model.document.objectCount, 1)
        model.tool = .text
        model.pointerDown(at: Vec2(5, 40), shift: false, option: false, command: false)
        XCTAssertNotNil(model.editingText)
        let svg = """
        ```svg
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="1" y="2" width="3" height="4"/></svg>
        ```
        """
        let extracted = AIResponseParser.extractSVG(svg)
        XCTAssertTrue(extracted?.contains("<rect") == true)
        try model.insertSVG(extracted!)
        XCTAssertGreaterThan(model.document.objectCount, 1)
        let palette = AIResponseParser.extractPalette("[{" + "\"name\":\"海\",\"hex\":\"#1144AA\"},{\"name\":\"沙\",\"hex\":\"#E6D3A3\"}]")
        XCTAssertEqual(palette.count, 2)
        model.addPalette(palette)
        XCTAssertTrue(model.document.swatches.contains { $0.name == "海" })
    }
}
