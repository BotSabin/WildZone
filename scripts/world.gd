extends Node3D
## Builds the map. Uses a fixed seed so every player sees exactly the
## same world (trees, rocks, camp).

const Data = preload("res://scripts/game_data.gd")
const U = preload("res://scripts/util.gd")
const ResourceNodeScript = preload("res://scripts/resource_node.gd")
const TreeScript = preload("res://scripts/tree_node.gd")
const Models = preload("res://scripts/models.gd")

const WORLD_SEED: int = 20261105
const QUARRY_CENTER: Vector3 = Vector3(0, 0, -100)
const LAKE_CENTER: Vector3 = Vector3(62, 0, 48)
const LAKE_RADIUS: float = 18.0
const CABIN_POS: Vector3 = Vector3(-16, 0, -12)
const RIVER_X: float = 96.0
const RIVER_HALF: float = 4.5
const GOLD_HILLS: Vector3 = Vector3(118, 0, -30)

var rng := RandomNumberGenerator.new()
var obstacles: Array = []   # Vector3(x, z, radius) - for animal AI
var rocks: Array = []       # index == id
var trees: Array = []       # index == id
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_mat: ProceduralSkyMaterial
var fire_light: OmniLight3D
var fire_mesh: MeshInstance3D
var fire_time: float = 0.0


func build() -> void:
	rng.seed = WORLD_SEED
	_build_environment()
	_build_ground()
	_build_camp()
	_build_cabin()
	_build_lake()
	_build_river()
	_build_quarry()
	_build_rocks()
	_build_forest()
	_build_border()
	U.bake(self)
	set_time(0.08)


func _process(delta: float) -> void:
	fire_time += delta
	if is_instance_valid(fire_light):
		fire_light.light_energy = 2.2 + sin(fire_time * 13.0) * 0.25 + sin(fire_time * 7.3) * 0.3
	if is_instance_valid(fire_mesh):
		var s: float = 1.0 + sin(fire_time * 11.0) * 0.08
		fire_mesh.scale = Vector3(s, 1.0 + sin(fire_time * 9.0) * 0.15, s)


# ==================================================
# ENVIRONMENT / DAY-NIGHT
# ==================================================

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.95
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.12
	environment.adjustment_contrast = 1.05
	environment.fog_enabled = true
	environment.fog_density = 0.006
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.rotation_degrees = Vector3(-55, 140, 0)
	moon.light_energy = 0.0
	add_child(moon)


## t: 0..1 (0 = sunrise, 0.25 = noon, 0.5 = sunset, 0.75 = midnight)
## Phones: no real-time shadows (the biggest cost on weak GPUs).
func set_mobile_quality() -> void:
	sun.shadow_enabled = false


