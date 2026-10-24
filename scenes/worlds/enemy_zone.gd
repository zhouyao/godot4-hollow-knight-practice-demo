@tool
extends Area2D
class_name EnemyZone

signal player_entered(zone: Node, player: Node2D)
signal player_exited(zone: Node, player: Node2D)

@export var size: Vector2 = Vector2(20, 20):
	set(value):
		size = value
		_update_shape()

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_shape()


func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		player_entered.emit(self, body)


func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		player_exited.emit(self, body)


func _update_shape() -> void:
	var collision_shape := $CollisionShape2D as CollisionShape2D
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		collision_shape.shape.size = size
