# 墨线

墨线（Lamina）是个人使用的原生 macOS 矢量编辑器。界面是深色的，菜单为中文，默认快捷键来自 Adobe Illustrator 帮助中心公开的 Mac 快捷键表。程序只使用公开文档，没有反编译 Illustrator，也不使用 Illustrator 的名称作为应用菜单。

绘图在需要时发生：Metal 底板暂停，矢量用 Core Graphics 画。没有常驻的显示链接，空闲时不应占住 CPU。

## 运行

需要 macOS 14 和 Xcode 15 或更新版本。

```bash
brew install xcodegen
xcodegen generate
open Lamina.xcodeproj
```

不签名的 Release 包：

```bash
xcodebuild -project Lamina.xcodeproj -scheme Lamina -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ENABLE_HARDENED_RUNTIME=NO build
open build/Build/Products/Release/Lamina.app
```

核心模型可以在 macOS 或 Linux 上单独测试：

```bash
swift test
```

GitHub Actions 的 `macOS` 工作流会跑这套测试，再生成未签名的 `Lamina.app`（zip）和 `Lamina.dmg`，并作为工作流产物上传。推送标签，或手动运行该工作流时，这两个文件会挂到对应的 GitHub Release 上。手动运行时可以填写标签名；留空则使用 `dispatch-<运行号>`。

## 文档从哪来

- `docs/menu_spec.md`：中文菜单结构。
- `Sources/LaminaCore/Resources/adobe_shortcuts_cn.txt`：公开帮助页里的默认快捷键。应用会把它拷进包内。
- 也可以从「编辑 > 键盘快捷键」导入 Illustrator 导出的 `.kys` 或制表符文本快捷键集。
- PDF 内容流按 Adobe PDF Reference 解释（路径、填色、描边、文字、渐变、剪贴、可选内容组）。旧式 PostScript `.ai` 按公开的 `%!PS` / `%AI5_` 运算符读入。图像描摹用阈值、色调分离和裂纹跟踪加曲线拟合。CMYK 显示在 macOS 上走通用 CMYK 色彩空间（ColorSync）转到 sRGB；PDF 写出用 DeviceCMYK。

## 已实现

- 中文菜单栏，条目按公开菜单说明排列。快捷键集中在一张表里：解析结果与 `Keymap.entries` 一致，并有单元测试核对全部 390 条以及菜单上的加速键。
- 深色窗口：左侧工具栏（按住约 0.35 秒弹出同组工具；柱形图工具长按可选柱形、堆积柱形、条形、堆积条形、折线、面积、散点、饼图、雷达）、填色/描边（X、D、⇧X、<、>、/）、文档标签、右侧属性与图层面板、底部缩放和画板切换。
- 选择、直接选择、编组选择和定界框变换；钢笔、曲率、添加/删除/转换锚点；矩形、圆角矩形、椭圆、多边形、星形、直线；点文字和区域文字。
- 图层、画板、填色/描边、色板（含 CMYK 青/品红/黄/黑版）、线性/径向渐变、路径查找器、编组、锁定、隐藏、排列、剪切蒙版、复合路径、撤销/重做、缩放、抓手、轮廓视图、叠印预览。
- 外来 PDF 和旧式 `.ai` 会解析成可编辑路径、文字、渐变和图层。带墨线 JSON 的 `.ai` 仍按文档模型往返。解析失败时才按页置入 PDF。读写 SVG。导出 PDF（CMYK 文档写 `k`/`K`）、PNG、SVG。
- 图像描摹：高保真/低保真照片、3/6/16 色、灰度、黑白徽标、素描、剪影、线条稿、技术绘图。
- 实时上色（平面图的面，端点可按间隙吸附）、透视网格（左墙、地板、右墙，矩形和图表可投到当前平面）、三维凸出/绕转/膨胀（兰伯特着色的填色面）。
- 画笔：书法（角度、圆度、直径，固定/随机/压感/倾斜/方位/旋转）、散点（大小、间距、散布、旋转和色调/色调和阴影/色相偏移）、艺术画笔（拉伸、参考线之间、等比、翻转、拐角收拢）、图案画笔（边/外角/内角/起点/终点、自动角、拉伸/添加间距/近似路径）、毛刷（笔尖形状、密度、粗细、不透明度、硬度、弹簧笔触和溅点预览）。描边记下压感采样。属性面板列出画笔库。扩展外观会把画笔描边烘成路径。画笔和铅笔的保真度、平滑度在双击工具或按 Return 的选项里。
- 钢笔：单击/拖出控制柄、Option 断开、Shift 限制 45°、按住空格移动正在放的锚点、按住 Command 临时直接选择、靠近起点显示闭合、从开放端点继续、接到另一条开放路径、在选中路径上自动添加/删除锚点、橡皮筋预览。曲率工具单击拟合、双击角点、拖动改点。锚点工具单击转换、拖动拉出对称控制柄、拖已有控制柄则断开。
- 工具栏里的工具都有对应手势：形状生成器沿拖动切面（Option 删除），橡皮擦和刻刀切开路径，剪刀把闭合路径打开、把开放路径拆成两条，旋转/镜像/缩放/倾斜带 Shift 约束，宽度工具可单侧拖动，变形工具有变形/扭转/收缩/膨胀/扇贝/晶格化/皱褶，自由变换在按住 Command 时做双线性扭曲，牵线用移动最小二乘，符号喷枪一族（喷枪、移位、紧缩、缩放、旋转、着色、滤色、样式），网格单击加密，渐变工具保留已有色标，吸管单击取样、Option 应用，度量给出 Δx/Δy/角度，混合逐个点选，切片和画板，实时上色桶和选区，透视网格可拖消失点，图表九种类型，铅笔/平滑/路径橡皮擦/连接，魔棒容差，套索按锚点，区域/路径/直排/修饰文字。每个工具都有测试。
- 带参数的菜单命令会弹出对话框（移动、旋转、对称、缩放、倾斜、分别变换、偏移、简化、描摹、栅格化、效果、图表、新建文档和新建图层等）。文件命令仍走系统打开/存储面板。
- AI 侧栏：Gemini、OpenAI、Claude、xAI Grok、DeepSeek、通义千问、Kimi、智谱 GLM、豆包，以及可改地址和模型的 OpenAI 兼容接口。密钥写入登录钥匙串。支持文字生成 SVG、把选区当作 SVG 发给模型再替换、以及生成色板。

