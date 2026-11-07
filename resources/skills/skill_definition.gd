class_name SkillDefinition
extends Resource

## 单个技能的展示数据，供技能面板使用。
## 在编辑器里把做好的 .tres 拖进 SkillRegistry 的 skills 数组即可上架。

## 稳定标识：技能条装配结果与配置存档都用它，改名 / 改翻译不受影响。
## 必须与 PlayerState.SKILL_STATES 里登记的 key 一致，否则装上也无法施放。
@export var id: StringName = &""
@export var display_name: StringName = &""   # 翻译 key（本项目用中文原文作 key，走 tr()）
@export var icon: Texture2D                    # 左侧图标
@export var preview_frames: SpriteFrames       # 右侧动画预览用的 SpriteFrames
@export var preview_animation: StringName = &"default"
@export var description: String = ""          # 翻译 key（中文原文，展示处走 tr()）
## 冷却时长（秒）：0 表示无冷却。施放时由玩家读取并计时，技能条 UI 也用它算遮罩比例。
@export var cooldown: float = 0.0
## 施放消耗的能量点数：0 表示不消耗能量。能量不足时技能按不出去。
@export var energy_cost: int = 1
