# MyGit 项目上下文

## 先读

- [README.md](README.md)：运行和首次使用方法。
- [DESIGN.md](DESIGN.md)：已确认的产品范围、交互和验收场景。
- [CONTEXT.md](CONTEXT.md)：工程、仓库组、工作树组的准确含义。
- [docs/adr/0001-discover-worktrees-from-registered-repositories.md](docs/adr/0001-discover-worktrees-from-registered-repositories.md)：仓库发现边界的原因。

## 产品边界

MyGit 是只读的原生 macOS Git 客户端，用于在一个工程中查看多个仓库及其 worktree 的未提交 diff 和本地提交记录。仓库由用户明确添加；不要按父目录、`mrepo_*` 目录或 `.mrepo-set` 自动导入。仓库组只整理导航；工作树组是跨仓库的一套 checkout 选择。同名分支自动归组，缺少对应 worktree 时沿用主检出目录，单仓库手动选择需要持久化。

不要擅自加入暂存、提交、切分支、克隆、fetch 或 push 等 Git 写入和联网操作。读取用户仓库时保持只读；测试使用临时仓库。

## 代码地图

- `Package.swift`：Swift Package 可执行程序，目标 macOS 14+。
- `Sources/MyGit/MyGitApp.swift`：应用入口和顶部「工作树」菜单。
- `Sources/MyGit/ContentView.swift`：侧边栏、快速切换、修改列表、提交时间线和详情视图。
- `Sources/MyGit/AppModel.swift`：工程配置、工作树组选择、刷新和持久化。
- `Sources/MyGit/Models.swift`：领域模型及工作树选择规则。
- `Sources/MyGit/GitClient.swift`：调用本机 `/usr/bin/git` 读取 worktree、status、diff、log 和提交详情。
- `Tests/MyGitTests/GitClientTests.swift`：临时仓库测试与配置往返测试。

用户配置存于 `~/Library/Application Support/MyGit/config.json`。修改 Codable 模型时注意已有配置的读取兼容性。构建产物是 `dist/MyGit.app`，由 `zsh scripts/build-app.sh` 生成，`.build/` 和 `dist/` 不纳入版本控制。

## 验证与交付

代码变更后运行 `swift test`；交付可运行应用时运行 `zsh scripts/build-app.sh`，再用 `codesign --verify dist/MyGit.app` 检查包。若改动界面，尽量实际打开应用检查；若电脑控制权限不可用，要明确说明视觉验收未完成。

当前工作目录本身尚未初始化为 Git 仓库。不要把 `AndroidProjects` 下的用户仓库当作本项目的版本库，也不要为了验证 MyGit 而修改那些仓库。
