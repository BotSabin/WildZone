extends RefCounted
## Procedural models for characters, tools and animals.
## Everything faces -Z (Godot forward).

const U = preload("res://scripts/util.gd")

const WOOD_LIGHT := Color(0.55, 0.36, 0.18)
const WOOD_DARK := Color(0.33, 0.2, 0.1)
const GUNMETAL := Color(0.16, 0.17, 0.19)
const STEEL := Color(0.62, 0.64, 0.68)
const GOLD := Color(0.95, 0.76, 0.25)
const LEATHER := Color(0.36, 0.22, 0.12)


# ==================================================
# CHARACTER
# ==================================================

static func build_character(c: Dictionary) -> Dictionary:
	var root := Node3D.new()
	var parts: Dictionary = {"root": root}
	var skin: Color = c["skin"]
	var jacket: Color = c["jacket"]
	var shirt: Color = c["shirt"]
	var pants: Color = c["pants"]
	var boots: Color = c["boots"]
	var hair: Color = c["hair"]
	var sig: String = c["signature"]
	var glove := Color(0.3, 0.2, 0.12)

	# ---- legs ----
	var hips: Array = []
	var knees: Array = []
	for side in [-1.0, 1.0]:
		var hip := U.pivot(root, Vector3(side * 0.13, 0.95, 0))
		U.capsule(hip, 0.11, 0.55, Vector3(0, -0.24, 0), pants)
		var knee := U.pivot(hip, Vector3(0, -0.47, 0))
		U.capsule(knee, 0.095, 0.48, Vector3(0, -0.2, 0), pants)
		U.cyl(knee, 0.1, 0.105, 0.16, Vector3(0, -0.36, 0), boots)
		U.box(knee, Vector3(0.19, 0.12, 0.3), Vector3(0, -0.43, -0.05), boots)
		U.box(knee, Vector3(0.2, 0.035, 0.32), Vector3(0, -0.49, -0.05), boots.darkened(0.4))
		hips.append(hip)
		knees.append(knee)
	parts["hips"] = hips
	parts["knees"] = knees

	# ---- body ----
	U.ellipsoid(root, Vector3(0.24, 0.13, 0.15), Vector3(0, 0.98, 0), pants)
	var torso := U.pivot(root, Vector3(0, 1.0, 0))
	parts["torso"] = torso
	if sig == "beard":
		# flannel: alternating darker stripes
		U.ellipsoid(torso, Vector3(0.27, 0.34, 0.17), Vector3(0, 0.36, 0), jacket)
		for i in range(4):
			U.box(torso, Vector3(0.5, 0.035, 0.33), Vector3(0, 0.2 + i * 0.12, 0), jacket.darkened(0.35))
	else:
		U.ellipsoid(torso, Vector3(0.27, 0.34, 0.17), Vector3(0, 0.36, 0), jacket)
	# open collar showing shirt
	var collar := U.box(torso, Vector3(0.13, 0.16, 0.03), Vector3(0, 0.56, -0.155), shirt)
	collar.rotation.x = 0.25
	U.box(torso, Vector3(0.07, 0.05, 0.12), Vector3(-0.09, 0.66, -0.1), jacket.darkened(0.15))
	U.box(torso, Vector3(0.07, 0.05, 0.12), Vector3(0.09, 0.66, -0.1), jacket.darkened(0.15))
	# zipper / buttons
	for i in range(3):
		U.sphere(torso, 0.012, Vector3(0, 0.22 + i * 0.1, -0.172), Color(0.15, 0.12, 0.1))
	# pockets
	U.box(torso, Vector3(0.1, 0.09, 0.02), Vector3(-0.13, 0.3, -0.16), jacket.darkened(0.2))
	U.box(torso, Vector3(0.1, 0.09, 0.02), Vector3(0.13, 0.3, -0.16), jacket.darkened(0.2))
	# belt + buckle
	var belt := U.cyl(torso, 0.24, 0.245, 0.07, Vector3(0, 0.05, 0), LEATHER)
	belt.scale = Vector3(1.0, 1.0, 0.68)
	U.box_m(torso, Vector3(0.07, 0.055, 0.02), Vector3(0, 0.05, -0.168), U.metal(GOLD))
	# backpack + bedroll
	U.box(torso, Vector3(0.34, 0.4, 0.16), Vector3(0, 0.36, 0.22), Color(0.3, 0.33, 0.24))
	U.box(torso, Vector3(0.26, 0.14, 0.04), Vector3(0, 0.28, 0.31), Color(0.25, 0.28, 0.2))
	var roll := U.cyl(torso, 0.08, 0.08, 0.42, Vector3(0, 0.6, 0.22), Color(0.45, 0.2, 0.15))
	roll.rotation.z = PI * 0.5
	# straps
	U.box(torso, Vector3(0.05, 0.36, 0.02), Vector3(-0.13, 0.42, -0.16), LEATHER)
	U.box(torso, Vector3(0.05, 0.36, 0.02), Vector3(0.13, 0.42, -0.16), LEATHER)

	match sig:
		"cape":
			U.ellipsoid(torso, Vector3(0.34, 0.12, 0.24), Vector3(0, 0.66, 0.02), Color(0.62, 0.5, 0.36))
			var cape := U.box(torso, Vector3(0.52, 0.66, 0.06), Vector3(0, 0.32, 0.34), Color(0.55, 0.43, 0.3))
			cape.rotation.x = -0.08
			U.box(root, Vector3(0.04, 0.2, 0.04), Vector3(0.22, 0.98, -0.1), Color(0.75, 0.75, 0.78))
			U.box(root, Vector3(0.05, 0.1, 0.05), Vector3(0.22, 1.12, -0.1), LEATHER)
		"binoculars":
			for x in [-0.05, 0.05]:
				var b := U.cyl(torso, 0.032, 0.032, 0.12, Vector3(x, 0.44, -0.21), Color(0.1, 0.1, 0.1))
				b.rotation.x = PI * 0.5
			U.box(torso, Vector3(0.12, 0.03, 0.03), Vector3(0, 0.44, -0.21), Color(0.1, 0.1, 0.1))
			var scarf := U.cyl(torso, 0.12, 0.14, 0.08, Vector3(0, 0.68, 0), Color(0.85, 0.65, 0.2))
			scarf.scale = Vector3(1.0, 1.0, 0.9)

	# ---- head ----
	U.cyl(root, 0.07, 0.08, 0.14, Vector3(0, 1.7, 0), skin)
	var head := U.pivot(root, Vector3(0, 1.74, 0))
	parts["head"] = head
	U.ellipsoid(head, Vector3(0.165, 0.2, 0.175), Vector3(0, 0.13, 0), skin)
	for x in [-0.065, 0.065]:
		U.ellipsoid(head, Vector3(0.036, 0.028, 0.012), Vector3(x, 0.16, -0.163), Color(0.96, 0.96, 0.95))
		U.sphere(head, 0.017, Vector3(x, 0.158, -0.173), Color(0.12, 0.09, 0.07))
		var brow := U.box(head, Vector3(0.065, 0.016, 0.02), Vector3(x, 0.205, -0.163), hair.darkened(0.2))
		brow.rotation.z = -0.15 if x < 0 else 0.15
		U.ellipsoid(head, Vector3(0.028, 0.05, 0.03), Vector3(x * 2.55, 0.13, 0.0), skin.darkened(0.05))
	U.ellipsoid(head, Vector3(0.03, 0.045, 0.035), Vector3(0, 0.11, -0.18), skin.darkened(0.08))
	U.box(head, Vector3(0.065, 0.013, 0.01), Vector3(0, 0.045, -0.17), Color(0.55, 0.25, 0.22))
	# hair
	U.ellipsoid(head, Vector3(0.172, 0.12, 0.182), Vector3(0, 0.25, 0.02), hair)
	U.ellipsoid(head, Vector3(0.165, 0.15, 0.1), Vector3(0, 0.15, 0.09), hair)
	if sig == "beard":
		U.ellipsoid(head, Vector3(0.15, 0.13, 0.1), Vector3(0, 0.0, -0.1), hair)
		U.ellipsoid(head, Vector3(0.08, 0.025, 0.03), Vector3(0, 0.07, -0.175), hair)

	var hat_color: Color = c["hat_color"]
	match String(c["hat"]):
		"ranger_hat":
			U.cyl(head, 0.17, 0.19, 0.15, Vector3(0, 0.34, 0), hat_color)
			U.cyl(head, 0.33, 0.34, 0.025, Vector3(0, 0.27, 0), hat_color)
			U.cyl(head, 0.192, 0.192, 0.035, Vector3(0, 0.29, 0), Color(0.15, 0.1, 0.06))
			var dent := U.box(head, Vector3(0.04, 0.03, 0.22), Vector3(0, 0.42, 0), hat_color.darkened(0.25))
			dent.rotation.x = 0.0
		"helmet":
			var helmet := U.ellipsoid(head, Vector3(0.2, 0.15, 0.21), Vector3(0, 0.27, 0), hat_color)
			helmet.scale = Vector3(0.2, 0.15, 0.21)
			U.cyl(head, 0.235, 0.235, 0.02, Vector3(0, 0.23, 0), hat_color.darkened(0.15))
			U.box(head, Vector3(0.03, 0.06, 0.36), Vector3(0, 0.39, 0), hat_color.darkened(0.1))
			var lamp := U.cyl(head, 0.05, 0.055, 0.07, Vector3(0, 0.32, -0.2), Color(0.2, 0.2, 0.2))
			lamp.rotation.x = PI * 0.5
			var lens := U.cyl(head, 0.04, 0.04, 0.01, Vector3(0, 0.32, -0.237), Color(1.0, 0.95, 0.7), 12, 3.0)
			lens.rotation.x = PI * 0.5
		"fur_hat":
			U.cyl(head, 0.2, 0.19, 0.24, Vector3(0, 0.33, 0), hat_color)
			U.ellipsoid(head, Vector3(0.2, 0.06, 0.2), Vector3(0, 0.45, 0), hat_color.lightened(0.1))
			var tail := U.ellipsoid(head, Vector3(0.05, 0.05, 0.18), Vector3(0.05, 0.25, 0.25), Color(0.8, 0.45, 0.15))
			tail.rotation.x = 0.8
		"beret":
			var beret := U.ellipsoid(head, Vector3(0.21, 0.07, 0.21), Vector3(0.03, 0.31, 0.0), hat_color)
			beret.rotation.z = -0.15
			var feather := U.ellipsoid(head, Vector3(0.015, 0.11, 0.035), Vector3(0.17, 0.38, 0.05), Color(0.9, 0.25, 0.15))
			feather.rotation.z = -0.5
		"beanie":
			U.ellipsoid(head, Vector3(0.18, 0.16, 0.19), Vector3(0, 0.27, 0.01), hat_color)
			U.cyl(head, 0.185, 0.185, 0.07, Vector3(0, 0.22, 0.0), hat_color.lightened(0.15))
			U.sphere(head, 0.05, Vector3(0, 0.44, 0.01), Color(0.85, 0.85, 0.85))

	# ---- arms ----
	var shoulders: Array = []
	var elbows: Array = []
	var hands: Array = []
	for side in [-1.0, 1.0]:
		var sh := U.pivot(root, Vector3(side * 0.33, 1.6, 0))
		U.sphere(sh, 0.1, Vector3.ZERO, jacket)
		U.capsule(sh, 0.085, 0.36, Vector3(0, -0.16, 0), jacket)
		var el := U.pivot(sh, Vector3(0, -0.32, 0))
		U.capsule(el, 0.075, 0.32, Vector3(0, -0.14, 0), jacket)
		U.cyl(el, 0.08, 0.08, 0.05, Vector3(0, -0.27, 0), jacket.darkened(0.25))
		U.ellipsoid(el, Vector3(0.055, 0.075, 0.05), Vector3(0, -0.34, 0), glove if sig != "scope" else skin)
		var hand := U.pivot(el, Vector3(0, -0.36, 0))
		shoulders.append(sh)
		elbows.append(el)
		hands.append(hand)
	parts["shoulders"] = shoulders
	parts["elbows"] = elbows
	parts["hands"] = hands
	return parts


