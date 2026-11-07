extends Node3D
## WILDZONE — co-op hunting, mining, chopping, building and trading.
##
## The host (or a dedicated server, or the player in solo mode) is the
## authority: it owns health, animals, trees, rocks, inventories, coins,
## levels and buildings. Clients only send their position and requests
## ("I shot", "mine rock 5", "build a wall here").
## Every RPC takes a single Array argument so it can be sent generically
## through _srv(), _to_peer() and _broadcast().

const Data = preload("res://scripts/game_data.gd")
const U = preload("res://scripts/util.gd")
const Building = preload("res://scripts/building.gd")
const NetworkManagerScript = preload("res://scripts/network_manager.gd")
const PlayerScript = preload("res://scripts/player.gd")
const AnimalScript = preload("res://scripts/animal.gd")
const WorldScript = preload("res://scripts/world.gd")
const HudScript = preload("res://scripts/hud.gd")
const Crazy = preload("res://scripts/crazygames.gd")

const SAVE_DIR: String = "user://saves"
const WORLD_SAVE: String = "user://saves/world.json"
const SETTINGS_PATH: String = "user://settings.cfg"
const SHOT_RANGE: float = 90.0
const RESPAWN_TIME: float = 6.0
const ROCK_RESPAWN: float = 120.0
const CARCASS_TIME: float = 150.0
const BUILD_RANGE: float = 14.0

var net: NetworkManagerScript
var world: WorldScript
var hud: HudScript

var players: Dictionary = {}        # peer_id -> player node (everyone)
var animals: Dictionary = {}        # animal_id -> animal node (everyone)
var structures: Dictionary = {}     # struct_id -> {"node", "kind", "cx", "cz", "level", "rot"}
var occupied: Dictionary = {}       # slot key -> struct_id
var structures_root: Node3D

# --- server only ---
var hosting: bool = false
var dedicated: bool = false
var pdata: Dictionary = {}          # peer_id -> save data + health
var next_animal_id: int = 1
var next_struct_id: int = 1
var respawn_queue: Array = []       # [seconds_left, type]
var ai_timer: float = 0.0
var sync_timer: float = 0.0
var time_sync_timer: float = 0.0
var save_timer: float = 0.0
var heal_timer: float = 0.0
var regen_timer: float = 0.0
var world_dirty: bool = false
var action_last: Dictionary = {}    # "peer|kind" -> msec of last mine/chop

# --- local ---
var in_game: bool = false
var shop_open: bool = false
var chat_open: bool = false
var inv_open: bool = false
var my_stats: Dictionary = {}
var my_dead: bool = false
var time_of_day: float = 0.08
var use_cd: float = 0.0
var hud_timer: float = 0.0
var current_target: Dictionary = {}
var menu_cam: Camera3D
var menu_cam_angle: float = 0.0
var local_name: String = ""
var local_char: int = 0
var tool_idx: int = 0
var build_idx: int = 0
var build_rot: int = 0
var build_target: Dictionary = {}
var ghost: Node3D
var ghost_kind: String = ""
var ghost_valid: int = -1
var ghost_ok_mat: StandardMaterial3D
var ghost_bad_mat: StandardMaterial3D


# ==================================================
# STARTUP
# ==================================================

func _ready() -> void:
	randomize()
	_setup_input_map()
	get_tree().set_auto_accept_quit(false)

	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build()
	structures_root = Node3D.new()
	structures_root.name = "Structures"
	add_child(structures_root)

	net = NetworkManagerScript.new()
	net.name = "NetworkManager"
	add_child(net)
	net.status_changed.connect(_on_net_status)
	net.connected_to_server.connect(_on_connected_to_server)
	net.connection_failed.connect(_on_connection_failed)
	net.server_lost.connect(_on_server_lost)
	net.peer_left.connect(_on_peer_left)

	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.solo_requested.connect(_on_solo_requested)
	hud.host_requested.connect(_on_host_requested)
	hud.host_online_requested.connect(_on_host_online_requested)
	hud.join_requested.connect(_on_join_requested)
	hud.sell_all_requested.connect(func(incl: bool) -> void: _srv("srv_sell_all", [incl]))
	hud.sell_requested.connect(func(item_id: String, count: int) -> void: _srv("srv_sell", [item_id, count]))
	hud.eat_requested.connect(func(item_id: String) -> void: _srv("srv_eat", [item_id]))
	hud.inventory_closed.connect(_close_inventory)
	hud.buy_requested.connect(func(item_id: String) -> void: _srv("srv_buy", [item_id]))
	hud.shop_closed.connect(_close_shop)
	hud.chat_submitted.connect(func(text: String) -> void: _srv("srv_chat", [text]))
	hud.chat_closed.connect(_on_chat_closed)

	ghost_ok_mat = _ghost_mat(Color(0.35, 1.0, 0.45, 0.42))
	ghost_bad_mat = _ghost_mat(Color(1.0, 0.3, 0.25, 0.42))

	menu_cam = Camera3D.new()
	menu_cam.fov = 60.0
	add_child(menu_cam)
	menu_cam.current = true

	var defaults: Dictionary = _load_settings()
	if Engine.has_meta("last_status"):
		defaults["status"] = Engine.get_meta("last_status")
		Engine.remove_meta("last_status")
	var room: String = _url_room()
	if not room.is_empty():
		defaults["room"] = room
		defaults["status"] = "Your friend invited you to room %s — pick a name and character, then press JOIN." % room
	hud.setup_menu(defaults)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Crazy.loading_stop()

	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--server"):
		_start_dedicated(args)


func _ghost_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


