import Foundation

/// Measured Illustrator 2026 values from the 0.4.13 comparison.
/// Numbers here are the live samples, not stand-ins.
public enum IllustratorZoom {
    /// Fixed zoom steps. The live samples are 33.33, 50, 66.67, 100 and 150,
    /// and a click from 87.79 lands on 100. The rest of the ladder is the same
    /// preset list those samples sit on.
    public static let steps: [Double] = [
        0.0313, 0.0417, 0.0625, 0.0833, 0.125, 0.1667, 0.25,
        0.3333, 0.5, 0.6667, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 64
    ]

    public static func next(_ zoom: Double, out: Bool) -> Double {
        if out {
            return steps.last { $0 < zoom - 0.0001 } ?? steps[0]
        }
        return steps.first { $0 > zoom + 0.0001 } ?? steps[steps.count - 1]
    }

    public static func percentLabel(_ zoom: Double) -> String {
        let percent = zoom * 100
        if abs(percent - percent.rounded()) < 0.005 {
            return String(format: "%.0f%%", locale: Locale(identifier: "en_US_POSIX"), percent)
        }
        return String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), percent)
    }
}

public enum IllustratorUnits {
    public static func points(fromMillimetres mm: Double) -> Double { mm * 72.0 / 25.4 }
    public static func millimetres(fromPoints points: Double) -> Double { points * 25.4 / 72.0 }

    /// `148.5` and `53.451`, trailing zeros dropped.
    public static func formatMillimetres(_ points: Double) -> String {
        var text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), millimetres(fromPoints: points))
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }

    public static func parseMillimetres(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "mm", with: "")
            .replacingOccurrences(of: "毫米", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let mm = Double(cleaned) else { return nil }
        return points(fromMillimetres: mm)
    }
}

/// Last shape-click sizes. The millimetre numbers are the live Illustrator samples.
public struct ShapeMemory: Equatable, Sendable {
    public var rectWidth = IllustratorUnits.points(fromMillimetres: 53.451)
    public var rectHeight = IllustratorUnits.points(fromMillimetres: 53.451)
    public var ellipseWidth = IllustratorUnits.points(fromMillimetres: 35.278)
    public var ellipseHeight = IllustratorUnits.points(fromMillimetres: 35.278)
    public var polygonRadius = IllustratorUnits.points(fromMillimetres: 17.639)
    public var polygonSides = 6
    public var starRadius1 = IllustratorUnits.points(fromMillimetres: 6.737)
    public var starRadius2 = IllustratorUnits.points(fromMillimetres: 17.639)
    public var starPoints = 5
    public var lineLength = IllustratorUnits.points(fromMillimetres: 35.278)
    public var lineAngle = 45.0
    public var lineFill = false
    public init() {}
}

public enum IllustratorParity {
    /// 描边 ▾ value list, in points.
    public static let strokeWeights: [Double] = [
        0.25, 0.5, 0.75, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 40, 60
    ]
    public static let miterLimit = 10.0
    public static let eraserDiameter = 10.0

    public static let hiddenShortcutTitles: Set<String> = [
        "全部适合窗口大小", "属性", "透视网格"
    ]

    /// Live Illustrator shows no shortcut on these three. The embedded table still has them.
    public static func chordSuppressed(_ action: String, _ chord: KeyChord) -> Bool {
        let optionCommandZero = KeyChord(modifiers: [.option, .command], key: .character("0"))
        let commandF11 = KeyChord(modifiers: .command, key: .function(11))
        let commandShiftI = KeyChord(modifiers: [.shift, .command], key: .character("i"))
        switch action {
        case "在窗口中查看所有画板": return chord == optionCommandZero
        case "显示/隐藏“属性”面板": return chord == commandF11
        case "显示/隐藏透视网格", "透视网格": return chord == commandShiftI
        default: return false
        }
    }

