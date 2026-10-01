# FastImageView

macOS 看图应用。打开一个文件夹后，用缩略图浏览当前这一层的图片，双击进入大图，左右切换，并把选中的图片移到废纸篓。同一次打开该文件夹期间可以用 `⌘Z` 撤销。

相机原片只读内嵌 JPEG 预览，不做传感器全尺寸解码。不递归子文件夹，不启用 App Sandbox。

## 要求

- macOS 14 或更高版本
- Swift 5.9（随 Xcode 15 或更新的命令行工具提供）

## 构建与运行

在仓库根目录：

```bash
swift build
swift run FastImageView
```

启动后用 `⌘O` 或「打开文件夹」选择目录。

## 测试

```bash
swift test
```

没有图形会话时，废纸篓往返测试会跳过。未设置 `FASTIMAGEVIEW_NEF_FIXTURE` 时，NEF 预览测试会跳过。这两项跳过不算失败。要跑 NEF 测试，把变量指到一个本地 NEF 文件：

```bash
FASTIMAGEVIEW_NEF_FIXTURE=/path/to/sample.nef swift test
```

若 `swift test` 因 `sandbox-exec` 报 `Operation not permitted`，改用：

```bash
swift test --disable-sandbox
```

## 支持的文件

扫描只看扩展名，不区分大小写。常见图片：JPEG、PNG、HEIC、GIF（第一帧）、TIFF、WebP、BMP。原片：NEF、CR2、CR3、ARW、RAF、ORF、RW2、DNG、PEF。

隐藏文件、目录和其他扩展名会被跳过。文件名按 Finder 的自然顺序排列。

## 常用操作

- 单击选中，双击或 Return 进入大图，`Esc` 回到网格。方向键不循环。
- 关键字匹配含扩展名的完整文件名，不区分大小写。格式按钮只列出本文件夹里出现过的格式；一个都不选等于全部。
- `Delete`、`fn+Delete` 和 `⌘⌫` 把当前选中项移到废纸篓。关键字框聚焦时，这些键只编辑文字。
- 大图里 `1` 按预览的实际像素显示（触控板可平移，鼠标滚轮仍切图），`0` 回到适合窗口。
