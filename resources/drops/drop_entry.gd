extends Resource
class_name DropEntry


## 物品 id：进 Inventory 的键，也是 HUD 显示的依据（&"coin" / &"food"）。
@export var item_id: StringName = &"coin"
## 掉落实体对应的场景：根节点必须是 Pickup 子类。
@export var scene: PackedScene = null
## 独立掉率（0~1）：先过这一关，再决定掉多少。
@export var chance: float = 1.0
## 总数量范围（实际数量在此区间随机）。
@export var min_amount: int = 1
@export var max_amount: int = 1
## 每个 Pickup 实体携带多少数量：决定"掉 30 金币"是 1 个钱袋还是 6 枚散币。
## 值越大实体越少、越省性能；值小则铺地更爽。默认 1。
@export var per_pickup: int = 1
## 单条最大实体数：防止极端数值刷屏。
@export var max_pickups: int = 8