    public static func shapeDialog(_ tool: Tool, memory: ShapeMemory) -> DialogRequest? {
        switch tool {
        case .rectangle:
            return form("单击矩形", "矩形", [
                ("width", "宽度", IllustratorUnits.formatMillimetres(memory.rectWidth)),
                ("height", "高度", IllustratorUnits.formatMillimetres(memory.rectHeight)),
                ("link", "约束宽度和高度比例", "1")
            ])
        case .ellipse:
            return form("单击椭圆", "椭圆", [
                ("width", "宽度", IllustratorUnits.formatMillimetres(memory.ellipseWidth)),
                ("height", "高度", IllustratorUnits.formatMillimetres(memory.ellipseHeight)),
                ("link", "约束宽度和高度比例", "1")
            ])
        case .polygon:
            return form("单击多边形", "多边形", [
                ("radius", "半径", IllustratorUnits.formatMillimetres(memory.polygonRadius)),
                ("sides", "边数", "\(memory.polygonSides)")
            ])
        case .star:
            return form("单击星形", "星形", [
                ("radius1", "半径 1", IllustratorUnits.formatMillimetres(memory.starRadius1)),
                ("radius2", "半径 2", IllustratorUnits.formatMillimetres(memory.starRadius2)),
                ("points", "角点数", "\(memory.starPoints)")
            ])
        case .line:
            return form("单击直线段", "直线段工具选项", [
                ("length", "长度", IllustratorUnits.formatMillimetres(memory.lineLength)),
                ("angle", "角度", String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), memory.lineAngle)),
                ("fill", "线段填色", "check:0")
            ])
        default:
            return nil
        }
    }

    public static func rotateDialog() -> DialogRequest {
        DialogRequest(
            action: "旋转对话框",
            title: "旋转",
            fields: [
                DialogField(key: "degrees", label: "角度", value: "0"),
                DialogField(key: "objects", label: "变换对象", value: "check:1"),
                DialogField(key: "patterns", label: "变换图案", value: "check:0"),
                DialogField(key: "preview", label: "预览", value: "check:1")
            ],
            confirmTitle: "确定",
            cancelTitle: "取消",
            alternateTitle: "复制"
        )
    }

    public static func scaleDialog() -> DialogRequest {
        DialogRequest(
            action: "缩放对话框",
            title: "比例缩放",
            fields: [
                DialogField(key: "uniform", label: "等比", value: "1"),
                DialogField(key: "percent", label: "等比缩放", value: "100"),
                DialogField(key: "horizontal", label: "水平", value: "100"),
                DialogField(key: "vertical", label: "垂直", value: "100"),
                DialogField(key: "corners", label: "缩放圆角", value: "check:0"),
                DialogField(key: "strokes", label: "比例缩放描边和效果", value: "check:0"),
                DialogField(key: "objects", label: "变换对象", value: "check:1"),
                DialogField(key: "patterns", label: "变换图案", value: "check:0"),
                DialogField(key: "preview", label: "预览", value: "check:1")
            ],
            confirmTitle: "确定",
            cancelTitle: "取消",
            alternateTitle: "复制"
        )
    }

    public static func reflectDialog() -> DialogRequest {
        DialogRequest(
            action: "对称对话框",
            title: "镜像",
            fields: [
                DialogField(key: "axis", label: "轴", value: "v"),
                DialogField(key: "angle", label: "角度", value: "90"),
                DialogField(key: "objects", label: "变换对象", value: "check:1"),
                DialogField(key: "patterns", label: "变换图案", value: "check:0"),
                DialogField(key: "preview", label: "预览", value: "check:1")
            ],
            confirmTitle: "确定",
            cancelTitle: "取消",
            alternateTitle: "复制"
        )
    }

    public static func eyedropperDialog() -> DialogRequest {
        DialogRequest(
            action: "吸管选项",
            title: "吸管选项",
            fields: [
                DialogField(key: "raster", label: "栅格取样大小", value: "点取样"),
                DialogField(key: "pickAppearance", label: "吸管挑选 外观", value: "check:0"),
                DialogField(key: "pickTransparency", label: "吸管挑选 透明度", value: "check:1"),
                DialogField(key: "pickFill", label: "吸管挑选 焦点填色", value: "check:1"),
                DialogField(key: "pickFillColor", label: "吸管挑选 填色颜色", value: "check:1"),
                DialogField(key: "pickFillOpacity", label: "吸管挑选 填色透明度", value: "check:1"),
                DialogField(key: "pickFillOverprint", label: "吸管挑选 填色叠印", value: "check:1"),
                DialogField(key: "pickStroke", label: "吸管挑选 焦点描边", value: "check:1"),
                DialogField(key: "pickStrokeColor", label: "吸管挑选 描边颜色", value: "check:1"),
                DialogField(key: "pickStrokeOpacity", label: "吸管挑选 描边透明度", value: "check:1"),
                DialogField(key: "pickStrokeOverprint", label: "吸管挑选 描边叠印", value: "check:1"),
                DialogField(key: "pickStrokeWidth", label: "吸管挑选 描边粗细", value: "check:1"),
                DialogField(key: "pickCap", label: "吸管挑选 端点", value: "check:1"),
                DialogField(key: "pickJoin", label: "吸管挑选 连接", value: "check:1"),
                DialogField(key: "pickMiter", label: "吸管挑选 斜接限制", value: "check:1"),
                DialogField(key: "pickDash", label: "吸管挑选 虚线样式", value: "check:1"),
                DialogField(key: "pickCharacter", label: "吸管挑选 字符样式", value: "check:1"),
                DialogField(key: "pickParagraph", label: "吸管挑选 段落样式", value: "check:1"),
                DialogField(key: "applyAppearance", label: "吸管应用 外观", value: "check:0"),
                DialogField(key: "applyTransparency", label: "吸管应用 透明度", value: "check:1"),
                DialogField(key: "applyFill", label: "吸管应用 焦点填色", value: "check:1"),
                DialogField(key: "applyStroke", label: "吸管应用 焦点描边", value: "check:1"),
                DialogField(key: "applyCharacter", label: "吸管应用 字符样式", value: "check:1"),
                DialogField(key: "applyParagraph", label: "吸管应用 段落样式", value: "check:1")
            ]
        )
    }

    public static func eraserDialog(diameter: Double) -> DialogRequest {
        DialogRequest(
            action: "橡皮擦工具选项",
            title: "橡皮擦工具选项",
            fields: [
                DialogField(key: "angle", label: "角度", value: "0"),
                DialogField(key: "angleMode", label: "角度变化", value: "固定"),
                DialogField(key: "roundness", label: "圆度", value: "100"),
                DialogField(key: "roundnessMode", label: "圆度变化", value: "固定"),
                DialogField(key: "diameter", label: "大小", value: String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), diameter)),
                DialogField(key: "sizeMode", label: "大小变化", value: "固定")
            ],
            confirmTitle: "确定",
            cancelTitle: "取消",
            alternateTitle: "重置"
        )
    }

    public static func documentDialog() -> DialogRequest {
        DialogRequest(
            action: "应用文档设置",
            title: "文档设置",
            fields: [
                DialogField(key: "gridSize", label: "网格大小", value: "中"),
                DialogField(key: "gridColor", label: "网格颜色", value: "浅色"),
                DialogField(key: "paper", label: "模拟彩纸", value: "check:0"),
                DialogField(key: "preset", label: "预设", value: "中分辨率"),
                DialogField(key: "knockout", label: "放弃输出中的白色叠印", value: "check:1")
            ]
        )
    }

    public static func deleteAnchorAlert() -> DialogRequest {
        DialogRequest(
            action: "删除锚点提示",
            title: "请针对路径的锚点使用删除锚点工具。",
            fields: [DialogField(key: "silence", label: "不再显示", value: "check:0")]
        )
    }

    public static let layerMenu: [String] = [
        "新建图层...",
        "新建子图层...",
        "复制图层",
        "删除所选图层",
        "删除隐藏图层",
        "-",
        "图层选项...",
        "-",
        "建立剪切蒙版",
        "进入隔离模式",
        "退出隔离模式",
        "-",
        "定位对象",
        "-",
        "合并所选图层",
        "拼合图稿",
        "收集到新图层中",
        "-",
        "释放到图层（顺序）",
        "释放到图层（累积）",
        "反向顺序",
        "-",
        "模板",
        "隐藏所有图层",
        "轮廓化所有图层",
        "锁定所有图层",
        "-",
        "粘贴时记住图层",
        "-",
        "面板选项..."
    ]

    public static let transformMenu: [String] = [
        "隐藏选项",
        "创建形状时显示",
        "-",
        "水平翻转",
        "垂直翻转",
        "-",
        "缩放描边和效果",
        "-",
        "仅变换对象",
        "仅变换图案",
        "变换两者",
        "-",
        "使用符号的套版色点"
    ]

    public static let contextSelected = ["生成矢量", "编辑路径", "填色", "描边", "边角", "•••"]
    public static let contextEmpty = ["生成矢量", "绘制（铅笔）"]

    private static func form(_ action: String, _ title: String, _ rows: [(String, String, String)]) -> DialogRequest {
        DialogRequest(action: action, title: title, fields: rows.map { DialogField(key: $0.0, label: $0.1, value: $0.2) })
    }
}

public struct SelectionReadout: Equatable, Sendable {
    public var name: String
    public var x: String
    public var y: String
    public var width: String
    public var height: String
    public var stroke: String
    public var opacity: String

    public init(name: String, x: String, y: String, width: String, height: String, stroke: String, opacity: String) {
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.stroke = stroke
        self.opacity = opacity
    }
}
