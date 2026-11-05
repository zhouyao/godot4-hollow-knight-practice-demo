# 关卡 / 转场系统使用清单

> 本文覆盖：常驻根场景架构、区域（Area）制作流程、入口 / 转场门 / 长椅 / 雾门 / 视野剔除 / 可拖拽相机边界、存档字段、调试与已知坑、全项目组件索引。
> 所有内容与当前仓库代码一一对应，改代码时请同步更新本文件。
>
> - 想快速上手做一块新地图：读第三节
> - 想查某个参数默认值：读第四节
> - 想找某个系统/组件在哪、干什么：读第九节

---

## 一、架构速览

```
main.tscn ──change_scene──▶ game_root.tscn（常驻，永不卸载）
							  ├─ WorldHost      ← 只换这里面的 Area
							  ├─ Player         ← 常驻，切关只"搬家"
							  ├─ AuCameraRig    ← 常驻
							  ├─ Hud / SkillBar ← 常驻，不重建
							  └─ FxHost
									 ↑
					 GameSession 异步挂载 level_N.tscn（WorldArea）
```

核心决策：

- **Player 常驻**，切关时先 `remove_child` 再从旧 Area 摘下，新 Area 挂载后插回 `Drops` 之前，保持原本的绘制顺序（前景仍盖住玩家）。
- **HUD / 技能条 / 相机只绑定一次**，切关不重来，因此血量、能量、技能冷却、镜头锁定全部连续。
- **Area 只是纯内容**，不含 Player / HUD / 相机 / 暂停 / 死亡结算。

| 层 | 文件 | 职责 |
| --- | --- | --- |
| 会话 | `globals/autoload/GameSession.gd` | 换关、入口定位、flags、跨关广播 |
| 黑场 | `globals/autoload/transition_layer.gd` | 淡入淡出、场景预加载 |
| 存档 | `globals/autoload/SaveManager.gd` | area_path / entry_id / flags |
| 根场景 | `scenes/worlds/game_root.tscn` + `.gd` | 玩家 / HUD / 相机 / 暂停 / 死亡 |
| 区域底座 | `scenes/worlds/_base/world_template.tscn` | 关卡内容骨架 |
| 区域脚本 | `scenes/worlds/_base/world_template.gd`（`class_name WorldArea`） | `zone_name` / `get_entry()` |

---

## 二、目录地图

```
scenes/worlds/
  game_root.tscn / game_root.gd        常驻根场景
  _base/
	world_template.tscn / .gd          区域底座（WorldArea）
	entry_point.tscn / .gd             入口标记（EntryPoint）
	level_gate.tscn / .gd              转场门（LevelGate）
	boss_fog_gate.tscn / .gd           BOSS 雾门（BossFogGate）
	view_culler.gd                     全局视野剔除（ViewCuller，常驻在 game_root）
	camera_bounds_rect.gd              可拖拽的相机边界矩形（CameraBoundsRect）
  levels/
	level_1.tscn / level_1.gd          区域：遗忘荒径
	level_2.tscn                       区域：试炼回廊
scenes/props/
  bench/bench.tscn / bench.gd          长椅存档点（Bench : EntryPoint）
  chest/chest.tscn / chest.gd          木箱（含 persistent_id）
scenes/ui/
  toast.tscn / toast.gd                轻量提示条
globals/autoload/
  GameSession.gd                       跨关卡会话
  transition_layer.gd                  黑场 + 场景加载
  SaveManager.gd                       存档（v2）
```

autoload 顺序（`project.godot`）中 `GameSession` 放在最后，因为它依赖 `TransitionLayer` 与 `SaveManager`。

---

## 三、操作清单

### A. 新建一块区域

- [ ] 复制 `scenes/worlds/levels/level_2.tscn` 作为模板
- [ ] 改根节点名（如 `WorldLevel3`）
- [ ] 设 `zone_name`（存档页显示的名字）
- [ ] 在 2D 编辑器里拖 `CameraBounds/CollisionShape2D` 的 handles，把绿框调到"镜头中心能走的范围"（见 G 节）
- [ ] 在 `LevelTransitions/Entries` 下至少放一个名为 `default` 的 `EntryPoint`
- [ ] 在 `KillBox` 下补 `CollisionShape2D`，覆盖整张地图
- [ ] 用 F6 单独跑一遍确认能玩

> **不要在关卡里放 Player / Hud / SkillBar / AuCameraRig** —— 它们属于 `game_root`，重复放置会出现两个玩家。

### B. 加一个入口点

- [ ] 实例化 `scenes/worlds/_base/entry_point.tscn`，挂到 `LevelTransitions/Entries`
- [ ] 节点名 = 入口 ID（`entry_id` 留空时自动取节点名）
- [ ] 位置：**地面 y − 75**（玩家胶囊中心；地面 500 → 入口 y=425）
- [ ] 需要朝向时设 `facing`：`0` 不改变 / `1` 朝右 / `-1` 朝左

### C. 加一扇转场门

- [ ] 实例化 `scenes/worlds/_base/level_gate.tscn`，挂到 `LevelTransitions/Gates`
- [ ] `target_area` 填目标场景路径
- [ ] `target_entry` 填目标区域的入口 ID
- [ ] `gate_id` 填**回程入口 ID**（留空则用节点名）—— 防止从对面走回来立刻被弹回去
- [ ] 需要"必须站在地上才触发"时开 `requires_ground`

门自带三重防重入：触发后上锁 → 玩家离开触发区才解锁 → 换关后若出生点就是本门则保持上锁。

### D. 加一张长椅（存档点）

