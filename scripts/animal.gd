extends Node3D
## An animal. The server runs its AI (server_tick); every player just
## shows the received position (net_pos) with smoothing.

const Data = preload("res://scripts/game_data.gd")
const U = preload("res://scripts/util.gd")
const Models = preload("res://scripts/models.gd")

var animal_id: int = 0
var type: String = "deer"
var data: Dictionary = {}
var hp: float = 1.0
var dead: bool = false
var skinned: bool = false

# --- simulation (server only) ---
var sim_pos: Vector3 = Vector3.ZERO
var sim_yaw: float = 0.0
var state: String = "idle"
var state_timer: float = 0.0
var wander_target: Vector3 = Vector3.ZERO
var target_peer: int = 0
var anger_timer: float = 0.0
var flee_from: Vector3 = Vector3.ZERO
var attack_cd: float = 0.0
var dead_timer: float = 0.0
var move_mode: int = 0   # 0 = idle, 1 = walk, 2 = run

# --- display ---
var net_pos: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_mode: int = 0
var body_root: Node3D
var legs: Array = []
var anim_phase: float = 0.0
var body_height: float = 0.5
var hit_radius: float = 0.5
var body_width: float = 0.4


func setup(p_id: int, p_type: String, pos: Vector3, yaw: float) -> void:
	animal_id = p_id
	type = p_type
	data = Data.ANIMALS[p_type]
	hp = float(data["hp"])
	sim_pos = pos
	sim_yaw = yaw
	net_pos = pos
	net_yaw = yaw
	position = pos
	rotation.y = yaw
	state_timer = randf_range(0.5, 3.0)
	_build_model()


func display_name() -> String:
	return String(data.get("name", type))


# ==================================================
# MODEL
# ==================================================

var head_node: Node3D
var tail_node: Node3D
var body_node: Node3D
var idle_time: float = 0.0


func _build_model() -> void:
	var p: Dictionary = Models.build_animal(type, data)
	body_root = p["root"]
	add_child(body_root)
	legs = p["legs"]
	head_node = p["head"]
	tail_node = p["tail"]
	body_node = p["body"]
	body_height = p["height"]
	hit_radius = p["hit_radius"]
	body_width = p["width"]
	idle_time = randf() * 10.0
	U.bake(body_root)
	U.set_view_range(body_root, 150.0)


# ==================================================
# DISPLAY (everyone)
# ==================================================

func set_net_state(pos: Vector3, yaw: float, mode: int) -> void:
	net_pos = pos
	net_yaw = yaw
	net_mode = mode
	if position.distance_to(pos) > 12.0:
		position = pos


func _process(delta: float) -> void:
	if dead:
		return
	if not visible:
		return
	position = position.lerp(net_pos, minf(1.0, delta * 10.0))
	rotation.y = lerp_angle(rotation.y, net_yaw, minf(1.0, delta * 8.0))

	var amount: float = 0.0
	var speed: float = 0.0
	if net_mode == 1:
		amount = 0.45
		speed = 7.0
	elif net_mode == 2:
		amount = 0.8
		speed = 13.0
	anim_phase += delta * speed
	idle_time += delta
	for i in range(legs.size()):
		var leg: Node3D = legs[i]
		var sgn: float = 1.0 if (i == 0 or i == 3) else -1.0
		leg.rotation.x = lerpf(leg.rotation.x, sin(anim_phase) * amount * sgn, minf(1.0, delta * 12.0))
	if is_instance_valid(body_node):
		var breath: float = 1.0 + sin(idle_time * 2.2) * 0.015
		body_node.scale = Vector3(breath, breath, 1.0)
		body_node.position.y = body_height + absf(sin(anim_phase)) * amount * 0.04
	if is_instance_valid(head_node):
		var graze: float = 0.0
		if net_mode == 0 and type in ["deer", "rabbit", "boar"]:
			graze = maxf(0.0, sin(idle_time * 0.35)) * 0.5
		head_node.rotation.x = lerpf(head_node.rotation.x, sin(anim_phase * 0.5) * amount * 0.08 + graze, minf(1.0, delta * 5.0))
		head_node.rotation.y = sin(idle_time * 0.6) * 0.15 * (1.0 - amount)
	if tail_node != null and is_instance_valid(tail_node):
		tail_node.rotation.y = sin(idle_time * (3.0 + amount * 6.0)) * 0.25


func get_hit_center(use_sim: bool) -> Vector3:
	var p: Vector3 = sim_pos if use_sim else position
	return p + Vector3(0, body_height, 0)


func flash_hit() -> void:
	if not is_instance_valid(body_root):
		return
	var tw := create_tween()
	body_root.scale = Vector3(1.12, 0.9, 1.12)
	tw.tween_property(body_root, "scale", Vector3.ONE, 0.15)


func set_dead_visual(pos: Vector3) -> void:
	dead = true
	net_pos = pos
	position = pos
	for leg in legs:
		leg.rotation.x = 0.0
	body_root.rotation.z = PI * 0.5
	body_root.position = Vector3(body_height, body_width, 0)


# ==================================================
# AI (server only)
# ==================================================

