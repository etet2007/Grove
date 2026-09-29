# MyGit

MyGit 是一个只读的原生 macOS Git 客户端，用于快速浏览同一工程内多个仓库、多个 worktree 的未提交 diff 和本地提交记录。

## 运行

需要 macOS 14 或更新版本，以及 Xcode 命令行工具。运行 `zsh scripts/build-app.sh` 后，双击 `dist/MyGit.app`。

首次使用：

1. 新建工程。
2. 新建可折叠的仓库组，例如 App、CSDK。
3. 在每个仓库组中添加已有的本地 Git 仓库目录。可一次选择多个目录。
4. 在侧边栏选择工作树组；同名分支会自动归组，缺失的仓库沿用主目录。
5. 点击仓库名可单独选择其 worktree；「恢复自动匹配」会清除手动选择。

`⌘K` 打开快速切换，`⌘R` 刷新。Mac 的「工作树」菜单也提供切换入口。应用每四秒自动刷新一次。配置保存在 `~/Library/Application Support/MyGit/config.json`。

## 验证

运行 `swift test`。测试使用临时 Git 仓库，不修改已有项目。
