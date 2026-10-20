import Foundation

public struct MenuNode: Equatable, Sendable {
    public var title: String
    public var action: String
    public var lookup: String?
    public var explicit: KeyChord?
    public var children: [MenuNode]

    public init(title: String, action: String? = nil, lookup: String? = nil, explicit: KeyChord? = nil, children: [MenuNode] = []) {
        self.title = title
        self.action = action ?? MenuCatalog.resolve(title)
        self.lookup = lookup
        self.explicit = explicit
        self.children = children
    }

    public var isSeparator: Bool { title == "-" }

    public func find(path: [String]) -> MenuNode? {
        guard let first = path.first else { return self }
        if title == first {
            if path.count == 1 { return self }
            for child in children {
                if let found = child.find(path: Array(path.dropFirst())) { return found }
            }
        }
        for child in children {
            if let found = child.find(path: path) { return found }
        }
        return nil
    }
}

public enum MenuCatalog {
    public static let aliases: [String: String] = [
        "新建": "创建文档",
        "从模板新建": "从模板创建文档",
        "打开": "打开文档",
        "关闭": "关闭文档窗口",
        "存储": "存储对文档所做的更改",
        "存储为": "打开“存储为”对话框",
        "存储副本": "存储文档的副本",
        "置入": "将文件置入文档",
        "导出为多种屏幕所用格式": "打开“导出为多种屏幕所用格式”对话框",
        "存储为Web所用格式": "打开“存储为 Web 所用格式”对话框",
        "打包": "打包文档",
        "文档设置": "打开“文档设置”对话框",
        "文件信息": "打开“文件信息”对话框",
        "打印": "打印",
        "退出": "退出应用程序",
        "还原": "还原",
        "重做": "重做",
        "首选项": "打开“偏好设置”对话框",
        "颜色设置": "打开“颜色设置”对话框",
        "键盘快捷键": "打开“键盘快捷键”对话框",
        "拼写检查": "拼写检查",
        "再次变换": "将变换重新应用于对象",
        "移动": "移动对象",
        "分别变换": "打开“分别变换”对话框",
        "置于顶层": "将所选对象移到前面",
        "前移一层": "将所选对象前移",
        "后移一层": "将所选对象后移",
        "置于底层": "将所选对象移到后面",
        "编组": "编组选定图稿",
        "取消编组": "取消选定图稿编组",
        "全部解锁": "解锁所选对象",
        "显示全部": "显示所有所选对象",
        "连接": "连接两个或更多路径",
        "平均": "平均两个或更多路径",
        "编辑图案": "编辑图案",
        "创建轮廓": "创建轮廓",
        "显示隐藏字符": "显示隐藏字符",
        "全部": "全选",
        "现用画板上的全部对象": "选择现用画板中的图稿",
        "取消选择": "取消选择",
        "重新选择": "重新选择",
        "上方的下一个对象": "选择当前所选对象上方的对象",
        "下方的下一个对象": "选择当前所选对象下方的对象",
        "应用上一个效果": "将上一个效果应用于选定对象",
        "上一个效果": "通过调整效果对话框中的值，将上一个效果应用于选定对象",
        "轮廓": "在文档的轮廓和 GPU 预览之间切换",
        "GPU预览": "在文档的 GPU 和 CPU 预览之间切换",
        "叠印预览": "在“叠印预览”模式下查看文档",
        "像素预览": "在“像素预览”模式下查看文档",
        "放大": "放大",
        "缩小": "缩小",
        "实际大小": "放大 100%",
        "全部适合窗口大小": "在窗口中查看所有画板",
        "隐藏画板": "显示/隐藏画板",
        "隐藏定界框": "隐藏定界框",
        "显示透明度网格": "显示透明网格",
        "更改为画板标尺": "显示/隐藏画板标尺",
        "隐藏参考线": "隐藏参考线",
        "锁定参考线": "锁定参考线",
        "建立参考线": "建立参考线",
        "释放参考线": "释放参考线",
        "智能参考线": "显示/隐藏智能参考线",
        "透视网格": "显示/隐藏透视网格",
        "显示网格": "显示网格",
        "对齐网格": "对齐网格",
        "对齐点": "对齐点",
        "属性": "显示/隐藏“属性”面板",
        "图层": "显示/隐藏“图层”面板",
        "颜色": "显示/隐藏“颜色”面板",
        "画笔": "显示/隐藏“画笔”面板",
        "描边": "显示/隐藏“描边”面板",
        "渐变": "显示/隐藏“渐变”面板",
        "信息": "显示/隐藏“信息”面板",
        "透明度": "显示/隐藏“透明度”面板",
        "外观": "显示/隐藏“外观”面板",
        "对齐面板": "显示/隐藏“对齐”面板",
        "变换": "显示/隐藏“变换”面板",
        "路径查找器": "显示/隐藏“路径查找器”面板",
        "符号": "显示/隐藏“符号”面板",
        "图形样式": "显示/隐藏“图形样式”面板",
        "字符": "打开“字符”面板",
        "段落": "打开“段落”面板",
        "制表符": "打开“选项卡”面板",
        "OpenType": "打开“OpenType”面板",
        "恢复": "恢复",
        "就地粘贴": "原位粘贴",
        "在所有画板上粘贴": "粘贴到所有画板上",
        "贴在前面": "贴在前面",
        "贴在后面": "贴在后面"
    ]