- [ ] 实例化 `scenes/props/bench/bench.tscn`，挂到 `LevelTransitions/Entries`
- [ ] 节点名 = `entry_id`（复活点 ID）
- [ ] 位置同样按"地面 y − 75"
- [ ] 参数：`save_on_rest`（默认 true）、`rest_cooldown`（1.5s）、`flash_time`（0.25s）

行为：碰到即存档 → 复活点切到本椅 → 存档坐标**钉在椅子位置**（不是玩家蹭到的位置）→ 弹提示条 → 发 `rested` 信号。

`Bench` 继承 `EntryPoint`，所以 `WorldArea.get_entry()` 能直接按 `entry_id` 找到它，不需要额外配"椅子对应哪个入口"。

### E. 加一扇 BOSS 雾门

- [ ] 实例化 `scenes/worlds/_base/boss_fog_gate.tscn`，挂到 `LevelTransitions/Gates`
- [ ] `boss_node` 指向 BOSS 根节点（相对路径）
- [ ] 节点原点 = 雾墙中心，摆在竞技场入口

| 事件 | 动作 |
| --- | --- |
| BOSS `enter_combat` | 落墙 + 雾淡入（挡住退路） |
| BOSS `boss_defeated` | 撤墙 + 雾淡出 |
| 读档时 BOSS 已击败 | 直接保持敞开 |

> 不监听 `leave_combat`：否则玩家跑远脱战就能把门重新打开，雾门形同虚设。

### F. 视野剔除（ViewCuller）

全局常驻在 `game_root.tscn`，**关卡里零配置**。换关时自动扫描当前区域，只保留"看得见 + 战斗中"的对象。

**唯一入口是分组**：只有把节点加入 `view_cull` 组，它才会被剔除。没有默认覆盖、没有隐式列表。

接入一个对象：

- [ ] 在关卡里的**实例**上加 `groups=["view_cull"]`
- [ ] 确认它的逻辑**可以被安全冻结**

> 本项目统一按实例声明：敌人基类 `enemy.tscn`、草场景 `grass.tscn` 都不带这个组，
> 所以每只怪、每株草都可以单独决定参不参与。

当前在组里的：

| 位置 | 覆盖 |
| --- | --- |
| `level_1` 的 5 个敌人实例 | Crawlid / Vengefly / Mosscreep / EnemyGround / EnemyFlying2 |
| `level_2` 的 2 个敌人实例 | EnemyGround / Crawlid |
| `level_1` 的 4 个草实例 | `Grass0` / `Grass2`（`Efffects_0/`）、`Grass1` / `Grass3`（`Effects/`） |

> **敌人基类 `enemy.tscn` 刻意不加这个组** —— 挂在基类上会强制所有实例参与、无法逐个关闭。
> 要控制到"这只参与、那只不参与"，就在关卡里的**实例**上加 `groups=["view_cull"]`。
> BOSS 场景 `boss.tscn` 也不在组里，`is Boss` 检查只是误加时的保险。

保护规则不看分组，只看节点自身状态（装饰节点没有这些属性，探测天然为假）：

| 条件 | 效果 |
| --- | --- |
| `combat_active == true` | 永不静默（防止玩家跑出屏幕脱战） |
| `is Boss` 或 `persistent_id` 非空 | 永不静默（阶段性演出 / 一次性精英） |

> **绝对不能加**：`Pickup`（存活时间在 `_physics_process` 里累加，冻结后永不消失）、转场门、长椅、BOSS 触发器、AuZone、AuCameraLockArea。
> 静态且没有 `_process` 的节点（如宝箱）加了也没有收益 —— Godot 对视口外的 `CanvasItem` 本来就有渲染裁剪。

静默动作：`visible` + `process_mode` + 子级 `CollisionShape2D.disabled` + 音频 `stream_paused`。

判定用**两个圈**做迟滞：进入视野外扩 `activate_margin`（默认 600）才唤醒，退出 `activate_margin + hysteresis`（默认 800）才静默，避免边界反复开关。

### G. 相机边界（可拖拽矩形）

`world_template.tscn` 预置了一个 `CameraBounds` 节点（`CameraBoundsRect`，`@tool` Area2D），下挂一个 `CollisionShape2D`（`RectangleShape2D`）。所有关卡继承后自动带一份。

> **矩形 = 相机「中心」允许活动的范围**，不是屏幕边的硬边界。
> 这是刻意选的语义：拖的框就是"镜头能走到哪"，不必理解 Godot 的 `limit_*` 钳的是屏幕四条边。

**编辑器里怎么用**

- [ ] 打开关卡场景，切到 2D 视图
- [ ] 选中 `CameraBounds/CollisionShape2D`，**直接拖黄色 handles** 改矩形大小（Godot 原生交互，无需插件）
- [ ] 拖 `CameraBounds` 节点本身 = 整体平移
- [ ] 绿框 = 你拖的框；红色外框 = 外扩 half 后的实际可见范围
- [ ] **两个框内部默认完全透明**（`fill_alpha = 0`），只留描边，不遮挡关卡内容；内部子节点 `CollisionShape2D` 的调试背景色也由 `fill_alpha` 控制，`world_template.tscn` 里直接存了 `debug_color = Color(0, 0.6, 0.7, 0)` 做双保险
- [ ] 绿框四角有实心圆：`corner_color` 配色、`corner_size` 调半径，视图缩小时自动放大
- [ ] `debug_draw`（默认开）控制整组提示；运行时 `_process` 关闭、`_draw` 直接返回，零开销
- [ ] 编辑器拿不到运行时的 `rig.zoom`，红框按 `preview_zoom`（默认 `Vector2.ONE`）画；**若关卡默认 zoom 不是 1，把它填成同值**

