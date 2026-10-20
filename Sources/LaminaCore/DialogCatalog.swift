import Foundation

public struct DialogField: Equatable, Sendable {
    public var key: String
    public var label: String
    public var value: String
    public init(key: String, label: String, value: String) {
        self.key = key
        self.label = label
        self.value = value
    }
}

public struct DialogRequest: Equatable, Sendable {
    public var action: String
    public var title: String
    public var fields: [DialogField]
    public init(action: String, title: String, fields: [DialogField]) {
        self.action = action
        self.title = title
        self.fields = fields
    }
}

public enum DialogCatalog {
    public static func request(for action: String) -> DialogRequest? {
        switch action {
        case "创建文档":
            return form(action, "新建文档", [("width", "宽度", "800"), ("height", "高度", "600"), ("mode", "颜色模式 rgb/cmyk", "rgb")])
        case "移动对象":
            return form(action, "移动", [("dx", "水平", "10"), ("dy", "垂直", "0")])
        case "旋转对话框":
            return form(action, "旋转", [("degrees", "角度", "30")])
        case "对称对话框":
            return form(action, "对称", [("axis", "轴 h/v", "h")])
        case "缩放对话框":
            return form(action, "缩放", [("percent", "百分比", "110")])
        case "倾斜对话框":
            return form(action, "倾斜", [("shear", "倾斜", "20")])
        case "打开“分别变换”对话框":
            return form(action, "分别变换", [("percent", "缩放 %", "105"), ("degrees", "旋转", "0"), ("copies", "副本", "1")])
        case "偏移路径":
            return form(action, "偏移路径", [("distance", "位移", "10")])
        case "简化":
            return form(action, "简化", [("tolerance", "容差", "1.5")])
        case "图像描摹":
            return form(action, "图像描摹", [("preset", "预设", TracePreset.blackAndWhiteLogo.name)])
        case "栅格化":
            return form(action, "栅格化", [("ppi", "分辨率", "72")])
        case "效果 投影":
            return form(action, "投影", [("dx", "X", "4"), ("dy", "Y", "4"), ("blur", "模糊", "6")])
        case "效果 内发光":
            return form(action, "内发光", [("blur", "模糊", "8")])
        case "效果 外发光":
            return form(action, "外发光", [("blur", "模糊", "10")])
        case "效果 圆角":
            return form(action, "圆角", [("radius", "半径", "12")])
        case "效果 羽化":
            return form(action, "羽化", [("radius", "半径", "8")])
        case "效果 凸出":
            return form(action, "凸出和斜角", [("depth", "深度", "16")])
        case "效果 绕转":
            return form(action, "绕转", [("angle", "角度", "360")])
        case "效果 膨胀":
            return form(action, "膨胀", [("amount", "数量", "12")])
        case "混合选项":
            return form(action, "混合选项", [("steps", "步数", "6")])
        case "区域文字选项":
            return form(action, "区域文字选项", [("leading", "行距", "0"), ("columns", "栏数", "1")])
        case "查找和替换":
            return form(action, "查找和替换", [("find", "查找", ""), ("replace", "替换为", "")])
        case "查找/替换字体":
            return form(action, "查找字体", [("font", "字体", "Helvetica")])
        case "文档栅格效果设置":
            return form(action, "文档栅格效果设置", [("ppi", "分辨率", "72")])
        case "拼写检查":
            return form(action, "拼写检查", [("note", "说明", "检查选中文字")])
        case "在打开“新建图层”对话框时添加图层":
            return form(action, "新建图层", [("name", "名称", "图层")])
        default:
            if action.hasPrefix("变形 ") {
                return form(action, action, [("bend", "弯曲", "0.5")])
            }
            if action.hasPrefix("扭曲 ") {
                return form(action, action, [("bend", "数量", "8")])
            }
            if action.hasPrefix("效果 ") {
                return form(action, action, [("amount", "数量", "8")])
            }
            if action.hasPrefix("图表 ") {
                return form(action, action, [("kind", "类型", "column")])
            }
            return nil
        }
    }

    private static func form(_ action: String, _ title: String, _ rows: [(String, String, String)]) -> DialogRequest {
        DialogRequest(action: action, title: title, fields: rows.map { DialogField(key: $0.0, label: $0.1, value: $0.2) })
    }
}