func set_time(t: float) -> void:
	var elev: float = sin(t * TAU)
	var day: float = clampf(elev * 2.5 + 0.35, 0.0, 1.0)
	sun.rotation = Vector3(-maxf(t * TAU, 0.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = clampf(elev * 1.6, 0.0, 0.95)
	sun.light_color = Color(1.0, 0.85, 0.7).lerp(Color(1.0, 0.97, 0.92), clampf(elev * 2.0, 0.0, 1.0))
	moon.light_energy = (1.0 - day) * 0.22
	var day_top := Color(0.2, 0.42, 0.7)
	var day_hor := Color(0.68, 0.76, 0.8)
	var dusk_hor := Color(0.85, 0.5, 0.3)
	var night_top := Color(0.01, 0.02, 0.06)
	var night_hor := Color(0.04, 0.06, 0.12)
	var horizon: Color = night_hor.lerp(dusk_hor, clampf(day * 2.0, 0.0, 1.0)).lerp(day_hor, clampf(day * 2.0 - 1.0, 0.0, 1.0))
	sky_mat.sky_top_color = night_top.lerp(day_top, day)
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = Color(0.05, 0.06, 0.05).lerp(Color(0.2, 0.22, 0.2), day)
	environment.ambient_light_energy = lerpf(0.3, 0.55, day)
	environment.fog_light_color = horizon
	environment.fog_density = lerpf(0.01, 0.0035, day)


static func is_night(t: float) -> bool:
	return sin(t * TAU) < -0.05


# ==================================================
# TERRAIN
# ==================================================

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(420, 1, 420)
	cs.shape = shape
	cs.position.y = -0.5
	body.add_child(cs)

	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(420, 420)
	mi.mesh = plane
	var m := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.seed = WORLD_SEED
	noise.frequency = 0.03
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var g := Gradient.new()
	g.set_color(0, Color(0.16, 0.25, 0.12))
	g.set_color(1, Color(0.3, 0.38, 0.17))
	tex.color_ramp = g
	m.albedo_texture = tex
	m.uv1_scale = Vector3(40, 40, 1)
	m.roughness = 1.0
	mi.material_override = m
	body.add_child(mi)

	# path from camp to quarry
	var path := U.box(self, Vector3(4.0, 0.04, 80.0), Vector3(0, 0.01, -50.0), Color(0.36, 0.29, 0.2))
	path.material_override = U.mat(Color(0.36, 0.29, 0.2), 1.0)
	# camp clearing
	U.cyl(self, 13.0, 13.0, 0.03, Vector3(0, 0.005, 0), Color(0.33, 0.33, 0.2), 32)


# ==================================================
# CAMP
# ==================================================

func _build_camp() -> void:
	# campfire
	for i in range(9):
		var a: float = float(i) / 9.0 * TAU
		U.sphere(self, 0.22, Vector3(cos(a) * 0.9, 0.1, sin(a) * 0.9), Color(0.4, 0.4, 0.42))
	var log1 := U.cyl(self, 0.1, 0.1, 1.3, Vector3(0, 0.15, 0), Color(0.3, 0.18, 0.08), 8)
	log1.rotation = Vector3(PI * 0.5, 0.4, 0)
	var log2 := U.cyl(self, 0.1, 0.1, 1.3, Vector3(0, 0.2, 0), Color(0.3, 0.18, 0.08), 8)
	log2.rotation = Vector3(PI * 0.5, -0.9, 0)
	fire_mesh = U.cyl(self, 0.0, 0.42, 0.9, Vector3(0, 0.6, 0), Color(1.0, 0.5, 0.1), 8, 3.0)
	U.cyl(fire_mesh, 0.0, 0.22, 0.6, Vector3(0, 0.05, 0), Color(1.0, 0.85, 0.3), 8, 4.0)
	fire_light = OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.6, 0.3)
	fire_light.omni_range = 16.0
	fire_light.position = Vector3(0, 1.4, 0)
	add_child(fire_light)
	U.label(self, "Campfire\n(heals you • animals stay away)", Vector3(0, 2.6, 0), 32, Color(1.0, 0.85, 0.6))

	# animals avoid the camp
	obstacles.append(Vector3(0, 0, Data.CAMP_SAFE_RADIUS - 2.0))

	# log benches
	for a in [0.6, 2.2, 3.9]:
		var bench := U.cyl(self, 0.22, 0.22, 2.0, Vector3(cos(a) * 3.0, 0.22, sin(a) * 3.0), Color(0.36, 0.22, 0.1), 8)
		bench.rotation = Vector3(PI * 0.5, -a + PI * 0.5, 0)

	# tents
	_tent(Vector3(-8.5, 0, -1.5), Color(0.5, 0.42, 0.25))
	_tent(Vector3(-6.5, 0, 7.5), Color(0.32, 0.4, 0.28))
	_tent(Vector3(8.5, 0, 6.5), Color(0.55, 0.3, 0.2))

	_build_trader()


func _tent(pos: Vector3, c: Color) -> void:
	var tent := U.cyl(self, 0.0, 2.1, 2.6, pos + Vector3(0, 1.3, 0), c, 4)
	tent.rotation.y = PI * 0.25
	U.box(self, Vector3(0.7, 1.0, 0.05), pos + Vector3(0, 0.5, -1.47), c.darkened(0.6))
	_solid_cylinder(pos, 1.5, 2.6)
	obstacles.append(Vector3(pos.x, pos.z, 1.8))


func _build_trader() -> void:
	var p: Vector3 = Data.TRADER_POS + Vector3(0, 0, -1.8)
	var wood := Color(0.42, 0.27, 0.13)
	# counter
	U.box(self, Vector3(3.2, 1.05, 0.9), p + Vector3(0, 0.52, 0.0), wood)
	_solid_box(p + Vector3(0, 0.52, 0.0), Vector3(3.2, 1.05, 0.9))
	# posts + roof
	for x in [-1.5, 1.5]:
		for z in [-0.4, -2.0]:
			U.box(self, Vector3(0.15, 2.8, 0.15), p + Vector3(x, 1.4, z), wood.darkened(0.2))
	var roof := U.box(self, Vector3(3.8, 0.12, 2.6), p + Vector3(0, 2.85, -1.1), Color(0.55, 0.2, 0.15))
	roof.rotation.x = -0.15
	# hanging pelts
	var furs: Array = [Color(0.85, 0.42, 0.14), Color(0.5, 0.5, 0.52), Color(0.3, 0.2, 0.13), Color(0.58, 0.38, 0.2)]
	for i in range(furs.size()):
		U.box(self, Vector3(0.5, 0.7, 0.04), p + Vector3(-1.2 + i * 0.8, 1.95, -0.35), furs[i])
	# the trader
	var trader_look: Dictionary = {
		"skin": Color(0.85, 0.65, 0.5), "jacket": Color(0.55, 0.15, 0.12), "shirt": Color(0.9, 0.88, 0.8),
		"pants": Color(0.22, 0.2, 0.3), "boots": Color(0.15, 0.1, 0.07), "hair": Color(0.6, 0.58, 0.55),
		"hat": "fur_hat", "hat_color": Color(0.2, 0.15, 0.12), "signature": "beard",
	}
	var tp: Dictionary = Models.build_character(trader_look)
	var t: Node3D = tp["root"]
	t.position = p + Vector3(0, 0, -1.0)
	t.rotation.y = PI
	add_child(t)
	tp["shoulders"][0].rotation = Vector3(0.5, 0, -0.2)
	tp["shoulders"][1].rotation = Vector3(0.5, 0, 0.2)
	U.label(self, "TRADER ION\n[E] buy / sell", p + Vector3(0, 3.4, 0), 40, Color(1.0, 0.85, 0.4))
	obstacles.append(Vector3(p.x, p.z - 1.0, 2.5))


func _build_cabin() -> void:
	var p: Vector3 = CABIN_POS
	var wall := Color(0.45, 0.3, 0.16)
	U.box(self, Vector3(8, 3.6, 6), p + Vector3(0, 1.8, 0), wall)
	_solid_box(p + Vector3(0, 1.8, 0), Vector3(8, 3.6, 6))
	for i in range(6):
		U.box(self, Vector3(8.05, 0.08, 6.05), p + Vector3(0, 0.3 + i * 0.6, 0), wall.darkened(0.25))
	var roof_l := U.box(self, Vector3(8.6, 0.2, 3.9), p + Vector3(0, 4.2, -1.55), Color(0.3, 0.2, 0.15))
	roof_l.rotation.x = 0.55
	var roof_r := U.box(self, Vector3(8.6, 0.2, 3.9), p + Vector3(0, 4.2, 1.55), Color(0.3, 0.2, 0.15))
	roof_r.rotation.x = -0.55
	U.box(self, Vector3(1.2, 2.2, 0.1), p + Vector3(1.5, 1.1, 3.02), Color(0.25, 0.15, 0.08))
	U.box(self, Vector3(1.0, 0.8, 0.1), p + Vector3(-2.0, 2.0, 3.02), Color(0.9, 0.8, 0.5), 0.6)
	U.box(self, Vector3(0.8, 1.6, 0.8), p + Vector3(3.0, 4.6, -1.0), Color(0.45, 0.42, 0.4))
	obstacles.append(Vector3(p.x, p.z, 5.0))


func _build_lake() -> void:
	var water := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = LAKE_RADIUS
	cm.bottom_radius = LAKE_RADIUS
	cm.height = 0.06
	cm.radial_segments = 40
	water.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.2, 0.3, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.0
	m.roughness = 0.15
	m.metallic_specular = 0.7
	water.material_override = m
	water.position = LAKE_CENTER + Vector3(0, 0.03, 0)
	add_child(water)
	U.cyl(self, LAKE_RADIUS + 1.5, LAKE_RADIUS + 1.5, 0.03, LAKE_CENTER + Vector3(0, 0.012, 0), Color(0.42, 0.38, 0.27), 40)
	for i in range(14):
		var a: float = rng.randf() * TAU
		var r: float = LAKE_RADIUS + rng.randf_range(0.5, 2.5)
		var reed := U.cyl(self, 0.02, 0.04, 1.2, LAKE_CENTER + Vector3(cos(a) * r, 0.6, sin(a) * r), Color(0.35, 0.45, 0.2), 5)
		reed.rotation.z = rng.randf_range(-0.2, 0.2)
	obstacles.append(Vector3(LAKE_CENTER.x, LAKE_CENTER.z, LAKE_RADIUS))
	U.label(self, "Green Lake", LAKE_CENTER + Vector3(0, 2.0, 0), 48, Color(0.7, 0.9, 1.0))


func _build_river() -> void:
	var length: float = 320.0
	var water := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(RIVER_HALF * 2.0, 0.06, length)
	water.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.22, 0.32, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.0
	m.roughness = 0.12
	m.metallic_specular = 0.7
	water.material_override = m
	water.position = Vector3(RIVER_X, 0.03, 0)
	add_child(water)
	for s in [-1.0, 1.0]:
		U.box(self, Vector3(1.6, 0.03, length), Vector3(RIVER_X + s * (RIVER_HALF + 0.8), 0.012, 0), Color(0.5, 0.45, 0.32))
	var z: float = -length * 0.5
	while z < length * 0.5:
		obstacles.append(Vector3(RIVER_X, z, RIVER_HALF + 0.8))
		z += 4.0
	U.label(self, "Cold River\n(build a bridge to cross)", Vector3(RIVER_X - 7.0, 2.5, -2.0), 48, Color(0.7, 0.9, 1.0))
	U.label(self, "GOLD HILLS", GOLD_HILLS + Vector3(0, 5.0, 0), 72, Color(1.0, 0.85, 0.35))


func _build_quarry() -> void:
	var q: Vector3 = QUARRY_CENTER
	U.cyl(self, 22.0, 22.0, 0.03, q + Vector3(0, 0.015, 0), Color(0.42, 0.4, 0.37), 32)
	var cliff := Color(0.4, 0.38, 0.36)
	for i in range(11):
		var a: float = PI + float(i) / 10.0 * PI
		var pos: Vector3 = q + Vector3(cos(a) * 25.0, 0, sin(a) * 25.0 * 0.8 - 6.0)
		var h: float = rng.randf_range(8.0, 14.0)
		var size := Vector3(rng.randf_range(8.0, 11.0), h, rng.randf_range(6.0, 9.0))
		var b := U.box(self, size, pos + Vector3(0, h * 0.5, 0), cliff.darkened(rng.randf_range(0.0, 0.2)))
		b.rotation.y = -a
		_solid_box(pos + Vector3(0, h * 0.5, 0), size, -a)
		obstacles.append(Vector3(pos.x, pos.z, 5.0))
	# mine entrance
	var wood := Color(0.35, 0.22, 0.1)
	var mine_pos: Vector3 = q + Vector3(0, 0, -22.0)
	U.box(self, Vector3(4.0, 4.0, 0.5), mine_pos + Vector3(0, 2.0, 0.6), Color(0.05, 0.05, 0.05))
	U.box(self, Vector3(0.4, 4.4, 0.4), mine_pos + Vector3(-2.2, 2.2, 1.0), wood)
	U.box(self, Vector3(0.4, 4.4, 0.4), mine_pos + Vector3(2.2, 2.2, 1.0), wood)
	U.box(self, Vector3(5.0, 0.4, 0.5), mine_pos + Vector3(0, 4.4, 1.0), wood)
	U.label(self, "QUARRY\nstone • iron • gold", q + Vector3(0, 5.5, -12.0), 64, Color(1.0, 0.9, 0.6))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.4)
	lamp.omni_range = 12.0
	lamp.light_energy = 1.5
	lamp.position = mine_pos + Vector3(0, 3.5, 2.5)
	add_child(lamp)
	U.sphere(self, 0.15, lamp.position, Color(1.0, 0.85, 0.5), 3.0)


