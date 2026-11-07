extends StaticBody3D
## A rock that can be mined (stone, iron, gold).

const Data = preload("res://scripts/game_data.gd")
const U = preload("res://scripts/util.gd")

var rock_id: int = 0
var rock_type: String = "stone"
var radius: float = 1.3
var active: bool = true
var amount: int = 0             # server only
var respawn_left: float = 0.0   # server only

var visual: Node3D
var shape_node: CollisionShape3D


func setup(p_id: int, p_type: String, rng: RandomNumberGenerator) -> void:
	rock_id = p_id
	rock_type = p_type
	set_meta("rock_id", p_id)
	var d: Dictionary = Data.ROCKS[p_type]
	radius = float(d["radius"]) * rng.randf_range(0.85, 1.2)
	amount = int(d["amount"])
	collision_layer = 1
	collision_mask = 0

	visual = Node3D.new()
	add_child(visual)

	var base: Color = d["color"]
	U.ellipsoid(visual, Vector3(radius, radius * 0.72, radius * 0.88), Vector3(0, radius * 0.3, 0), base)
	for i in range(4):
		var a: float = rng.randf() * TAU
		var r2: float = radius * rng.randf_range(0.38, 0.6)
		var lump := U.ellipsoid(
			visual, Vector3(r2, r2 * 0.8, r2),
			Vector3(cos(a) * radius * 0.65, r2 * 0.35, sin(a) * radius * 0.65),
			base.darkened(rng.randf_range(0.0, 0.18))
		)
		lump.rotation.y = rng.randf() * TAU

	var ore: Color = d["ore"]
	var glow: float = d["glow"]
	var specks: int = 5 if p_type == "stone" else 12
	for i in range(specks):
		var a2: float = rng.randf() * TAU
		var el: float = rng.randf_range(0.1, 1.1)
		var dir := Vector3(cos(a2) * cos(el), sin(el), sin(a2) * cos(el))
		var pos := Vector3(dir.x * radius * 0.97, radius * 0.3 + dir.y * radius * 0.7, dir.z * radius * 0.86)
		var s: float = rng.randf_range(0.1, 0.22)
		var sp := U.box_m(visual, Vector3(s, s * 0.7, s), pos, U.mat(ore, 0.35, glow, 0.6 if p_type != "stone" else 0.0))
		sp.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)

	shape_node = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.9
	shape.height = radius * 1.4
	shape_node.shape = shape
	shape_node.position.y = radius * 0.5
	add_child(shape_node)

	rotation.y = rng.randf() * TAU
	U.bake(visual)
	U.set_view_range(visual, 170.0)


func set_active(value: bool) -> void:
	active = value
	visible = value
	if is_instance_valid(shape_node):
		shape_node.set_deferred("disabled", not value)
	if value:
		amount = int(Data.ROCKS[rock_type]["amount"])


func hit_fx() -> void:
	if not is_instance_valid(visual):
		return
	var tw := create_tween()
	visual.scale = Vector3(1.08, 0.9, 1.08)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.18)
