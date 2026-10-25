class_name SkillRegistry
extends Resource

## 技能登记表：技能面板的唯一数据源（留作接入点）。
## 在编辑器里把 SkillDefinition 的 .tres 逐个加到 skills 数组即可。

@export var skills: Array[SkillDefinition] = []