# ==================================================
# ROCKS (ore)
# ==================================================

func _build_rocks() -> void:
	var quarry_list: Array = ["stone", "stone", "stone", "stone", "stone", "stone",
		"iron", "iron", "iron", "iron", "iron", "iron",
		"gold", "gold", "gold", "gold", "gold"]
	for t in quarry_list:
		for attempt in range(40):
			var a: float = rng.randf() * TAU
			var r: float = rng.randf_range(3.0, 17.0)
			var pos: Vector3 = QUARRY_CENTER + Vector3(cos(a) * r, 0, sin(a) * r * 0.85)
			if absf(pos.x) < 2.5 and pos.z > QUARRY_CENTER.z:
				continue
			if _rock_spot_ok(pos, 4.2):
				_add_rock(t, pos)
				break

	var hills: Array = ["gold", "gold", "gold", "gold", "iron", "iron", "iron", "stone"]
	for t in hills:
		for attempt in range(50):
			var a3: float = rng.randf() * TAU
			var r3: float = rng.randf_range(2.0, 10.0)
			var hp: Vector3 = GOLD_HILLS + Vector3(cos(a3) * r3 * 0.7, 0, sin(a3) * r3 * 1.4)
			if _rock_spot_ok(hp, 4.5):
				_add_rock(t, hp)
				break

	var wild_list: Array = []
	for i in range(14):
		wild_list.append("stone")
	for i in range(7):
		wild_list.append("iron")
	wild_list.append("gold")
	for t in wild_list:
		for attempt in range(60):
			var a: float = rng.randf() * TAU
			var r: float = rng.randf_range(22.0, Data.MAP_RADIUS - 6.0)
			var pos := Vector3(cos(a) * r, 0, sin(a) * r)
			if not _free_area(pos, 3.0):
				continue
			if _rock_spot_ok(pos, 8.0):
				_add_rock(t, pos)
				break


