import AppKit
import LaminaCore
import SwiftUI

struct DockRoot: View {
    @ObservedObject var workspace: Workspace
    @State private var settings = AISettings.load()
    @State private var apiKey = ""
    @State private var prompt = ""
    @State private var aiStatus = "密钥保存在登录钥匙串。"
    @State private var busy = false

    private var model: EditorModel { workspace.active.model }

    var body: some View {
        let _ = workspace.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(visiblePanels, id: \.self) { panel in
                    panelView(panel)
                }
                if visiblePanels.isEmpty {
                    Text("面板已隐藏。从“窗口”菜单打开属性或图层。")
                        .foregroundStyle(Color(nsColor: Theme.dim))
                        .font(.callout)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: Theme.panel))
        .onAppear { apiKey = KeychainStore.load(account: settings.provider.rawValue) ?? "" }
    }

    private var visiblePanels: [String] {
        let order = ["属性", "图层", "颜色", "色板", "描边", "渐变", "路径查找器", "对齐", "变换", "透明度", "外观", "画板", "信息", "字符", "段落", "AI", "首选项", "文档设置", "文件信息", "颜色设置", "键盘快捷键"]
        return order.filter { model.openPanels.contains($0) }
    }

    @ViewBuilder
    private func panelView(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name == "AI" ? "AI 助手" : name)
                .font(.headline)
                .foregroundStyle(Color(nsColor: Theme.text))
            switch name {
            case "属性": properties
            case "图层": layers
            case "颜色", "色板": swatches
            case "描边": strokeControls
            case "渐变": gradientControls
            case "路径查找器": pathfinder
            case "对齐": alignControls
            case "变换": transformInfo
            case "透明度": opacityControl
            case "外观": appearanceSummary
            case "画板": artboards
            case "信息": info
            case "字符", "段落": typeControls
            case "AI": aiPanel
            case "首选项": preferences
            case "文档设置": documentSettings
            case "文件信息": fileInfo
            case "颜色设置": colorSettings
            case "键盘快捷键": shortcutHelp
            default:
                Text(name)
            }
        }
        .padding(10)
        .background(Color(nsColor: Theme.raised))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selectionSummary).font(.callout).foregroundStyle(Color(nsColor: Theme.dim))
            if let box = model.selectionBounds() {
                Text(String(format: "X %.1f   Y %.1f", box.x, box.y))
                Text(String(format: "W %.1f   H %.1f", box.width, box.height))
            }
            strokeControls
            opacityControl
        }
    }

    private var selectionSummary: String {
        if model.selection.isEmpty { return "未选择对象" }
        let names = model.selection.prefix(3).compactMap { model.document.item(id: $0)?.name }
        return names.joined(separator: "、")
    }

    private var layers: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.document.layers.enumerated()), id: \.element.id) { index, layer in
                HStack {
                    Button(layer.visible ? "隐藏" : "显示") { workspace.toggleLayerVisible(index) }
                    Button(layer.locked ? "解锁" : "锁定") { workspace.toggleLayerLocked(index) }
                    Button(layer.name) { workspace.selectLayer(index) }
                        .buttonStyle(.plain)
                    Spacer()
                    Button("上") { workspace.moveLayer(index, by: -1) }
                    Button("下") { workspace.moveLayer(index, by: 1) }
                }
                .font(.callout)
            }
            if model.document.layers.allSatisfy(\.items.isEmpty) {
                Text("图层里还没有对象。").font(.callout).foregroundStyle(Color(nsColor: Theme.dim))
            }
            Button("添加图层") { workspace.perform("添加图层") }
        }
    }

    private var swatches: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 6)], spacing: 6) {
            ForEach(model.document.swatches) { swatch in
                Button {
                    if let color = swatch.paint.solidColor {
                        if model.activeAttrIsFill { workspace.applyFillHex(color.hex) }
                        else { workspace.applyStrokeHex(color.hex) }
                    } else {
                        model.currentFill = swatch.paint
                        model.applyFill(swatch.paint)
                        workspace.touch()
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: swatch.paint.solidColor?.nsColor ?? Theme.accent))
                        .frame(height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
        }
    }

    private var strokeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("描边 \(String(format: "%.1f pt", model.currentStroke?.width ?? 0))")
                .font(.callout)
            HStack {
                Button("0.5") { workspace.setStrokeWidth(0.5) }
                Button("1") { workspace.setStrokeWidth(1) }
                Button("2") { workspace.setStrokeWidth(2) }
                Button("4") { workspace.setStrokeWidth(4) }
                Button("无") { workspace.perform("选择无描边/填充模式") }
            }
            HStack {
                Button("均匀") { model.setWidthProfile(.uniform); workspace.touch() }
                Button("线性") { model.setWidthProfile(.linear); workspace.touch() }
                Button("三角") { model.setWidthProfile(.triangular); workspace.touch() }
                Button("椭圆") { model.setWidthProfile(.oval); workspace.touch() }
            }
        }
    }

    private var gradientControls: some View {
        HStack {
            Button("线性") {
                model.currentFill = .linear(.blackWhite)
                model.applyFill(.linear(.blackWhite))
                workspace.touch()
            }
            Button("径向") {
                var paint = GradientPaint.blackWhite
                paint.end = Vec2(0.5, 1)
                model.applyFill(.radial(paint))
                workspace.touch()
            }
        }
    }

    private var pathfinder: some View {
        HStack {
            Button("联集") { workspace.perform("路径查找器 联集") }
            Button("相减") { workspace.perform("路径查找器 相减") }
            Button("交集") { workspace.perform("路径查找器 交集") }
            Button("差集") { workspace.perform("路径查找器 差集") }
        }
    }

    private var alignControls: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("左") { workspace.perform("水平左对齐") }
                Button("中") { workspace.perform("水平居中对齐") }
                Button("右") { workspace.perform("水平右对齐") }
            }
            HStack {
                Button("上") { workspace.perform("垂直顶对齐") }
                Button("中") { workspace.perform("垂直居中对齐") }
                Button("下") { workspace.perform("垂直底对齐") }
            }
        }
    }

    private var transformInfo: some View {
        VStack(alignment: .leading) {
            if let box = model.selectionBounds() {
                Text(String(format: "%.1f, %.1f   %.1f × %.1f", box.x, box.y, box.width, box.height))
            } else {
                Text("选择对象后显示位置和尺寸。").foregroundStyle(Color(nsColor: Theme.dim))
            }
            HStack {
                Button("旋转 30°") { workspace.perform("旋转对话框") }
                Button("缩放 110%") { workspace.perform("缩放对话框") }
            }
        }
    }

    private var opacityControl: some View {
        HStack {
            Text("不透明度")
            Button("100%") { workspace.setOpacity(1) }
            Button("50%") { workspace.setOpacity(0.5) }
            Button("20%") { workspace.setOpacity(0.2) }
        }
        .font(.callout)
    }

    private var appearanceSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.activeAttrIsFill ? "当前目标：填色" : "当前目标：描边")
                .font(.callout)
            Text(appearanceDetail).font(.caption).foregroundStyle(Color(nsColor: Theme.dim))
            HStack {
                Button("再加填色") { model.addFillLayer(); workspace.touch() }
                Button("再加描边") { model.addStrokeLayer(); workspace.touch() }
            }
            Text("画笔库").font(.caption).foregroundStyle(Color(nsColor: Theme.dim))
            ForEach(model.brushLibrary) { preset in
                Button(preset.name) {
                    model.setBrush(preset.brush)
                    model.tool = .brush
                    workspace.touch()
                }
            }
            HStack {
                Button("叠印填色") { model.toggleOverprint(fill: true); workspace.touch() }
                Button("叠印描边") { model.toggleOverprint(fill: false); workspace.touch() }
            }
        }
    }

    private var appearanceDetail: String {
        guard let id = model.selection.first, let item = model.document.item(id: id) else {
            return "选择路径后可以叠多道填色和描边。"
        }
        let appearance = itemAppearance(item)
        let fills = appearance?.allFills.count ?? 0
        let strokes = appearance?.allStrokes.count ?? 0
        let over = (appearance?.overprintFill == true || appearance?.overprintStroke == true) ? " · 叠印" : ""
        return "\(fills) 道填色 · \(strokes) 道描边\(over)"
    }

    private func itemAppearance(_ item: ArtItem) -> Appearance? {
        switch item {
        case .path(let object): return object.appearance
        case .compound(let object): return object.appearance
        case .text(let object): return object.appearance
        default: return nil
        }
    }

    private var artboards: some View {
        VStack(alignment: .leading) {
            ForEach(Array(model.document.artboards.enumerated()), id: \.element.id) { index, board in
                Button(board.name) {
                    model.document.activeArtboard = index
                    model.fitArtboard()
                    workspace.touch()
                }
                .buttonStyle(.plain)
            }
            Button("新建画板") { workspace.perform("新建画板") }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.status).font(.callout)
            Text(String(format: "指针 %.1f, %.1f", model.hover.x, model.hover.y)).font(.callout)
            Text("\(model.document.objectCount) 个对象").font(.callout)
        }
    }

    private var typeControls: some View {
        VStack(alignment: .leading) {
            HStack {
                Button("加粗") { workspace.perform("加粗") }
                Button("斜体") { workspace.perform("斜体") }
                Button("下划线") { workspace.perform("下划线") }
            }
            HStack {
                Button("12") { workspace.perform("字号 12") }
                Button("24") { workspace.perform("字号 24") }
                Button("48") { workspace.perform("字号 48") }
                Button("轮廓") { workspace.perform("创建轮廓") }
            }
        }
    }

    private var aiPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AIProvider.allCases) { provider in
                        Button {
                            settings.provider = provider
                            settings.save()
                            apiKey = KeychainStore.load(account: provider.rawValue) ?? ""
                        } label: {
                            HStack(spacing: 6) {
                                ProviderMark(provider: provider)
                                Text(provider.title).font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(settings.provider == provider ? Color(nsColor: Theme.accent).opacity(0.35) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("模型", text: modelBinding)
                .textFieldStyle(.roundedBorder)
            if settings.provider == .custom {
                TextField("Base URL", text: $settings.customBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { settings.save() }
            }
            SecureField("API 密钥", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Button("存入钥匙串") {
                KeychainStore.save(account: settings.provider.rawValue, secret: apiKey)
                settings.save()
                aiStatus = "已写入钥匙串。"
            }
            TextField("描述要生成或修改的图形", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
            HStack {
                Button("文字生成 SVG") { runAI(.generate) }.disabled(busy)
                Button("按说明改选区") { runAI(.edit) }.disabled(busy)
                Button("生成色板") { runAI(.palette) }.disabled(busy)
            }
            Text(aiStatus).font(.caption).foregroundStyle(Color(nsColor: Theme.dim))
        }
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.model(for: settings.provider) },
            set: { newValue in
                settings.models[settings.provider.rawValue] = newValue
                settings.save()
            }
        )
    }

    private var preferences: some View {
        VStack(alignment: .leading) {
            Text("键盘微调 \(Int(model.nudge)) pt").font(.callout)
            HStack {
                Button("1 pt") { model.setNudge(1); workspace.touch() }
                Button("10 pt") { model.setNudge(10); workspace.touch() }
            }
        }
    }

    private var documentSettings: some View {
        VStack(alignment: .leading) {
            Text("单位 \(model.document.units.rawValue) · \(Int(model.document.rasterPPI)) ppi")
            HStack {
                Button("72 ppi") { model.document.rasterPPI = 72; workspace.touch() }
                Button("150") { model.document.rasterPPI = 150; workspace.touch() }
                Button("300") { model.document.rasterPPI = 300; workspace.touch() }
            }
        }
    }

    private var fileInfo: some View {
        VStack(alignment: .leading) {
            Text(model.document.title)
            Text("\(model.document.artboards.count) 个画板 · \(model.document.layers.count) 个图层 · \(model.document.objectCount) 个对象")
                .font(.callout)
                .foregroundStyle(Color(nsColor: Theme.dim))
        }
    }

    private var colorSettings: some View {
        HStack {
            Button("RGB") { workspace.perform("颜色模式 RGB") }
            Button("CMYK") { workspace.perform("颜色模式 CMYK") }
            Text(model.document.colorMode == .cmyk ? "当前 CMYK" : "当前 RGB")
                .font(.callout)
        }
    }

    private var shortcutHelp: some View {
        VStack(alignment: .leading) {
            Text("已载入 \(Keymap.entries.count) 条默认快捷键。").font(.callout)
            Text("当前集：\(model.keymap.setName)").font(.callout)
            Button("导入 .kys / 文本快捷键集") { workspace.importShortcuts() }
        }
    }

    private enum AITask { case generate, edit, palette }

    private func runAI(_ task: AITask) {
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            aiStatus = "先写一句说明。"
            return
        }
        settings.save()
        busy = true
        aiStatus = "正在请求 \(settings.provider.title)…"
        let snapshot = settings
        let selectionSVG = task == .edit ? Self.selectionSVG(model) : nil
        Task {
            do {
                switch task {
                case .generate:
                    let text = try await AIClient.complete(settings: snapshot, prompt: "只返回一个完整 SVG 文档，不要解释。图形：\(instruction)")
                    let svg = AIResponseParser.extractSVG(text) ?? ""
                    if svg.isEmpty { throw AIClientError.empty }
                    await MainActor.run {
                        try? model.insertSVG(svg)
                        aiStatus = "已插入 SVG。"
                    }
                case .edit:
                    guard let selectionSVG, selectionSVG.contains("<path") || selectionSVG.contains("<text") || selectionSVG.contains("<g") else {
                        throw AIClientError.badStatus(0, "先在画板上选中要修改的对象。")
                    }
                    let text = try await AIClient.complete(settings: snapshot, prompt: "下面是选区的 SVG。按说明修改后，只返回完整 SVG，不要解释。\n说明：\(instruction)\n\(selectionSVG)")
                    let svg = AIResponseParser.extractSVG(text) ?? ""
                    if svg.isEmpty { throw AIClientError.empty }
                    await MainActor.run {
                        model.deleteSelection(recordUndo: true)
                        try? model.insertSVG(svg)
                        aiStatus = "已按说明替换选区。"
                    }
                case .palette:
                    let text = try await AIClient.complete(settings: snapshot, prompt: "为主题“\(instruction)”生成 6 个配色。只返回 JSON 数组，每项包含 name 和 hex。")
                    let rows = AIResponseParser.extractPalette(text)
                    await MainActor.run {
                        if rows.isEmpty { aiStatus = "没有解析到色板。" }
                        else {
                            model.addPalette(rows)
                            aiStatus = "已添加 \(rows.count) 个色板。"
                        }
                    }
                }
            } catch {
                await MainActor.run { aiStatus = error.localizedDescription }
            }
            await MainActor.run {
                busy = false
                workspace.touch()
            }
        }
    }

    private static func selectionSVG(_ model: EditorModel) -> String? {
        let items = model.selection.compactMap { model.document.item(id: $0) }
        guard !items.isEmpty else { return nil }
        var document = LaminaDocument.blank(title: "选区", size: Vec2(800, 600))
        document.layers[0].items = items
        return SVGCodec.write(document)
    }
}

struct ProviderMark: View {
    var provider: AIProvider
    var body: some View {
        if let asset = provider.brandAsset {
            BrandSVGView(name: asset)
                .frame(width: asset == "deepseek" ? 44 : 22, height: 22)
                .accessibilityLabel(provider.title)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(red: provider.tint.0, green: provider.tint.1, blue: provider.tint.2))
                Text(provider.monogram)
                    .font(.system(size: provider.monogram.count > 2 ? 8 : 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            .accessibilityLabel(provider.title)
        }
    }
}