func _setup_input_map() -> void:
	var keys: Dictionary = {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"interact": [KEY_E],
		"medkit": [KEY_H],
		"chat": [KEY_T, KEY_ENTER],
		"tool_1": [KEY_1],
		"tool_2": [KEY_2],
		"tool_3": [KEY_3],
		"tool_4": [KEY_4],
		"rotate": [KEY_R],
		"build_next": [KEY_B],
		"inventory": [KEY_I, KEY_TAB],
	}
	for action in keys.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["alt_fire", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		InputMap.action_erase_events(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if hosting:
			_save_all()
		get_tree().quit()


# ==================================================
# LOCAL SETTINGS
# ==================================================

func _load_settings() -> Dictionary:
	var cfg := ConfigFile.new()
	var d: Dictionary = {"name": "", "char": 0, "ip": "", "port": 24560}
	if cfg.load(SETTINGS_PATH) == OK:
		for k in d.keys():
			d[k] = cfg.get_value("menu", k, d[k])
	return d


func _save_settings(p_name: String, p_char: int, ip: String, port: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "name", p_name)
	cfg.set_value("menu", "char", p_char)
	cfg.set_value("menu", "ip", ip)
	cfg.set_value("menu", "port", port)
	cfg.save(SETTINGS_PATH)


# ==================================================
# RPC HELPERS
# ==================================================

func _my_id() -> int:
	return multiplayer.get_unique_id()


func _sender() -> int:
	var s: int = multiplayer.get_remote_sender_id()
	return s if s != 0 else _my_id()


func _online() -> bool:
	return net.peer != null


## Request to the server (a direct call when we are the server).
func _srv(method: String, args: Array) -> void:
	if hosting:
		call(method, args)
	elif _online():
		rpc_id(1, method, args)


## Server -> one player.
func _to_peer(id: int, method: String, args: Array) -> void:
	if id == _my_id():
		call(method, args)
	elif _online():
		rpc_id(id, method, args)


## Server -> remote players only.
func _rpc_all(method: String, args: Array) -> void:
	if _online():
		rpc(method, args)


## Server -> everyone (including the host itself).
func _broadcast(method: String, args: Array) -> void:
	call(method, args)
	_rpc_all(method, args)


# ==================================================
# MENU / CONNECTING
# ==================================================

func _on_net_status(message: String) -> void:
	hud.set_status(message)
	print("[net] ", message)


func _on_solo_requested(p_name: String, p_char: int) -> void:
	_save_settings(p_name, p_char, hud.ip_input.text, NetworkManagerScript.DEFAULT_PORT)
	net.close()
	_begin_hosting(p_name, p_char)
	hud.set_server_info("Solo game • auto-saved")


func _on_host_requested(p_name: String, p_char: int, port: int) -> void:
	_save_settings(p_name, p_char, hud.ip_input.text, port)
	if net.host(port) != OK:
		return
	_begin_hosting(p_name, p_char)
	var ips: Array = NetworkManagerScript.local_ips()
	var ip_txt: String = ", ".join(PackedStringArray(ips)) if not ips.is_empty() else "your IP"
	hud.set_server_info("Hosting • friends join: %s  port %d" % [ip_txt, port])
	hud.add_chat("", "Server is up. Friends on your network can join at %s (port %d)." % [ip_txt, port])


func _url_room() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''", true)
	var code: String = String(v).to_upper() if v != null else ""
	return code if NetworkManagerScript.is_room_code(code) else ""


func _invite_link(code: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("window.location.origin + window.location.pathname", true)
	return "%s?room=%s" % [String(v), code] if v != null else ""


func _on_host_online_requested(p_name: String, p_char: int) -> void:
	_save_settings(p_name, p_char, hud.ip_input.text, NetworkManagerScript.DEFAULT_PORT)
	if net.host_online() != OK:
		return
	_begin_hosting(p_name, p_char)
	var code: String = net.room_code
	hud.set_server_info("ROOM CODE: %s  •  keep this tab open" % code)
	hud.add_chat("", "Your room code is %s. Friends open the game and type it in JOIN, or use this link:" % code)
	var link: String = _invite_link(code)
	if not link.is_empty():
		hud.add_chat("", link)
		JavaScriptBridge.eval("try { navigator.clipboard.writeText(%s); } catch (e) {}" % JSON.stringify(link), true)
		hud.notify("Invite link copied to clipboard!", Color(0.6, 0.9, 1.0))
	hud.big_message("ROOM  %s" % code)


func _begin_hosting(p_name: String, p_char: int) -> void:
	hosting = true
	local_name = p_name
	local_char = p_char
	_server_init()
	srv_join([p_name, p_char])


func _start_dedicated(args: PackedStringArray) -> void:
	var port: int = NetworkManagerScript.DEFAULT_PORT
	var idx: int = args.find("--port")
	if idx >= 0 and idx + 1 < args.size():
		port = int(args[idx + 1])
	if net.host(port) != OK:
		print("[server] could not start on port %d" % port)
		get_tree().quit(1)
		return
	dedicated = true
	hosting = true
	hud.visible = false
	_server_init()
	print("[server] WILDZONE dedicated server running on port %d" % port)


func _on_join_requested(p_name: String, p_char: int, address: String, port: int) -> void:
	_save_settings(p_name, p_char, address, port)
	local_name = p_name
	local_char = p_char
	if NetworkManagerScript.is_room_code(address) and NetworkManagerScript.can_host_online():
		net.join_online(address)
	else:
		net.connect_to(address, port)


func _on_connected_to_server() -> void:
	hud.set_status("Connected! Entering the world...")
	rpc_id(1, "srv_join", [local_name, local_char])
	hud.set_server_info("Online • room %s" % net.room_code if net.online else "Online")


func _on_connection_failed() -> void:
	hud.show_menu(true)


func _on_server_lost() -> void:
	_back_to_menu("The host closed the game or the connection was lost.")


func _back_to_menu(message: String) -> void:
	Engine.set_meta("last_status", message)
	net.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("reload_current_scene")


func _enter_game() -> void:
	in_game = true
	print("[game] entered the world as ", local_name)
	hud.show_menu(false)
	menu_cam.current = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_select_tool(0)
	Crazy.gameplay_start()
	hud.notify("Welcome, %s! Hunt, mine, chop, build — and sell to Trader Ion." % local_name, Color(1.0, 0.85, 0.5))


func ui_blocking() -> bool:
	return shop_open or chat_open or inv_open or not in_game


# ==================================================
# MAIN LOOP
# ==================================================

func _process(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta / Data.DAY_LENGTH, 1.0)
	world.set_time(time_of_day)

	if not in_game and not dedicated:
		menu_cam_angle += delta * 0.05
		menu_cam.position = Vector3(cos(menu_cam_angle) * 26.0, 9.0, sin(menu_cam_angle) * 26.0)
		menu_cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)

	if hosting:
		_server_process(delta)
	if in_game:
		_client_process(delta)


func _me():
	return players.get(_my_id())


func _client_process(delta: float) -> void:
	use_cd -= delta
	var me = _me()
	if me == null:
		return

	current_target = {} if my_dead else _find_target(me)
	var tool: String = Data.TOOLS[tool_idx]
	if tool == "hammer" and not my_dead and not shop_open:
		_update_ghost(me)
	elif is_instance_valid(ghost):
		ghost.visible = false
	hud.set_prompt("" if shop_open else String(current_target.get("text", "")))
	hud.set_swimming(me.in_water and not my_dead)

	if not chat_open:
		if shop_open:
			if Input.is_action_just_pressed("interact"):
				_close_shop()
		elif not my_dead:
			if Input.is_action_just_pressed("interact"):
				_interact()
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_use_tool(me, tool)

	hud_timer -= delta
	if hud_timer <= 0.0:
		hud_timer = 0.5
		hud.set_clock(time_of_day, WorldScript.is_night(time_of_day))
		var lines: Array = []
		for id in players.keys():
			var p = players[id]
			lines.append("Lv. %d %s%s  %s" % [p.level, p.player_name, " (you)" if id == _my_id() else "", "dead" if p.dead else "%d HP" % roundi(p.health)])
		hud.set_players(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not in_game:
		return
	if event.is_action_pressed("ui_cancel"):
		if shop_open:
			_close_shop()
		elif inv_open:
			_close_inventory()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("inventory") and not chat_open and not shop_open:
		if inv_open:
			_close_inventory()
		else:
			_open_inventory()
		get_viewport().set_input_as_handled()
		return
	if chat_open or shop_open or inv_open:
		return
	if event.is_action_pressed("chat"):
		chat_open = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("medkit"):
		_srv("srv_use_medkit", [])
	elif event.is_action_pressed("tool_1"):
		_select_tool(0)
	elif event.is_action_pressed("tool_2"):
		_select_tool(1)
	elif event.is_action_pressed("tool_3"):
		_select_tool(2)
	elif event.is_action_pressed("tool_4"):
		_select_tool(3)
	elif event.is_action_pressed("rotate"):
		build_rot = (build_rot + 1) % 4
	elif event.is_action_pressed("build_next"):
		_cycle_build(1)
	elif event is InputEventMouseButton and event.is_pressed() and tool_idx == 3:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_build(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_build(1)


func _on_chat_closed() -> void:
	chat_open = false
	if in_game:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ==================================================
# TOOLS (client)
# ==================================================

func _select_tool(idx: int) -> void:
	tool_idx = idx
	var tool: String = Data.TOOLS[idx]
	var me = _me()
	if me != null:
		me.set_tool(tool, _tool_levels(my_stats))
	hud.set_tool(idx)
	if idx == 3:
		hud.set_build_piece(build_idx, my_stats.get("inv", {}))
	_srv("srv_equip", [tool])


func _cycle_build(step: int) -> void:
	build_idx = posmod(build_idx + step, Data.BUILD_ORDER.size())
	hud.set_build_piece(build_idx, my_stats.get("inv", {}))


func _tool_levels(s: Dictionary) -> Dictionary:
	return {"rifle": int(s.get("rifle", 1)), "pickaxe": int(s.get("pickaxe", 1)), "axe": int(s.get("axe", 1)), "hammer": 1}


func _aim(me, max_dist: float) -> Dictionary:
	var cam: Camera3D = me.camera
	var origin: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * (max_dist + 4.5), 1)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _use_tool(me, tool: String) -> void:
	match tool:
		"rifle":
			if Input.is_action_just_pressed("fire") and use_cd <= 0.0:
				use_cd = 0.35
				local_fire(me)
		"pickaxe", "axe":
			if Input.is_action_pressed("fire") and use_cd <= 0.0:
				var kind: String = current_target.get("kind", "")
				me.play_swing()
				if tool == "pickaxe":
					use_cd = Data.mine_cooldown(int(my_stats.get("pickaxe", 1)), local_char, int(my_stats.get("level", 1)))
					if kind == "rock":
						_srv("srv_mine", [int(current_target["id"])])
				else:
					use_cd = Data.chop_cooldown(int(my_stats.get("axe", 1)), local_char, int(my_stats.get("level", 1)))
					if kind == "tree":
						_srv("srv_chop", [int(current_target["id"])])
		"hammer":
			if Input.is_action_just_pressed("fire") and not build_target.is_empty():
				if build_target.get("valid", false):
					me.play_swing()
					_srv("srv_build", [build_target["kind"], build_target["cx"], build_target["cz"], build_target["level"], build_target["rot"]])
				else:
					hud.notify(String(build_target.get("why", "Can't build here.")), Color(1.0, 0.6, 0.5))
			if Input.is_action_just_pressed("alt_fire") and current_target.get("kind", "") == "structure":
				me.play_swing()
				_srv("srv_unbuild", [int(current_target["id"])])


func _find_target(me) -> Dictionary:
	var p: Vector3 = me.global_position
	if _flat_dist(p, Data.TRADER_POS) < 3.5:
		return {"kind": "trader", "text": "[E] Trade with Ion — sell loot, buy gear"}
	for a in animals.values():
		if a.dead and not a.skinned and _flat_dist(p, a.position) < 3.2:
			return {"kind": "animal", "id": a.animal_id, "text": "[E] Skin the %s" % a.display_name()}

	var tool: String = Data.TOOLS[tool_idx]
	var hit: Dictionary = _aim(me, 4.0)
	if hit.is_empty():
		return {}
	var col = hit["collider"]
	var hp: Vector3 = hit["position"]
	if col == null:
		return {}
	if col.has_meta("struct_id"):
		if tool == "hammer" and p.distance_to(hp) < BUILD_RANGE:
			var sid: int = col.get_meta("struct_id")
			var kind: String = structures[sid]["kind"] if structures.has(sid) else ""
			return {"kind": "structure", "id": sid, "text": "[RMB] Remove %s (refund half)" % Data.PIECES.get(kind, {"name": "piece"})["name"]}
		return {}
	if _flat_dist(p, hp) > 3.0:
		return {}
	if col.has_meta("rock_id"):
		var rname: String = Data.ROCKS[col.rock_type]["name"]
		if tool == "pickaxe":
			return {"kind": "rock", "id": int(col.get_meta("rock_id")), "text": "[Hold LMB] Mine %s" % rname}
		return {"kind": "hint", "text": "Press 2 for your pickaxe to mine %s" % rname}
	if col.has_meta("tree_id"):
		if tool == "axe":
			return {"kind": "tree", "id": int(col.get_meta("tree_id")), "text": "[Hold LMB] Chop tree for wood"}
		return {"kind": "hint", "text": "Press 3 for your axe to chop this tree"}
	return {}


func _interact() -> void:
	match String(current_target.get("kind", "")):
		"trader":
			_open_shop()
		"animal":
			var me = _me()
			if me != null:
				me.play_swing()
			_srv("srv_skin", [int(current_target["id"])])


func _open_shop() -> void:
	if inv_open:
		_close_inventory()
	shop_open = true
	hud.show_shop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Crazy.gameplay_stop()


func _close_shop() -> void:
	shop_open = false
	hud.hide_shop()
	if in_game and not chat_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Crazy.gameplay_start()


func _open_inventory() -> void:
	inv_open = true
	hud.show_inventory()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Crazy.gameplay_stop()


func _close_inventory() -> void:
	inv_open = false
	hud.hide_inventory()
	if in_game and not chat_open and not shop_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Crazy.gameplay_start()


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ==================================================
# BUILD PREVIEW (client)
# ==================================================

func _update_ghost(me) -> void:
	var kind: String = Data.BUILD_ORDER[build_idx]
	var hit: Dictionary = _aim(me, BUILD_RANGE)
	if hit.is_empty():
		if is_instance_valid(ghost):
			ghost.visible = false
		build_target = {}
		if current_target.is_empty():
			current_target = {"kind": "hint", "text": "Aim at the ground to place a %s  •  [B / wheel] change piece" % Data.PIECES[kind]["name"]}
		return
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	if n.y < 0.5:
		p += n * 0.2
	else:
		p.y += 0.05
	var cell: Vector2i = Building.cell_of(p)
	var level: int = Building.level_of(p.y)
	var rot: int = build_rot
	if Data.PIECES[kind]["slot"] == "W":
		rot = Building.edge_rot(p, cell.x, cell.y)
	var center: Vector3 = Building.cell_center(cell.x, cell.y, level)
	var key: String = Building.slot_key(kind, cell.x, cell.y, level, rot)
	var cost: Dictionary = Data.PIECES[kind]["cost"]
	var why: String = ""
	if Data.unlock_level(kind) > int(my_stats.get("level", 1)):
		why = "Unlocks at Lv. %d." % Data.unlock_level(kind)
	elif occupied.has(key):
		why = "Something is already built there."
	elif _flat_dist(center, Vector3.ZERO) < 8.0 or _flat_dist(center, Data.TRADER_POS) < 6.0:
		why = "You can't build inside the camp."
	elif me.global_position.distance_to(center) > BUILD_RANGE:
		why = "Too far away."
	elif not Data.can_afford(my_stats.get("inv", {}), cost):
		why = "Not enough materials: needs %s." % Data.cost_text(cost)
	build_target = {"kind": kind, "cx": cell.x, "cz": cell.y, "level": level, "rot": rot, "valid": why.is_empty(), "why": why}

	if ghost_kind != kind or not is_instance_valid(ghost):
		if is_instance_valid(ghost):
			ghost.queue_free()
		ghost = Building.make_piece(kind, true)
		add_child(ghost)
		ghost_kind = kind
		ghost_valid = -1
	var v: int = 1 if why.is_empty() else 0
	if v != ghost_valid:
		U.override_all(ghost, ghost_ok_mat if v == 1 else ghost_bad_mat)
		ghost_valid = v
	ghost.global_transform = Building.piece_transform(cell.x, cell.y, level, rot)
	ghost.visible = true
	if current_target.get("kind", "") != "structure":
		var txt: String = "[LMB] Build %s (%s)  •  [R] rotate  •  [B / wheel] change" % [Data.PIECES[kind]["name"], Data.cost_text(cost)]
		if not why.is_empty():
			txt = "%s  •  %s" % [Data.PIECES[kind]["name"], why]
		current_target = {"kind": "build", "text": txt}


# ==================================================
# PLAYER POSITION
# ==================================================

func send_player_state(pos: Vector3, yaw: float) -> void:
	if hosting:
		_rpc_all("cl_state", [_my_id(), pos, yaw])
	elif _online():
		rpc_id(1, "srv_state", [pos, yaw])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_state(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not players.has(id):
		return
	var pos: Vector3 = a[0]
	var yaw: float = a[1]
	players[id].set_remote_state(pos, yaw)
	_rpc_all("cl_state", [id, pos, yaw])


@rpc("authority", "call_remote", "unreliable_ordered")
func cl_state(a: Array) -> void:
	var id: int = a[0]
	if id == _my_id() or not players.has(id):
		return
	players[id].set_remote_state(a[1], a[2])


@rpc("any_peer", "call_remote", "reliable")
func srv_equip(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id):
		return
	var tool: String = a[0]
	if not Data.TOOLS.has(tool):
		return
	pdata[id]["tool"] = tool
	_rpc_all("cl_equip", [id, tool, _tool_levels(pdata[id])])


@rpc("authority", "call_remote", "reliable")
func cl_equip(a: Array) -> void:
	var id: int = a[0]
	if id == _my_id() or not players.has(id):
		return
	players[id].set_tool(String(a[1]), a[2])


# ==================================================
# JOIN / LEAVE
# ==================================================

@rpc("any_peer", "call_remote", "reliable")
func srv_join(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if players.has(id) or pdata.has(id):
		return
	var p_name: String = String(a[0]).strip_edges().left(16)
	if p_name.is_empty():
		p_name = "Hunter"
	for other in pdata.values():
		if String(other["name"]) == p_name:
			p_name = "%s_%d" % [p_name, id % 100]
	var p_char: int = clampi(int(a[1]), 0, Data.CHARACTERS.size() - 1)

	var d: Dictionary = _load_player(p_name)
	d["name"] = p_name
	d["char"] = p_char
	d["max_hp"] = Data.max_hp(int(d["level"]))
	d["hp"] = d["max_hp"]
	d["dead"] = false
	d["respawn"] = 0.0
	d["tool"] = "rifle"
	pdata[id] = d

	var spawn: Vector3 = _camp_spawn_point()
	var saved: Array = d.get("pos", [])
	if saved.size() == 3:
		var sp := Vector3(float(saved[0]), float(saved[1]) + 0.3, float(saved[2]))
		if Vector2(sp.x, sp.z).length() < Data.PLAYER_LIMIT and sp.y > -1.0:
			spawn = sp

	if id != _my_id():
		for other_id in players.keys():
			var op = players[other_id]
			var od: Dictionary = pdata.get(other_id, {})
			_to_peer(id, "cl_spawn_player", [other_id, op.get_true_position(), op.player_name, op.char_idx,
				float(od.get("hp", 100.0)), float(od.get("max_hp", 100.0)), bool(od.get("dead", false)),
				int(od.get("level", 1)), String(od.get("tool", "rifle")), _tool_levels(od)])
		for an in animals.values():
			_to_peer(id, "cl_animal_spawn", [an.animal_id, an.type, an.sim_pos, an.sim_yaw, an.dead])
		var rocks_off: Array = []
		for rock in world.rocks:
			if not rock.active:
				rocks_off.append(rock.rock_id)
		var trees_off: Array = []
		for tree in world.trees:
			if not tree.active:
				trees_off.append(tree.tree_id)
		_to_peer(id, "cl_world_states", [rocks_off, trees_off])
		_to_peer(id, "cl_structures", [_structure_list()])
		_to_peer(id, "cl_time", [time_of_day])

	_broadcast("cl_spawn_player", [id, spawn, p_name, p_char, float(d["hp"]), float(d["max_hp"]), false,
		int(d["level"]), "rifle", _tool_levels(d)])
	_send_stats(id)
	_broadcast("cl_chat", ["", "Lv. %d %s the %s joined the game." % [int(d["level"]), p_name, Data.CHARACTERS[p_char]["name"]]])


@rpc("authority", "call_remote", "reliable")
func cl_spawn_player(a: Array) -> void:
	var id: int = a[0]
	if players.has(id):
		return
	var p := PlayerScript.new()
	p.name = "Player_%d" % id
	p.peer_id = id
	p.is_local = id == _my_id() and not dedicated
	p.player_name = a[2]
	p.char_idx = a[3]
	p.level = int(a[7])
	p.tool = String(a[8])
	p.tool_levels = a[9]
	p.main = self
	p.position = a[1]
	add_child(p)
	players[id] = p
	p.set_health(float(a[4]), float(a[5]))
	if bool(a[6]):
		p.set_dead(true)
	if p.is_local:
		_enter_game()
		hud.set_health(float(a[4]), float(a[5]))


@rpc("authority", "call_remote", "reliable")
func cl_remove_player(a: Array) -> void:
	var id: int = a[0]
	if players.has(id):
		var p = players[id]
		players.erase(id)
		if is_instance_valid(p):
			p.queue_free()


func _on_peer_left(id: int) -> void:
	if not hosting:
		return
	var left_name: String = ""
	if pdata.has(id):
		left_name = String(pdata[id]["name"])
		_save_player(id)
		pdata.erase(id)
	_broadcast("cl_remove_player", [id])
	if not left_name.is_empty():
		_broadcast("cl_chat", ["", "%s left the game." % left_name])


func _camp_spawn_point() -> Vector3:
	var a: float = randf_range(PI * 0.3, PI * 0.7)
	var r: float = randf_range(4.0, 6.0)
	return Vector3(cos(a) * r, 0.3, sin(a) * r)


# ==================================================
# STATS / INVENTORY / XP
# ==================================================

func _send_stats(id: int) -> void:
	if not pdata.has(id):
		return
	var d: Dictionary = pdata[id]
	var s: Dictionary = {
		"coins": d["coins"], "ammo": d["ammo"], "medkits": d["medkits"],
		"rifle": d["rifle"], "pickaxe": d["pickaxe"], "axe": d["axe"],
		"level": d["level"], "xp": d["xp"], "inv": d["inv"].duplicate(), "char": d["char"],
	}
	_to_peer(id, "cl_stats", [s])


@rpc("authority", "call_remote", "reliable")
func cl_stats(a: Array) -> void:
	var old_levels: Dictionary = _tool_levels(my_stats)
	my_stats = a[0]
	hud.update_stats(my_stats)
	if tool_idx == 3:
		hud.set_build_piece(build_idx, my_stats.get("inv", {}))
	var me = _me()
	if me != null and _tool_levels(my_stats) != old_levels:
		me.set_tool(Data.TOOLS[tool_idx], _tool_levels(my_stats))


func _give(id: int, item_id: String, count: int) -> void:
	if count <= 0 or not pdata.has(id):
		return
	var inv: Dictionary = pdata[id]["inv"]
	inv[item_id] = int(inv.get(item_id, 0)) + count
	_to_peer(id, "cl_notify", ["+%d %s" % [count, Data.item_name(item_id)], Color(0.75, 1.0, 0.6)])


func _add_xp(id: int, amount: int) -> void:
	if not pdata.has(id) or amount <= 0:
		return
	var d: Dictionary = pdata[id]
	if int(d["level"]) >= Data.MAX_LEVEL:
		return
	d["xp"] = int(d["xp"]) + amount
	var leveled: bool = false
	while int(d["level"]) < Data.MAX_LEVEL and int(d["xp"]) >= Data.xp_to_next(int(d["level"])):
		d["xp"] = int(d["xp"]) - Data.xp_to_next(int(d["level"]))
		d["level"] = int(d["level"]) + 1
		leveled = true
	if int(d["level"]) >= Data.MAX_LEVEL:
		d["xp"] = 0
	if leveled:
		var lvl: int = int(d["level"])
		var reward: Dictionary = Data.level_rewards(lvl)
		var bon: Dictionary = Data.bonuses(lvl)
		d["coins"] = int(d["coins"]) + int(reward["coins"])
		d["ammo"] = mini(int(d["ammo"]) + int(reward["ammo"]), int(bon["max_ammo"]))
		d["medkits"] = mini(int(d["medkits"]) + int(reward["medkits"]), int(bon["max_medkits"]))
		var msg: String = "Lv. %d reward: +%d coins, +%d ammo" % [lvl, int(reward["coins"]), int(reward["ammo"])]
		if int(reward["medkits"]) > 0:
			msg += ", +1 medkit"
		for kind in Data.UNLOCKS.keys():
			if int(Data.UNLOCKS[kind]) == lvl:
				msg += "  •  Unlocked: %s" % Data.PIECES[kind]["name"]
		if lvl == 10:
			msg += "  •  Health regeneration unlocked"
		_to_peer(id, "cl_notify", [msg, Color(1.0, 0.85, 0.35)])
		d["max_hp"] = Data.max_hp(int(d["level"]))
		d["hp"] = d["max_hp"]
		_broadcast("cl_level", [id, int(d["level"])])
		_broadcast("cl_health", [id, d["hp"], d["max_hp"]])
		_broadcast("cl_chat", ["", "%s reached Lv. %d!" % [d["name"], int(d["level"])]])
		_save_player(id)


@rpc("authority", "call_remote", "reliable")
func cl_level(a: Array) -> void:
	var id: int = a[0]
	if players.has(id):
		players[id].set_level(int(a[1]))
		players[id].level_up_fx()
	if id == _my_id():
		hud.big_message("LEVEL UP!  Lv. %d" % int(a[1]))
		if int(a[1]) % 10 == 0:
			Crazy.happy_time()


@rpc("authority", "call_remote", "reliable")
func cl_notify(a: Array) -> void:
	var c: Color = a[1] if a.size() > 1 else Color(1.0, 0.95, 0.8)
	hud.notify(String(a[0]), c)


# ==================================================
# SHOOTING
# ==================================================

func local_fire(me) -> void:
	var ammo: int = int(my_stats.get("ammo", 0))
	if ammo <= 0:
		hud.notify("Out of ammo! Buy more from Trader Ion.", Color(1.0, 0.6, 0.5))
		return
	my_stats["ammo"] = ammo - 1
	hud.set_ammo(ammo - 1)
	var cam: Camera3D = me.camera
	var origin: Vector3 = cam.global_position
	var dir: Vector3 = (-cam.global_transform.basis.z).normalized()
	var hit: Dictionary = _hit_test(origin, dir, false)
	me.play_recoil()
	_spawn_tracer(me.get_muzzle_pos(), hit["end"])
	var target_id: int = 0
	if hit["animal"] != null:
		target_id = hit["animal"].animal_id
	_srv("srv_shoot", [origin, dir, target_id, hit["end"]])


func _hit_test(origin: Vector3, dir: Vector3, use_sim: bool) -> Dictionary:
	var to: Vector3 = origin + dir * SHOT_RANGE
	var end: Vector3 = to
	var max_t: float = SHOT_RANGE
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1)
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		end = res["position"]
		max_t = origin.distance_to(end)
	var best = null
	var best_t: float = max_t
	for an in animals.values():
		if an.dead:
			continue
		var c: Vector3 = an.get_hit_center(use_sim)
		var t: float = (c - origin).dot(dir)
		if t < 0.0 or t > best_t:
			continue
		if (origin + dir * t).distance_to(c) <= an.hit_radius:
			best = an
			best_t = t
	if best != null:
		end = origin + dir * best_t
	return {"end": end, "animal": best}


@rpc("any_peer", "call_remote", "reliable")
func srv_shoot(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id) or not players.has(id):
		return
	var d: Dictionary = pdata[id]
	if d["dead"] or int(d["ammo"]) <= 0:
		_send_stats(id)
		return
	var origin: Vector3 = a[0]
	var dir: Vector3 = a[1]
	dir = dir.normalized()
	var target_id: int = a[2]
	var end: Vector3 = a[3]
	var shooter_pos: Vector3 = players[id].get_true_position()
	if origin.distance_to(shooter_pos) > 10.0:
		return
	d["ammo"] = int(d["ammo"]) - 1

	# the client reports what it hit; the server checks it is plausible
	if target_id != 0 and animals.has(target_id):
		var an = animals[target_id]
		if not an.dead:
			var c: Vector3 = an.get_hit_center(true)
			var t: float = (c - origin).dot(dir)
			var miss: float = (origin + dir * t).distance_to(c)
			if t > 0.0 and t <= SHOT_RANGE + 2.0 and miss <= an.hit_radius + 3.0:
				var ch: Dictionary = Data.CHARACTERS[int(d["char"])]
				var dmg: float = float(Data.RIFLE_DAMAGE[int(d["rifle"])]) * float(ch["damage"]) * Data.level_damage_mult(int(d["level"]))
				var killed: bool = an.take_damage(dmg, id, shooter_pos)
				_broadcast("cl_animal_hit", [target_id])
				_to_peer(id, "cl_hitmarker", [killed])
				if killed:
					an.dead_timer = 0.0
					_broadcast("cl_animal_dead", [target_id, an.sim_pos])
					_to_peer(id, "cl_notify", ["You took down a %s! Press E next to it to skin it." % an.display_name(), Color(1.0, 0.85, 0.4)])
					_add_xp(id, int(an.data["xp"]))

	_rpc_all("cl_shot_fx", [id, end])
	_send_stats(id)


@rpc("authority", "call_remote", "unreliable")
func cl_shot_fx(a: Array) -> void:
	var id: int = a[0]
	if id == _my_id() or not players.has(id):
		return
	players[id].play_recoil()
	_spawn_tracer(players[id].get_muzzle_pos(), a[1])


@rpc("authority", "call_remote", "reliable")
func cl_hitmarker(a: Array) -> void:
	hud.hit_marker(bool(a[0]))


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	if length < 0.2:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, length)
	mi.mesh = bm
	mi.material_override = U.mat(Color(1.0, 0.85, 0.45), 0.5, 3.0)
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	var dir: Vector3 = (to - from).normalized()
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	mi.look_at(to, up)
	var flash := U.sphere(self, 0.12, from, Color(1.0, 0.8, 0.3), 4.0)
	var tw := mi.create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(flash.queue_free)


# ==================================================
# ANIMALS
# ==================================================

func _create_animal(id: int, type: String, pos: Vector3, yaw: float, dead: bool) -> Node:
	if animals.has(id):
		return animals[id]
	var an := AnimalScript.new()
	an.name = "Animal_%d" % id
	an.setup(id, type, pos, yaw)
	add_child(an)
	animals[id] = an
	if dead:
		an.set_dead_visual(pos)
	return an


@rpc("authority", "call_remote", "reliable")
func cl_animal_spawn(a: Array) -> void:
	_create_animal(int(a[0]), String(a[1]), a[2], float(a[3]), bool(a[4]))


@rpc("authority", "call_remote", "unreliable")
func cl_animals(a: Array) -> void:
	var data: PackedFloat32Array = a[0]
	var i: int = 0
	while i + 4 < data.size():
		var id: int = int(data[i])
		if animals.has(id):
			animals[id].set_net_state(Vector3(data[i + 1], 0.0, data[i + 2]), data[i + 3], int(data[i + 4]))
		i += 5


@rpc("authority", "call_remote", "reliable")
func cl_animal_hit(a: Array) -> void:
	var id: int = a[0]
	if animals.has(id):
		animals[id].flash_hit()


@rpc("authority", "call_remote", "reliable")
func cl_animal_dead(a: Array) -> void:
	var id: int = a[0]
	if animals.has(id):
		animals[id].set_dead_visual(a[1])


@rpc("authority", "call_remote", "reliable")
func cl_animal_remove(a: Array) -> void:
	var id: int = a[0]
	if animals.has(id):
		var an = animals[id]
		animals.erase(id)
		an.queue_free()


@rpc("any_peer", "call_remote", "reliable")
func srv_skin(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	var aid: int = a[0]
	if not pdata.has(id) or not players.has(id) or not animals.has(aid):
		return
	var an = animals[aid]
	if not an.dead or an.skinned:
		return
	if _flat_dist(players[id].get_true_position(), an.sim_pos) > 4.5:
		return
	an.skinned = true
	var d: Dictionary = pdata[id]
	var loot: Dictionary = an.data["loot"]
	for item_id in loot.keys():
		var n: int = int(loot[item_id])
		if String(Data.CHARACTERS[int(d["char"])]["signature"]) == "cape" and item_id != "meat":
			n += 1
		if item_id != "meat" and randf() < float(Data.bonuses(int(d["level"]))["double"]):
			n *= 2
		_give(id, item_id, n)
	_add_xp(id, 3)
	_send_stats(id)
	_broadcast("cl_animal_remove", [aid])
	_queue_animal_respawn(String(an.type))


func _queue_animal_respawn(type: String) -> void:
	respawn_queue.append([randf_range(35.0, 75.0), type])


func _server_spawn_animal(type: String) -> void:
	var info: Dictionary = Data.ANIMALS[type]
	var min_dist: float = info["min_dist"]
	for attempt in range(40):
		var ang: float = randf() * TAU
		var r: float = randf_range(min_dist, Data.MAP_RADIUS - 6.0)
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not world.animal_spawn_ok(pos, float(info["radius"])):
			continue
		var near_player: bool = false
		for p in players.values():
			if _flat_dist(p.get_true_position(), pos) < 35.0:
				near_player = true
				break
		if near_player:
			continue
		var id: int = next_animal_id
		next_animal_id += 1
		var yaw: float = randf() * TAU
		_create_animal(id, type, pos, yaw, false)
		_rpc_all("cl_animal_spawn", [id, type, pos, yaw, false])
		return
	respawn_queue.append([10.0, type])


# ==================================================
# MINING / CHOPPING
# ==================================================

func _action_ready(id: int, kind: String, cd: float) -> bool:
	var key: String = "%d|%s" % [id, kind]
	var now: int = Time.get_ticks_msec()
	if action_last.has(key) and now - int(action_last[key]) < int(cd * 1000.0 * 0.8):
		return false
	action_last[key] = now
	return true


@rpc("any_peer", "call_remote", "reliable")
func srv_mine(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	var rid: int = a[0]
	if not pdata.has(id) or not players.has(id) or rid < 0 or rid >= world.rocks.size():
		return
	var d: Dictionary = pdata[id]
	if d["dead"]:
		return
	var rock = world.rocks[rid]
	if not rock.active:
		return
	if _flat_dist(players[id].get_true_position(), rock.position) > rock.radius + 4.0:
		return
	if not _action_ready(id, "mine", Data.mine_cooldown(int(d["pickaxe"]), int(d["char"]), int(d["level"]))):
		return

	var info: Dictionary = Data.ROCKS[rock.rock_type]
	var count: int = 1
	if rock.rock_type == "stone":
		count += int(d["pickaxe"]) - 1
	elif rock.rock_type == "iron" and int(d["pickaxe"]) >= 3:
		count += 1
	if int(d["char"]) == 1 and randf() < 0.25:
		count += 1
	if randf() < float(Data.bonuses(int(d["level"]))["double"]):
		count *= 2
	_give(id, String(info["item"]), count)
	if rock.rock_type != "stone" and randf() < 0.3:
		_give(id, "stone", 1)
	_add_xp(id, int(info["xp"]))
	_send_stats(id)

	rock.amount -= 1
	_broadcast("cl_rock_hit", [rid, id])
	if rock.amount <= 0:
		rock.respawn_left = ROCK_RESPAWN
		_broadcast("cl_rock_state", [rid, false])
		_to_peer(id, "cl_notify", ["The vein is empty. It refills in ~2 minutes.", Color(0.8, 0.8, 0.8)])


@rpc("authority", "call_remote", "reliable")
func cl_rock_hit(a: Array) -> void:
	var rid: int = a[0]
	var who: int = a[1]
	if rid >= 0 and rid < world.rocks.size():
		world.rocks[rid].hit_fx()
	if who != _my_id() and players.has(who):
		players[who].play_swing()


@rpc("authority", "call_remote", "reliable")
func cl_rock_state(a: Array) -> void:
	var rid: int = a[0]
	if rid >= 0 and rid < world.rocks.size():
		world.rocks[rid].set_active(bool(a[1]))


@rpc("any_peer", "call_remote", "reliable")
func srv_chop(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	var tid: int = a[0]
	if not pdata.has(id) or not players.has(id) or tid < 0 or tid >= world.trees.size():
		return
	var d: Dictionary = pdata[id]
	if d["dead"]:
		return
	var tree = world.trees[tid]
	if not tree.active:
		return
	if _flat_dist(players[id].get_true_position(), tree.position) > 4.5:
		return
	if not _action_ready(id, "chop", Data.chop_cooldown(int(d["axe"]), int(d["char"]), int(d["level"]))):
		return
	var wood: int = 1
	if int(d["axe"]) >= 2:
		wood += 1
	if String(Data.CHARACTERS[int(d["char"])]["signature"]) == "beard":
		wood += 1
	if randf() < float(Data.bonuses(int(d["level"]))["double"]):
		wood *= 2
	tree.hp -= 1
	if tree.hp <= 0:
		wood += 2
	_give(id, "wood", wood)
	_add_xp(id, Data.TREE_XP)
	_send_stats(id)
	_broadcast("cl_tree_hit", [tid, id])
	if tree.hp <= 0:
		tree.respawn_left = Data.TREE_RESPAWN
		_broadcast("cl_tree_state", [tid, false, true])


@rpc("authority", "call_remote", "reliable")
func cl_tree_hit(a: Array) -> void:
	var tid: int = a[0]
	var who: int = a[1]
	if tid >= 0 and tid < world.trees.size():
		world.trees[tid].hit_fx()
	if who != _my_id() and players.has(who):
		players[who].play_swing()


@rpc("authority", "call_remote", "reliable")
func cl_tree_state(a: Array) -> void:
	var tid: int = a[0]
	if tid >= 0 and tid < world.trees.size():
		world.trees[tid].set_active(bool(a[1]), bool(a[2]))


@rpc("authority", "call_remote", "reliable")
func cl_world_states(a: Array) -> void:
	for rid in a[0]:
		if int(rid) >= 0 and int(rid) < world.rocks.size():
			world.rocks[int(rid)].set_active(false)
	for tid in a[1]:
		if int(tid) >= 0 and int(tid) < world.trees.size():
			world.trees[int(tid)].set_active(false, false)


# ==================================================
# BUILDING
# ==================================================

func _structure_list() -> Array:
	var out: Array = []
	for sid in structures.keys():
		var s: Dictionary = structures[sid]
		out.append([sid, s["kind"], s["cx"], s["cz"], s["level"], s["rot"]])
	return out


func _place_structure(sid: int, kind: String, cx: int, cz: int, level: int, rot: int) -> void:
	if structures.has(sid) or not Data.PIECES.has(kind):
		return
	var node: Node3D = Building.make_piece(kind, false)
	node.name = "Struct_%d" % sid
	node.set_meta("struct_id", sid)
	structures_root.add_child(node)
	node.global_transform = Building.piece_transform(cx, cz, level, rot)
	U.set_view_range(node, 220.0)
	structures[sid] = {"node": node, "kind": kind, "cx": cx, "cz": cz, "level": level, "rot": rot}
	occupied[Building.slot_key(kind, cx, cz, level, rot)] = sid
	next_struct_id = maxi(next_struct_id, sid + 1)


func _remove_structure(sid: int) -> void:
	if not structures.has(sid):
		return
	var s: Dictionary = structures[sid]
	occupied.erase(Building.slot_key(s["kind"], s["cx"], s["cz"], s["level"], s["rot"]))
	if is_instance_valid(s["node"]):
		s["node"].queue_free()
	structures.erase(sid)


@rpc("any_peer", "call_remote", "reliable")
func srv_build(a: Array) -> void:
	if not hosting or a.size() < 5:
		return
	var id: int = _sender()
	if not pdata.has(id) or not players.has(id):
		return
	var kind: String = a[0]
	if not Data.PIECES.has(kind):
		return
	var cx: int = a[1]
	var cz: int = a[2]
	var level: int = clampi(int(a[3]), 0, 6)
	var rot: int = posmod(int(a[4]), 4)
	var d: Dictionary = pdata[id]
	var center: Vector3 = Building.cell_center(cx, cz, level)
	if occupied.has(Building.slot_key(kind, cx, cz, level, rot)):
		return
	if players[id].get_true_position().distance_to(center) > BUILD_RANGE + 3.0:
		return
	if _flat_dist(center, Vector3.ZERO) < 8.0 or _flat_dist(center, Data.TRADER_POS) < 6.0:
		return
	if Data.unlock_level(kind) > int(d["level"]):
		_to_peer(id, "cl_notify", ["%s unlocks at Lv. %d." % [Data.PIECES[kind]["name"], Data.unlock_level(kind)], Color(1.0, 0.6, 0.5)])
		return
	var cost: Dictionary = Data.PIECES[kind]["cost"]
	if not Data.can_afford(d["inv"], cost):
		_to_peer(id, "cl_notify", ["Not enough materials: needs %s." % Data.cost_text(cost), Color(1.0, 0.6, 0.5)])
		return
	for k in cost.keys():
		d["inv"][k] = int(d["inv"].get(k, 0)) - int(cost[k])
		if int(d["inv"][k]) <= 0:
			d["inv"].erase(k)
	var sid: int = next_struct_id
	next_struct_id += 1
	_broadcast("cl_build", [sid, kind, cx, cz, level, rot])
	_add_xp(id, 5)
	_send_stats(id)
	world_dirty = true


@rpc("authority", "call_remote", "reliable")
func cl_build(a: Array) -> void:
	_place_structure(int(a[0]), String(a[1]), int(a[2]), int(a[3]), int(a[4]), int(a[5]))


@rpc("authority", "call_remote", "reliable")
func cl_structures(a: Array) -> void:
	for s in a[0]:
		_place_structure(int(s[0]), String(s[1]), int(s[2]), int(s[3]), int(s[4]), int(s[5]))


@rpc("any_peer", "call_remote", "reliable")
func srv_unbuild(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	var sid: int = a[0]
	if not pdata.has(id) or not players.has(id) or not structures.has(sid):
		return
	var s: Dictionary = structures[sid]
	var center: Vector3 = Building.cell_center(s["cx"], s["cz"], s["level"])
	if players[id].get_true_position().distance_to(center) > BUILD_RANGE + 3.0:
		return
	var cost: Dictionary = Data.PIECES[s["kind"]]["cost"]
	for k in cost.keys():
		var back: int = int(cost[k]) / 2
		if back > 0:
			_give(id, k, back)
	_broadcast("cl_unbuild", [sid])
	_send_stats(id)
	world_dirty = true


@rpc("authority", "call_remote", "reliable")
func cl_unbuild(a: Array) -> void:
	_remove_structure(int(a[0]))


# ==================================================
# SHOP
# ==================================================

func _near_trader(id: int) -> bool:
	return players.has(id) and _flat_dist(players[id].get_true_position(), Data.TRADER_POS) < 6.0


@rpc("any_peer", "call_remote", "reliable")
func srv_sell_all(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id) or not _near_trader(id):
		return
	var incl: bool = bool(a[0]) if a.size() > 0 else false
	var d: Dictionary = pdata[id]
	var inv: Dictionary = d["inv"]
	var lvl: int = int(d["level"])
	var total: int = Data.sell_value(inv, lvl, incl)
	if total <= 0:
		return
	var kept: Dictionary = {}
	if not incl:
		for k in inv.keys():
			if Data.MATERIALS.has(k):
				kept[k] = inv[k]
	d["coins"] = int(d["coins"]) + total
	d["inv"] = kept
	_send_stats(id)
	_save_player(id)
	_to_peer(id, "cl_notify", ["Sold for %d coins!" % total, Color(1.0, 0.85, 0.3)])


@rpc("any_peer", "call_remote", "reliable")
func srv_sell(a: Array) -> void:
	if not hosting or a.size() < 2:
		return
	var id: int = _sender()
	if not pdata.has(id) or not _near_trader(id):
		return
	var item_id: String = a[0]
	var d: Dictionary = pdata[id]
	var have: int = int(d["inv"].get(item_id, 0))
	var count: int = int(a[1])
	if count < 0 or count > have:
		count = have
	if count <= 0 or not Data.ITEMS.has(item_id):
		return
	var total: int = count * Data.sell_price(item_id, int(d["level"]))
	d["inv"][item_id] = have - count
	if int(d["inv"][item_id]) <= 0:
		d["inv"].erase(item_id)
	d["coins"] = int(d["coins"]) + total
	_send_stats(id)
	_save_player(id)
	_to_peer(id, "cl_notify", ["Sold %d %s for %d coins" % [count, Data.item_name(item_id), total], Color(1.0, 0.85, 0.3)])


@rpc("any_peer", "call_remote", "reliable")
func srv_eat(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id):
		return
	var item_id: String = a[0]
	var d: Dictionary = pdata[id]
	if d["dead"] or int(d["inv"].get(item_id, 0)) <= 0 or not Data.ITEMS.get(item_id, {}).has("eat"):
		return
	if float(d["hp"]) >= float(d["max_hp"]):
		_to_peer(id, "cl_notify", ["You're not hungry — health is full.", Color(0.8, 0.8, 0.8)])
		return
	d["inv"][item_id] = int(d["inv"][item_id]) - 1
	if int(d["inv"][item_id]) <= 0:
		d["inv"].erase(item_id)
	d["hp"] = minf(float(d["max_hp"]), float(d["hp"]) + float(Data.ITEMS[item_id]["eat"]))
	_broadcast("cl_health", [id, d["hp"], d["max_hp"]])
	_send_stats(id)


@rpc("any_peer", "call_remote", "reliable")
func srv_buy(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id) or not _near_trader(id):
		return
	var item_id: String = a[0]
	var d: Dictionary = pdata[id]
	var price: int = Data.shop_price(item_id, d)
	if price < 0 or int(d["coins"]) < price:
		return
	d["coins"] = int(d["coins"]) - price
	var msg: String = ""
	match item_id:
		"ammo":
			d["ammo"] = mini(int(d["ammo"]) + 20, int(Data.bonuses(int(d["level"]))["max_ammo"]))
			msg = "+20 ammo"
		"medkit":
			d["medkits"] = int(d["medkits"]) + 1
			msg = "+1 medkit"
		"rifle", "pickaxe", "axe":
			d[item_id] = int(d[item_id]) + 1
			msg = "New gear: %s!" % Data.tool_name(item_id, int(d[item_id]))
			_rpc_all("cl_equip", [id, String(d.get("tool", "rifle")), _tool_levels(d)])
		_:
			d["coins"] = int(d["coins"]) + price
			return
	_send_stats(id)
	_save_player(id)
	_to_peer(id, "cl_notify", [msg, Color(0.6, 0.9, 1.0)])


@rpc("any_peer", "call_remote", "reliable")
func srv_use_medkit(_a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id):
		return
	var d: Dictionary = pdata[id]
	if d["dead"] or int(d["medkits"]) <= 0:
		return
	if float(d["hp"]) >= float(d["max_hp"]):
		_to_peer(id, "cl_notify", ["Your health is already full.", Color(0.8, 0.8, 0.8)])
		return
	d["medkits"] = int(d["medkits"]) - 1
	d["hp"] = minf(float(d["max_hp"]), float(d["hp"]) + 60.0)
	_broadcast("cl_health", [id, d["hp"], d["max_hp"]])
	_send_stats(id)


# ==================================================
# HEALTH / DEATH
# ==================================================

func _damage_player(id: int, amount: float, source: String) -> void:
	if not pdata.has(id):
		return
	var d: Dictionary = pdata[id]
	if d["dead"]:
		return
	d["hp"] = maxf(0.0, float(d["hp"]) - amount)
	_broadcast("cl_health", [id, d["hp"], d["max_hp"]])
	_to_peer(id, "cl_notify", ["-%d HP (%s)" % [roundi(amount), source], Color(1.0, 0.45, 0.4)])
	if float(d["hp"]) <= 0.0:
		d["dead"] = true
		d["respawn"] = RESPAWN_TIME
		_broadcast("cl_player_dead", [id, "Killed by a %s" % source])
		_broadcast("cl_chat", ["", "%s was killed by a %s." % [d["name"], source]])


@rpc("authority", "call_remote", "reliable")
func cl_health(a: Array) -> void:
	var id: int = a[0]
	var hp: float = a[1]
	var mx: float = a[2]
	if players.has(id):
		players[id].set_health(hp, mx)
	if id == _my_id():
		hud.set_health(hp, mx)


@rpc("authority", "call_remote", "reliable")
func cl_player_dead(a: Array) -> void:
	var id: int = a[0]
	if players.has(id):
		players[id].set_dead(true)
	if id == _my_id():
		my_dead = true
		hud.show_death(true, String(a[1]))


@rpc("authority", "call_remote", "reliable")
func cl_player_respawn(a: Array) -> void:
	var id: int = a[0]
	if players.has(id):
		players[id].respawn_at(a[1])
	if id == _my_id():
		my_dead = false
		hud.show_death(false)


# ==================================================
# CHAT / TIME
# ==================================================

@rpc("any_peer", "call_remote", "reliable")
func srv_chat(a: Array) -> void:
	if not hosting:
		return
	var id: int = _sender()
	if not pdata.has(id):
		return
	var text: String = String(a[0]).strip_edges().left(120)
	if text.is_empty():
		return
	_broadcast("cl_chat", ["Lv. %d %s" % [int(pdata[id]["level"]), pdata[id]["name"]], text])


@rpc("authority", "call_remote", "reliable")
func cl_chat(a: Array) -> void:
	hud.add_chat(String(a[0]), String(a[1]))
	if dedicated:
		print("[chat] ", a[0], ": ", a[1])


@rpc("authority", "call_remote", "unreliable")
func cl_time(a: Array) -> void:
	time_of_day = float(a[0])


# ==================================================
# SERVER
# ==================================================

func _server_init() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_world()
	for type in Data.ANIMAL_TYPES:
		for i in range(int(Data.ANIMALS[type]["count"])):
			_server_spawn_animal(type)


func _server_process(delta: float) -> void:
	# animal AI (20 Hz)
	ai_timer += delta
	if ai_timer >= 0.05:
		var dt: float = ai_timer
		ai_timer = 0.0
		var alive: Array = []
		for id in players.keys():
			if pdata.has(id) and not pdata[id]["dead"]:
				alive.append([id, players[id].get_true_position()])
		var night: bool = WorldScript.is_night(time_of_day)
		var to_remove: Array = []
		for an in animals.values():
			var res: Dictionary = an.server_tick(dt, alive, night, world.obstacles)
			if not res.is_empty():
				_damage_player(int(res["peer"]), float(res["damage"]), an.display_name())
			if an.dead and an.dead_timer > CARCASS_TIME:
				to_remove.append(an)
		for an in to_remove:
			_broadcast("cl_animal_remove", [an.animal_id])
			_queue_animal_respawn(String(an.type))

	# animal positions to clients (10 Hz)
	sync_timer += delta
	if sync_timer >= 0.1:
		sync_timer = 0.0
		if _online():
			var data := PackedFloat32Array()
			for an in animals.values():
				if an.dead:
					continue
				data.append(float(an.animal_id))
				data.append(an.sim_pos.x)
				data.append(an.sim_pos.z)
				data.append(an.sim_yaw)
				data.append(float(an.move_mode))
			_rpc_all("cl_animals", [data])

	# new animals
	var i: int = respawn_queue.size() - 1
	while i >= 0:
		respawn_queue[i][0] = float(respawn_queue[i][0]) - delta
		if float(respawn_queue[i][0]) <= 0.0:
			var type: String = respawn_queue[i][1]
			respawn_queue.remove_at(i)
			_server_spawn_animal(type)
		i -= 1

	# rocks and trees growing back
	for rock in world.rocks:
		if not rock.active and rock.respawn_left > 0.0:
			rock.respawn_left -= delta
			if rock.respawn_left <= 0.0:
				_broadcast("cl_rock_state", [rock.rock_id, true])
	for tree in world.trees:
		if not tree.active and tree.respawn_left > 0.0:
			tree.respawn_left -= delta
			if tree.respawn_left <= 0.0:
				_broadcast("cl_tree_state", [tree.tree_id, true, false])

	# respawning players + healing at campfires
	heal_timer += delta
	var do_heal: bool = heal_timer >= 1.0
	if do_heal:
		heal_timer = 0.0
	regen_timer += delta
	if regen_timer >= 5.0:
		regen_timer = 0.0
		for rid in pdata.keys():
			var rd: Dictionary = pdata[rid]
			var regen: float = float(Data.bonuses(int(rd["level"]))["regen"])
			if regen > 0.0 and not rd["dead"] and float(rd["hp"]) < float(rd["max_hp"]):
				rd["hp"] = minf(float(rd["max_hp"]), float(rd["hp"]) + regen)
				_broadcast("cl_health", [rid, rd["hp"], rd["max_hp"]])
	for id in pdata.keys():
		var d: Dictionary = pdata[id]
		if d["dead"]:
			d["respawn"] = float(d["respawn"]) - delta
			if float(d["respawn"]) <= 0.0:
				d["dead"] = false
				d["hp"] = d["max_hp"]
				_broadcast("cl_health", [id, d["hp"], d["max_hp"]])
				_broadcast("cl_player_respawn", [id, _camp_spawn_point()])
		elif do_heal and players.has(id) and float(d["hp"]) < float(d["max_hp"]):
			if _near_fire(players[id].get_true_position()):
				d["hp"] = minf(float(d["max_hp"]), float(d["hp"]) + 5.0)
				_broadcast("cl_health", [id, d["hp"], d["max_hp"]])

	time_sync_timer += delta
	if time_sync_timer >= 5.0:
		time_sync_timer = 0.0
		_rpc_all("cl_time", [time_of_day])

	save_timer += delta
	if save_timer >= 20.0 or (world_dirty and save_timer >= 3.0):
		save_timer = 0.0
		_save_all()


func _near_fire(p: Vector3) -> bool:
	if _flat_dist(p, Vector3.ZERO) < Data.CAMP_SAFE_RADIUS:
		return true
	for s in structures.values():
		if s["kind"] == "campfire" and is_instance_valid(s["node"]):
			if p.distance_to(s["node"].global_position) < 6.0:
				return true
	return false


# ==================================================
# SAVING (on the host)
# ==================================================

func _save_path(p_name: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, p_name.to_lower().validate_filename()]


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


func _write_json(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))


func _load_player(p_name: String) -> Dictionary:
	var d: Dictionary = {"coins": 0, "ammo": 40, "medkits": 1, "rifle": 1, "pickaxe": 1, "axe": 1,
		"level": 1, "xp": 0, "inv": {}, "pos": []}
	var parsed: Variant = _read_json(_save_path(p_name))
	if parsed is Dictionary:
		if parsed.has("pick") and not parsed.has("pickaxe"):
			parsed["pickaxe"] = parsed["pick"]
		for k in d.keys():
			if parsed.has(k):
				d[k] = parsed[k]
	for k in ["coins", "ammo", "medkits", "xp"]:
		d[k] = maxi(0, int(d[k]))
	for k in ["rifle", "pickaxe", "axe"]:
		d[k] = clampi(int(d[k]), 1, Data.MAX_TOOL_LEVEL)
	d["level"] = clampi(int(d["level"]), 1, Data.MAX_LEVEL)
	var clean_inv: Dictionary = {}
	if d["inv"] is Dictionary:
		for k in d["inv"].keys():
			if Data.ITEMS.has(k) and int(d["inv"][k]) > 0:
				clean_inv[k] = int(d["inv"][k])
	d["inv"] = clean_inv
	if not (d["pos"] is Array):
		d["pos"] = []
	return d


func _save_player(id: int) -> void:
	if not pdata.has(id):
		return
	var d: Dictionary = pdata[id]
	var pos: Array = []
	if players.has(id) and not d["dead"]:
		var p: Vector3 = players[id].get_true_position()
		pos = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]
	var out: Dictionary = {
		"name": d["name"], "coins": d["coins"], "ammo": d["ammo"], "medkits": d["medkits"],
		"rifle": d["rifle"], "pickaxe": d["pickaxe"], "axe": d["axe"],
		"level": d["level"], "xp": d["xp"], "inv": d["inv"], "pos": pos,
	}
	_write_json(_save_path(String(d["name"])), out)


func _save_world() -> void:
	_write_json(WORLD_SAVE, {"version": 1, "time": time_of_day, "next_struct": next_struct_id, "structures": _structure_list()})
	world_dirty = false


func _load_world() -> void:
	var parsed: Variant = _read_json(WORLD_SAVE)
	if not (parsed is Dictionary):
		return
	time_of_day = float(parsed.get("time", time_of_day))
	next_struct_id = int(parsed.get("next_struct", 1))
	var list: Variant = parsed.get("structures", [])
	if list is Array:
		for s in list:
			if s is Array and s.size() >= 6:
				_place_structure(int(s[0]), String(s[1]), int(s[2]), int(s[3]), int(s[4]), int(s[5]))


func _save_all() -> void:
	for id in pdata.keys():
		_save_player(id)
	_save_world()