# ==================================================
# TOOLS (handle along -Z, grip at origin)
# ==================================================

static func build_rifle(level: int, scoped: bool) -> Node3D:
	var r := Node3D.new()
	var wood: Color = WOOD_LIGHT if level == 1 else (WOOD_DARK if level == 2 else Color(0.25, 0.13, 0.08))
	var steel: Color = Color(0.4, 0.4, 0.42) if level == 1 else GUNMETAL
	var stock := U.box(r, Vector3(0.06, 0.12, 0.34), Vector3(0, -0.04, 0.2), wood)
	stock.rotation.x = 0.12
	U.box(r, Vector3(0.065, 0.05, 0.06), Vector3(0, -0.02, 0.38), Color(0.12, 0.1, 0.08))
	U.box(r, Vector3(0.05, 0.12, 0.06), Vector3(0, -0.08, 0.02), wood)
	U.box_m(r, Vector3(0.06, 0.08, 0.26), Vector3(0, 0.02, -0.1), U.metal(steel))
	U.box(r, Vector3(0.065, 0.055, 0.32), Vector3(0, -0.02, -0.36), wood)
	var barrel := U.cyl_m(r, 0.017, 0.02, 0.62, Vector3(0, 0.035, -0.5), U.metal(steel), 10)
	barrel.rotation.x = PI * 0.5
	var bolt := U.cyl_m(r, 0.012, 0.012, 0.08, Vector3(0.05, 0.04, -0.02), U.metal(STEEL), 8)
	bolt.rotation.z = PI * 0.5
	U.sphere(r, 0.018, Vector3(0.09, 0.04, -0.02), STEEL)
	var guard := U.box_m(r, Vector3(0.012, 0.05, 0.07), Vector3(0, -0.05, -0.02), U.metal(steel))
	guard.rotation.x = 0.3
	U.box_m(r, Vector3(0.012, 0.03, 0.012), Vector3(0, 0.065, -0.78), U.metal(steel))
	if scoped or level >= 3:
		var scope := U.cyl_m(r, 0.028, 0.028, 0.3, Vector3(0, 0.1, -0.1), U.metal(Color(0.08, 0.08, 0.09)), 12)
		scope.rotation.x = PI * 0.5
		for z in [-0.26, 0.06]:
			var bell := U.cyl_m(r, 0.036, 0.03, 0.06, Vector3(0, 0.1, z), U.metal(Color(0.08, 0.08, 0.09)), 12)
			bell.rotation.x = PI * 0.5
		var lens := U.cyl(r, 0.03, 0.03, 0.005, Vector3(0, 0.1, -0.292), Color(0.4, 0.7, 1.0), 12, 1.5)
		lens.rotation.x = PI * 0.5
		U.box_m(r, Vector3(0.02, 0.04, 0.02), Vector3(0, 0.065, -0.18), U.metal(GUNMETAL))
		U.box_m(r, Vector3(0.02, 0.04, 0.02), Vector3(0, 0.065, -0.02), U.metal(GUNMETAL))
	if level >= 3:
		var ring := U.cyl_m(r, 0.024, 0.024, 0.03, Vector3(0, 0.035, -0.7), U.metal(GOLD), 10)
		ring.rotation.x = PI * 0.5
	if level >= 2:
		var sling := U.box(r, Vector3(0.01, 0.02, 0.5), Vector3(-0.04, -0.09, -0.08), LEATHER)
		sling.rotation.x = -0.1
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.035, -0.83)
	r.add_child(muzzle)
	return r


