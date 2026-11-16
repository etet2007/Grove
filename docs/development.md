# 开发与构建

[返回中文首页](../README.zh-CN.md) · [English overview](../README.md)

## 构建前提

- macOS 14 或更新版本是应用的运行下限。
- 打包需要完整 Xcode，且所选安装中包含 Icon Composer 的 `ictool`。仅安装 Command Line Tools 不足以运行当前打包脚本。
- 用 `xcode-select -p` 检查所选开发目录；需要时使用 `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` 切换至实际 Xcode 安装路径。
- 登录钥匙串中需要可用的代码签名身份。默认名称与配置方法见下文。
- 首次 SwiftPM 构建需下载 `Package.resolved` 锁定的依赖。

以下命令均在仓库根目录执行。当前脚本构建本机架构，未生成通用二进制；macOS 14 运行下限不代表打包工具可以仅在 macOS 14 上使用。

## 代码签名

构建脚本默认使用登录钥匙串中的 `MyGit Local Code Signing` 证书签名，不再使用每次改动后身份都会变化的临时签名。首次在本机配置时，可以在「钥匙串访问」的「证书助理 → 创建证书」中创建同名的「自签名根证书」，证书类型选「代码签名」。如果已有其他代码签名证书，可运行 `GROVE_SIGNING_IDENTITY="证书名称" zsh scripts/build-app.sh`。自签名证书仅用于本机开发；向其他人分发时应使用 Developer ID 签名。

## 构建与启动

```sh
zsh scripts/build-app.sh
codesign --verify dist/Grove.app
open dist/Grove.app
```

使用其他已安装的签名身份：

```sh
GROVE_SIGNING_IDENTITY="证书名称" zsh scripts/build-app.sh
```

当前流程生成本机开发包；对外分发的 Developer ID 签名、公证与更新签名要求见 [发布流程](releasing.md)。

## 测试与性能验证

运行 `swift test`。测试使用临时 Git 仓库，不修改已有项目。

`GROVE_SEARCH_BENCHMARK=1 swift test --filter DiffSearchTests` 可测量 5 万行内容中修改查询文本的主线程同步耗时；这衡量输入是否阻塞界面，不代表搜索结果完成时间。该耗时测试默认跳过，取消和结果一致性测试始终运行。

窗口缩放性能可在机器空闲时运行 `GROVE_RESIZE_BENCHMARK=1 swift test --filter WindowResizePerformanceTests`。测试使用临时配置和合成的 1,000 行 diff，自动调整完整窗口尺寸，输出布局与绘制的中位耗时及 P95，以 16.7 ms 检查 60 Hz 帧预算；默认跳过，避免机器负载造成普通测试误报。另可运行 `GROVE_RESIZE_BENCHMARK=1 swift test --filter RetainedPaneTests`，测量访问过 6 个仓库详情后隐藏页面对缩放的影响，并验证切回后的滚动位置。该测量不等同于真实拖动帧率，仍需手动检查连续拖动、全屏切换及分栏宽度。

## Agent 联调

自动测试不调用模型服务。需要联调某个已登录的本机 Agent 时，运行 `GROVE_TEST_AGENT=codex swift test --filter CommitExecutionTests.testLiveAgentGenerationWhenExplicitlyEnabled`，可将 `codex` 换成 `claude` 或 `omp`。联调只在临时仓库生成建议，不提交。

## 图标素材与生成

应用图标原始素材为 `Resources/GroveIcon-source.png`。运行 `zsh scripts/generate-icon.sh` 可重新生成带 macOS 圆角及透明留白的 PNG 和多尺寸 ICNS，再构建应用即可使用。

当前图标采用绿色树形 A 方案，原始候选稿保存在 `design/icon-exploration/2026-11-03-green-grove/A-vector-green.png`；`Resources/GroveIcon-source.png` 是裁去展示背景后的打包输入。`scripts/generate-icon.swift` 为其添加圆角与透明留白。修改素材后运行 `zsh scripts/generate-icon.sh`，生成 `Resources/GroveIcon.png` 和用于应用包的 `Resources/GroveIcon.icns`。

## 命名与兼容标识

产品、Swift 包、可执行文件、图标资源和源码目录已统一为 Grove（`Sources/Grove`、`Tests/GroveTests`）。为保留已有工程、偏好设置及更新签名，Bundle ID 仍为 `dev.stephenlau.mygit`，配置仍位于 `~/Library/Application Support/MyGit/config.json`，设置窗口的历史位置键和本机 `MyGit Local Code Signing` 证书也继续沿用。构建优先读取 `GROVE_SIGNING_IDENTITY`、`GROVE_VERSION`、`GROVE_BUILD`，同时兼容对应的旧 `MYGIT_*` 构建变量。

工程结构与界面规范见 [AGENTS.md](../AGENTS.md) 和 [DESIGN.md](../DESIGN.md)。图标运行行为见 [设置与外观](user-guide.md#设置与外观)。
