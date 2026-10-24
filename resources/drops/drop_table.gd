extends Resource
class_name DropTable


## 掉落条目：一只怪可以掉多种东西（钱币 + 食物各一条）。
@export var entries: Array[DropEntry] = []
## 单次死亡生成的实体总数上限，超出部分丢弃（保底防刷屏）。
@export var max_pickups: int = 12


## 掷一次掉落，返回 [{scene, item_id, amount}, ...]。
## 传入 rng 便于测试时用固定种子复现，正常流程由 DropSpawner 新建。
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if e == null or e.scene == null or not e.scene.can_instantiate():
			continue
		if rng.randf() > e.chance:
			continue
		var lo := mini(e.min_amount, e.max_amount)
		var hi := maxi(e.min_amount, e.max_amount)
		var total := rng.randi_range(lo, hi)
		var per := maxi(1, e.per_pickup)
		var count := mini(ceili(float(total) / float(per)), e.max_pickups)
		for i in count:
			var amount := mini(per, total - i * per)
			if amount <= 0:
				break
			out.append({"scene": e.scene, "item_id": e.item_id, "amount": amount})
		if out.size() >= max_pickups:
			break
	return out
