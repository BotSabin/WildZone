extends Control
## On-screen controls for phones and tablets (landscape, Wild Rift style):
## floating joystick on the left, drag anywhere else to look around,
## round action buttons on the right. Handles real multi-touch, so you can
## walk, look and shoot at the same time.

const Data = preload("res://scripts/game_data.gd")

const LOOK_SENS: float = 0.0042
const PITCH_FACTOR: float = 0.7
const STICK_RADIUS: float = 75.0

var main = null
var font: Font

# finger index -> what it controls: "stick", "look" or a button id
var fingers: Dictionary = {}
var stick_center: Vector2 = Vector2.ZERO
var stick_pos: Vector2 = Vector2.ZERO
var stick_finger: int = -1
var pressed: Dictionary = {}       # button id -> true while held
var buttons: Array = []            # [{id, label, pos, r, action, hold}]
var rotate_hint: Label
var look_last: Dictionary = {}     # finger index -> last position (for smooth looking)
var look_vel: Vector2 = Vector2.ZERO
var finger_pos: Dictionary = {}    # finger index -> last known position (any role)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	rotate_hint = Label.new()
	rotate_hint.text = "Turn your phone sideways\nto play WILDZONE"
	rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotate_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rotate_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rotate_hint.add_theme_font_size_override("font_size", 34)
	rotate_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.05, 0.05, 0.96)
	rotate_hint.add_theme_stylebox_override("normal", bg)
	rotate_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rotate_hint)
	rotate_hint.visible = false


func active() -> bool:
	return main != null and main.in_game and not main.ui_blocking() and not main.my_dead


func _process(_delta: float) -> void:
	var sz: Vector2 = get_viewport_rect().size
	rotate_hint.visible = sz.y > sz.x * 1.05
	if not active() and not fingers.is_empty():
		_release_all()
	if look_vel != Vector2.ZERO:
		var me = main._me() if main != null else null
		if me != null and active():
			me.apply_look(look_vel * LOOK_SENS * Vector2(1.0, PITCH_FACTOR))
		look_vel = Vector2.ZERO
	_layout()
	queue_redraw()


func _layout() -> void:
	var sz: Vector2 = get_viewport_rect().size
	var tool: String = Data.TOOLS[main.tool_idx] if main != null else "rifle"
	var use_label: String = {"rifle": "FIRE", "pickaxe": "MINE", "axe": "CHOP", "hammer": "BUILD"}.get(tool, "USE")
	var w: float = sz.x
	var h: float = sz.y
	var tool_label: String = "SWAP"
	buttons = [
		{"id": "use", "label": use_label, "pos": Vector2(w - 115, h - 120), "r": 62.0, "action": "fire", "hold": true},
		{"id": "jump", "label": "JUMP", "pos": Vector2(w - 240, h - 68), "r": 42.0, "action": "jump", "hold": true},
		{"id": "interact", "label": "E", "pos": Vector2(w - 235, h - 185), "r": 38.0, "action": "interact", "hold": true},
		{"id": "tool", "label": tool_label, "pos": Vector2(w - 122, h - 250), "r": 40.0, "action": "", "hold": false},
		{"id": "sprint", "label": "RUN", "pos": Vector2(w - 352, h - 58), "r": 34.0, "action": "sprint", "hold": true},
		{"id": "menu", "label": "MENU", "pos": Vector2(w - 200, 40), "r": 27.0, "action": "", "hold": false},
		{"id": "inv", "label": "BAG", "pos": Vector2(w - 200, 102), "r": 27.0, "action": "", "hold": false},
		{"id": "med", "label": "+HP", "pos": Vector2(w - 200, 164), "r": 27.0, "action": "", "hold": false},
		{"id": "chat", "label": "CHAT", "pos": Vector2(w - 40, 200), "r": 27.0, "action": "", "hold": false},
	]
	if tool == "hammer":
		buttons.append({"id": "rotate", "label": "ROT", "pos": Vector2(w - 348, h - 160), "r": 32.0, "action": "", "hold": false})
		buttons.append({"id": "piece", "label": "NEXT", "pos": Vector2(w - 335, h - 258), "r": 32.0, "action": "", "hold": false})
		buttons.append({"id": "remove", "label": "DEL", "pos": Vector2(w - 218, h - 290), "r": 30.0, "action": "alt_fire", "hold": true})


func button_rect(id: String) -> Rect2:
	for b in buttons:
		if b["id"] == id:
			var r: float = float(b["r"]) + 6.0
			return Rect2(Vector2(b["pos"]) - Vector2(r, r), Vector2(r, r) * 2.0)
	return Rect2()


func _button_at(p: Vector2) -> Dictionary:
	for b in buttons:
		if p.distance_to(b["pos"]) <= float(b["r"]) + 12.0:
			return b
	return {}


