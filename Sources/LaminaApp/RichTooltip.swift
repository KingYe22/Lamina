import AppKit
import LaminaCore

enum ToolTips {
    static func parts(_ tool: Tool) -> (name: String, shortcut: String?) {
        let name = Keymap.toolForTitle.first { $0.value == tool }?.key ?? "\(tool.title)工具"
        let shortcut = Keymap.chords(forTitle: name).first?.display
        return (name, shortcut)
    }

    static func heading(_ tool: Tool) -> String {
        let part = parts(tool)
        guard let shortcut = part.shortcut else { return part.name }
        return "\(part.name) (\(shortcut))"
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

/// Illustrator rich tool card: white surface, title, shortcut badge, and body.
/// Tool tips also show a preview band and 「了解详细信息」. It lives in the window so screenshots include it.
final class RichTooltip: NSView {
    static let shared = RichTooltip(frame: .zero)
    private var title = ""
    private var body = ""
    private var shortcut: String?
    private var previewTool: Tool?
    private let shadowPad: CGFloat = 12
    private let cardWidth: CGFloat = 252
    private let previewHeight: CGFloat = 118

    func show(from view: NSView, localPoint: NSPoint, title: String, body: String, tool: Tool? = nil) {
        if let tool {
            let part = ToolTips.parts(tool)
            self.title = part.name
            self.shortcut = part.shortcut
            self.previewTool = tool
        } else {
            self.title = title
            self.shortcut = nil
            self.previewTool = nil
        }
        self.body = body
        let bodyFont = Theme.ui(12)
        let bodyWidth = cardWidth - 28
        let bodyRect = (body as NSString).boundingRect(
            with: NSSize(width: bodyWidth, height: 180),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont]
        )
        let learn: CGFloat = tool == nil ? 8 : 40
        let cardHeight = (tool == nil ? 16 : previewHeight + 14) + 22 + ceil(bodyRect.height) + learn
        let width = cardWidth + shadowPad * 2
        let height = cardHeight + shadowPad * 2
        guard let content = view.window?.contentView else { return }
        let windowPoint = view.convert(localPoint, to: nil)
        let origin = content.convert(windowPoint, from: nil)
        var x = origin.x + 18
        if view.bounds.width <= 120 {
            let edge = view.convert(NSPoint(x: view.bounds.maxX, y: localPoint.y), to: nil)
            x = content.convert(edge, from: nil).x + 10
        }
        var frame = NSRect(x: x, y: origin.y - height + shadowPad + 28, width: width, height: height)
        if frame.maxX > content.bounds.width - 8 { frame.origin.x = max(8, content.bounds.width - frame.width - 8) }
        if frame.minX < 8 { frame.origin.x = 8 }
        if frame.minY < 8 { frame.origin.y = 8 }
        if frame.maxY > content.bounds.height - 8 { frame.origin.y = max(8, content.bounds.height - frame.height - 8) }
        self.frame = frame
        if superview !== content { content.addSubview(self, positioned: .above, relativeTo: nil) }
        needsDisplay = true
    }

    func hide() { removeFromSuperview() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: shadowPad, dy: shadowPad)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 16
        shadow.set()
        NSColor.white.setFill()
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
        cardPath.fill()
        NSShadow().set()

        let textTop: CGFloat
        if let tool = previewTool {
            let preview = NSRect(x: card.minX, y: card.maxY - previewHeight, width: card.width, height: previewHeight)
            NSGraphicsContext.saveGraphicsState()
            cardPath.addClip()
            drawPreview(preview, tool: tool)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1).setFill()
            NSRect(x: card.minX, y: preview.minY, width: card.width, height: 1).fill()
            textTop = preview.minY - 16
        } else {
            textTop = card.maxY - 18
        }

        let titleFont = Theme.ui(13, weight: .semibold)
        let titleColor = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
        (title as NSString).draw(at: NSPoint(x: card.minX + 14, y: textTop - 4), withAttributes: [
            .font: titleFont, .foregroundColor: titleColor
        ])
        if let shortcut, !shortcut.isEmpty {
            drawBadge(shortcut, in: card, baseline: textTop - 6)
        }

