# Grove 替换图标的 Icon Composer 资源

2026-11-05，使用本机 Xcode 27.2 / Icon Composer 27.2（143）。

`Grove.icon` 是已在原生 Icon Composer 打开并保存的最小文档：背景加一个现有树形素材层，图案层关闭 glass 和额外阴影，不重新制作树形几何。其内部材质已经包含在原始概念图中，不能再叠加一套玻璃效果。此文档保留的是经典树形参考；其他款的原始素材仍在 `design/icon-exploration/`。

`scripts/render-system-app-icons.swift` 复用此原生文档的已验证结构，仅替换 `Assets/Artwork.png`：先从各款原始概念图提取不带圆角遮罩的方形图案，再调用 Icon Composer 自带 `ictool --export-image`，固定 macOS、Default、design generation 26。工具根据当前 `xcode-select -p` 定位，构建需要完整 Xcode。

CLI 的 macOS 输出铺满画布，并非 UI 的「macOS pre-Tahoe」留白导出。本流程因此只在输出外加透明留白，不再裁圆角或模拟高光。1024 画布中的图标宽 824，对齐调查时默认图标 512 画布中宽 412 的比例。随后生成单张 256 × 256 像素 JPEG 2000（有损质量参数 0.7，保留 alpha），逻辑尺寸 128 pt；Dock 的 128 pt 内容在 Retina 下对应 256 像素，不再携带额外的大尺寸表示。它是带固定效果的扁平资源，不是会实时响应系统明暗、着色或光照的分层系统图标。

构建脚本通过 `Bundle.resourceURL` 定位资源目录，将八款 JP2 放入其 `SystemAppIcons/`（Xcode 生成的资源包对应 `Contents/Resources/SystemAppIcons/`），并运行 `scripts/verify-app-icons.swift` 经 Bundle 接口实际读取全部图标，缺失、尺寸或透明通道不符、总量超过 512 KB、重复携带原始大图时立即中止构建；设置页与 Dock 读取相同的缓存图像；默认款仍以 `applicationIconImage = nil` 交还系统；设置页的默认款预览通过 `NSWorkspace.icon(forFile:)` 读取同一应用包的系统图标，避免回退到偏大、缺少外壳效果的原始 PNG。运行时切换和退出后的 Dock 插件读取同一资源。这里取代了此前创建临时应用包再用 NSWorkspace 获取图标的实验。

`preview.png` 展示实际导出资源在浅、深背景及 112、64、32 像素的外观。已检查素材导出；实际 Dock 切换效果由用户验收。请先退出所有旧 Grove 实例，只运行本次 `dist/Grove.app`，避免 `/Applications/Grove.app` 与本次构建共用偏好/通知影响观察。

重新导出可运行：

```sh
swift scripts/render-system-app-icons.swift /tmp/grove-composer-icons
```

正常 `zsh scripts/build-app.sh` 会自动生成，无需手动复制导出文件。源 PNG 不变；此流程不调用图像生成服务。

体积优化：应用包仅保留这八款小尺寸导出图和默认 ICNS，移除资源 bundle 中的原始 1024 像素 PNG 副本；源码中的原始素材与 SwiftPM 开发/测试资源不变。
