extends Node

## 技能面板的统一访问入口（自动加载名 Skills）。读取 SkillRegistry，面板只认这个 list。

const REGISTRY_PATH := "res://resources/skills/skill_registry.tres"

var list: Array[SkillDefinition] = []

func _ready() -> void:
	var registry := load(REGISTRY_PATH) as SkillRegistry
	if registry != null:
		list = registry.skills


## 按 id 反查技能定义（技能条显示图标、名字用）。找不到或 id 为空返回 null。
func by_id(skill_id: StringName) -> SkillDefinition:
	if skill_id == &"":
		return null
	for def in list:
		if def.id == skill_id:
			return def
	return null


## 取技能的冷却时长（秒）；id 为空、未上架或未配置冷却都返回 0（= 无冷却）。
func cooldown_of(skill_id: StringName) -> float:
	var def := by_id(skill_id)
	return 0.0 if def == null else maxf(def.cooldown, 0.0)


## 取技能的施放能量消耗（点数）；id 为空、未上架都返回 0（= 不消耗）。
func energy_cost_of(skill_id: StringName) -> int:
	var def := by_id(skill_id)
	return 0 if def == null else maxi(def.energy_cost, 0)
