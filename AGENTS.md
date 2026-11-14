# AGENTS.md

面向 AI 编码代理的项目说明。读者默认对本项目一无所知，请先阅读本文件再动手改代码。

## 项目概述

FastImageView 是一个 macOS 看图应用（纯 SwiftPM 工程，无 Xcode 工程文件）。打开一个文件夹后，用缩略图网格浏览当前这一层的图片；双击进入大图，左右切换；可以把选中的图片移到废纸篓，并在同一次打开期间用 `⌘Z` 撤销。

关键产品约束（改动时勿破坏）：

- 相机原片（NEF/NRW/CR2/CR3/ARW/SR2/SRF/RAF/ORF/RW2/DNG/PEF）只读内嵌 JPEG 预览，不做传感器全尺寸解码。
- 不递归子文件夹。
- 不启用 App Sandbox。
- 要求 macOS 14+，Swift 5.9（swift-tools-version: 5.9）。

## 构建与运行

仓库根目录即包根，配置全部在 `Package.swift` 里：

```bash
swift build              # 构建
swift run FastImageView  # 运行（⌘O 或「打开文件夹」选择目录）
swift test               # 测试
```

打包成 `.app` 并安装（默认装到 `/Applications`，ad-hoc 签名）：

```bash
Scripts/package-app.sh [目标目录]
```

该脚本会做 `swift build -c release`、组装 `FastImageView.app`（每次从 `Support/Info.plist` 复制，保留 `CFBundleDocumentTypes` 以便访达「打开方式」）、复制 `AppIcon.icns`、`codesign --sign -` 签名并用 `lsregister` 注册。打包用资源还有 `Scripts/MakeJpegFixture.swift`（重新生成测试 fixture 的独立脚本，用法：`swift Scripts/MakeJpegFixture.swift`，需在仓库根目录运行）。

注意：`swift run` 启动的是裸可执行文件，没有 app bundle，因此 `FastImageViewApp.init()` 里会手动 `setActivationPolicy(.regular)` 并激活窗口——这是有意为之，勿删除。

## 提交约定

完成用户提出的一项修改需求后，默认立刻提交一笔 git commit（不要等用户再说「提交」）。不要 push，除非用户要求。不要把 `FastImageView.app/`、密钥或无关杂项一并提交。

## 代码组织

三个 SwiftPM target（见 `Package.swift`）：

- `Sources/FastImageViewCore` —— 与 UI 无关的业务逻辑，全部为可单测的纯 Swift / Foundation / CoreGraphics / ImageIO 代码，不 import AppKit 或 SwiftUI。一个文件一个主题，均为小文件（多数 < 300 行）：
  - `BrowserModel.swift` —— `@MainActor @Observable` 的中心状态机，持有目录、选中、缩放、撤销栈；通过协议注入依赖（`FolderScanning`、`PreviewPipeline`、`FolderWatching`、`TrashStorage`），`BrowserModel.live()` 组装真实实现。
  - `ImageFile.swift` / `ImageCatalog.swift` —— 文件模型（格式枚举、iCloud 状态）与过滤/选中逻辑（关键字、格式筛选、多选）。
  - `FolderScanner.swift` —— 目录枚举（跳过隐藏文件，按 Finder 自然顺序排序）。
  - `PreviewPipeline.swift` / `PreviewScheduler.swift` / `ImageByteCache.swift` / `ThumbnailDiskStore.swift` —— 缩略图/大图解码管线、调度、内存字节缓存与磁盘缩略图缓存（SHA256 键）。
  - `DeletionService.swift` —— 移入废纸篓与恢复，含可注入的 `TrashStorage`。
  - `KeyRouting.swift` / `DropRouting.swift` / `CopyRouting.swift` —— 纯函数式的按键/拖放/拷贝决策。
  - `ViewerZoom.swift` / `PreviewSizing.swift` / `GridLayout.swift` / `ScrollAccumulator.swift` —— 缩放、尺寸、网格布局、滚轮累计等纯计算。
  - `CaptureInfo.swift` —— 从 EXIF 提取拍摄信息（相机、镜头、光圈等）。
  - `GIFPlayback.swift` —— GIF 动图播放逻辑（第一帧之外的帧）。
  - `FolderWatch.swift` —— 目录变化监听（DispatchSource，可替换为 `IdleFolderWatch` 空实现）。
  - `RecentFolderList.swift` —— 「打开最近」列表（UserDefaults 持久化）。