func _input(event: InputEvent) -> void:
	if rotate_hint.visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var p: Vector2 = _to_local(t.position)
		if t.pressed:
			if not active():
				return
			if fingers.has(t.index):
				_finger_up(t.index)   # stale finger with the same number
			finger_pos[t.index] = p
			var mm: Control = main.hud.minimap
			if Rect2(mm.position, mm.size).has_point(p):
				finger_pos.erase(t.index)
				mm.toggle_big()
				get_viewport().set_input_as_handled()
				return
			var b: Dictionary = _button_at(p)
			if not b.is_empty():
				fingers[t.index] = b["id"]
				_press_button(b)
			elif p.x < get_viewport_rect().size.x * 0.42 and stick_finger < 0:
				fingers[t.index] = "stick"
				stick_finger = t.index
				stick_center = p
				stick_pos = p
			else:
				fingers[t.index] = "look"
				look_last[t.index] = p
			get_viewport().set_input_as_handled()
		else:
			var idx: int = _resolve(t.index, p)
			if fingers.has(idx):
				_finger_up(idx)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		var np: Vector2 = _to_local(d.position)
		var idx2: int = _resolve(d.index, np)
		if not fingers.has(idx2):
			return
		if idx2 != d.index and not fingers.has(d.index):
			_rekey(idx2, d.index)
			idx2 = d.index
		finger_pos[idx2] = np
		var what2: String = fingers[idx2]
		if what2 == "stick":
			stick_pos = np
			var v: Vector2 = (stick_pos - stick_center) / STICK_RADIUS
			if v.length() > 1.0:
				stick_center = stick_pos - v.normalized() * STICK_RADIUS
				v = v.normalized()
			_set_move(v)
		elif what2 == "look":
			# our own per-finger delta (the browser's "relative" is unreliable with 2 fingers)
			var last: Vector2 = look_last.get(idx2, np)
			look_last[idx2] = np
			var delta: Vector2 = np - last
			if delta.length() < 80.0:
				look_vel += delta
		get_viewport().set_input_as_handled()


func _finger_up(idx: int) -> void:
	var what: String = fingers[idx]
	fingers.erase(idx)
	finger_pos.erase(idx)
	look_last.erase(idx)
	if what == "stick":
		stick_finger = -1
		_set_move(Vector2.ZERO)
	elif what != "look":
		_release_button(what)


## Phones' browsers sometimes renumber fingers when another finger lifts.
## If the index doesn't match where that finger was, use the closest known finger.
func _resolve(index: int, p: Vector2) -> int:
	if fingers.has(index) and Vector2(finger_pos.get(index, p)).distance_to(p) < 110.0:
		return index
	var best: int = -1
	var best_d: float = 110.0
	for k in finger_pos.keys():
		var dd: float = Vector2(finger_pos[k]).distance_to(p)
		if dd < best_d:
			best_d = dd
			best = k
	return best if best >= 0 else index


func _rekey(old: int, new_idx: int) -> void:
	if old == new_idx or not fingers.has(old):
		return
	var role = fingers[old]
	fingers.erase(old)
	fingers[new_idx] = role
	if finger_pos.has(old):
		finger_pos[new_idx] = finger_pos[old]
		finger_pos.erase(old)
	if look_last.has(old):
		look_last[new_idx] = look_last[old]
		look_last.erase(old)
	if stick_finger == old:
		stick_finger = new_idx


func _scale() -> float:
	return get_viewport().get_final_transform().get_scale().x if get_viewport() != null else 1.0


func _to_local(screen_pos: Vector2) -> Vector2:
	# Godot already converts touch positions into the game's (stretched) coordinates.
	return screen_pos


func _set_move(v: Vector2) -> void:
	_axis("move_left", -v.x)
	_axis("move_right", v.x)
	_axis("move_forward", -v.y)
	_axis("move_back", v.y)
	if v.length() > 0.97:
		Input.action_press("sprint")
	elif not pressed.has("sprint"):
		Input.action_release("sprint")


func _axis(action: String, value: float) -> void:
	if value > 0.05:
		Input.action_press(action, clampf(value, 0.0, 1.0))
	else:
		Input.action_release(action)


func _press_button(b: Dictionary) -> void:
	var id: String = b["id"]
	pressed[id] = true
	var action: String = b["action"]
	if not action.is_empty():
		Input.action_press(action)
		return
	match id:
		"menu":
			main.toggle_pause()
		"tool":
			main._select_tool((main.tool_idx + 1) % Data.TOOLS.size())
		"inv":
			main._open_inventory()
		"med":
			main._srv("srv_use_medkit", [])
		"chat":
			main._open_chat()
		"rotate":
			main.build_rot = (main.build_rot + 1) % 4
		"piece":
			main._cycle_build(1)


func _release_button(id: String) -> void:
	pressed.erase(id)
	for b in buttons:
		if b["id"] == id and not String(b["action"]).is_empty():
			Input.action_release(String(b["action"]))


func _release_all() -> void:
	for id in pressed.keys():
		_release_button(id)
	pressed.clear()
	fingers.clear()
	finger_pos.clear()
	look_last.clear()
	look_vel = Vector2.ZERO
	stick_finger = -1
	_set_move(Vector2.ZERO)
	Input.action_release("sprint")


func _draw() -> void:
	if not active() or rotate_hint.visible:
		return
	# joystick
	if stick_finger >= 0:
		draw_circle(stick_center, STICK_RADIUS, Color(1, 1, 1, 0.12))
		draw_arc(stick_center, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		var knob: Vector2 = stick_center + (stick_pos - stick_center).limit_length(STICK_RADIUS)
		draw_circle(knob, 34.0, Color(1, 0.85, 0.45, 0.55))
	else:
		var sz: Vector2 = get_viewport_rect().size
		var hint := Vector2(130, sz.y - 120)
		draw_arc(hint, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0)
		draw_circle(hint, 30.0, Color(1, 1, 1, 0.12))
	# buttons
	for b in buttons:
		var pos: Vector2 = b["pos"]
		var r: float = b["r"]
		var on: bool = pressed.has(b["id"])
		var main_btn: bool = b["id"] == "use"
		var fill: Color = Color(0.95, 0.7, 0.25, 0.6) if on else (Color(0.85, 0.55, 0.18, 0.42) if main_btn else Color(0.08, 0.1, 0.09, 0.5))
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0, TAU, 40, Color(1.0, 0.85, 0.5, 0.75 if main_btn else 0.45), 3.0 if main_btn else 2.0)
		var fs: int = 22 if main_btn else (16 if r >= 38.0 else 13)
		var label: String = b["label"]
		var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, pos + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
