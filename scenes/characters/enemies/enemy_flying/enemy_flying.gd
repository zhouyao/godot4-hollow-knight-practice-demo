extends Enemy


## 吐弹能力（muzzle / projectile_scene / projectile_damage / launch_projectile）已上提到 Enemy 基类，
## 陆地怪与飞行怪共用同一套实现，这里只保留飞行专属的调参。

# 分组：飞行专属调参单独折叠，与基类分组平级显示在检查器末尾。
@export_group("飞行调参覆盖（-1 = 沿用状态默认）")
## 追击时与目标保持的水平距离（像素）：< 0 表示沿用 chase 状态自身的默认值。
## 根节点暴露本参数，是为了能在世界场景里对每只飞行怪单独覆盖（实例内部子节点无法在外部改）。
@export var keep_distance: float = -1.0
## 进入攻击的射程（像素）：< 0 表示沿用 chase 状态自身的默认值。
## 名字不能叫 attack_range：Enemy 基类已有同名导出（地面怪用），子类不可重复声明。
@export var fly_attack_range: float = -1.0
## 飞行速度倍率（乘以 enemy.move_speed）：< 0 表示沿用 chase 状态自身的默认值。
@export_range(-1.0, 10.0, 0.05) var fly_speed_multiplier: float = -1.0
