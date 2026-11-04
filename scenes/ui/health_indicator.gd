extends MarginContainer
class_name HealthIndicator

## 单格血量面具（空之骑士 HUD）：
## 满血播 idle 微光；掉血播 break 后停在 empty；回血播 appear 后转 idle。
##
## 本节点不自己读血量：Hud 按 max_health 生成 N 个实例，在 health_changed 时
## 把（旧值, 新值）一起广播，每格只比较自己的序号决定播哪段。
## 这样既不用给每格单独连玩家信号，也能正确处理一次掉多格 / 读档跳变。

## 第几格（从 1 起）：index <= health 表示这一格是满的。
@export var index: int = 1

@onready var sprite: AnimatedSprite2D = $HealthAnimatedSprite

## 动画序列令牌：短时间内连伤 / 连回血时，旧协程醒来不会劫持新序列的第二段动画。
var _sequence_id := 0


func update_health(old_health: int, new_health: int) -> void:
	if index <= old_health and index > new_health:
		_play_sequence(&"break", &"empty")
	elif index <= new_health and index > old_health:
		_play_sequence(&"appear", &"idle")


func _play_sequence(first: StringName, second: StringName) -> void:
	_sequence_id += 1
	var token := _sequence_id
	sprite.play(first)
	await sprite.animation_finished
	if token != _sequence_id or not is_instance_valid(sprite):
		return
	sprite.play(second)
