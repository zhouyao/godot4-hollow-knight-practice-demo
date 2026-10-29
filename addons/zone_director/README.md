# Zone Director（addon）

Godot 4.x 可嵌套的 2D 区域系统。本目录可整体复制到任意工程的 `addons/` 下使用。

## 包含内容

- `AuZone.gd` —— 区域节点（`@tool` Area2D 子类，`class_name AuZone`），负责形状、进出检测、嵌套关系、通道声明
- `AuZoneDirector.gd` —— 区域仲裁中心（autoload），维护活跃区域集并对互斥通道仲裁
- `AuZoneBehavior.gd` —— 效果挂件基类（`class_name AuZoneBehavior`），挂在 AuZone 下即可生效
- `behaviors/AuFootstepBehavior.gd` —— 地面脚步声挂件
- `scenes/zone.tscn` —— 空模板（Area2D + CollisionShape2D）
- `plugin.cfg` / `plugin.gd` —— 插件入口（无编辑器 UI）

命名与 `addons/camera_director` 同族：`AuCameraDirector` / `AuCameraLockArea` / `AuCameraBehavior`
↔ `AuZoneDirector` / `AuZone` / `AuZoneBehavior`；拼写统一用美式 `Behavior`。

## 快速接入

1. 复制本目录到你的工程 `addons/zone_director/`。
2. **手动注册 autoload**：项目设置 → 自动加载，添加
   `res://addons/zone_director/AuZoneDirector.gd`，节点名填 `AuZoneDirector`。
   或直接往 `project.godot` 的 `[autoload]` 写一行：

   ```ini
   AuZoneDirector="*res://addons/zone_director/AuZoneDirector.gd"
   ```

   > 插件刻意**不**用 `add_autoload_singleton()` 自动安装：那需要重启编辑器才生效，
   > 且禁用插件会把 autoload 一起移除、导致引用它的脚本编译失败。
   > 手动注册一次即可，与 `AuCameraDirector` 的做法一致。
3. 项目设置 → 插件 → 启用 `Zone Director`（可选，仅为了在插件列表里可见）。
4. 实例化 `scenes/zone.tscn`，或在场景里添加 Area2D 后挂上 `AuZone.gd`。
5. 在检查器填 `size`、`surface` / `ambient` / `lighting` / `tags` 即可。

## 通道模型

| 通道 | 类型 | 含义 | 查询方式 |
|---|---|---|---|
| `surface` | **互斥**（唯一胜者） | 地面材质：grass / water / stone / snow | `AuZoneDirector.surface()` |
| `lighting` | **互斥**（唯一胜者） | 光照：dark / torch / bright | `AuZoneDirector.lighting()` |
| `ambient` | 叠加 | 环境氛围：rain / fog / snow / indoor | `AuZoneDirector.has_ambient(&"rain")` |
| `tags` | 叠加 | 任意标签：combat / no_dash ... | `AuZoneDirector.has_tag(&"combat")` |

留空 = 不参与该通道。互斥通道的仲裁顺序：**depth 深者胜 → `zone_priority` 高者胜 → 面积小者胜 → 树序稳定**。

## 嵌套

AuZone 在场景树中的 **AuZone 祖先链层数**即为 `depth`，越深 = 越内层 = 越具体：

```
RainZone (ambient=rain, surface=water)
└── GrassZone (surface=grass)      ← depth 1，在雨区里踩草地时 grass 胜出
```

也可以把 `parent_zone` 指向任意 AuZone 来跨树指定包含关系。
**即使不做嵌套**，同级的两个区域也会按"面积小者胜"自然得出正确结果
（1920×1080 的雨区 vs 140×32 的草区 → 草区胜）。

### 典型效果：雨区里的草区

| 玩家位置 | `surface()` | `has_ambient(&"rain")` |
|---|---|---|
| 雨区外 | `default` | `false` |
| 雨区内 | `water` | `true` |
| 雨区内的草地上 | `grass` | `true`（雨照常下） |

## 新增一种区域效果

写一个 `AuZoneBehavior` 子类挂到 AuZone 下面，重写需要的回调：

```gdscript
extends AuZoneBehavior
class_name MyZoneBehavior

func _ready() -> void:
	super._ready()          # 必须调：基类在这里向宿主登记自己

func on_entered(_body: Node2D) -> void: pass    # 目标进入
func on_exited(_body: Node2D) -> void: pass     # 目标离开
func on_gained(_channel: StringName) -> void: pass  # 本区域成为该互斥通道的胜者
func on_lost(_channel: StringName) -> void: pass    # 本区域失去该通道
```

`AuZone` 与 `AuZoneDirector` 都不用改。
（宿主 `AuZone._ready()` 还会扫描一遍子节点作为兜底，子类忘了 `super._ready()` 也不会漏登记。）

## 关键参数（AuZone）

`size`、`centered`、`parent_zone`、`surface`、`ambient`、`lighting`、`tags`、
`zone_priority`、`detect_mask`、`target_group`。

`AuZoneDirector` 侧只有 `exit_grace`（离开区域后的宽限时长，默认 0.15s，
用于消除边界反复横跳造成的表现闪烁）。

## 依赖边界

仅依赖 Godot 内置节点与 autoload 机制，**不含也不引用任何贴图 / 音频资源**
—— `AuFootstepBehavior.footstep_streams` 默认为空，请由使用方在检查器或场景里注入。
角色检测通过 `body.is_in_group("player")` 实现，请让你的玩家节点加入 `"player"` 组
（可用 `target_group` 改成别的组名）。

`AuZone` 默认 `collision_layer = 0`、`monitorable = false`：只检测别人，不被别人检测，
避免误占玩家层或被攻击区命中。

## 迁移旧区域

`AuZone` 保留了与 `EnemyZone` 同名的 `player_entered / player_exited` 信号与同样的
两个参数，因此用 `has_signal("player_entered")` 做鸭子类型判定的旧消费方**零改动**。
把旧代码里当作**类型**用的 `EnemyZone` 直接换成 `AuZone` 即可（两者都有 `size` 与
`global_position`）。