static func _handle(t: Node3D, length: float, c: Color) -> void:
	var h := U.cyl(t, 0.022, 0.026, length, Vector3(0, 0, -length * 0.5 + 0.08), c, 8)
	h.rotation.x = PI * 0.5
	var grip := U.cyl(t, 0.03, 0.03, 0.14, Vector3(0, 0, 0.0), LEATHER, 8)
	grip.rotation.x = PI * 0.5


static func build_pickaxe(level: int) -> Node3D:
	var t := Node3D.new()
	var head_c: Color = [STEEL, STEEL, Color(0.5, 0.55, 0.62), Color(0.45, 0.47, 0.5)][level]
	_handle(t, 0.8, WOOD_LIGHT if level < 3 else WOOD_DARK)
	var tip_z: float = -0.66
	U.box_m(t, Vector3(0.06, 0.07, 0.07), Vector3(0, 0, tip_z), U.metal(head_c.darkened(0.2)))
	for s in [-1.0, 1.0]:
		var spike := U.cyl_m(t, 0.006, 0.035, 0.26, Vector3(0, s * 0.15, tip_z + 0.025), U.metal(head_c), 6)
		spike.rotation.x = 0.0 if s > 0 else PI
		spike.rotation.x += 0.18 * s
		if level >= 3:
			U.cyl_m(spike, 0.004, 0.012, 0.06, Vector3(0, 0.12, 0), U.metal(GOLD), 6)
	return t


