extends CharacterBody3D
## A player character (local or a friend).

const Data = preload("res://scripts/game_data.gd")
const U = preload("res://scripts/util.gd")
const Models = preload("res://scripts/models.gd")

const WALK_SPEED: float = 6.0
const SPRINT_SPEED: float = 9.5
const JUMP_VELOCITY: float = 6.0
const GRAVITY: float = 18.0
const MOUSE_SENSITIVITY: float = 0.0022
const SWING_TIME: float = 0.45

var peer_id: int = 1
var is_local: bool = false
var player_name: String = "Player"
var char_idx: int = 0
var level: int = 1
var main = null

var health: float = 100.0
var max_health: float = 100.0
var dead: bool = false
var speed_mult: float = 1.0
var in_water: bool = false

var tool: String = "rifle"
var tool_levels: Dictionary = {"rifle": 1, "pickaxe": 1, "axe": 1, "hammer": 1}

var pitch: float = -0.15
var remote_position: Vector3 = Vector3.ZERO
var remote_yaw: float = 0.0
var sync_timer: float = 0.0
var last_anim_pos: Vector3 = Vector3.ZERO
var anim_phase: float = 0.0
var anim_amount: float = 0.0
var swing_timer: float = 0.0
var recoil: float = 0.0

var parts: Dictionary = {}
var model: Node3D
var held_tool: Node3D
var back_rifle: Node3D
var muzzle: Node3D
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var camera: Camera3D
var name_label: Label3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.3
	var c: Dictionary = Data.CHARACTERS[clampi(char_idx, 0, Data.CHARACTERS.size() - 1)]
	_update_speed()
	parts = Models.build_character(c)
	model = parts["root"]
	U.bake(model)
	add_child(model)
	_build_collision()
	_build_camera()
	name_label = U.label(self, "", Vector3(0, 2.4, 0), 30)
	refresh_tools()
	remote_position = global_position
	remote_yaw = rotation.y
	last_anim_pos = global_position
	_update_label()
	if is_local:
		camera.current = true
		name_label.visible = false
		camera_pivot.rotation.x = pitch
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		U.set_view_range(model, 160.0)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 1.85
	collision.shape = shape
	collision.position.y = 0.925
	add_child(collision)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.position = Vector3(0, 1.65, 0)
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.position = Vector3(0.55, 0.2, 0)
	spring_arm.spring_length = 4.0
	spring_arm.collision_mask = 1
	spring_arm.margin = 0.2
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	spring_arm.shape = sh
	camera_pivot.add_child(spring_arm)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.far = 600.0
	camera.current = false
	spring_arm.add_child(camera)


# ==================================================
# TOOLS
# ==================================================

func set_tool(p_tool: String, levels: Dictionary) -> void:
	tool = p_tool
	for k in levels.keys():
		tool_levels[k] = int(levels[k])
	refresh_tools()


func refresh_tools() -> void:
	if is_instance_valid(held_tool):
		held_tool.queue_free()
	if is_instance_valid(back_rifle):
		back_rifle.queue_free()
	var c: Dictionary = Data.CHARACTERS[char_idx]
	var scoped: bool = String(c["signature"]) == "scope"
	var hand: Node3D = parts["hands"][1]
	var torso: Node3D = parts["torso"]
	muzzle = null
	match tool:
		"rifle":
			held_tool = Models.build_rifle(int(tool_levels["rifle"]), scoped)
			held_tool.position = Vector3(0.14, 1.36, -0.32)
			U.bake(held_tool)
			model.add_child(held_tool)
			muzzle = held_tool.get_node("Muzzle")
		"pickaxe":
			held_tool = Models.build_pickaxe(int(tool_levels["pickaxe"]))
		"axe":
			held_tool = Models.build_axe(int(tool_levels["axe"]), String(c["signature"]) == "beard")
		_:
			held_tool = Models.build_hammer()
	if tool != "rifle":
		held_tool.rotation.x = -0.3
		U.bake(held_tool)
		hand.add_child(held_tool)
		back_rifle = Models.build_rifle(int(tool_levels["rifle"]), scoped)
		back_rifle.position = Vector3(0.0, 0.42, 0.34)
		back_rifle.rotation = Vector3(0, PI * 0.5, 0.9)
		U.bake(back_rifle)
		torso.add_child(back_rifle)
	_set_rest_pose()