    public static func resolve(_ title: String) -> String { aliases[title] ?? title }

    public static let bar: [MenuNode] = [
        fileMenu, editMenu, objectMenu, typeMenu, selectMenu, effectMenu, viewMenu, windowMenu, helpMenu
    ]

    public static let appMenu = MenuNode(title: "墨线", children: [
        item("关于墨线", action: "关于墨线"),
        .separator,
        item("首选项", lookup: "打开“偏好设置”对话框"),
        .separator,
        item("退出", lookup: "退出应用程序")
    ])

    public static func item(_ title: String, action: String? = nil, lookup: String? = nil, explicit: KeyChord? = nil) -> MenuNode {
        MenuNode(title: title, action: action, lookup: lookup ?? (action == nil ? title : nil), explicit: explicit)
    }

    public static func sub(_ title: String, _ children: [MenuNode]) -> MenuNode {
        MenuNode(title: title, action: title, children: children)
    }

    private static func chord(_ key: KeyID, _ mods: KeyModifiers) -> KeyChord {
        KeyChord(modifiers: mods, key: key)
    }

    private static let cmd = KeyModifiers.command
    private static let shift = KeyModifiers.shift
    private static let opt = KeyModifiers.option

    public static let fileMenu = sub("文件", [
        item("新建"),
        item("从模板新建"),
        item("打开"),
        sub("最近打开的文件", [item("清除最近的文件", action: "清除最近的文件")]),
        .separator,
        item("关闭"),
        item("存储"),
        item("存储为"),
        item("存储副本"),
        item("恢复"),
        .separator,
        item("置入"),
        sub("导出", [
            item("导出为多种屏幕所用格式"),
            item("导出为…", action: "导出为"),
            item("存储为Web所用格式")
        ]),
        item("打包"),
        .separator,
        item("文档设置"),
        sub("文档颜色模式", [
            item("RGB 颜色", action: "颜色模式 RGB"),
            item("CMYK 颜色", action: "颜色模式 CMYK")
        ]),
        item("文件信息"),
        .separator,
        item("打印")
    ])

    public static let editMenu = sub("编辑", [
        item("还原"),
        item("重做"),
        .separator,
        item("剪切"),
        item("复制"),
        item("粘贴"),
        item("贴在前面"),
        item("贴在后面"),
        item("就地粘贴"),
        item("在所有画板上粘贴"),
        item("清除", action: "清除"),
        .separator,
        item("查找和替换", action: "查找和替换"),
        item("拼写检查"),
        sub("编辑颜色", [
            item("反相", action: "反相颜色"),
            item("转换为灰度", action: "转换为灰度"),
            item("调整饱和度", action: "调整饱和度")
        ]),
        item("颜色设置"),
        item("键盘快捷键")
    ])