        let bodyFont = Theme.ui(12)
        let bodyColor = NSColor(srgbRed: 0.28, green: 0.28, blue: 0.30, alpha: 1)
        let bodyBottom = card.minY + (previewTool == nil ? 12 : 42)
        let bodyRect = NSRect(
            x: card.minX + 14,
            y: bodyBottom,
            width: card.width - 28,
            height: max(18, textTop - 22 - bodyBottom)
        )
        (body as NSString).draw(
            with: bodyRect,
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont, .foregroundColor: bodyColor]
        )
        if previewTool != nil {
            drawLearnMore(in: card)
        }

        NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()
    }

    /// Original preview, not a copy of Illustrator's sample photograph.
    private func drawPreview(_ rect: NSRect, tool: Tool) {
        let sky = NSGradient(colors: [
            NSColor(srgbRed: 0.80, green: 0.86, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.90, blue: 0.84, alpha: 1)
        ])
        sky?.draw(in: rect, angle: -90)
        let hill = NSBezierPath()
        hill.move(to: NSPoint(x: rect.minX, y: rect.minY))
        hill.line(to: NSPoint(x: rect.minX, y: rect.minY + rect.height * 0.28))
        hill.curve(
            to: NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.46),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.50),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.22)
        )
        hill.curve(
            to: NSPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22),
            controlPoint1: NSPoint(x: rect.midX + rect.width * 0.16, y: rect.minY + rect.height * 0.62),
            controlPoint2: NSPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.18)
        )
        hill.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        hill.close()
        NSColor(srgbRed: 0.42, green: 0.55, blue: 0.74, alpha: 1).setFill()
        hill.fill()
        let mark = NSRect(x: rect.midX - 16, y: rect.midY - 4, width: 32, height: 32)
        drawMark(tool, in: mark)
    }

    private func drawMark(_ tool: Tool, in box: NSRect) {
        NSColor.black.setStroke()
        NSColor.white.setFill()
        switch tool {
        case .zoom:
            let glass = NSRect(x: box.minX, y: box.minY + 8, width: 18, height: 18)
            NSBezierPath(ovalIn: glass).fill()
            let ring = NSBezierPath(ovalIn: glass.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.8
            ring.stroke()
            let plus = NSBezierPath()
            plus.move(to: NSPoint(x: glass.midX - 4, y: glass.midY))
            plus.line(to: NSPoint(x: glass.midX + 4, y: glass.midY))
            plus.move(to: NSPoint(x: glass.midX, y: glass.midY - 4))
            plus.line(to: NSPoint(x: glass.midX, y: glass.midY + 4))
            plus.lineWidth = 1.6
            plus.stroke()
            let handle = NSBezierPath()
            handle.lineWidth = 2.4
            handle.lineCapStyle = .round
            handle.move(to: NSPoint(x: glass.maxX - 3, y: glass.minY + 3))
            handle.line(to: NSPoint(x: box.maxX - 1, y: box.minY + 2))
            handle.stroke()
        case .brush:
            let brush = NSBezierPath()
            brush.lineWidth = 3.2
            brush.lineCapStyle = .round
            brush.move(to: NSPoint(x: box.minX + 4, y: box.minY + 6))
            brush.line(to: NSPoint(x: box.maxX - 4, y: box.maxY - 4))
            brush.stroke()
            NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.minY + 2, width: 7, height: 7)).fill()
            NSBezierPath(ovalIn: NSRect(x: box.minX + 1, y: box.minY + 2, width: 7, height: 7)).stroke()
        case .rectangle, .roundedRectangle, .ellipse, .polygon, .star, .line, .arc, .flare, .spiral:
            let cross = NSBezierPath()
            cross.lineWidth = 2
            cross.lineCapStyle = .round
            cross.move(to: NSPoint(x: box.midX, y: box.minY + 4))
            cross.line(to: NSPoint(x: box.midX, y: box.midY - 3))
            cross.move(to: NSPoint(x: box.midX, y: box.midY + 3))
            cross.line(to: NSPoint(x: box.midX, y: box.maxY - 4))
            cross.move(to: NSPoint(x: box.minX + 4, y: box.midY))
            cross.line(to: NSPoint(x: box.midX - 3, y: box.midY))
            cross.move(to: NSPoint(x: box.midX + 3, y: box.midY))
            cross.line(to: NSPoint(x: box.maxX - 4, y: box.midY))
            cross.stroke()
        default:
            let chip = NSBezierPath(roundedRect: box.insetBy(dx: 4, dy: 6), xRadius: 3, yRadius: 3)
            chip.lineWidth = 1.6
            NSColor.white.setFill()
            chip.fill()
            chip.stroke()
        }
    }

    private func drawBadge(_ shortcut: String, in card: NSRect, baseline: CGFloat) {
        let font = Theme.ui(11, weight: .medium)
        let text = shortcut as NSString
        let size = text.size(withAttributes: [.font: font])
        let badge = NSRect(x: card.maxX - 14 - size.width - 14, y: baseline - 2, width: size.width + 14, height: 18)
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        NSColor(srgbRed: 0.78, green: 0.78, blue: 0.80, alpha: 1).setStroke()
        let edge = NSBezierPath(roundedRect: badge.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        edge.lineWidth = 1
        edge.stroke()
        text.draw(at: NSPoint(x: badge.minX + 7, y: badge.minY + 2), withAttributes: [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 1)
        ])
    }

    private func drawLearnMore(in card: NSRect) {
        let font = Theme.ui(12)
        let label = "了解详细信息" as NSString
        let size = label.size(withAttributes: [.font: font])
        let button = NSRect(
            x: card.midX - (size.width + 28) / 2,
            y: card.minY + 10,
            width: size.width + 28,
            height: 24
        )
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: button, xRadius: 12, yRadius: 12).fill()
        NSColor(srgbRed: 0.80, green: 0.80, blue: 0.82, alpha: 1).setStroke()
        let edge = NSBezierPath(roundedRect: button.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        edge.lineWidth = 1
        edge.stroke()
        label.draw(
            at: NSPoint(x: button.minX + 14, y: button.minY + 4),
            withAttributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)]
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
