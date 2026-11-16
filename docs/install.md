# 安装 Grove / Install Grove

[简体中文 README](../README.zh-CN.md) · [English README](../README.md)

## 中文

### 系统要求

- macOS 14 或更新版本。
- 本次预览包面向 Apple Silicon（M 系列芯片，arm64）；不适用于 Intel Mac。
- 下载预编译包不需要安装 Xcode 或配置签名证书。Grove 使用系统 Git；首次使用时若系统提示安装命令行工具，请按系统提示完成安装。
- 浏览无需 Agent。使用辅助提交时，另行配置本机 Codex、Claude Code 或 OMP。

### 下载与安装

1. 从 [GitHub Releases](https://github.com/etet2007/Grove/releases) 的 Assets 中下载适合芯片架构的 ZIP 文件。
2. 双击 ZIP 解压，将 `Grove.app` 拖到「应用程序」。
3. 从「应用程序」打开 Grove，新建工程并添加你已有的本地 Git 仓库。

### 未公证 Preview 的首次打开

若发布说明明确标注为未公证 Preview，应用使用自签名证书，macOS 无法通过 Apple 的开发者身份与公证检查。请先核对发布来源与包的校验值，再决定是否信任。

尝试打开应用后，如果系统显示无法验证开发者或无法检查恶意软件，你可以在「系统设置 → 隐私与安全性」找到 Grove 的拦截提示，选择「仍要打开」，再按系统要求确认。具体界面取决于 macOS 版本；受组织管理的 Mac 可能无法允许例外。操作方法见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

### 校验下载

将 ZIP 与同一发布中的 `SHA256SUMS.txt` 下载到同一目录，在终端切换到该目录，运行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

应显示对应文件 `OK`。校验值只用于与发布包核对，不代表经过 Apple 公证。

## English

### Requirements

- macOS 14 or later.
- This Preview build targets Apple Silicon (M-series, arm64). It does not run on Intel Macs.
- The prebuilt app does not require Xcode or your own signing certificate. Grove uses system Git; if macOS prompts you to install Command Line Tools on first use, follow the system prompt.
- An Agent is optional. Set up an installed Codex, Claude Code, or OMP only for assisted commit preparation.

### Download and install

1. Download the ZIP for your Mac's architecture from the Assets section of [GitHub Releases](https://github.com/etet2007/Grove/releases).
2. Unzip the archive and move `Grove.app` to Applications.
3. Open Grove from Applications, create a project, and add your existing local Git repositories.

### Opening an unnotarized Preview

If the release notes mark the app as an unnotarized Preview, it uses a self-signed certificate and has not passed Apple's Developer ID and notarization checks. Verify the release source and checksum before deciding whether to trust it.

After attempting to open the app, you may choose **System Settings → Privacy & Security → Open Anyway** for Grove and follow the confirmation prompts. The exact UI depends on your macOS version, and managed Macs may block this exception. See [Apple's instructions](https://support.apple.com/102445).

Download `SHA256SUMS.txt` from the same release, place it beside the ZIP, and run `shasum -a 256 -c SHA256SUMS.txt` in that directory. The matching file should report `OK`. A checksum is not a substitute for Apple notarization.

## 应用内更新 / In-app updates

GitHub Releases 的下载入口和 Grove 的 Git 仓库更新机制分别维护。没有明确提供独立更新仓库时，请从 Releases 手动下载新版，不要把源码仓库填作更新源。

GitHub Releases downloads and Grove's Git-repository-based updater are separate. Use Releases for manual upgrades unless a dedicated update repository is explicitly provided; the source repository is not an update source.