func _set_rest_pose() -> void:
	var sh: Array = parts["shoulders"]
	var el: Array = parts["elbows"]
	if tool == "rifle":
		sh[1].rotation = Vector3(0.75, 0, -0.25)
		el[1].rotation = Vector3(0.75, 0, 0)
		sh[0].rotation = Vector3(1.05, 0, 0.75)
		el[0].rotation = Vector3(0.35, 0, 0)
	else:
		sh[1].rotation = Vector3(0.3, 0, 0.12)
		el[1].rotation = Vector3(0.9, 0, 0)
		sh[0].rotation = Vector3(0.0, 0, -0.1)
		el[0].rotation = Vector3(0.2, 0, 0)


func play_swing() -> void:
	if tool == "rifle":
		return
	swing_timer = SWING_TIME


func play_recoil() -> void:
	recoil = 1.0


func get_muzzle_pos() -> Vector3:
	if muzzle != null and is_instance_valid(muzzle):
		return muzzle.global_position
	return global_position + Vector3(0, 1.4, 0)


# ==================================================
# INPUT / PHYSICS
# ==================================================

func _unhandled_input(event: InputEvent) -> void:
	if not is_local:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		rotation.y -= mm.relative.x * MOUSE_SENSITIVITY
		pitch -= mm.relative.y * MOUSE_SENSITIVITY
		pitch = clampf(pitch, deg_to_rad(-65.0), deg_to_rad(50.0))
		camera_pivot.rotation.x = pitch
	elif event is InputEventMouseButton and event.is_pressed():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and main != null and not main.ui_blocking():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if is_local:
		_local_physics(delta)
	else:
		_remote_physics(delta)
	_animate(delta)


func _local_physics(delta: float) -> void:
	var can_control: bool = not dead and main != null and not main.ui_blocking()
	in_water = main != null and main.world.is_water(global_position) and global_position.y < 0.06

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif can_control and Input.is_action_just_pressed("jump") and not in_water:
		velocity.y = JUMP_VELOCITY

	var input_vec := Vector2.ZERO
	if can_control:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
	var speed: float = WALK_SPEED
	if Input.is_action_pressed("sprint") and not in_water:
		speed = SPRINT_SPEED
	speed *= speed_mult
	if in_water:
		speed *= 0.38

	if direction.length() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * 8.0 * delta)
	move_and_slide()

	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > Data.PLAYER_LIMIT:
		flat = flat.normalized() * Data.PLAYER_LIMIT
		global_position.x = flat.x
		global_position.z = flat.y
	if global_position.y < -20.0:
		global_position = Vector3(0, 2, 6)
		velocity = Vector3.ZERO

	sync_timer += delta
	if sync_timer >= 0.05:
		sync_timer = 0.0
		main.send_player_state(global_position, rotation.y)


func _remote_physics(delta: float) -> void:
	if global_position.distance_to(remote_position) > 10.0:
		global_position = remote_position
	else:
		global_position = global_position.lerp(remote_position, minf(1.0, delta * 12.0))
	rotation.y = lerp_angle(rotation.y, remote_yaw, minf(1.0, delta * 12.0))
	if main != null:
		in_water = main.world.is_water(global_position) and global_position.y < 0.06