**换算**（组件内部做，`GameSession._apply_camera_bounds()` 只取结果）：

```
half = 视口尺寸 / (2 * zoom)          # 本项目 zoom=1 → (960, 540)

limit_left   = rect.position.x − half.x
limit_right  = rect.end.x      + half.x
limit_top    = rect.position.y − half.y
limit_bottom = rect.end.y      + half.y
```

把框的**下边缘**拖到玩家站立高度附近即可（地面 y=500 → 玩家中心 425）；组件会自动补出 `bottom = 425 + 540 = 965` 以上，不会再出现"镜头被顶高、玩家贴屏幕下方"。

**当前两关的框**

| 区域 | 中心范围 Rect2 | CollisionShape2D `size` / `position` | 生效 limits |
| --- | --- | --- | --- |
| level_1 | `Rect2(-3000, -960, 9888, 1425)` | `9888×1425` / `(1944, -247.5)` | `-3960, -1500, 7848, 1005` |
| level_2 | `Rect2(640, -250, 2880, 710)` | `2880×710` / `(2080, 105)` | `-320, -790, 4480, 1000` |

与改造前的手动值几乎完全一致；level_2 的 `get_screen_center_position()` 实测 `(612, 411)`，取景未变化。

**注意事项**

- **`resource_local_to_scene = true` 必须保留**：`RectangleShape2D` 是子资源，默认在继承场景间共享，否则改 level_1 的框会把 level_2 的一起改掉。脚本 `_ready()` 里还有一次 `duplicate()` 兜底。实测 `shapes independent = true` ✓
- **用 shape handles 改大小，不要缩放节点**：组件按 `shape.size × global_scale` 计算，缩放节点虽然也能用，但编辑器里不直观
- **地图加内容后要手动拖一下**：这是本方案的取舍（换掉了自动扫描那套复杂度）
- **zoom 变化会自动重算**：`AuCameraRig.zoom_changed` 信号（含 tween 逐帧）→ `GameSession.refresh_camera_limits()` → 四条 limit 同步更新。也可手动调 `GameSession.refresh_camera_limits()`
- **`resource_local_to_scene = true` 与 `_own_shape()`**：前者保证继承场景间不共享 shape；后者只在运行时 `duplicate()` 兜底，编辑器里跳过，否则保存关卡时会把拖好的尺寸改写成一条 shape override
- 形状无效（删了 CollisionShape2D 或换成非矩形）时回落 `±1000 万`，等于不限制

**验证方法**：运行时打印 `get_viewport().get_camera_2d().get_screen_center_position()`，让玩家走到四个角，检查中心是否被钳在 `rect` 内。

### H. 加一个一次性物件

- [ ] 在 `chest.tscn` 实例上填 `persistent_id`，命名带区域前缀，如 `chest:level_2/02`
- [ ] 留空 = 换关 / 读档后重新出现

代码侧：

```gdscript
if GameSession.has_flag(id):
	# 已经发生过：恢复成"已完成"状态
GameSession.set_flag(id)   # 随下一次 save_game() 落盘
```

BOSS 用 `SaveManager.mark_defeated()`（**立刻写盘**）；普通箱子用 `set_flag()`（**下次存档才写**）。

### I. 弹一条提示

```gdscript
var toast := preload("res://scenes/ui/toast.tscn").instantiate() as Toast
add_child(toast)
toast.show_text("已保存")
```

文案走 `TranslationServer`，源文案即 key。Toast 层级 115（技能条 110 之上、死亡遮罩 120 之下），淡入 0.2s → 停留 1.4s → 淡出 0.3s → 自毁。

---

## 四、参数速查

### GameSession

| 成员 | 说明 |
| --- | --- |
| `travel_to(area_path, entry_id)` | 运行时换关（淡出 → 换 Area → 淡入） |
| `bootstrap(area_path, entry_id)` | 启动用，**不做淡入**（调用方负责） |
| `current_area_path` / `current_entry_id` | 当前区域 / 入口 |
| `content_root()` | 临时物件该挂的根节点（弹幕 / 特效 / 掉落） |
| `has_flag(id)` / `set_flag(id)` | 一次性事件 |
| `zone_name()` | 当前区域名 |
| `snap_camera()` | 相机瞬移到玩家 |
| `bind_root(root)` | 由 GameRoot 在 `_ready` 注入；同时连接 `AuCameraRig.zoom_changed` |
| `refresh_camera_limits()` | 重算相机四条 limit；换关时自动调用，zoom 变化时由信号自动触发 |
| `is_traveling()` | 是否正在换关 |
| `reset()` | 回主菜单时清引用 |
| 信号 | `area_load_started(area_path)` / `area_changed(area_path, entry_id)` / `rested(bench_id)` |

### TransitionLayer

| 方法 | 说明 |
| --- | --- |
| `fade_out(t := -1)` / `fade_in(t := -1)` | 纯黑场，默认 0.45s |
| `change_scene(path)` | 只负责淡出 + 切场景，**目标场景必须自己调 `fade_in()`** |
| `prefetch(path)` | 后台线程预加载（菜单停留时预热） |
| `set_black(bool)` | 立即全黑 / 全透明 |
| 信号 | `faded_out` / `faded_in` |

### WorldArea

| 成员 | 说明 |
| --- | --- |
| `@export zone_name` | 存档页显示的区域名 |
| `get_entry(entry_id) -> Node2D` | 查找顺序：`Entries` → `LevelTransitions` 直属子节点 → 全树按 `entry_id` 扫描 |

### CameraBoundsRect