    public static let objectMenu = sub("对象", [
        sub("变换", [
            item("再次变换"),
            item("移动"),
            item("旋转", action: "旋转对话框"),
            item("对称", action: "对称对话框"),
            item("缩放", action: "缩放对话框"),
            item("倾斜", action: "倾斜对话框"),
            item("分别变换"),
            item("重置定界框", action: "重置定界框")
        ]),
        sub("排列", [
            item("置于顶层"),
            item("前移一层"),
            item("后移一层"),
            item("置于底层")
        ]),
        sub("对齐", [
            item("水平左对齐", action: "水平左对齐"),
            item("水平居中对齐", action: "水平居中对齐"),
            item("水平右对齐", action: "水平右对齐"),
            item("垂直顶对齐", action: "垂直顶对齐"),
            item("垂直居中对齐", action: "垂直居中对齐"),
            item("垂直底对齐", action: "垂直底对齐")
        ]),
        item("编组"),
        item("取消编组"),
        sub("锁定", [
            item("所选对象", action: "锁定所选对象", lookup: "锁定所选对象")
        ]),
        item("全部解锁"),
        sub("隐藏", [
            item("所选对象", action: "隐藏所选对象", lookup: "隐藏所选对象")
        ]),
        item("显示全部"),
        item("扩展", action: "扩展"),
        item("扩展外观", action: "扩展外观"),
        item("栅格化", action: "栅格化"),
        sub("路径", [
            item("连接"),
            item("平均"),
            item("轮廓化描边", action: "轮廓化描边"),
            item("偏移路径", action: "偏移路径"),
            item("简化", action: "简化")
        ]),
        sub("形状", [
            item("扩展形状", action: "扩展形状"),
            item("转换为矩形", action: "转换为矩形"),
            item("转换为椭圆", action: "转换为椭圆")
        ]),
        sub("图案", [
            item("建立", action: "建立图案"),
            item("编辑图案")
        ]),
        sub("混合", [
            item("建立", action: "混合对象", lookup: "混合对象"),
            item("释放", action: "完成向混合添加对象", lookup: "完成向混合添加对象"),
            item("混合选项", action: "混合选项")
        ]),
        sub("封套扭曲", [
            item("用变形建立", action: "使用变形封套扭曲对象", lookup: "使用变形封套扭曲对象"),
            item("用网格建立", action: "使用网格作为封套形状来扭曲对象", lookup: "使用网格作为封套形状来扭曲对象"),
            item("用顶层对象建立", action: "使用其他对象作为封套形状来扭曲对象", lookup: "使用其他对象作为封套形状来扭曲对象"),
            item("释放", action: "释放封套")
        ]),
        sub("实时上色", [
            item("建立", action: "进行实时上色（使用油漆桶工具时）", lookup: "进行实时上色（使用油漆桶工具时）"),
            item("释放", action: "释放实时上色")
        ]),
        item("图像描摹", action: "图像描摹"),
        sub("剪切蒙版", [
            item("建立", action: "创建剪切蒙版", lookup: "创建剪切蒙版"),
            item("释放", action: "释放剪切蒙版", lookup: "释放剪切蒙版")
        ]),
        sub("复合路径", [
            item("建立", action: "创建复合路径", lookup: "创建复合路径"),
            item("释放", action: "释放复合路径", lookup: "释放复合路径")
        ]),
        sub("画板", [
            item("新建画板", action: "新建画板"),
            item("适合图稿边界", action: "画板适合图稿"),
            item("重新排列画板", action: "重新排列画板")
        ])
    ])

    public static let typeMenu = sub("文字", [
        sub("字体", [
            item("苹方", action: "字体 PingFang SC"),
            item("黑体-简", action: "字体 Heiti SC"),
            item("宋体-简", action: "字体 Songti SC"),
            item("Helvetica", action: "字体 Helvetica"),
            item("Times", action: "字体 Times")
        ]),
        sub("大小", [6, 8, 9, 10, 12, 14, 18, 24, 36, 48, 72].map { size in
            item("\(size) pt", action: "字号 \(size)")
        }),
        item("区域文字选项", action: "区域文字选项"),
        sub("路径文字", [
            item("路径文字", action: "转为路径文字"),
            item("直排路径文字", action: "转为直排路径文字")
        ]),
        item("创建轮廓"),
        item("查找/替换字体", action: "查找/替换字体"),
        item("显示隐藏字符")
    ])

    public static let selectMenu = sub("选择", [
        item("全部"),
        item("现用画板上的全部对象"),
        item("取消选择"),
        item("重新选择"),
        item("反向", action: "反向选择"),
        item("上方的下一个对象"),
        item("下方的下一个对象", explicit: chord(.leftBracket, [opt, cmd])),
        sub("相同", [
            item("填充颜色", action: "相同填充颜色"),
            item("描边颜色", action: "相同描边颜色"),
            item("描边宽度", action: "相同描边宽度"),
            item("不透明度", action: "相同不透明度")
        ]),
        sub("对象", [
            item("全部对象", action: "选择全部对象"),
            item("文本对象", action: "选择文本对象"),
            item("同图层上的对象", action: "选择同图层"),
            item("方向手柄", action: "选择方向手柄"),
            item("剪切蒙版", action: "选择剪切蒙版")
        ]),
        item("存储所选对象", action: "存储所选对象")
    ])

