# Environment FX（addon）

Godot 4.x 程序化 2D 雾 / 雨特效。本目录可整体复制到任意工程的 `addons/` 下使用。

## 包含内容
- `fog.gd` / `fog.tscn` / `fog.gdshader` —— 雾
- `rain.gd` / `rain.tscn` / `rain.gdshader` —— 雨
- `snow.gd` / `snow.tscn` / `snow.gdshader` —— 雪
- `plugin.cfg` / `plugin.gd` —— 插件入口（无编辑器 UI）

## 快速接入
1. 复制本目录到你的工程 `addons/environment_fx/`。
2. 项目设置 → 插件 → 启用 `Environment FX`（可选）。
3. 实例化 `fog.tscn` / `rain.tscn`，或在场景里添加 `Fog` / `Rain` 节点。
4. 在检查器调节导出参数即可。

## 关键参数（Fog / Rain / Snow）
`size`、`region_enabled`、`region_fade`、`elliptical`、`cloud_noise_scale`、
`coverage`、`softness`、`edge_noise`、`density_variation`、`edge_margin`、
`edge_gamma`、`density`、`thickness`、`fog_color`（Rain 为 `rain_color`，Snow 为 `snow_color`）、
`angle_deg`（Rain / Snow：下落角度 / 风向）、`chaos`（Rain / Snow：紊乱度 / 漂移）、
`rain_speed`（仅 Rain：下落速度倍率）、`snow_speed`（仅 Snow：下落速度倍率，
默认 0.8，比雨更慢）、
`flake_shape`（仅 Snow：雪片形态，枚举 `0=柔六瓣` `1=柔圆点` `2=六角晶体`
`3=散景大圆` `4=闪烁亮片`，默认 `0`）、
`activate_with_player`、`fade_duration`、`layer_scales`、`scroll_scale`、`draw_z`。

三个类的公开接口、参数范围与默认值保持一致，可互相替换；
区别仅在视觉表现（雾 = 云雾噪声，雨 = 下落雨丝，雪 = 柔和六瓣雪花，均无外部贴图）。
**雪相对雨的差异**：雪删除了雨丝线性拉伸 `trail_scale` 与水珠头 `droplet` / `drop_size` /
`drop_stretch` / `drop_brightness` 等参数，改为程序化雪花，并提供 `flake_shape` 形态选择器
（柔六瓣 / 柔圆点 / 六角晶体 / 散景大圆 / 闪烁亮片）。
雪比雨更慢、更柔（默认 `coverage=0.45`、`softness=0.7`、`chaos=0.6`、
`snow_speed=0.8`、`density=0.4`）；因雪花是实心占面积，密度默认值已刻意调低以避免白幕，
需要更密可在面板 / 检查器上调高 `coverage` / `density`。雪片尺寸由 `thickness` 控制，
最大半径约 `0.3`（单格局部单位，近景层像素直径约 38px）。

## 雪：实现要点与排错
- **无缝平铺**：雪花在正方形网格单元内下落并用 `fract` 回卷；每片叠加「单元边缘渐隐窗」，
  在触及单元边界前淡出，消除平铺接缝处的硬切 / 闪烁，跨 Parallax2D 平铺块天然无缝。
- **形态选择器 `flake_shape`**：纯程序化（无贴图），五态由着色器内 `snowflake()` 对
  `spine` / `core` / `glow` 分量的取舍，外加闪烁亮片的 `TIME` 相位切换实现；对外仅一个枚举下拉。
- **排错：场景整屏纯白**：通常不是密度问题，而是**着色器编译失败**——
  Godot 会把编译失败的 CanvasItem 回退成默认白色矩形。请在「输出」面板查看 `SHADER ERROR`
  （例如重复定义内置常量 `TAU` 等），修正后白屏即消失。

## 演示场景
- `main.tscn` —— 示例选择菜单（雾 / 雨 / 雪三个入口）
- `scenes/demo/fog.tscn` —— 雾效演示（控制面板实时调参）
- `scenes/demo/rain_demo.tscn` —— 降雨演示（与雾效演示同一套控制项与布局）
- `scenes/demo/snow_demo.tscn` —— 降雪演示（同上一套控制项与布局，去掉水珠头 / 拖影；
  新增「雪片形态」下拉框切换 `flake_shape`，历史记录已纳入该参数）

## 依赖边界
仅依赖 Godot 内置节点与程序化噪声（`NoiseTexture2D` + `FastNoiseLite`），
**无需任何外部贴图 / 音频资源**。角色检测通过 `body.is_in_group("player")` 实现，
请让你的玩家节点加入 `"player"` 组。