| 成员 | 说明 |
| --- | --- |
| `@export debug_draw` | `true`，编辑器 2D 视图画绿框 + 红色外框（运行时无效） |
| `@export fill_alpha` | `0.0`，绿框填充**与** `CollisionShape2D.debug_color.a` 的不透明度；默认全透明，调大才铺色块 |
| `@export corner_color` | `Color(0.30,1.0,0.45,0.95)`，绿框四角实心圆的颜色 |
| `@export corner_size` | `20.0`，四角实心圆半径（世界单位），缩小时自动放大 |
| `@export preview_zoom` | `Vector2.ONE`，编辑器画红框时假定的 zoom（运行时不读，用 `rig.zoom`） |
| `get_center_rect() -> Rect2` | 相机中心允许活动的世界矩形（来自 `CollisionShape2D` 的 shape） |
| `get_camera_limits(zoom, viewport_size) -> Rect2` | 换算成 Camera2D 四条 limit，由 `GameSession` 换关时调用 |

### EntryPoint / LevelGate / Bench / BossFogGate / ViewCuller / Chest

| 类 | 参数 | 默认 |
| --- | --- | --- |
| `EntryPoint` | `entry_id` / `facing` | `&""`（取节点名） / `0` |
| `LevelGate` | `target_area` / `target_entry` / `gate_id` / `requires_ground` | `""` / `&"default"` / `&""` / `false` |
| `Bench` | `save_on_rest` / `rest_cooldown` / `flash_time` | `true` / `1.5` / `0.25` |
| `BossFogGate` | `boss_node` / `fade_time` | `NodePath()` / `0.35` |
| `ViewCuller` | `enabled` / `check_interval` / `activate_margin` / `hysteresis` / `protect_in_combat` / `cull_audio` / `debug_draw` | `true` / `0.15` / `600` / `200` / `true` / `true` / `false` |
| `Chest` | `persistent_id` | `""` |

### SaveManager

| 成员 | 说明 |
| --- | --- |
| `save_game(force := false, respawn_anchor := null)` | `respawn_anchor: Vector2` 可钉住复活坐标 |
| `current_scene_path()` | 读档要进的区域（兼容旧 `scene_path`） |
| `current_entry_id()` | 读档要进的入口 |
| `is_flagged(id)` / `mark_flag(id)` / `flag_list()` | 一次性事件 |
| `is_defeated(id)` / `mark_defeated(id)` | BOSS 永久击败（立即写盘） |
| `apply_pending_state(root)` | 读档回填（**必须在 `bootstrap()` 之后调用**） |

存档字段（v2）：

```json
{
  "version": 2,
  "area_path": "res://scenes/worlds/levels/level_2.tscn",
  "scene_path": "…（旧字段，兼容保留）",
  "entry_id": "bench_03",
  "zone": "试炼回廊",
  "player": { "x": 2600, "y": 425, "health": 8, "max_health": 8, "energy": 5, "max_energy": 10, "facing": 1 },
  "inventory": {},
  "monarch_wings": true,
  "defeated": ["hollow_knight"],
  "flags": ["chest:level_2/01"]
}
```

读 v1 旧档时自动补 `area_path` / `entry_id` / `flags`，下次存档升级为 v2。

---

## 五、调试清单

| 目的 | 做法 |
| --- | --- |
| 单关调试 | 在编辑器里 F6 直接跑 `level_*.tscn` —— 自动补玩家 + 相机（无 HUD） |
| 快速验证可加载 | `Godot --headless --path . res://scenes/worlds/game_root.tscn --quit-after 180` |
| 刷新导入缓存 | `Godot --headless --editor --quit` |
| 检查泄漏 | 临时探针读 `Performance.get_monitor(Performance.OBJECT_NODE_COUNT)`，往返切关对比 |
| 检查存档 | `~/Library/Application Support/Godot/app_userdata/Misted/saves/slot_N.json` |
| 模拟输入 | `Input.action_press("right")` + `player.buffer_jump()`（走真实状态机，不是假传送） |

基准数据（当前内容）：level_1 ↔ level_2 往返 3 轮，节点数稳定在 **664**、对象数稳定在 **4628**，无泄漏。

---

## 六、已知坑

- [ ] **IDE 报 `Identifier "GameSession" not declared`** —— 语言服务器缓存了旧 autoload 列表，重启编辑器即消失（引擎侧已用 headless 验证正常）
- [ ] **`get_tree().current_scene` 现在是 `game_root`** —— 任何"把东西挂到当前场景"的代码要改用 `GameSession.content_root()`
- [ ] **新区域里放 Player** —— 会与常驻玩家冲突
- [ ] **`change_scene` 后一直黑屏** —— 目标场景没调 `TransitionLayer.fade_in()`
- [ ] **镜头上抬、玩家贴屏幕底部** —— `CameraBounds` 绿框的下边缘没拖到玩家站立高度附近（见 G 节）
- [ ] **改一个关卡的框，别的关卡跟着变** —— `RectangleShape2D` 丢了 `resource_local_to_scene = true`（脚本 `_ready()` 有 `duplicate()` 兜底）
- [ ] **镜头边界完全不生效** —— 检查 `CameraBounds/CollisionShape2D` 的 shape 是不是 `RectangleShape2D`、size 是否 > 0；无效时回落 `±1000 万`
- [ ] **地图加内容后镜头范围没变** —— 这是本方案的设计取舍，需要手动再拖一次框
- [ ] **台阶挡住通行** —— 台阶底部要高于 `地面 y − 75 − 40`（玩家头顶 350）
- [ ] **`view_cull` 组里放了有自毁计时的节点（如 `Pickup`）** —— 冻结后 `_age` 不再增长，节点永不消失
- [ ] **ViewCuller 突然不生效** —— 先看 `enabled`，再确认目标在当前区域的子树里（它只收 `current_area` 的后代）
- [ ] **某个节点不参与剔除** —— 检查该**实例**上有没有 `groups=["view_cull"]`（`enemy.tscn` / `grass.tscn` 都刻意不带，漏加不会报错）
- [ ] **长椅不触发** —— 检查节点是否带 `entry_id`（留空时自动取节点名），且 ID 在同一区域内唯一
- [ ] **改 `.tscn` 的 `index` / `unique_id`** —— 会打乱继承节点的顺序与 `parent_id_path` 引用
- [ ] **`apply_pending_state` 早于 `bootstrap`** —— 存档坐标会被入口落点覆盖

