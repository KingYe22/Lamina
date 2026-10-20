import AppKit
import LaminaCore

enum ToolTips {
    static func heading(_ tool: Tool) -> String {
        let name = Keymap.toolForTitle.first { $0.value == tool }?.key ?? "\(tool.title)工具"
        guard let chord = Keymap.chords(forTitle: name).first else { return name }
        return "\(name) (\(chord.display))"
    }

    static func body(_ tool: Tool) -> String {
        switch tool {
        case .selection: return "单击选择对象，拖移绘制选框。按住 Shift 加选。"
        case .directSelection: return "选择锚点或路径段，拖移以调整形状。"
        case .groupSelection: return "在组内逐级选择对象。"
        case .magicWand: return "按填色或描边的相似度选择对象。"
        case .lasso: return "自由圈选锚点或对象。"
        case .pen: return "单击放置锚点，拖移拉出方向线。靠近起点可闭合。"
        case .addAnchor: return "在路径上单击以添加锚点。"
        case .deleteAnchor: return "单击锚点将其从路径上删除。"
        case .convertAnchor: return "在角点和平滑点之间转换，拖移可拉出手柄。"
        case .curvature: return "单击放置点，路径会自动弯曲。双击可切换角点。"
        case .text: return "单击创建点文字，拖移创建区域文字。"
        case .areaText: return "拖移一个区域，文字在其中折行。"
        case .pathText: return "在路径上放置并排列文字。"
        case .verticalText: return "创建直排文字。"
        case .touchType: return "单独移动、缩放或旋转文字中的字符。"
        case .line: return "拖移绘制直线。按住 Shift 限制为 45°。"
        case .arc: return "拖移绘制弧线。按住 Shift 得到四分之一圆。"
        case .spiral: return "拖移绘制螺旋线。"
        case .rectGrid: return "拖移绘制矩形网格。"
        case .polarGrid: return "拖移绘制同心圆和放射分割。"
        case .rectangle: return "拖移绘制矩形。按住 Shift 绘制正方形，按住 Option 从中心绘制。"
        case .roundedRectangle: return "拖移绘制圆角矩形。按住 Shift 等比，按住 Option 从中心绘制。"
        case .ellipse: return "拖移绘制椭圆。按住 Shift 绘制正圆，按住 Option 从中心绘制。"
        case .polygon: return "拖移绘制多边形。拖动时按上下方向键增减边数。"
        case .star: return "拖移绘制星形。拖动时按上下方向键增减角数。"
        case .flare: return "拖移绘制镜头光晕。"
        case .brush: return "拖移绘制画笔笔迹，松开后生成路径。"
        case .blobBrush: return "拖移绘制填色的斑点形状。"
        case .pencil: return "拖移徒手画线，松开后拟合为路径。"
        case .smooth: return "沿路径拖移，使锚点变得平滑。"
        case .pathEraser: return "沿路径拖移，擦掉经过的一段。"
        case .joinTool: return "拖过两个端点，将它们连接起来。"
        case .shaper: return "徒手画出矩形或椭圆，松手后识别为形状。"
        case .eraser: return "拖移擦除经过的图稿。"
        case .scissors: return "在路径上单击，将其剪开。"
        case .knife: return "拖移把图稿切成独立的部分。"
        case .rotate: return "拖移使所选对象绕中心旋转。按住 Shift 限制角度。"
        case .reflect: return "拖移指定镜像轴，翻转所选对象。"
        case .scale: return "拖移缩放所选对象。按住 Shift 保持比例。"
        case .shear: return "拖移使所选对象倾斜。"
        case .reshape: return "拖移路径段，让形状跟着变形。"
        case .width: return "在描边上拖移，改变该处的线宽。"
        case .freeTransform: return "拖移控制点缩放、旋转或扭曲所选对象。"
        case .gradient: return "在对象上拖移，设置渐变的方向和长度。"
        case .mesh: return "单击对象，添加渐变网格点。"
        case .eyedropper: return "单击图稿，拾取它的填色和描边。"
        case .measure: return "拖移测量两点之间的距离和角度。"
        case .hand: return "拖移平移画布。绘制时按住空格可临时移动形状。"
        case .zoom: return "单击放大，按住 Option 单击缩小，拖移可框选缩放。"
        default: return "在画板上单击或拖移以使用\(tool.title)。"
        }
    }
}

/// Illustrator-style two-line tooltip. It lives in the window so screenshots include it.
final class RichTooltip: NSView {
    static let shared = RichTooltip(frame: .zero)
    private var title = ""
    private var body = ""

    func show(from view: NSView, localPoint: NSPoint, title: String, body: String) {
        self.title = title
        self.body = body
        let titleFont = Theme.ui(12, weight: .semibold)
        let bodyFont = Theme.ui(12)
        let titleSize = (title as NSString).size(withAttributes: [.font: titleFont])
        let bodyRect = (body as NSString).boundingRect(
            with: NSSize(width: 144, height: 120),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont]
        )
        let width = min(160, max(titleSize.width, bodyRect.width) + 16)
        let height = titleSize.height + bodyRect.height + 12
        guard let content = view.window?.contentView else { return }
        let windowPoint = view.convert(localPoint, to: nil)
        let origin = content.convert(windowPoint, from: nil)
        var frame = NSRect(x: origin.x + 22, y: origin.y - height + 8, width: min(width, 160), height: height)
        if frame.maxX > content.bounds.width - 8 { frame.origin.x = max(8, origin.x - frame.width - 8) }
        if frame.minY < 8 { frame.origin.y = 8 }
        self.frame = frame
        if superview !== content { content.addSubview(self, positioned: .above, relativeTo: nil) }
        needsDisplay = true
    }

    func hide() { removeFromSuperview() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        Theme.field.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
        Theme.fieldBorder.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        border.lineWidth = 1
        border.stroke()
        let titleFont = Theme.ui(12, weight: .semibold)
        let bodyFont = Theme.ui(12)
        (title as NSString).draw(at: NSPoint(x: 8, y: bounds.height - 18), withAttributes: [
            .font: titleFont, .foregroundColor: Theme.text
        ])
        (body as NSString).draw(
            with: NSRect(x: 8, y: 4, width: bounds.width - 16, height: bounds.height - 22),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont, .foregroundColor: Theme.text]
        )
    }
}

enum Hover {
    static func install(on view: NSView) {
        for area in view.trackingAreas { view.removeTrackingArea(area) }
        view.addTrackingArea(NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: view,
            userInfo: nil
        ))
    }
}
