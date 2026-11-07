extends RefCounted
## Building pieces: grid snapping, slot keys and the 3D models/colliders.

const Data = preload("res://scripts/game_data.gd")
const U = preload("res://scripts/util.gd")

const PLANK := Color(0.58, 0.4, 0.22)
const PLANK_DARK := Color(0.42, 0.28, 0.15)
const LOG := Color(0.47, 0.32, 0.17)
const STONE := Color(0.52, 0.51, 0.5)
const SHINGLE := Color(0.45, 0.22, 0.16)


static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / Data.GRID)), int(floor(p.z / Data.GRID)))


static func level_of(y: float) -> int:
	return maxi(0, int(floor(y / Data.STORY + 0.35)))


static func cell_center(cx: int, cz: int, level: int) -> Vector3:
	return Vector3((float(cx) + 0.5) * Data.GRID, float(level) * Data.STORY, (float(cz) + 0.5) * Data.GRID)


## Picks the cell edge nearest to the aimed point (for walls).
static func edge_rot(p: Vector3, cx: int, cz: int) -> int:
	var c: Vector3 = cell_center(cx, cz, 0)
	var dx: float = p.x - c.x
	var dz: float = p.z - c.z
	if absf(dz) >= absf(dx):
		return 0 if dz < 0.0 else 2
	return 1 if dx > 0.0 else 3


static func piece_transform(cx: int, cz: int, level: int, rot: int) -> Transform3D:
	var t := Transform3D()
	t.basis = Basis(Vector3.UP, -float(rot) * PI * 0.5)
	t.origin = cell_center(cx, cz, level)
	return t


static func slot_key(kind: String, cx: int, cz: int, level: int, rot: int) -> String:
	var slot: String = Data.PIECES[kind]["slot"]
	if slot == "W":
		var r: int = posmod(rot, 4)
		if r == 2:
			cz += 1
			r = 0
		elif r == 3:
			cx -= 1
			r = 1
		return "W|%d|%d|%d|%d" % [cx, cz, level, r]
	return "%s|%d|%d|%d" % [slot, cx, cz, level]


# ==================================================
# MODELS
# ==================================================