---

## 七、当前关卡内容

### level_1（遗忘荒径，x -4000..8000）

| 类型 | 节点 | 坐标 / 配置 |
| --- | --- | --- |
| 入口 | `default` | (4700, 200) |
| 入口 | `from_level_2` | (-3100, 425) |
| 长椅 | `bench_01` | (4600, 425) |
| 门 | `ToLevel2` | (-3400, 425) → level_2 / `from_level_1` |
| 雾门 | `HollowKnightFog` | (2000, 200) |
| 雾门 | `SoulMasterFog` | (5000, 200) |

> 敌人与草丛的离屏剔除由常驻的 `ViewCuller` 统一处理：5 个敌人实例与 4 个草实例各自声明了 `groups=["view_cull"]`，关卡里不再有房间节点。

`SoulMaster` 的 `BossArenaBehavior.auto_start_fight` 已改为 `true`（踏入竞技场即触发入场演出并开战）。

### level_2（试炼回廊，x -320..4480）

| 类型 | 节点 | 坐标 / 配置 |
| --- | --- | --- |
| 地面 | `Floor1A` | x -320..896 |
| **深沟** | — | **x 896..1456（560px，需二段跳）** |
| 地面 | `Floor1B` | x 1456..4080 |
| 台阶 | `Ledge1` / `2` / `3` / `4` | y=300 / 220 / 300 / 220 |
| 入口 | `default` / `from_level_1` | (-200, 425) / (-100, 425) |
| 长椅 | `bench_02` / `bench_03` | (300, 425) / (2600, 425) |
| 门 | `ToLevel1` | (150, 425) → level_1 / `from_level_2` |
| 宝箱 | `Chest1` / `Chest2` | (60, 500) / (3300, 500)，`persistent_id` 分别为 `chest:level_2/01`、`chest:level_2/02` |
| 敌人 | `EnemyGround` / `Crawlid` | (1800, 423) / (3600, 423) |

**能力门槛实测**（真实输入模拟，非假传送）：

| 能力 | 最远落点 | 结果 |
| --- | --- | --- |
| 单跳（`has_monarch_wings = false`） | x ≈ 1253 | 掉进沟里，`floor = false` |
| 二段跳（`has_monarch_wings = true`） | x ≈ 1483 | 落在 Floor1B 上，`floor = true` |

单跳射程约 458px、二段跳约 782px，560px 的沟宽正好卡在两者之间，两侧各留约 120px 余量。

---

## 八、死亡与复活链路

```
玩家在任意位置死亡
  → GameRoot._start_death_sequence()：暂停 → 播死亡动作 → 黑场倒数 3 秒
  → Globals.return_to_save_select()：回主菜单并停在存档选择页
  → 玩家点存档槽 → SaveManager.load_game() → change_scene(game_root)
  → GameSession.bootstrap(area_path, entry_id)：加载区域并落到入口
  → SaveManager.apply_pending_state()：存档坐标覆盖入口落点
```

死亡全程**不写存档**，所以复活点永远是最后一次休息的长椅。已验证：雾门内死亡 → 重登回到 `bench_01`。

---

## 九、组件索引

按“解决什么问题”分组，覆盖全项目的功能性组件及其实际落点。

> 与第二节的区别：第二节是**本次改造新增/改动的文件**；本节是**全项目组件地图**，包含插件与既有系统。

### 9.1 区域与空间查询（Zone 系）

| 组件 | 位置 | 作用 | 关键参数 | 项目内实例 |
| --- | --- | --- | --- | --- |
| `AuZone` | `addons/zone_director/AuZone.gd` + `scenes/zone.tscn` | 通用区域：回答“谁在里面”，并参与通道仲裁；编辑器里矩形中间与内部 `CollisionShape2D` 背景都透明、四角画可配色的实心三角形 | 五组：通道 / 形状 / 嵌套 / 检测 / **编辑器预览**（`show_corners_in_editor` / `fill_alpha` / `corner_color` / `corner_size`） | level_1 `EnemyZones/EnemyZone`、`EnemyZone2`、`BossArena`×2、`GrassZone`×4、`RainZone`×2；level_2 `EnemyZones/EnemyZone` |
| `AuZoneDirector` | autoload | 通道仲裁中心：同一通道多层区域时决定谁生效 | `surface()` / `has_tag()` / `top_of(channel)` | 全局常驻 |
| `AuZoneBehavior` | `addons/zone_director/AuZoneBehavior.gd` | 区域行为基类，挂在 AuZone 子节点 | `on_entered` / `on_exited` / `on_gained` / `on_lost` | — |
| `AuFootstepBehavior` | `addons/zone_director/behaviors/` | 按地面材质播脚步声 | `footstep_streams` / `step_interval` | `GrassZone/FootstepBehavior`、`RainZone/Zone/FootstepBehavior2` |
| `WetSplashBehavior` | `scenes/worlds/_zones/behaviors/` | 踩水溅水花 | `effect_sheet` / `splash_z_index` | `RainZone/Zone/WetSplashBehavior` |
| `BossArenaBehavior` | `scenes/characters/bosses/_base/behaviors/` | 玩家踏入竞技场即开战 | `auto_start_fight` / `boss_node` | `HollowKnightScene/BossArena/BossArenaBehavior`、`SoulMasterScene/BossArena/BossArenaBehavior` |

