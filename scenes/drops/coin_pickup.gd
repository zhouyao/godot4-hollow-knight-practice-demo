extends Pickup
class_name CoinPickup


# 行为完全由 Pickup 基类承担（累加进 Inventory），
# 保留子类只为了在 DropEntry 里按类型区分，以及后续扩展（如金币面额换贴图）。
