# SpriteFrames To AnimationPlayer

一个 Godot 4 编辑器插件，把 `AnimatedSprite2D` 的 `SpriteFrames` 一键转换成 `AnimationPlayer` 的动画（含 `frame` / `animation` 两条轨道），方便用 `AnimationPlayer` 统一管理、混编、过渡所有精灵动画。

- 插件版本：`1.3.3`
- 作者：AuAu
- 标签：`2d`、`animation`、`tools`
- 目标引擎：Godot 4（含 4.7 的 API 适配，如对 `AnimatedSprite2D.playing` 移除、`AnimationLibrary` 等的处理）

---

## 功能特性

- **一键转换**：`AnimatedSprite2D` 的每条 SpriteFrames 动画 → 同名 `Animation`，内含两条离散数值轨道：
  - `<sprite>:animation`：在 `t=0` 切到同名精灵动画；
  - `<sprite>:frame`：逐帧关键帧，时间轴按 `duration / fps` 铺开。
- **两个入口**：
  - 场景树面板右键选中 `AnimationPlayer` → **导入 SpriteFrames**；
  - 顶部菜单 **Project > Tools** 下的同名入口（无选区时取场景里第一个 `AnimationPlayer`）。
- **目标不写死**：右键进来的 `AnimationPlayer` 只是默认值，对话框里可切到场景内任意 `AnimationPlayer`；目标动画库也可在对话框里点选（含 `<global>` 与已有库）。
- **可勾选导入**：逐条勾选要导入的精灵动画，支持全选 / 全不选；自动跳过帧数为 0 的 `default` 动画。
- **循环保留**：原 SpriteFrames 的 `loop` 设置映射到 `Animation.loop_mode`（`LOOP_LINEAR` / `LOOP_NONE`）。
- **同名覆盖可控**：可勾选「覆盖同名动画」，未勾选时同名动画会被跳过；对话框会明确提示哪些会被覆盖 / 跳过。
- **批量导出**：勾选「对场景里所有 AnimatedSprite2D 同样处理」，每个精灵可各指定一个目标 `AnimationPlayer`，共享同一目标的同名动画会自动加节点名前缀（`PlayerAnimatedSprite_walk` 等）避免互相覆盖。
- **停掉精灵自身播放**：导入后可清除精灵的 `autoplay`、停止其自身播放，避免与 `AnimationPlayer` 抢 `frame`。
- **整体撤销**：导出（含批量）挂在 `EditorUndoRedoManager` 上，编辑器中 `Ctrl+Z` 一次即可回滚。
- **跟随编辑器语言**：内建简体中文 / 英文文案，随「编辑器设置 → 界面 → 编辑器语言」切换（zh 开头算中文，其余回落英文）。

---

## 安装

1. 把整个 `sprite_frames_to_animation_player/` 目录放到项目的 `addons/` 下（即 `res://addons/sprite_frames_to_animation_player/`）。
2. 在 Godot 编辑器里打开 **Project > Project Settings > Plugins**。
3. 找到 **SpriteFrames To AnimationPlayer**，把状态切到 **Enable**。

> 插件为 `@tool` 编辑器插件，运行时不会加载到打包后的游戏里。

---

## 使用方法

### 入口一：场景树右键

1. 在场景树面板里选中一个 `AnimationPlayer`（可多选，多选时只给一个入口，真正目标在对话框里挑）。
2. 右键 → 点击 **导入 SpriteFrames → <名称>**（或其多选区变体）。
3. 在弹出的对话框里完成设置（见下），点 **导入**。

### 入口二：顶部工具菜单

1. 选中目标 `AnimationPlayer`（不选中也会自动取场景里第一个）。
2. **Project > Tools > 导入 SpriteFrames 到 AnimationPlayer**，打开同一对话框。

### 对话框选项