> `AuZone` 只负责“谁在里面”，**开战是 `BossArenaBehavior` 做的**。

### 9.2 视野剔除

| 组件 | 位置 | 作用 | 关键参数 | 项目内实例 |
| --- | --- | --- | --- | --- |
| `ViewCuller` | `scenes/worlds/_base/view_culler.gd` | 按相机视野开关节点（可见性 / 处理 / 碰撞 / 音频），带战斗与 BOSS 保护 | `enabled` / `check_interval` / `activate_margin` / `hysteresis` / `protect_in_combat` / `cull_audio` / `debug_draw` | `GameRoot/ViewCuller`（唯一一份，常驻） |
| `view_cull` 组 | 节点上声明 `groups=["view_cull"]` | 唯一的参与入口，按实例选择 | — | level_1 5 个敌人 + 4 株草实例、level_2 2 个敌人实例 |

> 与 AuZone 的区别：AuZone 是“查询与事件”，不改变任何节点状态；ViewCuller 是“性能开关”，会改 `visible` / `process_mode` / 碰撞 / 音频。
>
> 判据：**只有逻辑可以被安全冻结的节点才该加入**。`Pickup` 因为存活时间在 `_physics_process` 里累加，绝不能加。

### 9.3 相机

| 组件 | 位置 | 作用 | 关键参数 | 项目内实例 |
| --- | --- | --- | --- | --- |
| `AuCameraRig` | `addons/camera_director/AuCameraRig.gd` | 常驻相机装置，真正驱动 Camera2D；`zoom` setter 发 `zoom_changed(new_zoom)`（含 tween 逐帧） | `base_offset` / `zoom` / `dead_zone` / `limit_*` / `shake_*` / `snap_to_target()` | `GameRoot/AuCameraRig`（唯一一份） |
| `AuCameraDirector` | autoload | 相机行为栈仲裁 | `set_follow` / `register_area` / `push_override` / `tween_zoom` / `shake*` / `look_up` / `look_down` | 全局常驻 |
| `AuFollowBehavior` | `behaviors/follow_behavior.gd` | 基础跟随 | 目标节点 | 内置 |
| `AuLockAreaBehavior` | `behaviors/lock_area_behavior.gd` | 锁定区生效时的相机约束 | 关联 `AuCameraLockArea` | 运行时按进出注册 |
| `AuShotBehavior` | `behaviors/shot_behavior.gd` | 镜头接管（分镜 / BOSS 演出） | 目标 / zoom | `AuCameraDirector.push_override()` |
| `AuCameraLockArea` | `addons/camera_director/AuCameraLockArea.gd` | 局部相机锁定区；编辑器里矩形内部透明、四角画可配色的实心方框 | Inspector 四组：① 区域 `area_size` / `centered` / `detect_layer` ② 锁定（子组 参考点 / 活动范围）`*_lock_marker` / `*_range` ③ 镜头行为 `can_look_up` / `can_look_down` ④ 编辑器预览 `show_corners_in_editor` / `fill_alpha` / `corner_color` / `corner_size` | level_1 `CameraLock/Areas/RightCameraLock`、`LeftCameraLock`、`ZoomCameraLock`、`HollowKnightCameraLock`、`SoulMasterCameraLock` |
| 锁定参考点 | level_1 `CameraLock/Markers/*` | 锁定用的 Marker2D | — | `vertical_lock` / `horizontal_lock` / `hollow_knight_lock` / `soul_master_lock` |
| `CameraBoundsRect` | `_base/camera_bounds_rect.gd`（`@tool` Area2D） | 编辑器里可拖拽的**相机中心活动范围**，自身换算成四条 limit；预览框与内部 `CollisionShape2D` 背景都透明、四角实心圆可配色 | `debug_draw` / `preview_zoom` / `fill_alpha` / `corner_color` / `corner_size` / `CollisionShape2D.shape` | `WorldTemplate/CameraBounds`，每个 Area 继承一份 |
| `CollisionShape2D` | `CameraBounds` 子节点 | 拖 handles 改矩形大小（原生编辑器交互） | `RectangleShape2D.size` / `position` | level_1 `9888×1425 @ (1944,-247.5)`；level_2 `2880×710 @ (2080,105)` |

> `AuCameraLockArea` 是**局部行为**（在某区域内改变跟随目标 / 范围），`CameraBoundsRect` 是**全局硬边界**（限制镜头中心能走到哪），两者叠加生效。

### 9.4 关卡流转

