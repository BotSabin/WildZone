extends StaticBody3D
## A tree that can be chopped for wood. Leaves a stump and grows back later.

const U = preload("res://scripts/util.gd")
const Data = preload("res://scripts/game_data.gd")

var tree_id: int = 0
var is_pine: bool = true
var active: bool = true
var hp: int = Data.TREE_HP          # server only
var respawn_left: float = 0.0       # server only

var visual: Node3D
var stump: Node3D
var shape_node: CollisionShape3D


func setup(p_id: int, pine: bool, rng: RandomNumberGenerator) -> void:
	tree_id = p_id
	is_pine = pine
	collision_layer = 1
	collision_mask = 0
	set_meta("tree_id", p_id)

	visual = Node3D.new()
	add_child(visual)
	var bark := Color(0.3, 0.2, 0.12)
	var h: float
	if pine:
		h = rng.randf_range(5.0, 9.0)
		U.cyl(visual, 0.16, 0.3, h * 0.4, Vector3(0, h * 0.2, 0), bark, 8)
		var green := Color(0.07, rng.randf_range(0.22, 0.3), 0.12)
		for i in range(4):
			var layer_h: float = h * 0.38
			var y: float = h * 0.28 + i * h * 0.16 + layer_h * 0.5
			var rad: float = h * 0.27 * (1.0 - i * 0.2)
			U.cyl(visual, 0.0, rad, layer_h, Vector3(0, y, 0), green.lightened(i * 0.04), 9)
	else:
		h = rng.randf_range(3.2, 4.6)
		U.cyl(visual, 0.2, 0.34, h, Vector3(0, h * 0.5, 0), bark, 8)
		var branch := U.cyl(visual, 0.07, 0.11, 1.3, Vector3(0.45, h * 0.75, 0), bark, 6)
		branch.rotation.z = -0.8
		var c := Color(rng.randf_range(0.14, 0.26), rng.randf_range(0.32, 0.44), 0.13)
		U.ellipsoid(visual, Vector3(1.9, 1.6, 1.9), Vector3(0, h + 0.8, 0), c)
		U.ellipsoid(visual, Vector3(1.2, 1.0, 1.2), Vector3(1.0, h + 0.2, 0.5), c.darkened(0.1))
		U.ellipsoid(visual, Vector3(1.1, 0.9, 1.1), Vector3(-0.9, h + 0.4, -0.4), c.lightened(0.06))
	visual.rotation.y = rng.randf() * TAU

	stump = Node3D.new()
	add_child(stump)
	U.cyl(stump, 0.28, 0.34, 0.45, Vector3(0, 0.22, 0), bark, 8)
	U.cyl(stump, 0.26, 0.26, 0.02, Vector3(0, 0.455, 0), Color(0.75, 0.6, 0.4), 8)
	stump.visible = false

	shape_node = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.4
	shape.height = 4.0
	shape_node.shape = shape
	shape_node.position.y = 2.0
	add_child(shape_node)
	U.bake(visual)
	U.bake(stump)
	U.set_view_range(visual, 190.0)


func set_active(value: bool, animate: bool = false) -> void:
	if value == active:
		return
	active = value
	if value:
		hp = Data.TREE_HP
		visual.rotation.x = 0.0
		visual.rotation.z = 0.0
		visual.scale = Vector3(0.3, 0.3, 0.3)
		visual.visible = true
		stump.visible = false
		shape_node.set_deferred("disabled", false)
		var tw := create_tween()
		tw.tween_property(visual, "scale", Vector3.ONE, 2.0)
	else:
		stump.visible = true
		shape_node.set_deferred("disabled", true)
		if animate:
			var tw2 := create_tween()
			tw2.tween_property(visual, "rotation:z", PI * 0.48, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw2.tween_callback(func() -> void: visual.visible = false)
		else:
			visual.visible = false


func hit_fx() -> void:
	if not active:
		return
	var tw := create_tween()
	visual.rotation.x = 0.05
	tw.tween_property(visual, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