static func build_axe(level: int, big: bool) -> Node3D:
	var t := Node3D.new()
	var length: float = 0.85 if big else 0.7
	_handle(t, length, WOOD_LIGHT)
	var hz: float = -length + 0.15
	var head_c: Color = [STEEL, Color(0.45, 0.46, 0.5), STEEL, Color(0.6, 0.62, 0.66)][level]
	var scale: float = 1.25 if big else 1.0
	U.box_m(t, Vector3(0.05, 0.08, 0.08), Vector3(0, 0.0, hz), U.metal(head_c.darkened(0.3)))
	var blade := U.box_m(t, Vector3(0.025, 0.17 * scale, 0.12 * scale), Vector3(0, -0.11 * scale, hz - 0.01), U.metal(head_c))
	blade.rotation.x = 0.12
	U.box_m(t, Vector3(0.028, 0.02, 0.16 * scale), Vector3(0, -0.2 * scale, hz - 0.01), U.metal(STEEL.lightened(0.3)))
	if level >= 2:
		U.box_m(t, Vector3(0.03, 0.06, 0.06), Vector3(0, 0.07, hz), U.metal(head_c.darkened(0.3)))
	if big:
		U.box(t, Vector3(0.05, 0.03, 0.03), Vector3(0, 0.0, -length * 0.4), Color(0.7, 0.15, 0.12))
	return t