func _rock_spot_ok(pos: Vector3, spacing: float) -> bool:
	for rock in rocks:
		if rock.position.distance_to(pos) < spacing:
			return false
	return true


func _add_rock(t: String, pos: Vector3) -> void:
	var rock := ResourceNodeScript.new()
	rock.position = pos
	rock.setup(rocks.size(), t, rng)
	rock.name = "Rock_%d" % rocks.size()
	add_child(rock)
	rocks.append(rock)
	obstacles.append(Vector3(pos.x, pos.z, rock.radius))


## True when the spot is not in camp, lake, river, quarry, cabin or on the path.
func _free_area(pos: Vector3, margin: float) -> bool:
	var flat := Vector2(pos.x, pos.z)
	if flat.length() < 16.0 + margin:
		return false
	if flat.distance_to(Vector2(LAKE_CENTER.x, LAKE_CENTER.z)) < LAKE_RADIUS + 2.0 + margin:
		return false
	if flat.distance_to(Vector2(QUARRY_CENTER.x, QUARRY_CENTER.z)) < 26.0 + margin:
		return false
	if flat.distance_to(Vector2(CABIN_POS.x, CABIN_POS.z)) < 6.0 + margin:
		return false
	if absf(pos.x) < 3.0 + margin * 0.5 and pos.z < -8.0 and pos.z > -80.0:
		return false
	if absf(pos.x - RIVER_X) < RIVER_HALF + 2.0 + margin:
		return false
	return true


