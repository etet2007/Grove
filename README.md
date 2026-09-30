# MyGit

MyGit 是一个只读的原生 macOS Git 客户端，用于快速浏览同一工程内多个仓库、多个 worktree 的未提交 diff 和本地提交记录。

## 运行

需要 macOS 14 或更新版本，以及 Xcode 命令行工具。运行 `zsh scripts/build-app.sh` 后，双击 `dist/MyGit.app`。

构建脚本默认使用登录钥匙串中的 `MyGit Local Code Signing` 证书签名，不再使用每次改动后身份都会变化的临时签名。首次在本机配置时，可以在「钥匙串访问」的「证书助理 → 创建证书」中创建同名的「自签名根证书」，证书类型选「代码签名」。如果已有其他代码签名证书，可运行 `MYGIT_SIGNING_IDENTITY="证书名称" zsh scripts/build-app.sh`。自签名证书仅用于本机开发；向其他人分发时应使用 Developer ID 签名。

首次使用：

1. 新建工程。
2. 新建可折叠的仓库组，例如 App、CSDK。
3. 在每个仓库组中添加已有的本地 Git 仓库目录。可一次选择多个目录。
4. 在侧边栏选择工作树组；同名分支会自动归组，缺失的仓库沿用主目录。
5. 点击仓库名可单独选择其 worktree；「恢复自动匹配」会清除手动选择。

`⌘K` 打开快速切换，`⌘R` 刷新。Mac 的「工作树」菜单也提供切换入口。应用每四秒自动刷新一次。配置保存在 `~/Library/Application Support/MyGit/config.json`。

工程可从窗口标题栏的工程菜单切换。通过「文件 → 新建窗口」打开多个窗口后，各窗口可以独立选择工程和工作树组。

点击顶部「创建 MR」，选择仓库后会在浏览器打开该仓库的 GitLab 创建页面，并预选当前 checkout 的分支。链接来自本地 Git 远端配置；分支需要已推送到 GitLab，才能在网页中创建 MR。应用不会自动推送或提交 MR。

## 验证

运行 `swift test`。测试使用临时 Git 仓库，不修改已有项目。

图标源文件为 `scripts/generate-icon.swift`。修改后运行 `zsh scripts/generate-icon.sh`，生成 `Resources/MyGitIcon.png` 和用于应用包的 `Resources/MyGitIcon.icns`。
