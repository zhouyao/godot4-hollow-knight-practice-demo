extends Projectile
class_name AspidProjectile

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _launch_sfx: AudioStreamPlayer2D = $LaunchSfx
@onready var _impact_sfx: AudioStreamPlayer2D = $ImpactSfx

## 命中收尾只做一次：monitoring 要延迟到帧末才真正关掉，这之前同一物理帧里
## 还可能有别的 body 触发 body_entered，不能重复结算 / 播音效 / queue_free。
var _finished := false


func _ready() -> void:
	super._ready()
	if _sprite != null:
		_sprite.play(&"fly")


func fire(dir: Vector2, damage: int) -> void:
	super.fire(dir, damage)
	if _launch_sfx != null and _launch_sfx.stream != null:
		_launch_sfx.play()


func _on_body_entered(body: Node2D) -> void:
	if _finished or _grace > 0.0:
		return

	var should_impact := false
	if is_target(body):
		if not _hit.has(body):
			body.take_damage(_damage, self)
			_hit.append(body)
		should_impact = true
	elif (body.collision_layer & Globals.LAYER_OBJECTS) != 0:
		should_impact = true

	if not should_impact:
		return

	if pierce:
		_play_impact()
		return

	_finish_with_impact()


func _play_impact() -> void:
	if _impact_sfx != null and _impact_sfx.stream != null:
		_impact_sfx.play()


func _finish_with_impact() -> void:
	if _finished:
		return
	_finished = true
	set_physics_process(false)
	# 本函数从 Area2D.body_entered 的回调里进来：此刻物理服务器仍在派发 in/out
	# 信号、空间被锁定，直接写 monitoring 会被拒绝并报
	# "Function blocked during in/out signal. Use set_deferred(...)"。
	# 与 grass.gd / chest.gd / boss.gd 一样延迟到当前物理帧结束之后生效。
	set_deferred("monitoring", false)
	if _sprite != null:
		_sprite.visible = false

	_play_impact()

	# 让命中声播完再销毁；没有音效时立即销毁
	if _impact_sfx != null and _impact_sfx.stream != null and _impact_sfx.playing:
		await _impact_sfx.finished
	queue_free()