## players: Array of [peer_id, Vector3]. Returns {"peer": id, "damage": x} on attack.
func server_tick(dt: float, players: Array, night: bool, obstacles: Array) -> Dictionary:
	var result: Dictionary = {}
	if dead:
		dead_timer += dt
		return result

	attack_cd -= dt
	state_timer -= dt
	anger_timer -= dt

	var behavior: String = data["behavior"]
	var sense: float = data["sense"]
	if night and behavior == "aggressive":
		sense *= 1.5

	var nearest_id: int = 0
	var nearest_d: float = INF
	var nearest_pos: Vector3 = Vector3.ZERO
	for p in players:
		var pp: Vector3 = p[1]
		var d: float = Vector2(pp.x - sim_pos.x, pp.z - sim_pos.z).length()
		if d < nearest_d:
			nearest_d = d
			nearest_id = int(p[0])
			nearest_pos = pp

	# --- pick state ---
	if behavior == "passive":
		if nearest_d < sense:
			state = "flee"
			flee_from = nearest_pos
		elif anger_timer > 0.0:
			state = "flee"
		elif state == "flee":
			state = "idle"
			state_timer = randf_range(1.0, 3.0)
	else:
		var target_pos: Variant = _find_player(players, target_peer)
		if target_peer != 0 and target_pos != null:
			var td: float = Vector2(target_pos.x - sim_pos.x, target_pos.z - sim_pos.z).length()
			var keep: bool = anger_timer > 0.0 or (behavior == "aggressive" and td < sense * 1.8)
			if Vector2(target_pos.x, target_pos.z).length() < Data.CAMP_SAFE_RADIUS:
				keep = false
			if not keep:
				target_peer = 0
		else:
			target_peer = 0

		if target_peer == 0 and behavior == "aggressive" and nearest_d < sense:
			if Vector2(nearest_pos.x, nearest_pos.z).length() > Data.CAMP_SAFE_RADIUS:
				target_peer = nearest_id

		if target_peer != 0:
			state = "chase"
		elif state == "chase":
			state = "idle"
			state_timer = randf_range(1.0, 3.0)

	# --- movement ---
	var dir: Vector3 = Vector3.ZERO
	var speed: float = 0.0
	move_mode = 0

	match state:
		"idle":
			if state_timer <= 0.0:
				state = "wander"
				state_timer = randf_range(5.0, 10.0)
				var a: float = randf() * TAU
				var r: float = randf_range(4.0, 14.0)
				wander_target = sim_pos + Vector3(cos(a) * r, 0, sin(a) * r)
				if wander_target.length() > Data.MAP_RADIUS - 5.0:
					wander_target = wander_target.normalized() * (Data.MAP_RADIUS - 15.0)
		"wander":
			var to_t: Vector3 = wander_target - sim_pos
			to_t.y = 0.0
			if to_t.length() < 1.0 or state_timer <= 0.0:
				state = "idle"
				state_timer = randf_range(2.0, 6.0)
			else:
				dir = to_t.normalized()
				speed = data["walk"]
				move_mode = 1
		"flee":
			var away: Vector3 = sim_pos - flee_from
			away.y = 0.0
			if away.length() < 0.01:
				away = Vector3(randf() - 0.5, 0, randf() - 0.5)
			dir = away.normalized()
			if sim_pos.length() > Data.MAP_RADIUS - 12.0:
				dir = (dir - sim_pos.normalized() * 1.2).normalized()
			speed = data["run"]
			move_mode = 2
		"chase":
			var tp: Variant = _find_player(players, target_peer)
			if tp == null:
				target_peer = 0
				state = "idle"
			else:
				var to_p: Vector3 = tp - sim_pos
				to_p.y = 0.0
				var dist: float = to_p.length()
				var reach: float = float(data["radius"]) + 1.3
				if dist > 0.01:
					sim_yaw = lerp_angle(sim_yaw, atan2(-to_p.x, -to_p.z), minf(1.0, dt * 10.0))
				if dist <= reach:
					if attack_cd <= 0.0:
						attack_cd = data["attack_cd"]
						result = {"peer": target_peer, "damage": float(data["damage"])}
				else:
					dir = to_p.normalized()
					speed = data["run"]
					move_mode = 2

	if speed > 0.0 and dir.length() > 0.01:
		var new_pos: Vector3 = sim_pos + dir * speed * dt
		new_pos = _resolve_obstacles(new_pos, obstacles)
		if new_pos.length() > Data.MAP_RADIUS:
			new_pos = new_pos.normalized() * Data.MAP_RADIUS
		new_pos.y = 0.0
		sim_pos = new_pos
		sim_yaw = lerp_angle(sim_yaw, atan2(-dir.x, -dir.z), minf(1.0, dt * 8.0))

	# the host renders its own simulation
	net_pos = sim_pos
	net_yaw = sim_yaw
	net_mode = move_mode
	return result


func _find_player(players: Array, peer: int) -> Variant:
	if peer == 0:
		return null
	for p in players:
		if int(p[0]) == peer:
			return p[1]
	return null


func _resolve_obstacles(pos: Vector3, obstacles: Array) -> Vector3:
	var r_self: float = data["radius"]
	for o in obstacles:
		var ob: Vector3 = o
		var rr: float = ob.z + r_self
		var dx: float = pos.x - ob.x
		var dz: float = pos.z - ob.y
		if absf(dx) > rr or absf(dz) > rr:
			continue
		var d2: float = dx * dx + dz * dz
		if d2 < rr * rr and d2 > 0.0001:
			var d: float = sqrt(d2)
			pos.x = ob.x + dx / d * rr
			pos.z = ob.y + dz / d * rr
	return pos


## Returns true when the animal died.
func take_damage(amount: float, attacker: int, attacker_pos: Vector3) -> bool:
	if dead:
		return false
	hp -= amount
	var behavior: String = data["behavior"]
	if behavior == "passive":
		state = "flee"
		flee_from = attacker_pos
		anger_timer = 6.0
	else:
		target_peer = attacker
		anger_timer = 12.0
		state = "chase"
	if hp <= 0.0:
		hp = 0.0
		dead = true
		dead_timer = 0.0
		return true
	return false