### 供应商标识

侧栏里能放进包的，是各厂商公开的标志文件，只供个人、非商业地认出是哪一家。标志本身仍归厂商所有。

| 供应 | 文件 | 来源 |
| --- | --- | --- |
| Gemini | `Resources/Brands/gemini.svg` | Google 公开的 `gemini_sparkle` SVG（`gstatic.com`） |
| OpenAI | `Resources/Brands/openai.svg` | OpenAI 2025 品牌包里的白色 monoblossom SVG（`cdn.openai.com/brand/OpenAI-Logos-2025.zip`） |
| Claude | `Resources/Brands/claude.svg` | Wikimedia 上的 Claude 符号，来源标注为 anthropic.com。Anthropic 的 Brandfolder 新闻资料包提供的是 PNG，没有直接的 SVG 地址 |
| DeepSeek | `Resources/Brands/deepseek.svg` | Wikimedia 上的 DeepSeek 字标 SVG。`cdn.deepseek.com/logo.svg` 不存在，官方 CDN 提供的是 PNG |

xAI、通义千问、Kimi、智谱、豆包这次没有取到厂商自己发布的 SVG（xAI 品牌包下载返回拒绝，通义页面是 PNG，Kimi 是 favicon ICO，智谱和豆包的图标地址没有给出 SVG）。这几家仍用字母标，没有拿第三方图标库冒充官方文件。

## 还没有做到

这不是 Illustrator。下面这些仍然达不到它的完成度：

- 没有 Creative Cloud 库、Adobe Fonts 或云文档。
- 画笔仍不是 Illustrator 那一套。书法是椭圆支撑函数围出的色带，不是沿笔尖扫过的真实书法轮廓。艺术画笔的拐角是把顶点沿角平分线收一点，不是重叠处理。图案画笔的“近似路径”保持原路径，只是按自然长度铺砖，不会改写路径去凑整砖。毛刷是确定性的弹簧笔尖加溅点累积，不是 Adobe 的 GPU 鬃毛模拟，也没有实时笔刷预览窗口里的那套光照。
- 牵线是移动最小二乘相似变换，不是 Illustrator 的三角网格，没有重叠和扩张。网格是规则色块，单击增加一列，不能单独拖网格点。自由变换的 Command 拖角是四角双线性，不是完整的自由扭曲封套。
- 形状生成器、橡皮擦、刻刀走平面图或路径查找器，复杂曲线和自交路径上会和 Illustrator 有出入。透视是两点网格，把拖动映射到当前平面，不是完整的透视选区编辑。符号工具改的是名为“符号实例”的副本，没有符号库和注册点。修饰文字的偏移记在编辑器里，不写进文件。直排用负行距把字逐个往下排。
- 智能参考线会吸到锚点、参考线和画板边，没有 Illustrator 的全部对齐标签。锚点和控制柄可以关掉显示。平板电脑的压力、倾斜、方位和旋转从 NSEvent 读进描边采样；这台 Linux 环境无法接数位板验证。
- ICC 只覆盖 macOS 上的通用 CMYK（ColorSync）和 PDF DeviceCMYK 公式，没有任意 ICC 颜色查找表。
- “GPU 预览”是暂停的 Metal 底板加 Core Graphics 矢量，不是一整条 GPU 矢量管线。
- PDF 的 LZW、内联图像，以及一部分旧式 AI 文字运算符还不读。JPEG 描摹要先在应用里变成 PNG；核心只描 PNG 或原始 RGBA。
- 投影和模糊在画布上是 Core Graphics 阴影预览；真正的像素结果在“栅格化”之后。
- 体积低于 30 MB、空闲约 150 MB 内存、CPU 接近 0 是按“按需重绘、不跑显示链接”设计的目标。这个 Linux 环境不能启动 macOS 应用，所以没有在这里量过包体、内存，也没有跑过 macOS CI。
