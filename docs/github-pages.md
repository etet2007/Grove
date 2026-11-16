# GitHub Pages 主页

[中文 README](../README.zh-CN.md) · [English README](../README.md)

主页源码位于 `site/`，使用 HTML、CSS 和原生 JavaScript，无框架、无构建依赖，不加载第三方字体或统计脚本。中英文通过页面右上角切换，偏好仅保存在浏览器本地。

## 本地预览

在仓库根目录运行：

```sh
python3 -m http.server 8080 --directory site --bind 127.0.0.1
```

然后打开 <http://127.0.0.1:8080>。资源均为相对路径，支持 GitHub Pages 的仓库子路径。也可直接打开 `site/index.html`；HTTP 预览更接近部署环境。预览结束后用 Ctrl+C 停止服务。

## 发布

正式源码仓库：[etet2007/Grove](https://github.com/etet2007/Grove)，默认分支为 `main`。产品主页：[Grove](https://etet2007.github.io/Grove/)。主页通过下述 GitHub Actions 工作流发布。

1. 将源码推送到正式 GitHub 仓库。
2. 在仓库 **Settings → Pages → Build and deployment → Source** 中选择 **GitHub Actions**。
3. 在默认分支运行 **Publish Grove homepage** 工作流；之后默认分支的 `site/` 或工作流变更会自动发布。
4. 发布地址由工作流的 `github-pages` environment 提供，检查页面、截图和中英文切换。

工作流只在仓库默认分支部署，不假定默认分支名称。GitHub Pages 的 environment 分支保护应允许该分支。流程使用 GitHub 官方的 [Pages 自定义工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

发布时自动将正式源码地址写入 `site/site-config.js`，显示 GitHub 源码与构建指南链接。本地没有配置该地址时，这两个链接隐藏，页面仍可阅读和交互。需要本地检查这两个入口时，可以在该文件中填入已经确定的正式 GitHub 仓库 URL；不要使用猜测地址。当前没有虚构下载链接；有正式安装包后再添加下载入口。

## 内容与素材

- `site/index.html`：页面结构、中英文文案和截图替代文本。`data-zh` / `data-en` 是对应翻译；图片替代文本使用 `data-zh-alt` / `data-en-alt`。
- `site/styles.css`：Grove 深灰工作台与绿色配色、响应式排版和减少动态效果支持。
- `site/app.js`：语言切换、工作树组示意、复制命令、源码链接和进入视口动画。
- `site/assets/grove-icon.png`：来自 `Resources/GroveIcon.png` 的 Grove 图标。
- `site/assets/grove-changes.png`：原生修改视图，多仓库、工作树选择与并排 diff。
- `site/assets/grove-history.png`：原生本地提交历史图与提交详情。
- `site/assets/grove-review.png`：原生跨仓库文件审阅视图。

截图使用当前源码的原生 `ContentView` 和 `AppModel` 渲染，配置与 Git 仓库位于临时目录，通过临时截图辅助程序采集；未读取用户工程配置。Orbit、orbit-app、search-kit、native-sdk 和 feature/search 均为演示内容，不代表真实客户或真实工程。截图不是 AI 生成或网页仿制界面；它们展示原生内容视图，不包含应用工具栏。用于采集的临时代码已删除，Swift 产品源码未改动。

工作树组交互是网页示意，不运行 Git，也不会创建工作树。默认展示同名分支匹配和 SDK 主目录回退；选择「主目录」后展示整套主检出目录，切回 feature/search 可恢复示例。没有 JavaScript 时，页面仍完整展示默认分组及中文内容。

更新应用截图时，继续使用独立演示配置和临时仓库，保留真实原生界面，不展示用户工程、私有远端、个人路径或凭据。CSS 负责截图取景，点击截图可打开完整原图。

## 设计与验收记录

设计方向采用 `design-taste-frontend` 的 **The product performs**（seed `297422314`），保留 Grove 的系统字体、深灰工作台和绿色品牌色，没有重抽方向。核心构思：让 Grove 的「跨仓库 checkout 选择」成为页面中可操作的说明。主要交互是切换 feature/search 与主目录，逐个看到仓库选择及回退依据。原生截图承担产品展示，分支与仓库 SVG 图标只承担示意；没有使用外部摄影、AI 生成产品截图或装饰视频。

本次检查：

- 最终静态页面在 1440、768、390 px 通过浏览器视觉检查：0 FAIL，3 WARN；逐张检查了首屏与全页截图。
- 中英文分别检查 1440、768、390、320 px，无整页横向溢出，所有标题均在两行以内。
- 验证键盘 Enter 选择工作树组、匹配与回退显示、语言切换及偏好恢复、复制命令、配置源码 URL 后的入口、无 JavaScript 阅读与 `file://` 直接预览。浏览器未捕获 JavaScript 异常。
- JavaScript 语法、静态资源与锚点、工作流 YAML 解析、`git diff --check` 均通过。
- 原生截图采集辅助程序在临时仓库中运行成功；不把这次素材采集视为应用完整界面验收，未重新打包发布 App。生产 Swift 源码没有变更。

保留的设计提示：没有匹配本次需求的真实操作视频，因此以截图与分组交互说明产品；15 个进入视口的动效元素保持克制，并支持系统减少动态效果；手机端字号包含正文、辅助文字、导航与标题层级，未为了减少字号种类牺牲内容可读性。

最终视觉自评（非外部评分）：

```text
ROUND 3
Seen in one second: Grove native Mac Git client with a real multi-repository change view.
Idea (one sentence): Cross-repository checkout selection becomes an interactive explanation.
Live thing: Select feature/search or Primary Checkout and see matching and fallback per repository.
Layout words by section: hero=wide product view / worktrees=selector and map / review=asymmetric crops / commits=paired prose / start=setup panel
Scores: design 7.5 · usability 8.0 · creativity 7.0 · content 8.0 → overall 7.6
Caps applied: None; 15 individually triggered entrances and the working selector provide deliberate motion. No video is retained as a stated limitation.
Top three problems and disposition:
1. mobile-fold: the first version required horizontal scrolling to inspect the hero screenshot; now the full screenshot fits, with a full-size image link.
2. tablet-fold: the first version placed the headline lower than its supporting copy; now both align at the top.
3. desktop-page-01: the history crop showed an empty commit in the first capture; the final demo history uses commits with actual file changes.
```

仍可继续完善：可下载且经验证的安装包，以及一段演示工作树组切换的真实录屏。当前截图为中文界面；网站文案与图片替代文本同时提供中英文。演示仓库名称和内容可保留为示例，正式发布前无需替换为用户真实工程。