func _animate(delta: float) -> void:
	var moved: Vector3 = global_position - last_anim_pos
	moved.y = 0.0
	var spd: float = moved.length() / maxf(delta, 0.0001)
	last_anim_pos = global_position

	var target_amt: float = clampf(spd / 6.0, 0.0, 1.0) if not dead else 0.0
	anim_amount = lerpf(anim_amount, target_amt, minf(1.0, delta * 10.0))
	anim_phase += delta * (4.0 + spd * 1.25)
	var s: float = sin(anim_phase)
	var hips: Array = parts["hips"]
	var knees: Array = parts["knees"]
	hips[0].rotation.x = s * 0.65 * anim_amount
	hips[1].rotation.x = -s * 0.65 * anim_amount
	knees[0].rotation.x = -maxf(0.0, -s) * 0.9 * anim_amount
	knees[1].rotation.x = -maxf(0.0, s) * 0.9 * anim_amount
	var torso: Node3D = parts["torso"]
	torso.position.y = 1.0 + absf(s) * 0.03 * anim_amount
	if not dead:
		model.position.y = -0.55 if in_water else 0.0

	var sh: Array = parts["shoulders"]
	var el: Array = parts["elbows"]
	if swing_timer > 0.0:
		swing_timer -= delta
		var t: float = clampf(1.0 - swing_timer / SWING_TIME, 0.0, 1.0)
		var ang: float = lerpf(2.6, -0.05, ease(t, 2.2))
		sh[1].rotation = Vector3(ang, 0, 0.12)
		el[1].rotation = Vector3(0.25, 0, 0)
		sh[0].rotation = Vector3(ang - 0.2, 0, -0.15)
		el[0].rotation = Vector3(0.3, 0, 0)
		if swing_timer <= 0.0:
			_set_rest_pose()
	elif tool != "rifle":
		sh[0].rotation.x = -s * 0.5 * anim_amount
	else:
		recoil = maxf(0.0, recoil - delta * 6.0)
		if is_instance_valid(held_tool):
			held_tool.position.z = -0.32 + recoil * 0.08
			held_tool.rotation.x = recoil * 0.12


# ==================================================
# STATE
# ==================================================

func set_remote_state(pos: Vector3, yaw: float) -> void:
	remote_position = pos
	remote_yaw = yaw


func get_true_position() -> Vector3:
	return global_position if is_local else remote_position


func set_health(hp: float, p_max: float = -1.0) -> void:
	health = hp
	if p_max > 0.0:
		max_health = p_max
	_update_label()


func set_level(lvl: int) -> void:
	level = lvl
	_update_speed()
	_update_label()


func _update_speed() -> void:
	var c: Dictionary = Data.CHARACTERS[clampi(char_idx, 0, Data.CHARACTERS.size() - 1)]
	speed_mult = float(c["speed"]) * float(Data.bonuses(level)["speed"])


func set_dead(value: bool) -> void:
	dead = value
	if value:
		model.rotation.z = PI * 0.5
		model.position = Vector3(0.95, 0.3, 0)
		velocity = Vector3.ZERO
	else:
		model.rotation.z = 0.0
		model.position = Vector3.ZERO
	_update_label()


func respawn_at(pos: Vector3) -> void:
	global_position = pos
	remote_position = pos
	last_anim_pos = pos
	velocity = Vector3.ZERO
	health = max_health
	set_dead(false)


func level_up_fx() -> void:
	var ring := U.cyl(self, 1.2, 1.2, 0.05, Vector3(0, 0.1, 0), Color(1.0, 0.85, 0.3), 24, 3.0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "position:y", 2.2, 0.8)
	tw.tween_property(ring, "scale", Vector3(0.2, 1.0, 0.2), 0.8)
	tw.chain().tween_callback(ring.queue_free)


func _update_label() -> void:
	if not is_instance_valid(name_label):
		return
	if dead:
		name_label.text = "Lv. %d %s\n(dead)" % [level, player_name]
		name_label.modulate = Color(0.8, 0.8, 0.8)
	else:
		name_label.text = "Lv. %d %s\n%d / %d HP" % [level, player_name, roundi(health), roundi(max_health)]
		name_label.modulate = Color(1.0, 0.95, 0.8)