- `Sources/FastImageView` —— SwiftUI/AppKit 可执行层：
  - `FastImageViewApp.swift` —— `@main` 入口、菜单命令（打开/搜索/撤销/拷贝/缩放等，通过 `NotificationCenter` 转发到视图）。
  - `ContentView.swift` —— 单一大视图（约 1300 行）：空状态、加载状态、网格、大图、右键菜单、toast、事件监听（`NSViewRepresentable` 桥接）。
  - `Theme.swift` —— `AppTheme` 集中管理所有配色/间距/圆角常量，经 `\.appTheme` environment 注入。规则：**视图里不允许出现硬编码颜色/字号/间距**，新视觉常量一律加到这里。
  - `Clipboard.swift` / `ViewerExtras.swift` —— 剪贴板写入与大图辅助视图。
- `Tests/FastImageViewCoreTests` —— 只测 Core 层（约 20 个 XCTest 文件），fixture 在 `Fixtures/`（`sample.jpg`、`sample.png`，经 `Package.swift` 的 `resources: [.copy("Fixtures")]` 打包）。

## 代码风格约定

从现有代码归纳，请保持一致：

- 注释与文档一律用简体中文（README、代码内注释等均如此），用户可见字符串也是中文。
- Core 层类型尽量声明为 `Sendable` / 纯值类型；决策类逻辑写成无状态的纯函数（如 `KeyRouting.decide`、`DropRouting.decide`、`PreviewDecodeWriteDecision.decide`），便于单测。
- 协议 + 注入是默认的可测性模式：新增依赖时先定义协议，真实实现之外提供一个测试替身（参考 `FolderWatching` / `IdleFolderWatch`）。
- 并发：`BrowserModel` 等 UI 相关状态用 `@MainActor`；后台解码用 Swift concurrency，跨线程回写用 generation/epoch 校验丢弃过期结果（勿引入数据竞争）。
- UI 视觉常量集中进 `Theme.swift`，遵循统一验收标准（无硬编码颜色、Light/Dark 正常等）。
- 不引入第三方依赖（当前 Package.swift 零依赖，保持如此）。

## 测试说明

```bash
swift test
```

约定与已知跳过（跳过不算失败）：

- 废纸篓往返测试需要图形会话：无 GUI 时 `DeletionServiceTests` 通过 `XCTSkipUnless(hasDesktopSession())` 自动跳过。
- NEF 预览测试需要真实相机文件：设置 `FASTIMAGEVIEW_NEF_FIXTURE=/path/to/sample.nef swift test`，未设置则跳过。
- 若 `swift test` 因 `sandbox-exec` 报 `Operation not permitted`，用 `swift test --disable-sandbox`。

测试写法：Core 层全部走协议替身（脚本化 scanner、recording pipeline、内存 trash 等，见 `BrowserModelTests.swift` 开头的几个私有类），不碰真实文件系统（磁盘缓存类测试除外）。新增业务逻辑请照此模式补测试；UI 层（`Sources/FastImageView`）目前无测试。

## 部署与发布

- 无 CI 配置、无版本管理流程；发布即本地运行 `Scripts/package-app.sh` 生成 ad-hoc 签名的 `FastImageView.app` 并 `ditto` 到目标目录（默认 `/Applications`）。
- Bundle ID 为 `local.FastImageView`；`Support/Info.plist` 声明了图片文档类型（Viewer 角色，Alternate 排名），打包脚本首次生成 plist 时会写入同一组键。
- 仓库内已有一个 `FastImageView.app/` 目录（打包产物/工作副本），`git status` 干净时它未被跟踪；不要把它当作源码的一部分修改。

## 安全与边界

- 不启用 App Sandbox；删除走系统废纸篓（`FileManager.trashItem`），删除前不二次确认文件内容。
- 路径处理注意：文件名匹配按扩展名且不区分大小写；隐藏文件始终跳过；解码一律限制 `maxPixelSize`，原片从不全尺寸解码（防内存暴涨）。
- 不要把任何密钥/凭证放入仓库；本项目目前不需要任何密钥。

## 其他参考

- `README.md` —— 用户视角的功能说明、支持的格式列表、快捷键清单。