| 组件 | 位置 | 作用 | 关键参数 | 项目内实例 |
| --- | --- | --- | --- | --- |
| `GameSession` | autoload | 换关中枢：异步加载 Area、玩家“搬家”、入口定位、flags | `travel_to` / `bootstrap` / `content_root` / `has_flag` / `set_flag` / `snap_camera` | 全局常驻 |
| `TransitionLayer` | autoload（CanvasLayer） | 黑场 + 场景预加载 | `fade_out` / `fade_in` / `change_scene` / `prefetch` | 全局常驻 |
| `GameRoot` | `scenes/worlds/game_root.tscn/.gd` | 常驻骨架：Player / HUD / 相机 / 暂停 / 死亡 | — | 游戏根场景 |
| `WorldArea` | `scenes/worlds/_base/world_template.gd` | 区域底座 | `zone_name` / `get_entry()` | level_1 `WorldTest`、level_2 `WorldLevel2` |
| `EntryPoint` | `_base/entry_point.tscn/.gd` | 出生点标记 | `entry_id`（空则取节点名）/ `facing` | level_1 `default`、`from_level_2`；level_2 `default`、`from_level_1` |
| `LevelGate` | `_base/level_gate.tscn/.gd` | 区域转场门 | `target_area` / `target_entry` / `gate_id` / `requires_ground` | level_1 `ToLevel2`；level_2 `ToLevel1` |
| `Bench` | `scenes/props/bench/` | 长椅存档点（继承 EntryPoint） | `save_on_rest` / `rest_cooldown` / `flash_time` | level_1 `bench_01`；level_2 `bench_02`、`bench_03` |
| `BossFogGate` | `_base/boss_fog_gate.tscn/.gd` | BOSS 雾门（战斗封锁） | `boss_node` / `fade_time` | level_1 `HollowKnightFog`、`SoulMasterFog` |

### 9.5 存档与持久化

| 组件 | 位置 | 作用 | 关键字段 | 项目内实例 |
| --- | --- | --- | --- | --- |
| `SaveManager` | autoload | 存档读写、预览、回填 | `area_path` / `entry_id` / `zone` / `player` / `inventory` / `monarch_wings` / `defeated` / `flags` | 全局常驻 |
| `Chest.persistent_id` | `scenes/props/chest/chest.gd` | 一次性木箱 | 写 `flags` | level_1 `chest:level_1/01`；level_2 `chest:level_2/01`、`02` |
| `Enemy.persistent_id` | `enemies/_base/enemy.gd` | BOSS / 精英永久击败 | 写 `defeated`（立即落盘） | `hollow_knight`、`soul_master` 等 |
| `Inventory` | autoload | 背包（coin / food …） | `to_dict` / `load_from_dict` / `changed` | 全局常驻 |
| `Globals.has_monarch_wings` | `globals/autoload/Globals.gd` | 能力解锁标记（二段跳） | 默认 `true` | 全局常驻 |

> 两套持久化的分工：`defeated` 是“关键进度”（立刻写盘），`flags` 是“一次性事件”（随下次存档写盘）。

### 9.6 敌人 AI 子系统

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| `Enemy`（基类） | `enemies/_base/enemy.gd` | 配置、生命、掉落、死亡、信号广播 |
| `EnemyStateMachine` + 状态 | `_base/EnemyStateMachine.gd`、`_base/states/` | `idle` / `patrol` / `chase` / `attack` / `return` / `hurt` / `death` |
| `EnemyAggro` | `_base/aggro/enemy_aggro.gd` | 视线、leash、领地绑定、战斗丢失计时、出界宽限 |
| `EnemyFacing` | `_base/facing/` | 转身 / 翻面表现 |
| `EnemyAudio` | `_base/audio/` | 音效 + 镜头可见性裁剪 |
| `EnemySteering` | `_base/steering/enemy_steering.gd` | 移动转向 / 回避 |
| `EnemyLocomotion`（资源） | `resources/characters/enemies/_shared/locomotion/` | 运动介质（地面 / 飞行 / 游泳），介质参数不再堆进 `Enemy` |
| `EnemyTuning`（资源） | `_shared/enemy_tuning.gd` + `.tres` | 调参预设（按种类共享） |

> `enemy_zone`（AuZone）决定“**何时**开战”，`leash_range` 决定“**追多远**”。领地常比 leash 宽，所以有 `zone_exit_chase_time` 宽限。

### 9.7 BOSS 专用

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| `Boss`（基类） | `bosses/_base/boss.gd` | 阶段 `phase_index`、`boss_defeated`、`_dead()` |
| `BossState` + 状态 | `bosses/<boss>/states/` | HollowKnight：dormant…；SoulMaster：entrance / idle… |
| `BossArenaBehavior` | `bosses/_base/behaviors/` | 踏入竞技场开战 |
| `BossChain` | `bosses/hollow_knight/effects/boss_chain.tscn` | 锁链（砍断触发开战） |
| BOSS 特效 | `boss_plume` / `boss_soul_orb` / `quake_effect` / `teleport_trail` | 弹幕与表现 |
| `BossFogGate` | `_base/` | 战斗中封锁退路 |

### 9.8 战斗与手感

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| Player 状态机 | `players/player/states/` | `idle` / `walk` / `jump` / `fall` / `land` / `double_jump` / `dash` / `look_up` / `look_down` / `slash_forward` / `slash_up` / `slash_down` / `block` / `cure` / `hurt` / `death` / `freeze` |
| `PlayerCombat` | autoload | 全局战斗状态标记（`is_attacking`） |
| `HitEffect` | `scenes/effects/hit_effect.gd` | 受击特效分发（按伤害来源选场景） |
| `Ammo` | `scenes/projectiles/_base/ammo.gd` | 弹幕基类：阵营 `faction`、`usable_by`、`fire()` |
| 弹幕变体 | `projectile` / `projectile_split` / `projectile_spread` | 普通 / 分裂 / 散射 |
| `DropSpawner` | autoload | 掉落物抛飞与容器归属 |
| `Pickup` / `coin_pickup` | `scenes/drops/` | 拾取物、音效延迟释放 |
| 屏震 | `AuCameraDirector.shake / shake_light / shake_medium / shake_heavy` | 战斗反馈 |

### 9.9 环境表现