| 选项 | 说明 |
| --- | --- |
| 目标 AnimationPlayer | 写入的目标，可切到场景里任意 `AnimationPlayer`。 |
| 来源 AnimatedSprite2D | 数据来源的精灵（单个模式）。 |
| 对所有精灵同样处理 | 批量模式：勾选后每个精灵各有一行「目标」下拉。 |
| 要导入的动画 | 列出来源精灵的全部 SpriteFrames 动画，可逐条勾选，显示帧数 / 时长 / 是否循环。 |
| 目标动画库 | 表格单选：`<global>`、已有库或「导入时新建」；右侧提示该库现有动画及覆盖情况。 |
| 覆盖同名动画 | 同名时覆盖（否则跳过）。 |
| 停掉精灵自身播放 | 清除 `autoplay`、停止精灵自身播放。 |

点击 **导入** 后，结果（如「已导出 N 条动画」）会同时显示在对话框底部与编辑器 Output 面板。

---

## 导出细节

- 轨道路径按 `AnimationPlayer.root_node` 计算（取 `root_node` 到精灵的 `get_path_to`）。
- 时间戳：`time += get_frame_duration(anim) / fps`，`fps` 取 `max(speed, 0.01)` 防止除零。
- 批量导出时，多个精灵共用同一目标且同名会加 `前缀_`（`prefix = sprite.name`）；独占目标的不加。
- 撤销通过 `exporter.gd` 在导出前对每个精灵拍快照（`autoplay`、`animation`、`frame`、`is_playing`、被替换/新增的动画等），回滚时还原。

---

## 目录结构

| 文件 | 职责 |
| --- | --- |
| `plugin.cfg` | 插件清单（名称、描述、版本、入口脚本）。 |
| `plugin.gd` | `EditorPlugin` 主体：注册入口、绑定右键菜单、弹对话框、挂撤销。 |
| `scene_tree_menu_hook.gd` | 钩住场景树 `PopupMenu` 的 `about_to_popup` / `id_pressed`，注入入口项。 |
| `context_menu.gd` | 右键菜单兜底（`EditorContextMenuPlugin`），以及菜单逻辑 `plan_items`。 |
| `import_dialog.gd` | 导入对话框 UI 与数据：目标/来源/库/动画/批量/覆盖等。 |
| `sprite_frames_converter.gd` | 核心转换：`SpriteFrames` → `AnimationLibrary` / `Animation`（两轨道）。 |
| `exporter.gd` | 真正执行导出与回滚，挂在 UndoRedo 上支持整体撤销。 |
| `node_finder.gd` | 递归收集场景内某类节点（`AnimatedSprite2D` / `AnimationPlayer`）。 |
| `i18n.gd` | 内建中/英文案字典，跟随编辑器语言切换。 |
| `LICENSE` | MIT 许可证全文，与商店页面选择的许可证类型一致。 |
| `AI_USAGE.md` | AI 参与开发的说明（哪些内容由 AI 生成、人工做了什么）。 |

---

## 兼容性说明

- 针对 Godot 4.7 的破坏性变更做了适配：`AnimatedSprite2D` 已无 `playing` 属性（改用 `is_playing()` / `stop()`）；`TreeItem` 无 `CELL_MODE_RADIO`（用 `CELL_MODE_CHECK` + 手动互斥实现单选动画库）等。
- 若场景树右键菜单未注入成功，插件会回退到 `EditorContextMenuPlugin` 路径（此时菜单项可能无法点击，会在 Output 提示）。

---

## 许可证

MIT License，见 `LICENSE` 文件（与 Godot Asset Store 页面选择的许可证类型一致）。

Copyright (c) 2026 AuAu

---

## AI 使用说明

本插件在开发过程中使用了 AI 辅助，具体说明见 `AI_USAGE.md`。

简述：GDScript 源码、内建中英文案与本文档的初稿由 AI 编码助手生成，随后由作者在 Godot 4.7 编辑器中逐项人工审阅、调试、修正（含右键菜单注入、UndoRedo 快照、4.7 API 破坏性变更适配等），最终代码由作者确认并负责。插件不含 AI 生成的图片、音频等素材。