    public static let effectMenu = sub("效果", [
        item("应用上一个效果"),
        item("上一个效果"),
        item("文档栅格效果设置", action: "文档栅格效果设置"),
        sub("3D和材质", [
            item("凸出与斜角", action: "效果 凸出"),
            item("绕转", action: "效果 绕转")
        ]),
        sub("SVG滤镜", [
            item("高斯模糊", action: "SVG滤镜 高斯模糊"),
            item("投影", action: "SVG滤镜 投影")
        ]),
        sub("变形", ["弧形", "拱形", "旗帜", "波形", "鱼眼", "膨胀", "扭转"].map { item($0, action: "变形 \($0)") }),
        sub("扭曲和变换", [
            item("变换", action: "扭曲 变换"),
            item("扭拧", action: "扭曲 扭拧"),
            item("收缩和膨胀", action: "扭曲 收缩和膨胀"),
            item("波纹效果", action: "扭曲 波纹"),
            item("粗糙化", action: "扭曲 粗糙化")
        ]),
        item("栅格化", action: "栅格化"),
        sub("路径", [
            item("位移路径", action: "效果 位移路径"),
            item("轮廓化描边", action: "轮廓化描边")
        ]),
        sub("路径查找器", [
            item("相加", action: "路径查找器 联集"),
            item("相减", action: "路径查找器 相减"),
            item("交集", action: "路径查找器 交集"),
            item("差集", action: "路径查找器 差集")
        ]),
        sub("转换为形状", [
            item("矩形", action: "转换为矩形"),
            item("圆角矩形", action: "转换为圆角矩形"),
            item("椭圆", action: "转换为椭圆")
        ]),
        sub("风格化", [
            item("投影", action: "效果 投影"),
            item("内发光", action: "效果 内发光"),
            item("外发光", action: "效果 外发光"),
            item("圆角", action: "效果 圆角"),
            item("羽化", action: "效果 羽化"),
            item("涂抹", action: "效果 涂抹")
        ])
    ])

    public static let viewMenu = sub("视图", [
        item("轮廓"),
        item("GPU预览"),
        item("叠印预览"),
        item("像素预览"),
        .separator,
        item("放大"),
        item("缩小"),
        item("画板适合窗口大小", action: "画板适合窗口大小", explicit: chord(.character("0"), cmd)),
        item("全部适合窗口大小"),
        item("实际大小"),
        .separator,
        item("隐藏边缘", action: "隐藏边缘", explicit: chord(.character("h"), cmd)),
        item("隐藏画板"),
        item("隐藏定界框"),
        item("显示透明度网格"),
        sub("标尺", [
            item("显示标尺", action: "显示标尺", explicit: chord(.character("r"), cmd)),
            item("更改为画板标尺")
        ]),
        sub("参考线", [
            item("隐藏参考线"),
            item("锁定参考线"),
            item("建立参考线"),
            item("释放参考线", explicit: chord(.character("5"), [opt, cmd]))
        ]),
        item("智能参考线"),
        item("透视网格"),
        item("显示网格"),
        item("对齐网格"),
        item("对齐点")
    ])

    public static let windowMenu = sub("窗口", [
        sub("工作区", [
            item("基本功能", action: "工作区 基本功能"),
            item("传统基本功能", action: "工作区 传统基本功能"),
            item("排版", action: "工作区 排版"),
            item("绘画", action: "工作区 绘画"),
            item("描摹", action: "工作区 描摹"),
            item("重置基本功能", action: "工作区 重置")
        ]),
        item("属性"),
        item("图层"),
        item("颜色"),
        item("画笔"),
        item("描边"),
        item("渐变"),
        item("信息"),
        item("透明度"),
        item("外观"),
        item("对齐", action: "显示/隐藏“对齐”面板", lookup: "显示/隐藏“对齐”面板"),
        item("变换"),
        item("路径查找器"),
        item("符号"),
        item("图形样式"),
        item("字符"),
        item("段落"),
        item("制表符"),
        item("OpenType"),
        item("色板", action: "显示/隐藏色板"),
        item("画板", action: "显示/隐藏画板面板"),
        item("资源导出", action: "显示/隐藏资源导出"),
        item("AI 助手", action: "显示/隐藏 AI"),
        sub("工具栏", [
            item("基本", action: "工具栏 基本"),
            item("高级", action: "工具栏 高级")
        ])
    ])

    public static let helpMenu = sub("帮助", [
        item("墨线帮助", action: "调用帮助", lookup: "调用帮助"),
        item("键盘快捷键说明", action: "键盘快捷键说明"),
        item("快捷键诊断", action: "快捷键诊断"),
        item("关于快捷键来源", action: "关于快捷键来源")
    ])

    public static func flattened(_ nodes: [MenuNode] = bar) -> [MenuNode] {
        var result: [MenuNode] = []
        func walk(_ node: MenuNode) {
            result.append(node)
            node.children.forEach(walk)
        }
        nodes.forEach(walk)
        return result
    }

    /// Chord shown in the menu. Prefers the menu spec's explicit chord, then the first menu-eligible chord of the lookup entry.
    public static func menuChord(for node: MenuNode, keymap: UserKeymap = UserKeymap()) -> KeyChord? {
        if let explicit = node.explicit { return explicit }
        let key = node.lookup ?? node.action
        if let custom = keymap.overrides[key] { return custom }
        if let custom = keymap.overrides[node.title] { return custom }
        return Keymap.chords(forTitle: key).first { $0.menuEligible }
            ?? Keymap.chords(forTitle: node.action).first { $0.menuEligible }
    }
}

extension MenuNode {
    public static let separator = MenuNode(title: "-", action: "-")
}