static func build_hammer() -> Node3D:
	var t := Node3D.new()
	_handle(t, 0.55, WOOD_LIGHT)
	U.box_m(t, Vector3(0.07, 0.2, 0.07), Vector3(0, 0.02, -0.47), U.metal(GUNMETAL))
	U.cyl_m(t, 0.045, 0.045, 0.04, Vector3(0, 0.13, -0.47), U.metal(STEEL), 10)
	var claw := U.box_m(t, Vector3(0.05, 0.1, 0.03), Vector3(0, -0.11, -0.45), U.metal(GUNMETAL))
	claw.rotation.x = 0.4
	return t


# ==================================================
# ANIMALS
# ==================================================

## Returns {root, body, legs, head, tail, height, hit_radius, width}
static func build_animal(type: String, data: Dictionary) -> Dictionary:
	var root := Node3D.new()
	var col: Color = data["color"]
	var belly: Color = data["belly"]
	var dark: Color = col.darkened(0.45)
	var black := Color(0.05, 0.04, 0.04)
	var p: Dictionary = {"root": root, "legs": [], "tail": null}
	var spec: Dictionary = {}
	match type:
		"rabbit":
			spec = {"body": Vector3(0.14, 0.14, 0.2), "y": 0.2, "leg": 0.13, "leg_r": 0.035, "spread": Vector2(0.08, 0.12),
				"head": Vector3(0.1, 0.1, 0.11), "head_pos": Vector3(0, 0.33, -0.2), "muzzle": Vector3(0.055, 0.05, 0.05), "muzzle_off": Vector3(0, -0.03, -0.09)}
		"fox":
			spec = {"body": Vector3(0.14, 0.15, 0.34), "y": 0.44, "leg": 0.34, "leg_r": 0.035, "spread": Vector2(0.09, 0.25),
				"head": Vector3(0.12, 0.11, 0.13), "head_pos": Vector3(0, 0.58, -0.42), "muzzle": Vector3(0.05, 0.045, 0.11), "muzzle_off": Vector3(0, -0.035, -0.14)}
		"deer":
			spec = {"body": Vector3(0.24, 0.3, 0.6), "y": 1.1, "leg": 0.95, "leg_r": 0.05, "spread": Vector2(0.14, 0.45),
				"head": Vector3(0.1, 0.11, 0.17), "head_pos": Vector3(0, 1.72, -0.78), "muzzle": Vector3(0.07, 0.07, 0.09), "muzzle_off": Vector3(0, -0.04, -0.16)}
		"boar":
			spec = {"body": Vector3(0.3, 0.32, 0.55), "y": 0.64, "leg": 0.38, "leg_r": 0.07, "spread": Vector2(0.18, 0.38),
				"head": Vector3(0.18, 0.2, 0.24), "head_pos": Vector3(0, 0.64, -0.65), "muzzle": Vector3(0.1, 0.09, 0.1), "muzzle_off": Vector3(0, -0.07, -0.22)}
		"wolf":
			spec = {"body": Vector3(0.19, 0.23, 0.5), "y": 0.8, "leg": 0.7, "leg_r": 0.05, "spread": Vector2(0.11, 0.36),
				"head": Vector3(0.13, 0.13, 0.16), "head_pos": Vector3(0, 1.06, -0.66), "muzzle": Vector3(0.07, 0.065, 0.13), "muzzle_off": Vector3(0, -0.045, -0.17)}
		"bear":
			spec = {"body": Vector3(0.55, 0.55, 0.9), "y": 1.05, "leg": 0.62, "leg_r": 0.16, "spread": Vector2(0.32, 0.55),
				"head": Vector3(0.3, 0.28, 0.3), "head_pos": Vector3(0, 1.2, -1.08), "muzzle": Vector3(0.16, 0.13, 0.17), "muzzle_off": Vector3(0, -0.07, -0.25)}

	var b: Vector3 = spec["body"]
	var by: float = spec["y"]
	var body := U.pivot(root, Vector3(0, by, 0))
	p["body"] = body
	U.ellipsoid(body, b, Vector3.ZERO, col)
	U.ellipsoid(body, Vector3(b.x * 0.85, b.y * 0.55, b.z * 0.85), Vector3(0, -b.y * 0.45, 0), belly)

	# legs: hip pivots, upper + lower segment, hoof/paw
	var leg_len: float = spec["leg"]
	var lr: float = spec["leg_r"]
	var spread: Vector2 = spec["spread"]
	var hoofed: bool = type == "deer" or type == "boar"
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var hip := U.pivot(root, Vector3(corner.x * spread.x, leg_len + 0.02, corner.y * spread.y))
		var upper: float = leg_len * 0.55
		var lower: float = leg_len * 0.5
		U.capsule(hip, lr * 1.45, upper + lr, Vector3(0, -upper * 0.45, 0), col)
		U.capsule(hip, lr, lower + lr, Vector3(0, -leg_len + lower * 0.5, 0), col if type != "fox" else dark)
		if hoofed:
			U.cyl(hip, lr * 0.9, lr * 1.1, 0.06, Vector3(0, -leg_len + 0.03, 0), black, 8)
		else:
			U.ellipsoid(hip, Vector3(lr * 1.3, lr * 0.8, lr * 1.6), Vector3(0, -leg_len + lr * 0.6, -lr * 0.4), dark)
		p["legs"].append(hip)

	# head
	var hs: Vector3 = spec["head"]
	var head := U.pivot(root, spec["head_pos"])
	p["head"] = head
	U.ellipsoid(head, hs, Vector3.ZERO, col)
	var mz: Vector3 = spec["muzzle"]
	var moff: Vector3 = spec["muzzle_off"]
	var muzzle_c: Color = belly if type in ["fox", "wolf", "bear", "deer"] else col.lightened(0.1)
	U.ellipsoid(head, mz, moff, muzzle_c)
	U.ellipsoid(head, Vector3(mz.x * 0.45, mz.y * 0.4, mz.x * 0.35), moff + Vector3(0, mz.y * 0.35, -mz.z * 0.95), black if type != "rabbit" else Color(0.9, 0.55, 0.6))
	for s in [-1.0, 1.0]:
		var eye_pos := Vector3(s * hs.x * 0.62, hs.y * 0.25, -hs.z * 0.62)
		U.sphere(head, maxf(hs.x * 0.14, 0.014), eye_pos, black)
		U.sphere(head, maxf(hs.x * 0.05, 0.006), eye_pos + Vector3(s * 0.004, hs.x * 0.07, -hs.x * 0.1), Color(1, 1, 1), 0.5)

	match type:
		"rabbit":
			for s in [-1.0, 1.0]:
				var ear := U.ellipsoid(head, Vector3(0.03, 0.13, 0.016), Vector3(s * 0.045, 0.15, 0.03), col)
				ear.rotation = Vector3(0.25, 0, s * -0.15)
				var inner := U.ellipsoid(head, Vector3(0.018, 0.1, 0.008), Vector3(s * 0.045, 0.15, 0.02), Color(0.9, 0.65, 0.65))
				inner.rotation = ear.rotation
			U.ellipsoid(body, Vector3(0.15, 0.13, 0.12), Vector3(0, 0.0, 0.1), col)
			p["tail"] = U.sphere(body, 0.06, Vector3(0, 0.05, b.z + 0.02), Color(0.97, 0.97, 0.95))
		"fox":
			for s in [-1.0, 1.0]:
				var ear := U.cyl(head, 0.0, 0.05, 0.13, Vector3(s * 0.06, 0.13, 0.02), dark, 6)
				ear.rotation.z = s * -0.25
			var tail_pivot := U.pivot(body, Vector3(0, 0.0, b.z * 0.9))
			var tail := U.ellipsoid(tail_pivot, Vector3(0.075, 0.075, 0.26), Vector3(0, -0.06, 0.22), col)
			tail.rotation.x = 0.4
			U.sphere(tail_pivot, 0.065, Vector3(0, -0.15, 0.44), Color(0.97, 0.96, 0.92))
			p["tail"] = tail_pivot
		"deer":
			var neck := U.capsule(root, 0.1, 0.62, Vector3(0, 1.42, -0.58), col)
			neck.rotation.x = -0.65
			for s in [-1.0, 1.0]:
				var ear := U.ellipsoid(head, Vector3(0.04, 0.085, 0.02), Vector3(s * 0.1, 0.08, 0.05), col)
				ear.rotation.z = s * -0.9
				var antler_c := Color(0.85, 0.78, 0.62)
				var main_a := U.cyl(head, 0.012, 0.025, 0.42, Vector3(s * 0.07, 0.26, 0.03), antler_c, 6)
				main_a.rotation = Vector3(0.25, 0, s * -0.35)
				var b1 := U.cyl(head, 0.01, 0.018, 0.2, Vector3(s * 0.13, 0.33, -0.06), antler_c, 6)
				b1.rotation = Vector3(-0.6, 0, s * -0.3)
				var b2 := U.cyl(head, 0.008, 0.016, 0.16, Vector3(s * 0.17, 0.42, 0.06), antler_c, 6)
				b2.rotation = Vector3(0.5, 0, s * -0.7)
			U.ellipsoid(body, Vector3(0.12, 0.13, 0.05), Vector3(0, 0.08, b.z * 0.97), Color(0.97, 0.95, 0.9))
			var dtail := U.pivot(body, Vector3(0, 0.15, b.z * 0.95))
			U.ellipsoid(dtail, Vector3(0.04, 0.08, 0.03), Vector3(0, -0.04, 0.02), col)
			p["tail"] = dtail
		"boar":
			var snout := U.cyl(head, 0.075, 0.09, 0.12, moff + Vector3(0, 0, -0.04), Color(0.45, 0.32, 0.28), 10)
			snout.rotation.x = PI * 0.5
			for s in [-1.0, 1.0]:
				var tusk := U.cyl(head, 0.004, 0.018, 0.14, Vector3(s * 0.07, -0.1, -0.28), Color(0.96, 0.93, 0.84), 6)
				tusk.rotation = Vector3(-0.3, 0, s * -0.5)
				var ear := U.cyl(head, 0.0, 0.06, 0.12, Vector3(s * 0.12, 0.17, 0.06), col.darkened(0.2), 5)
				ear.rotation = Vector3(0.4, 0, s * -0.5)
			U.ellipsoid(body, Vector3(0.07, 0.11, 0.45), Vector3(0, b.y * 0.85, -0.02), Color(0.15, 0.12, 0.1))
			var btail := U.pivot(body, Vector3(0, 0.1, b.z * 0.95))
			U.cyl(btail, 0.01, 0.02, 0.18, Vector3(0, -0.08, 0.04), col, 6)
			p["tail"] = btail
		"wolf":
			U.ellipsoid(root, Vector3(0.21, 0.26, 0.23), Vector3(0, 0.86, -0.33), col)
			U.ellipsoid(root, Vector3(0.16, 0.19, 0.2), Vector3(0, 1.0, -0.48), col.lightened(0.08))
			for s in [-1.0, 1.0]:
				var ear := U.cyl(head, 0.0, 0.055, 0.14, Vector3(s * 0.075, 0.13, 0.04), col.darkened(0.2), 5)
				ear.rotation.z = s * -0.2
			var wtail := U.pivot(body, Vector3(0, 0.1, b.z * 0.92))
			var tl := U.ellipsoid(wtail, Vector3(0.065, 0.065, 0.28), Vector3(0, -0.12, 0.22), col)
			tl.rotation.x = 0.65
			U.sphere(wtail, 0.05, Vector3(0, -0.27, 0.42), col.darkened(0.4))
			p["tail"] = wtail
		"bear":
			U.ellipsoid(root, Vector3(0.46, 0.42, 0.38), Vector3(0, 1.36, -0.35), col)
			U.ellipsoid(root, Vector3(0.34, 0.36, 0.3), Vector3(0, 1.18, -0.75), col)
			for s in [-1.0, 1.0]:
				U.sphere(head, 0.09, Vector3(s * 0.21, 0.24, 0.05), col.darkened(0.2))
				U.sphere(head, 0.05, Vector3(s * 0.21, 0.24, 0.0), belly.darkened(0.3))
			var btail2 := U.pivot(body, Vector3(0, 0.15, b.z * 0.97))
			U.sphere(btail2, 0.08, Vector3.ZERO, col)
			p["tail"] = btail2

	p["height"] = by
	p["hit_radius"] = maxf(b.z, b.y) + 0.12
	p["width"] = b.x
	return p
