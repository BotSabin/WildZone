extends Control
## Round minimap (top-right): the whole valley, north up, with you (gold arrow),
## your friends (blue arrows + names), your buildings and the main places.
## Tap / click it or press M for a big map.

const WorldScript = preload("res://scripts/world.gd")
const Data = preload("res://scripts/game_data.gd")

const WORLD_R: float = 160.0     # metres from the centre to the map edge

var main = null
var big: bool = false
var small_size: float = 170.0
var font: Font
var timer: float = 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	_place()


func set_small_size(s: float) -> void:
	small_size = s
	_place()


func toggle_big() -> void:
	big = not big
	z_index = 20 if big else 0
	_place()
	queue_redraw()


func _place() -> void:
	var vs: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	if big:
		var s: float = minf(vs.y - 40.0, vs.x - 40.0)
		size = Vector2(s, s)
		position = (vs - size) * 0.5
	else:
		size = Vector2(small_size, small_size)
		position = Vector2(vs.x - small_size - 12.0, 12.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		toggle_big()
		accept_event()


func _process(delta: float) -> void:
	timer -= delta
	_place()
	if timer <= 0.0:
		timer = 0.1
		queue_redraw()


func _to_map(p: Vector3) -> Vector2:
	var r: float = size.x * 0.5
	var v := Vector2(p.x, p.z) / WORLD_R * (r - 4.0)
	return Vector2(r, r) + v


func _arrow(at: Vector2, yaw: float, s: float, col: Color) -> void:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	var pts := PackedVector2Array([at + fwd * s * 1.3, at - fwd * s * 0.7 + side * s * 0.85, at - fwd * s * 0.3, at - fwd * s * 0.7 - side * s * 0.85])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 1.5)


func _draw() -> void:
	if main == null:
		return
	var r: float = size.x * 0.5
	var c := Vector2(r, r)
	var k: float = (r - 4.0) / WORLD_R
	# ground + mountains rim
	draw_circle(c, r, Color(0.2, 0.17, 0.12, 0.9))
	draw_circle(c, 150.0 * k, Color(0.24, 0.42, 0.22, 0.92))
	# river + lake
	var rx0: Vector2 = _to_map(Vector3(WorldScript.RIVER_X - WorldScript.RIVER_HALF, 0, 0))
	var rx1: Vector2 = _to_map(Vector3(WorldScript.RIVER_X + WorldScript.RIVER_HALF, 0, 0))
	var half_h: float = sqrt(maxf(0.0, 150.0 * 150.0 - WorldScript.RIVER_X * WorldScript.RIVER_X)) * k
	draw_rect(Rect2(rx0.x, c.y - half_h, maxf(2.0, rx1.x - rx0.x), half_h * 2.0), Color(0.25, 0.5, 0.8))
	draw_circle(_to_map(WorldScript.LAKE_CENTER), WorldScript.LAKE_RADIUS * k, Color(0.25, 0.5, 0.8))
	# places
	draw_circle(_to_map(WorldScript.QUARRY_CENTER), 22.0 * k, Color(0.55, 0.52, 0.48, 0.9))
	draw_circle(_to_map(WorldScript.GOLD_HILLS), 16.0 * k, Color(0.75, 0.62, 0.25, 0.9))
	draw_circle(_to_map(Vector3.ZERO), Data.CAMP_SAFE_RADIUS * k, Color(0.9, 0.6, 0.25, 0.45))
	draw_circle(_to_map(Data.TRADER_POS), maxf(2.5, 2.0 * k), Color(1.0, 0.85, 0.3))
	# buildings
	for sid in main.structures.keys():
		var n = main.structures[sid].get("node")
		if is_instance_valid(n):
			var bp: Vector2 = _to_map(n.global_position)
			draw_rect(Rect2(bp - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.55, 0.36, 0.2))
	# labels on the big map
	if big:
		_text("Camp & Trader", _to_map(Vector3(0, 0, 14)), 15, Color(1, 0.9, 0.6))
		_text("Quarry", _to_map(WorldScript.QUARRY_CENTER) + Vector2(0, 4), 15, Color(1, 1, 1))
		_text("Gold Hills", _to_map(WorldScript.GOLD_HILLS) + Vector2(0, 26.0 * k), 15, Color(1, 0.9, 0.5))
		_text("Green Lake", _to_map(WorldScript.LAKE_CENTER) + Vector2(0, 4), 15, Color(0.85, 0.95, 1))
		_text("River", _to_map(Vector3(WorldScript.RIVER_X, 0, -80)), 14, Color(0.85, 0.95, 1))
	# players: friends first, you on top
	var my_id = main._my_id()
	var s: float = 6.0 if not big else 9.0
	for id in main.players.keys():
		if id == my_id:
			continue
		var p = main.players[id]
		if not is_instance_valid(p):
			continue
		var at: Vector2 = _to_map(p.global_position)
		var col := Color(0.35, 0.8, 1.0) if not p.dead else Color(0.6, 0.6, 0.6)
		_arrow(at, p.rotation.y, s, col)
		_text(p.player_name, at + Vector2(0, -s - 4.0), 13 if not big else 16, col)
	var me = main._me()
	if me != null:
		_arrow(_to_map(me.global_position), me.rotation.y, s + 1.0, Color(1.0, 0.82, 0.3))
	# frame + north
	draw_arc(c, r - 1.0, 0, TAU, 64, Color(1.0, 0.85, 0.5, 0.85), 2.5)
	_text("N", Vector2(r, 14), 14, Color(1, 1, 1))
	if big:
		_text("tap the map (or press M) to close", Vector2(r, size.y - 10.0), 14, Color(1, 1, 1, 0.8))


func _text(t: String, at: Vector2, fs: int, col: Color) -> void:
	var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at + Vector2(-w * 0.5, 0)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