## ghost = preview only (no collision, no light).
static func make_piece(kind: String, ghost: bool) -> Node3D:
	var root: Node3D
	if ghost:
		root = Node3D.new()
	else:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		root = body
	var g: float = Data.GRID
	var h: float = Data.STORY
	match kind:
		"floor":
			_solid(root, Vector3(g, 0.12, g), Vector3(0, 0.06, 0), 0.0, PLANK, ghost)
			for i in range(6):
				U.box(root, Vector3(0.03, 0.005, g), Vector3(-g * 0.5 + 0.5 * (i + 0.5) + 0.0, 0.122, 0), PLANK_DARK)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					U.box(root, Vector3(0.2, 0.3, 0.2), Vector3(x * (g * 0.5 - 0.1), -0.1, z * (g * 0.5 - 0.1)), LOG)
		"wall":
			_solid(root, Vector3(g, h, 0.22), Vector3(0, h * 0.5, -g * 0.5), 0.0, LOG, ghost)
			for i in range(6):
				var ln := U.cyl(root, 0.13, 0.13, g + 0.1, Vector3(0, 0.26 + i * 0.52, -g * 0.5), LOG.darkened(0.12 if i % 2 == 0 else 0.0), 8)
				ln.rotation.z = PI * 0.5
		"door":
			var side_w: float = (g - 1.2) * 0.5
			for s in [-1.0, 1.0]:
				_solid(root, Vector3(side_w, h, 0.22), Vector3(s * (0.6 + side_w * 0.5), h * 0.5, -g * 0.5), 0.0, LOG, ghost)
			_solid(root, Vector3(1.2, h - 2.4, 0.22), Vector3(0, 2.4 + (h - 2.4) * 0.5, -g * 0.5), 0.0, LOG, ghost)
			U.box(root, Vector3(1.32, 0.12, 0.28), Vector3(0, 2.4, -g * 0.5), PLANK_DARK)
			for s2 in [-1.0, 1.0]:
				U.box(root, Vector3(0.1, 2.4, 0.28), Vector3(s2 * 0.62, 1.2, -g * 0.5), PLANK_DARK)
		"window":
			var sw: float = (g - 1.2) * 0.5
			_solid(root, Vector3(g, 1.0, 0.22), Vector3(0, 0.5, -g * 0.5), 0.0, LOG, ghost)
			_solid(root, Vector3(g, h - 2.3, 0.22), Vector3(0, 2.3 + (h - 2.3) * 0.5, -g * 0.5), 0.0, LOG, ghost)
			for s in [-1.0, 1.0]:
				_solid(root, Vector3(sw, 1.3, 0.22), Vector3(s * (0.6 + sw * 0.5), 1.65, -g * 0.5), 0.0, LOG, ghost)
			if not ghost:
				U.box_m(root, Vector3(1.2, 1.3, 0.03), Vector3(0, 1.65, -g * 0.5), U.mat(Color(0.6, 0.8, 0.95, 0.35), 0.05))
			U.box(root, Vector3(0.06, 1.3, 0.26), Vector3(0, 1.65, -g * 0.5), PLANK_DARK)
			U.box(root, Vector3(1.3, 0.08, 0.34), Vector3(0, 1.0, -g * 0.5 - 0.04), PLANK_DARK)
		"stone_wall":
			_solid(root, Vector3(g, h, 0.4), Vector3(0, h * 0.5, -g * 0.5), 0.0, STONE, ghost)
			for i in range(5):
				for j in range(4):
					var off: float = 0.375 if i % 2 == 0 else 0.0
					U.box(root, Vector3(0.7, 0.55, 0.44), Vector3(-g * 0.5 + 0.375 + j * 0.75 + off - 0.19, 0.3 + i * 0.62, -g * 0.5), STONE.darkened(0.05 * float((i + j) % 3)))
		"fence":
			if not ghost:
				var fcs := CollisionShape3D.new()
				var fshape := BoxShape3D.new()
				fshape.size = Vector3(g, 1.2, 0.2)
				fcs.shape = fshape
				fcs.position = Vector3(0, 0.6, -g * 0.5)
				root.add_child(fcs)
			for x in [-1.45, 0.0, 1.45]:
				U.box(root, Vector3(0.14, 1.25, 0.14), Vector3(x, 0.62, -g * 0.5), LOG)
			for y in [0.4, 0.85]:
				U.box(root, Vector3(g, 0.1, 0.06), Vector3(0, y, -g * 0.5), PLANK)
		"roof":
			var ang: float = atan2(1.0, g)
			var length: float = sqrt(g * g + 1.0)
			_solid(root, Vector3(g + 0.3, 0.14, length + 0.3), Vector3(0, h + 0.55, 0), ang, SHINGLE, ghost)
			for i in range(6):
				var z: float = -length * 0.5 + (i + 0.5) * (length / 6.0)
				var sh := U.box(root, Vector3(g + 0.32, 0.05, 0.3), Vector3(0, h + 0.55 + 0.08 + sin(ang) * -z, z * cos(ang)), SHINGLE.darkened(0.15 if i % 2 == 0 else 0.0))
				sh.rotation.x = ang
		"stairs":
			var ang2: float = atan2(h, g)
			var len2: float = sqrt(g * g + h * h)
			_solid(root, Vector3(1.6, 0.15, len2), Vector3(0, h * 0.5, 0), ang2, PLANK, ghost)
			for i in range(8):
				var t: float = (i + 0.5) / 8.0
				U.box(root, Vector3(1.6, 0.06, 0.3), Vector3(0, h * t + 0.08, g * 0.5 - g * t), PLANK_DARK)
			for s in [-1.0, 1.0]:
				var rail := U.box(root, Vector3(0.08, 0.08, len2), Vector3(s * 0.82, h * 0.5 + 0.9, 0), LOG)
				rail.rotation.x = ang2
		"bridge":
			_solid(root, Vector3(g, 0.1, g), Vector3(0, 0.05, 0), 0.0, PLANK, ghost)
			for i in range(8):
				U.box(root, Vector3(g - 0.4, 0.03, 0.025), Vector3(0, 0.102, -g * 0.5 + (i + 0.5) * g / 8.0), PLANK_DARK)
			for s in [-1.0, 1.0]:
				_solid(root, Vector3(0.1, 1.0, g), Vector3(s * (g * 0.5 - 0.05), 0.6, 0), 0.0, LOG, ghost)
				for z2 in [-1.3, 0.0, 1.3]:
					U.box(root, Vector3(0.14, 1.3, 0.14), Vector3(s * (g * 0.5 - 0.05), 0.45, z2), LOG.darkened(0.2))
			U.box(root, Vector3(0.18, 0.5, g), Vector3(-g * 0.5 + 0.09, -0.2, 0), LOG.darkened(0.3))
			U.box(root, Vector3(0.18, 0.5, g), Vector3(g * 0.5 - 0.09, -0.2, 0), LOG.darkened(0.3))
		"campfire":
			_solid(root, Vector3(1.1, 0.35, 1.1), Vector3(0, 0.17, 0), 0.0, Color(0.42, 0.42, 0.44), ghost)
			for i in range(9):
				var a: float = float(i) / 9.0 * TAU
				U.sphere(root, 0.18, Vector3(cos(a) * 0.65, 0.12, sin(a) * 0.65), Color(0.45, 0.45, 0.47))
			var l1 := U.cyl(root, 0.08, 0.08, 1.0, Vector3(0, 0.38, 0), LOG.darkened(0.3), 8)
			l1.rotation = Vector3(PI * 0.5, 0.5, 0)
			var l2 := U.cyl(root, 0.08, 0.08, 1.0, Vector3(0, 0.42, 0), LOG.darkened(0.3), 8)
			l2.rotation = Vector3(PI * 0.5, -0.9, 0)
			U.cyl(root, 0.0, 0.3, 0.7, Vector3(0, 0.75, 0), Color(1.0, 0.5, 0.1), 8, 3.0)
			U.cyl(root, 0.0, 0.16, 0.45, Vector3(0, 0.7, 0), Color(1.0, 0.85, 0.3), 8, 4.0)
			if not ghost:
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.6, 0.3)
				light.omni_range = 9.0
				light.light_energy = 1.8
				light.position = Vector3(0, 1.2, 0)
				root.add_child(light)
	if not ghost:
		U.bake(root)
	return root


static func _solid(root: Node3D, size: Vector3, pos: Vector3, rot_x: float, c: Color, ghost: bool) -> void:
	var mi := U.box(root, size, pos, c)
	mi.rotation.x = rot_x
	if ghost or not (root is StaticBody3D):
		return
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	cs.rotation.x = rot_x
	root.add_child(cs)
