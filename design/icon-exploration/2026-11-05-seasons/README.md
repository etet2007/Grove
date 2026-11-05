# Grove 四季图标

以内置 image_gen 的 style-transfer 编辑模式生成，参考为 `../2026-11-03-green-grove/A-vector-green.png`。完整提示词见 [prompts.json](prompts.json)，未使用 API/CLI。保留单树、三枚 Git 节点、弧形分叉与层叠树冠。

- `spring.png`：粉色与鼠尾草绿，柔和纸感。
- `summer.png`：翠绿、青绿与柠檬绿，通透层叠玻璃。
- `autumn.png`：金黄、赭红与酒红，宽阔折纸切面。
- `winter.png`：冰蓝、灰蓝与午夜蓝，磨砂陶瓷雕塑。

以上保留工具输出的透明原图（1254 × 1254）。`swift scripts/generate-app-icons.swift` 对已有款和四季款统一裁切、蒙版、留白与尺寸，生成 `Sources/Grove/Resources/AppIcons/` 下的 1024 × 1024 运行时图标。默认 A 直接沿用 `Resources/GroveIcon.png`。新款只用于用户主动选择后的 Dock 和应用切换器，不替换应用包默认 ICNS。
