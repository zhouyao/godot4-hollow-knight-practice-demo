extends Enemy


@onready var muzzle: Marker2D = $Muzzle

## 吐出的投射物场景：不配则 launch_projectile() 直接返回，飞行怪只能近身。
@export var projectile_scene: PackedScene = null
## 投射物携带的伤害值（在 setup() 时传给投射物，与 contact_damage 相互独立）。
@export var projectile_damage: int = 1

func launch_projectile(scene: PackedScene = null) -> void:
	var proj := scene if scene != null else projectile_scene
	if proj == null:
		return
	var p := proj.instantiate()
	get_tree().current_scene.add_child(p)
	p.global_position = muzzle.global_position
	var dir := Vector2(move_direction, 0.0)
	if is_instance_valid(target):
		dir = (target.global_position - muzzle.global_position).normalized()
	p.setup(dir, projectile_damage)

func _flip_extra() -> void:
	if muzzle != null:
		muzzle.position.x *= -1
		muzzle.reset_physics_interpolation()
