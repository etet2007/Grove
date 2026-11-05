# Grove 项目上下文

产品名称、Swift 模块、源码目录与产物均使用 Grove。Bundle ID `dev.stephenlau.mygit`、`Application Support/MyGit` 配置目录、`MyGit.Settings` 历史窗口位置键和 `MyGit Local Code Signing` 签名证书是有意保留的兼容标识；不要直接全局替换这些值。构建接受 `GROVE_*` 变量并兼容旧的 `MYGIT_*` 构建变量。历史图标探索素材中的旧名称不代表当前产品命名。

## 先读

- [README.md](README.md)：运行和首次使用方法。
- [DESIGN.md](DESIGN.md)：已确认的产品范围、交互和验收场景。
- [CONTEXT.md](CONTEXT.md)：工程、仓库组、工作树组的准确含义。
- [docs/adr/0001-discover-worktrees-from-registered-repositories.md](docs/adr/0001-discover-worktrees-from-registered-repositories.md)：仓库发现边界的原因。

## 产品边界

Grove 是原生 macOS Git 客户端，用于在一个工程中查看多个仓库及其 worktree 的未提交 diff 和本地提交记录。仓库由用户明确添加；不要按父目录、`mrepo_*` 目录或 `.mrepo-set` 自动导入。仓库组只整理导航；工作树组是跨仓库的一套 checkout 选择。同名分支自动归组，缺少对应 worktree 时沿用主检出目录，单仓库手动选择需要持久化。

允许用户点击仓库条目的分支名，从本地分支列表主动切换当前 checkout；只使用非强制 Git switch，不丢弃修改、不自动 stash、不创建分支、不覆盖其他 worktree 的分支占用。允许用户在未暂存的文本 diff 中选择修改块或行，确认后仅丢弃所选工作文件内容；保留暂存区，文件或暂存区变化时拒绝执行。允许用户为单个 checkout 准备提交：设置本机 Codex、Claude Code 或 OMP 和提交 Skill，Agent 在目标 checkout 中只读获取 Git 修改、相关文件和历史，自行加载用户选择的 Skill，只生成按完整文件拆分的提交方案，用户审阅每笔说明与准确 diff 并确认后，由 Grove 使用临时 index 顺序执行本地提交。保留未选中的暂存内容及工作文件，不绕过 hook 或签名；HEAD、分支、暂存区或相关文件变化时拒绝执行，部分成功时显示已产生的哈希并停止后续操作。允许用户从单仓库远端操作面板主动 Fetch、Pull、Push：绑定当前 checkout；仓库标题按钮按当前 upstream 直接执行并就地显示结果，右键高级面板允许明确选择远端和目标分支并确认。Pull 仅 fast-forward 且拒绝未提交修改，不自动 stash/rebase；Push 只推送当前 HEAD 到明确分支，可选择设置 upstream，不强推、不批量推送。操作显示实时 Git 输出并刷新。除此之外不要擅自加入克隆等 Git 写入和联网操作。浏览仓库时保持只读；验证切分支、Discard、提交和远端操作只使用临时仓库及本地 bare 远端。Agent 可使用其已配置的模型服务，Grove 仅在用户点击操作按钮或确认高级面板时执行 Git 联网，不自动 fetch。

## 界面一致性（必须遵守）

新增或修改界面前，必须先读 [DESIGN.md 的「全局控件视觉规范」](DESIGN.md#全局控件视觉规范)，并检查 `Sources/Grove/WorkbenchControls.swift` 中已有的共享组件。Grove 的原生技术栈不意味着使用 SwiftUI 默认控件外观；所有应用内控件必须遵循已确认的「中性深灰工作台」风格。

- 搜索框使用 `WorkbenchSearchField`，普通文本输入使用 `WorkbenchTextField`，单值下拉使用 `WorkbenchPicker`，按钮和分段选择复用现有 Workbench 样式。不要直接加入 `.roundedBorder` 输入框、默认外观的 `Picker` 或系统凸起按钮，造成同一应用中混用两套视觉语言。
- 内联编辑等需要保留独立焦点绑定的场景，复用 `WorkbenchControlSurface`；不要在业务视图中复制颜色、圆角、边框和悬停逻辑。共享组件能力不足时，先扩展共享组件，再接入业务界面。
- 主界面、设置、弹窗和弹出层遵循同一套样式。筛选栏控件基准高度 32 pt，表单输入 36 pt，统一 6 pt 圆角；同一行控件对齐，字号与高度随全局字号缩放。默认、悬停、焦点、选中、按下和禁用状态都要处理。
- 系统菜单栏、右键菜单和系统文件选择面板保留 macOS 原生交互；应用内的搜索框和单值选择器不属于这一例外。
- 界面交付不能只以编译或单元测试通过为依据。实际检查搜索输入与清除、下拉展开与鼠标选择、方向键、回车确认、Esc 取消和焦点恢复，并检查窄栏、长选项及字号缩放下的布局。验收时确认运行的是本次 `dist/Grove.app`，避免旧实例或 `/Applications` 中的旧版本干扰；无法完成的检查必须明确说明。

## 代码地图

- `Package.swift`：Swift Package 可执行程序，目标 macOS 14+。
- `Sources/Grove/GroveApp.swift`：应用入口和顶部「工作树」菜单。
- `Sources/Grove/ContentView.swift`：侧边栏、快速切换、修改列表、提交时间线和详情视图。
- `Sources/Grove/RetainedPane.swift`：按首次访问创建并保留页面，隐藏时脱离布局树，切回后复用滚动与界面状态。
- `Sources/Grove/WorkbenchControls.swift`：全局视觉 token、搜索框、输入框、下拉选择与共享交互样式。
- `Sources/Grove/AppModel.swift`：工程配置、工作树组选择、刷新和持久化。
- `Sources/Grove/Models.swift`：领域模型及工作树选择规则。
- `Sources/Grove/CommitAgent.swift`：Agent 检测、Skill 引用加载和结构化提交方案。
- `Sources/Grove/CommitExecution.swift`：改动快照、临时 index 和确认后的提交执行。
- `Sources/Grove/CommitViews.swift`：提交设置与方案审阅。
- `Sources/Grove/GitClient.swift`：调用本机 `/usr/bin/git` 读取 worktree、status、diff、log 和提交详情。
- `Tests/GroveTests/GitClientTests.swift`：临时仓库测试与配置往返测试。

用户配置存于 `~/Library/Application Support/MyGit/config.json`。修改 Codable 模型时注意已有配置的读取兼容性。构建产物是 `dist/Grove.app`，由 `zsh scripts/build-app.sh` 生成，`.build/` 和 `dist/` 不纳入版本控制。

## 验证与交付

代码变更后运行 `swift test`；交付可运行应用时运行 `zsh scripts/build-app.sh`，再用 `codesign --verify dist/Grove.app` 检查包。若改动界面，尽量实际打开应用检查；若电脑控制权限不可用，要明确说明视觉验收未完成。

Grove 已初始化为 Git 仓库，当前目录可能是额外 worktree。版本控制操作只针对 Grove；不要把 `AndroidProjects` 下的用户仓库当作本项目的版本库，也不要为了验证 Grove 而修改那些仓库。

## 应用更新发布约定

用户希望后续由 Agent 处理 Grove 的更新发布。收到相关请求时，先读 [docs/releasing.md](docs/releasing.md)，按其中流程核对版本、测试、打包和发布；已确定的信息不要重复询问。正式更新仓库地址、发布分支和本机路径尚未提供，首次确定后记入该文档。不要将本地测试仓库当作正式发布源，也不要默认重写 Git 历史。
