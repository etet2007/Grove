# MyGit 项目上下文

## 先读

- [README.md](README.md)：运行和首次使用方法。
- [DESIGN.md](DESIGN.md)：已确认的产品范围、交互和验收场景。
- [CONTEXT.md](CONTEXT.md)：工程、仓库组、工作树组的准确含义。
- [docs/adr/0001-discover-worktrees-from-registered-repositories.md](docs/adr/0001-discover-worktrees-from-registered-repositories.md)：仓库发现边界的原因。

## 产品边界

MyGit 是原生 macOS Git 客户端，用于在一个工程中查看多个仓库及其 worktree 的未提交 diff 和本地提交记录。仓库由用户明确添加；不要按父目录、`mrepo_*` 目录或 `.mrepo-set` 自动导入。仓库组只整理导航；工作树组是跨仓库的一套 checkout 选择。同名分支自动归组，缺少对应 worktree 时沿用主检出目录，单仓库手动选择需要持久化。

允许用户点击仓库条目的分支名，从本地分支列表主动切换当前 checkout；只使用非强制 Git switch，不丢弃修改、不自动 stash、不创建分支、不覆盖其他 worktree 的分支占用。允许用户在未暂存的文本 diff 中选择修改块或行，确认后仅丢弃所选工作文件内容；保留暂存区，文件或暂存区变化时拒绝执行。允许用户为单个 checkout 准备提交：设置本机 Codex、Claude Code 或 OMP 和提交 Skill，Agent 在目标 checkout 中只读获取 Git 修改、相关文件和历史，自行加载用户选择的 Skill，只生成按完整文件拆分的提交方案，用户审阅每笔说明与准确 diff 并确认后，由 MyGit 使用临时 index 顺序执行本地提交。保留未选中的暂存内容及工作文件，不绕过 hook 或签名；HEAD、分支、暂存区或相关文件变化时拒绝执行，部分成功时显示已产生的哈希并停止后续操作。允许用户从单仓库远端操作面板主动 Fetch、Pull、Push：绑定当前 checkout；仓库标题按钮按当前 upstream 直接执行并就地显示结果，右键高级面板允许明确选择远端和目标分支并确认。Pull 仅 fast-forward 且拒绝未提交修改，不自动 stash/rebase；Push 只推送当前 HEAD 到明确分支，可选择设置 upstream，不强推、不批量推送。操作显示实时 Git 输出并刷新。除此之外不要擅自加入克隆等 Git 写入和联网操作。浏览仓库时保持只读；验证切分支、Discard、提交和远端操作只使用临时仓库及本地 bare 远端。Agent 可使用其已配置的模型服务，MyGit 仅在用户点击操作按钮或确认高级面板时执行 Git 联网，不自动 fetch。

## 代码地图

- `Package.swift`：Swift Package 可执行程序，目标 macOS 14+。
- `Sources/MyGit/MyGitApp.swift`：应用入口和顶部「工作树」菜单。
- `Sources/MyGit/ContentView.swift`：侧边栏、快速切换、修改列表、提交时间线和详情视图。
- `Sources/MyGit/AppModel.swift`：工程配置、工作树组选择、刷新和持久化。
- `Sources/MyGit/Models.swift`：领域模型及工作树选择规则。
- `Sources/MyGit/CommitAgent.swift`：Agent 检测、Skill 引用加载和结构化提交方案。
- `Sources/MyGit/CommitExecution.swift`：改动快照、临时 index 和确认后的提交执行。
- `Sources/MyGit/CommitViews.swift`：提交设置与方案审阅。
- `Sources/MyGit/GitClient.swift`：调用本机 `/usr/bin/git` 读取 worktree、status、diff、log 和提交详情。
- `Tests/MyGitTests/GitClientTests.swift`：临时仓库测试与配置往返测试。

用户配置存于 `~/Library/Application Support/MyGit/config.json`。修改 Codable 模型时注意已有配置的读取兼容性。构建产物是 `dist/MyGit.app`，由 `zsh scripts/build-app.sh` 生成，`.build/` 和 `dist/` 不纳入版本控制。

## 验证与交付

代码变更后运行 `swift test`；交付可运行应用时运行 `zsh scripts/build-app.sh`，再用 `codesign --verify dist/MyGit.app` 检查包。若改动界面，尽量实际打开应用检查；若电脑控制权限不可用，要明确说明视觉验收未完成。

MyGit 已初始化为 Git 仓库，当前目录可能是额外 worktree。版本控制操作只针对 MyGit；不要把 `AndroidProjects` 下的用户仓库当作本项目的版本库，也不要为了验证 MyGit 而修改那些仓库。
