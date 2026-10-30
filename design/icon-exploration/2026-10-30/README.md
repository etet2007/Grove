# MyGit 图标方向探索

本轮使用内置 image_gen 分别生成三个概念。完整提示词见 prompts.json；原始生成图片保存在同目录。工具未返回费用数据。

- A / 分岔轨道：蓝色粗轨道与三节点。16 px 仍可辨识分岔，32 px 起节点关系清楚；推荐继续探索。弱点是接近常见 Git 分支符号，需要在定稿中提高轮廓独特性。
- B / 叠合工作树：青绿与米白的三层实体。64 px 能看出层次，16 px 层间距离与深色后层明显丢失，且容易被读成文件夹。
- C / 负形汇流：暖白底与朱红切口圆体。小尺寸色块醒目，但切口在 16 px 弱化，容易被理解为 C 或饼图，与 Git 的语义关联较弱。

comparison.png 包含三方向的 176 px 预览及浅、深周围背景上的 16 / 32 / 64 px 样本；这些是实际栅格尺寸，聊天中的显示可能被整体缩放。圆角为概念蒙版模拟，未验证 Icon Composer 原生外观，不代表原生 Dark 变体。

用户最终选择 `exec-3f3891d3-115c-48b0-a12d-002bf1b99f8f`，即 `A5-turquoise-blue.png` 原版（未水平翻转）。源图按字节复制至 `Resources/MyGitIcon-source.png`。`scripts/generate-icon.swift` 仅添加与旧图标一致的圆角和透明留白，生成 1024 px 的 `Resources/MyGitIcon.png`，再由现有 shell 脚本生成正式 `.icns`。本次沿用应用已有的静态 ICNS 路线，未制作 Composer 分层、原生 `.icon` 或动态外观。

生成预览：`swift design/icon-exploration/2026-10-30/make-preview.swift "$PWD/design/icon-exploration/2026-10-30"`。
