# 同形材质图标

使用内置 image_gen 的 style-transfer 编辑模式，以 `../2026-11-03-green-grove/A-vector-green.png` 为唯一参考重新生成。提示词见 [prompts.json](prompts.json)。

- `folded-single-tree.png`：蓝、青、淡紫的层叠纸质浮雕。
- `sculpted-single-tree.png`：紫色切面陶瓷浮雕。

两款均保留 A 的单树、三枚圆形 Git 节点、弧形分叉、喇叭形树干及圆弧层叠树冠。替代旧三棵树林的 E/F 运行时图标，旧探索原图保留。设置中与 A/B/A2 合并到「通用」组。运行 `swift scripts/generate-app-icons.swift` 生成统一尺寸、圆角与透明留白的应用资源。
