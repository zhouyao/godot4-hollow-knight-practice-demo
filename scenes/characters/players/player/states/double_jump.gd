extends PlayerState

## 帝王之翼：空中振翅（二段跳）。
## 动作 / 音效复用地面跳（项目还没有独立的振翅帧），另叠一次短促的冷白闪光当作"展翼"反馈。
## 上升段留在本状态，速度转下切 fall，落地切 land；能否振翅、还剩几次由 PlayerInitial 统一裁决。


@export_group("状态过渡 Transitions")
## 落回地面时切往的状态（一般是 land）。改成 idle 可以直接跳过落地硬直。
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.JUMP)
	_play_action(PlayerStateNames.JUMP)
	_flash_wings()

func get_transition(_delta: float) -> StringName:
	if player.is_on_floor():
		return target_grounded
	if player.velocity.y >= 0.0:
		return PlayerStateNames.FALL
	return &""


## 一次性"展翼"闪光：只动 modulate，不动 scale —— scale.x 承担朝向，振翅期间改它会导致翻面错乱。
func _flash_wings() -> void:
	var sprite := player.player_animated_sprite
	if sprite == null:
		return
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate", Color(1.5, 1.7, 2.0), 0.05)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.18)
