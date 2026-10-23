@tool
extends NavigationRegion2D


func _ready() -> void:
	_sync_sensor_to_polygon()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_sensor_to_polygon()

func _sync_sensor_to_polygon() -> void:
	var sensor := get_node_or_null("TerritorySensor")
	var poly := navigation_polygon
	if sensor == null or poly == null:
		return
	var verts := poly.get_vertices()
	if verts.is_empty():
		return
	var min_p := verts[0]
	var max_p := verts[0]
	for v in verts:
		min_p = min_p.min(v)
		max_p = max_p.max(v)
	var size := max_p - min_p
	var center := (min_p + max_p) * 0.5
	var shape_node := sensor.get_node_or_null("CollisionShape2D")
	if shape_node == null:
		return
	if shape_node.shape == null or not (shape_node.shape is RectangleShape2D):
		shape_node.shape = RectangleShape2D.new()
	if shape_node.shape.size != size:
		shape_node.shape.size = size
	if shape_node.position != Vector2.ZERO:
		shape_node.position = Vector2.ZERO
	if sensor.position != center:
		sensor.position = center