| 组件 | 位置 | 作用 | 关键参数 |
| --- | --- | --- | --- |
| `rain.tscn` / `fog.tscn` / `snow.tscn` | `addons/environment_fx/` | 雨 / 雾 / 雪，跟随玩家的 `PlayerZone` | `region_fade` / `elliptical` / `draw_z` / `density` |
| `RainZone` | `_zones/rain_zone.tscn` | 组合件：Zone + 脚步声 + 水花 + 雨 | `zone_size` |
| `GrassZone` | `_zones/grass_zone.tscn` | 组合件：Zone + 草丛脚步声 | `surface` / `zone_priority` |
| 光照 | `DirectionalLight2D`（level_1 `Lights/`）、`PointLight2D`（玩家身上） | 全局 / 局部光照 | `energy` / `blend_mode` |
| `OcclusionLayer` | 关卡模板 | 遮挡层容器 | — |
| `Parallax2D` | level_1 `Background/Layer_1..3`、`Foreground/` | 视差分层 | `scroll_scale` / `repeat_size` |
| 物理插值 | `project.godot` → `physics/common/physics_interpolation` | 平滑插值；瞬移后必须 `reset_physics_interpolation()` | 开 |

### 9.10 UI 与反馈

| 组件 | 位置 | 作用 |
| --- | --- | --- |
| `Hud` / `HealthIndicator` | `scenes/ui/` | 血量 / 灵魂球 / 钱币 |
| `SkillBar` / `SkillSlot` | `scenes/ui/skill_bar/` | 常驻技能条（拖放绑定） |
| `PauseMenu` / `SkillPanel` / `SaveMenu` / `SystemSettings*` / `MainMenu*` | `scenes/menus/` | 各层界面 |
| `FocusButton` / `MenuButton` / `FocusMenuButton` | `scenes/menus/common/buttons/` | 手柄焦点导航 |
| `DeathScreen` | `scenes/ui/death_screen.tscn` | 死亡黑场倒数 |
| `Toast` | `scenes/ui/toast.tscn` | 轻量提示（长椅休息等） |
| `UiAudio` | autoload | 按钮音效 |
| `Tr` + `Settings.localization` | — | 本地化（源文案即 key） |
| `Settings.display` / `Settings.volume` | autoload | 显示 / 音量 |

### 9.11 全局服务（12 个 autoload）

| 名字 | 作用 |
| --- | --- |
| `Globals` | 常量、物理层掩码、调试开关、能力解锁 |
| `Inventory` | 背包 |
| `DropSpawner` | 掉落抛飞 |
| `Settings` | 显示 / 音量 / 本地化 |
| `UiAudio` | UI 音效 |
| `TransitionLayer` | 黑场 + 场景预加载 |
| `AuCameraDirector` | 相机行为仲裁 |
| `AuZoneDirector` | 区域通道仲裁 |
| `Skills` | 技能注册表 |
| `PlayerCombat` | 战斗状态标记 |
| `SaveManager` | 存档 |
| `GameSession` | 关卡会话（最后注册，依赖前两者） |

### 9.12 调试与工具

| 组件 | 作用 |
| --- | --- |
| `scenes/debug/character_debug.tscn` | 角色调试面板（由 `Globals.debug_enabled` 控制显隐） |
| `CameraBoundsRect.debug_draw` | 编辑器 2D 视图画绿框（中心范围）+ 红色外框（实际可见范围），可拖 handles 调大小；`fill_alpha` 默认 0 = 内部全透明（含 `CollisionShape2D` 调试背景），四角实心圆由 `corner_color` / `corner_size` 配置 |
| `AuCameraLockArea` 四角方框 | 编辑器 2D 视图在锁定区四角画实心方框 + 矩形轮廓；`corner_color` / `corner_size` / `show_corners_in_editor` 可配。`fill_alpha` 默认 `0` = 矩形内部完全透明（同步到 `CollisionShape2D.debug_color`） |
| `AuZone` 四角三角形 | 编辑器 2D 视图在区域四角画实心直角三角形；`corner_color` / `corner_size` / `show_corners_in_editor` 可配。`fill_alpha` 默认 `0` = 矩形内部与 `CollisionShape2D` 调试背景都全透明，只留描边 |
| `addons/gdUnit4` | 单元测试框架 |
| `addons/sprite_frames_to_animation_player` | SpriteFrames → AnimationPlayer 转换工具 |
| `Player/CharacterDebug` | 玩家身上的血量 / 能量 / 状态显示 |

### 9.13 易混淆概念对照

| 易混 | 区别 |
| --- | --- |
| `AuZone` vs `ViewCuller` | 前者查询“谁在里面”并广播事件；后者按屏幕距离开关节点，不广播任何东西 |
| `AuCameraLockArea` vs `CameraBoundsRect` | 前者是局部行为（改跟随 / 范围 / 缩放）；后者是全局硬边界（限制相机中心活动范围） |
| `EnemyZone` vs `leash_range` | 领地决定何时开战；leash 决定追多远，两者用 `zone_exit_chase_time` 衔接 |
| `BossArena`（AuZone）vs `BossFogGate` | 前者是开战触发器；后者是战斗中的物理封锁 |
| `EntryPoint` vs `Bench` | Bench 是“带存档行为的 EntryPoint”，因此能被 `get_entry()` 直接当作复活点 |
| `Enemy.persistent_id` vs `Chest.persistent_id` | 前者写 `defeated`（立即落盘）；后者写 `flags`（下次存档落盘） |
| `WorldArea` vs `GameRoot` | WorldArea 是“一块地图内容”；GameRoot 是“常驻的游戏骨架”，两者不是继承关系 |