func is_water(pos: Vector3) -> bool:
	if Vector2(pos.x - LAKE_CENTER.x, pos.z - LAKE_CENTER.z).length() < LAKE_RADIUS:
		return true
	return absf(pos.x - RIVER_X) < RIVER_HALF


# ==================================================
# FOREST
# ==================================================

func _build_forest() -> void:
	var placed: int = 0
	var tries: int = 0
	while placed < 170 and tries < 3000:
		tries += 1
		var a: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * (Data.PLAYER_LIMIT + 8.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		if not _free_area(pos, 0.0):
			continue
		var near_rock: bool = false
		for rock in rocks:
			if rock.position.distance_to(pos) < rock.radius + 2.0:
				near_rock = true
				break
		if near_rock:
			continue
		var tree := TreeScript.new()
		tree.position = pos
		tree.setup(trees.size(), rng.randf() < 0.62, rng)
		tree.name = "Tree_%d" % trees.size()
		add_child(tree)
		trees.append(tree)
		obstacles.append(Vector3(pos.x, pos.z, 0.7))
		placed += 1

	# bushes
	for i in range(60):
		var a2: float = rng.randf() * TAU
		var r2: float = rng.randf_range(14.0, Data.PLAYER_LIMIT)
		var bp := Vector3(cos(a2) * r2, 0, sin(a2) * r2)
		if not _free_area(bp, -2.0):
			continue
		var s: float = rng.randf_range(0.5, 1.0)
		U.ellipsoid(self, Vector3(s * 1.3, s * 0.8, s * 1.2), bp + Vector3(0, s * 0.4, 0), Color(0.15, rng.randf_range(0.28, 0.38), 0.12))


func _build_border() -> void:
	for i in range(46):
		var a: float = float(i) / 46.0 * TAU + rng.randf_range(-0.05, 0.05)
		var r: float = rng.randf_range(155.0, 175.0)
		var h: float = rng.randf_range(25.0, 50.0)
		var pos := Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		var mtn := U.cyl(self, rng.randf_range(0.0, 3.0), rng.randf_range(18.0, 28.0), h, pos, Color(0.3, 0.33, 0.3).darkened(rng.randf_range(0.0, 0.3)), 7)
		mtn.rotation.y = rng.randf() * TAU
		U.cyl(self, 0.0, 4.0, 5.0, pos + Vector3(0, h * 0.5 - 1.5, 0), Color(0.92, 0.94, 0.96), 7)


# ==================================================
# COLLISION HELPERS
# ==================================================

func _solid_box(pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _solid_cylinder(pos: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos + Vector3(0, height * 0.5, 0)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# ==================================================
# USED BY THE SERVER
# ==================================================

func animal_spawn_ok(pos: Vector3, radius: float) -> bool:
	if Vector2(pos.x, pos.z).length() < Data.CAMP_SAFE_RADIUS + 6.0:
		return false
	for o in obstacles:
		var ob: Vector3 = o
		if Vector2(pos.x - ob.x, pos.z - ob.y).length() < ob.z + radius + 0.5:
			return false
	return true
