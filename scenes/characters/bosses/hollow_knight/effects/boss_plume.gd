extends Area2D
class_name BossPlume

## 下砸预警柱：BOSS 起跳时在落点地面施放一排，先播 plume_antic（不伤人，仅预警）；
## 待 BOSS 落地后由施法者调用 burst() 引爆：播放 plume_burst 并对范围内玩家结算一次伤害，随后自毁。


@export var damage: int = 1

var _source: Node2D = null
var _active: bool = false
var _has_hit: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# 预警阶段：先关监测（不伤人）。
	monitoring = false
	body_entered.connect(_on_body_entered)
	if _sprite != null:
		_sprite.play(&"plume_antic")


## 由施法者（BOSS）在起跳时调用：配置伤害与伤害来源（来源用于玩家格挡 / 受击判定）。
func setup(dmg: int, source: Node2D) -> void:
	damage = dmg
	_source = source
	if _sprite != null and not _sprite.is_playing():
		_sprite.play(&"plume_antic")


## 引爆：播放 plume_burst、开启伤害判定，并延迟一帧结算重叠
## （覆盖"玩家站定重叠、body_entered 不补发"的边界，确保必定结算一次）。
func burst() -> void:
	if _active:
		return
	_active = true
	monitoring = true
	if _sprite != null:
		if not _sprite.animation_finished.is_connected(_on_burst_finished):
			_sprite.animation_finished.connect(_on_burst_finished)
		_sprite.play(&"plume_burst")
	call_deferred("_check_overlap")


func _check_overlap() -> void:
	if not _active or _has_hit:
		return
	var p := _player()
	if p != null and get_overlapping_bodies().has(p):
		_has_hit = true
		p.take_damage(damage, _source)


func _on_body_entered(body: Node) -> void:
	if not _active or _has_hit:
		return
	var p := _player()
	if body == p:
		_has_hit = true
		p.take_damage(damage, _source)


func _player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] if not players.is_empty() else null


func _on_burst_finished() -> void:
	queue_free()
