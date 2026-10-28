class_name EnemyTuning
extends Resource


## 怪物调参预设：把散落在各状态节点上的数值集中到一个资源里，一份 .tres 可给多只怪复用。
##
## 取值优先级（见 EnemyState._tuning()）：
##   tuning（本资源，整类怪的预设） > 敌人根节点同名导出（逐只微调） > 状态脚本自身的默认值
## 所有字段默认 -1 = "不覆盖，往下层要值"，所以不填任何字段的 tuning 完全等价于没配。
##
## 加新参数只改本文件一处，不必再像以前那样同时改
## 基类导出 / _validate_property / 状态默认值 / 根节点代理 四个地方。

@export_group("移动")
## 基础移动速度（像素 / 秒）：巡逻 / 追击 / 返回的所有倍率都乘以它。
## 整只怪"快一点还是慢一点"改这里，不必逐个状态节点改三个倍率。
@export var move_speed: float = -1.0

@export_group("巡逻")
## 巡逻半径（像素）：无领地时出生点左右各伸出这么远。
@export var patrol_radius: float = -1.0
## 巡逻速度倍率（相对 enemy.move_speed）。
@export var patrol_speed_multiplier: float = -1.0
## 抵达端点后的停留时长（秒）。
@export var patrol_wait_time: float = -1.0
## 纵向浮动幅度（像素）：仅飞行怪，0 = 只做水平往返。
@export var bob_amplitude: float = -1.0
## 纵向浮动频率（弧度 / 秒）：仅飞行怪。
@export var bob_frequency: float = -1.0

@export_group("追击")
## 追击速度倍率（乘以 enemy.move_speed）。
@export var chase_speed_multiplier: float = -1.0
## 前方踏空导致无法靠近目标时，坚持多久放弃战斗回巢（秒）：仅地面怪。
@export var blocked_give_up_time: float = -1.0

@export_group("攻击")
## 近战触发距离（像素）：纯近战怪（未配 projectile_scene）用。
@export var melee_attack_range: float = -1.0
## 远程吐弹射程（像素）：配了 projectile_scene 时用。
@export var shoot_range: float = -1.0
## 远程追击时与目标保持的水平距离（像素），0 = 不保持距离。
@export var shoot_keep_distance: float = -1.0
## 两次攻击之间的冷却（秒）。
@export var attack_interval: float = -1.0
## 近战一次扑击的最短硬直（秒），到点即回 chase。
@export var attack_hold: float = -1.0
## 远程吐弹后的后摇（秒），到点即回 chase。
@export var attack_recover: float = -1.0

@export_group("返回")
## 抵达出生点的判定距离（像素）。
@export var arrive_distance: float = -1.0
## 返回速度倍率（相对 enemy.move_speed）。
@export var return_speed_multiplier: float = -1.0
## 朝家那一步会踏空时，锁定方向至少走满这么多像素才允许重新规划：仅地面怪。
@export var escape_distance: float = -1.0
## 连续退避超过这么久就放弃防踏空判定，直接朝家走（秒）：仅地面怪。
@export var escape_patience: float = -1.0
