extends CanvasLayer
## All UI: main menu, in-game HUD, toolbar, build bar, trader shop and chat.

const Data = preload("res://scripts/game_data.gd")
const NetScript = preload("res://scripts/network_manager.gd")

signal solo_requested(player_name: String, char_idx: int)
signal host_requested(player_name: String, char_idx: int, port: int)
signal host_online_requested(player_name: String, char_idx: int)
signal join_requested(player_name: String, char_idx: int, address: String, port: int)
signal sell_all_requested(include_materials: bool)
signal sell_requested(item_id: String, count: int)
signal eat_requested(item_id: String)
signal inventory_closed
signal buy_requested(item_id: String)
signal shop_closed
signal chat_submitted(text: String)
signal chat_closed

const GOLD := Color(1.0, 0.8, 0.4)
const TEXT := Color(0.95, 0.93, 0.88)
const DIM := Color(0.72, 0.72, 0.66)
const BEGIN := Control.GROW_DIRECTION_BEGIN
const END := Control.GROW_DIRECTION_END
const BOTH := Control.GROW_DIRECTION_BOTH
const TOOL_LABELS: Array = ["Rifle", "Pickaxe", "Axe", "Build"]

var root: Control

# menu
var menu: Control
var name_input: LineEdit
var ip_input: LineEdit
var port_input: LineEdit
var char_desc: Label
var status_label: Label
var selected_char: int = 0
var char_buttons: Array = []

# game
var game_ui: Control
var hp_bar: ProgressBar
var hp_text: Label
var xp_bar: ProgressBar
var level_label: Label
var coins_label: Label
var ammo_label: Label
var medkit_label: Label
var clock_label: Label
var server_label: Label
var prompt_label: Label
var hit_label: Label
var players_label: Label
var water_label: Label
var inv_box: VBoxContainer
var notify_box: VBoxContainer
var chat_log: VBoxContainer
var chat_input: LineEdit
var death_overlay: ColorRect
var death_label: Label
var big_label: Label
var tool_slots: Array = []
var build_bar: HBoxContainer
var build_slots: Array = []

# shop
var shop_panel: PanelContainer
var shop_coins: Label
var shop_sell_list: VBoxContainer
var shop_sell_button: Button
var shop_buy_buttons: Dictionary = {}
var shop_sell_everything: Button

# inventory window
var inv_panel: PanelContainer
var inv_title: Label
var inv_grid: GridContainer
var char_title: Label
var char_xp: ProgressBar
var char_info: Label

var last_stats: Dictionary = {}


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_game_ui()
	_build_shop()
	_build_inventory()
	_build_menu()
	game_ui.visible = false


# ==================================================
# HELPERS
# ==================================================

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var normal := _style(Color(0.2, 0.17, 0.12, 0.95), Color(0.75, 0.55, 0.25, 0.6))
	var hover := _style(Color(0.32, 0.25, 0.14, 0.95), Color(1.0, 0.75, 0.35, 0.9))
	var pressed := _style(Color(0.5, 0.36, 0.16, 0.95), Color(1.0, 0.8, 0.4, 1.0))
	var disabled := _style(Color(0.12, 0.12, 0.12, 0.8), Color(0.3, 0.3, 0.3, 0.5))
	for sb in [normal, hover, pressed, disabled]:
		sb.set_content_margin_all(8)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var le := _style(Color(0.05, 0.05, 0.05, 0.9), Color(0.6, 0.5, 0.3, 0.6))
	le.set_content_margin_all(7)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", _style(Color(0.05, 0.05, 0.05, 0.9), GOLD))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	return t


func _style(bg: Color, border: Color = Color(0.85, 0.65, 0.3, 0.35)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	return sb


func _panel(alpha: float = 0.72) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.08, 0.07, alpha)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Pins a control to an anchor point and lets it grow with its content.
func _anchor(c: Control, ax: float, ay: float, ox: float, oy: float, gh: Control.GrowDirection, gv: Control.GrowDirection) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = gh
	c.grow_vertical = gv


func _label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, height)
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	back.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _full_width(c: Control, y_top: float, y_bottom: float, bottom_anchor: bool) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	var a: float = 1.0 if bottom_anchor else 0.0
	c.anchor_top = a
	c.anchor_bottom = a
	c.offset_top = y_top
	c.offset_bottom = y_bottom


# ==================================================
# MAIN MENU
# ==================================================

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.02, 0.02, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)

	var panel := _panel(0.88)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(560, 0)
	_anchor(panel, 0.5, 0.5, 0, 0, BOTH, BOTH)
	menu.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var title := _label("WILDZONE", 48, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("Hunt • Mine • Chop • Build • Trade — alone or with friends", 14, Color(0.8, 0.85, 0.75))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())

	v.add_child(_label("Your name", 14, DIM))
	name_input = LineEdit.new()
	name_input.max_length = 16
	name_input.placeholder_text = "e.g. Name"
	v.add_child(name_input)

	v.add_child(_label("Choose your character", 14, DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	v.add_child(row)
	var group := ButtonGroup.new()
	for i in range(Data.CHARACTERS.size()):
		var ch: Dictionary = Data.CHARACTERS[i]
		var b := Button.new()
		b.text = String(ch["name"])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col: Color = ch["jacket"]
		b.add_theme_color_override("font_color", col.lightened(0.45))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_char_selected.bind(i))
		row.add_child(b)
		char_buttons.append(b)
	char_desc = _label("", 14, Color(0.88, 0.86, 0.7))
	char_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(char_desc)
	v.add_child(HSeparator.new())

	var solo_btn := Button.new()
	solo_btn.text = "PLAY SOLO"
	solo_btn.add_theme_font_size_override("font_size", 20)
	solo_btn.pressed.connect(func() -> void: solo_requested.emit(_player_name(), selected_char))
	v.add_child(solo_btn)
	v.add_child(_label("Your progress, buildings and world are saved automatically.", 12, DIM))

	if NetScript.can_host_online():
		v.add_child(HSeparator.new())
		v.add_child(_label("Play with friends online", 17, GOLD))
		var online_btn := Button.new()
		online_btn.text = "HOST ONLINE GAME  (get a room code)"
		online_btn.pressed.connect(func() -> void: host_online_requested.emit(_player_name(), selected_char))
		v.add_child(online_btn)
		v.add_child(_label("Share the code or link with friends. Keep this tab open while they play.", 12, DIM))

	if NetScript.can_host():
		v.add_child(HSeparator.new())
		v.add_child(_label("Host a game for friends", 17, GOLD))
		var host_row := HBoxContainer.new()
		v.add_child(host_row)
		host_row.add_child(_label("Port:", 14))
		port_input = LineEdit.new()
		port_input.text = "24560"
		port_input.custom_minimum_size = Vector2(90, 0)
		host_row.add_child(port_input)
		var host_btn := Button.new()
		host_btn.text = "HOST GAME"
		host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host_btn.pressed.connect(func() -> void: host_requested.emit(_player_name(), selected_char, _port()))
		host_row.add_child(host_btn)

	v.add_child(HSeparator.new())
	v.add_child(_label("Join a friend or server", 17, GOLD))
	var join_row := HBoxContainer.new()
	v.add_child(join_row)
	ip_input = LineEdit.new()
	ip_input.placeholder_text = "Room code (e.g. K7P2Q)" if NetScript.can_host_online() else "IP (192.168.1.20) or wss://server.address"
	ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_input)
	var join_btn := Button.new()
	join_btn.text = "JOIN"
	join_btn.pressed.connect(func() -> void: join_requested.emit(_player_name(), selected_char, ip_input.text.strip_edges(), _port()))
	join_row.add_child(join_btn)

	status_label = _label("", 14, Color(1.0, 0.85, 0.6))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)
	_on_char_selected(0)


func setup_menu(defaults: Dictionary) -> void:
	name_input.text = String(defaults.get("name", ""))
	ip_input.text = String(defaults.get("ip", ""))
	if String(defaults.get("room", "")) != "":
		ip_input.text = String(defaults["room"])
	if port_input != null:
		port_input.text = str(int(defaults.get("port", 24560)))
	_on_char_selected(clampi(int(defaults.get("char", 0)), 0, Data.CHARACTERS.size() - 1))
	set_status(String(defaults.get("status", "")))


func _on_char_selected(i: int) -> void:
	selected_char = i
	for j in range(char_buttons.size()):
		char_buttons[j].button_pressed = (j == i)
	var ch: Dictionary = Data.CHARACTERS[i]
	char_desc.text = "%s — %s" % [ch["name"], ch["desc"]]


func _player_name() -> String:
	var n: String = name_input.text.strip_edges()
	if n.is_empty():
		n = "Hunter%d" % (randi() % 900 + 100)
		name_input.text = n
	return n


func _port() -> int:
	if port_input == null:
		return NetScript.DEFAULT_PORT
	return clampi(int(port_input.text), 1024, 65535)


func set_status(text: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = text


func show_menu(value: bool) -> void:
	menu.visible = value
	game_ui.visible = not value


# ==================================================
# IN-GAME HUD
# ==================================================

func _build_game_ui() -> void:
	game_ui = Control.new()
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(game_ui)

	var cross := _label("+", 28)
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_ui.add_child(cross)
	hit_label = _label("X", 30, Color(1.0, 0.3, 0.2))
	hit_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hit_label.modulate.a = 0.0
	game_ui.add_child(hit_label)

	# top-left: clock + server
	var tl := VBoxContainer.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(tl, 0, 0, 16, 12, END, END)
	game_ui.add_child(tl)
	tl.add_child(_label("WILDZONE", 22, GOLD))
	clock_label = _label("08:00", 16)
	tl.add_child(clock_label)
	server_label = _label("", 13, Color(0.75, 0.85, 0.75))
	tl.add_child(server_label)

	# top-right: players
	var pp := _panel()
	_anchor(pp, 1, 0, -16, 12, BEGIN, END)
	game_ui.add_child(pp)
	players_label = _label("Players", 14)
	pp.add_child(players_label)

	# bottom-left: stats
	var sp := _panel()
	sp.custom_minimum_size = Vector2(280, 0)
	_anchor(sp, 0, 1, 16, -16, END, BEGIN)
	game_ui.add_child(sp)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 3)
	sp.add_child(sv)
	level_label = _label("Lv. 1", 18, GOLD)
	sv.add_child(level_label)
	xp_bar = _bar(Color(0.95, 0.75, 0.2), 8)
	sv.add_child(xp_bar)
	hp_text = _label("Health 100 / 100", 14)
	sv.add_child(hp_text)
	hp_bar = _bar(Color(0.82, 0.2, 0.15), 14)
	sv.add_child(hp_bar)
	coins_label = _label("Coins: 0", 18, GOLD)
	sv.add_child(coins_label)
	ammo_label = _label("Ammo: 0", 15)
	sv.add_child(ammo_label)
	medkit_label = _label("Medkits: 0  [H]", 15)
	sv.add_child(medkit_label)

	# right: backpack
	var ip := _panel()
	ip.custom_minimum_size = Vector2(220, 0)
	_anchor(ip, 1, 0.5, -16, 0, BEGIN, BOTH)
	game_ui.add_child(ip)
	var iv := VBoxContainer.new()
	ip.add_child(iv)
	iv.add_child(_label("Backpack", 18, GOLD))
	inv_box = VBoxContainer.new()
	iv.add_child(inv_box)

	# toolbar (bottom centre)
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 6)
	tb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(tb, 0.5, 1, 0, -34, BOTH, BEGIN)
	game_ui.add_child(tb)
	for i in range(4):
		var slot := _panel(0.6)
		slot.custom_minimum_size = Vector2(118, 0)
		var l := _label("%d  %s" % [i + 1, TOOL_LABELS[i]], 14)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(l)
		tb.add_child(slot)
		tool_slots.append(slot)

	# build bar (above toolbar)
	build_bar = HBoxContainer.new()
	build_bar.add_theme_constant_override("separation", 4)
	build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(build_bar, 0.5, 1, 0, -96, BOTH, BEGIN)
	build_bar.visible = false
	game_ui.add_child(build_bar)
	for kind in Data.BUILD_ORDER:
		var bslot := _panel(0.6)
		var bl := _label("", 12)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bslot.add_child(bl)
		build_bar.add_child(bslot)
		build_slots.append(bslot)

	water_label = _label("Swimming — find or build a bridge!", 16, Color(0.6, 0.85, 1.0))
	water_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_width(water_label, 110, 130, false)
	water_label.visible = false
	game_ui.add_child(water_label)

	prompt_label = _label("", 19, Color(1.0, 0.95, 0.75))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_width(prompt_label, -190, -165, true)
	game_ui.add_child(prompt_label)

	notify_box = VBoxContainer.new()
	notify_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_width(notify_box, 140, 140, false)
	game_ui.add_child(notify_box)

	big_label = _label("", 42, GOLD)
	big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_width(big_label, 60, 110, false)
	big_label.modulate.a = 0.0
	game_ui.add_child(big_label)

	var chat_wrap := VBoxContainer.new()
	chat_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_wrap.custom_minimum_size = Vector2(380, 0)
	_anchor(chat_wrap, 0, 0.6, 16, 0, END, BEGIN)
	game_ui.add_child(chat_wrap)
	chat_log = VBoxContainer.new()
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_wrap.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Type a message, Enter to send (Esc to cancel)"
	chat_input.max_length = 120
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_input.gui_input.connect(_on_chat_gui_input)
	chat_wrap.add_child(chat_input)

	var help := _label("WASD move • Shift sprint • Space jump • 1-4 tools • LMB use • E interact • I inventory • H medkit • T chat • Esc cursor", 12, Color(0.8, 0.8, 0.75, 0.8))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_width(help, -24, -4, true)
	game_ui.add_child(help)

	death_overlay = ColorRect.new()
	death_overlay.color = Color(0.4, 0.0, 0.0, 0.35)
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	game_ui.add_child(death_overlay)
	death_label = _label("YOU DIED", 34, Color(1.0, 0.85, 0.8))
	death_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death_overlay.add_child(death_label)


func update_stats(s: Dictionary) -> void:
	last_stats = s
	var lvl: int = int(s.get("level", 1))
	var xp: int = int(s.get("xp", 0))
	if lvl >= Data.MAX_LEVEL:
		level_label.text = "Lv. %d  (MAX)" % lvl
		xp_bar.value = 100
	else:
		var need: int = Data.xp_to_next(lvl)
		level_label.text = "Lv. %d   %d / %d XP" % [lvl, xp, need]
		xp_bar.value = 100.0 * float(xp) / float(need)
	coins_label.text = "Coins: %d" % int(s.get("coins", 0))
	ammo_label.text = "Ammo: %d" % int(s.get("ammo", 0))
	medkit_label.text = "Medkits: %d   [H]" % int(s.get("medkits", 0))
	for i in range(4):
		var t: String = Data.TOOLS[i]
		var lbl: Label = tool_slots[i].get_child(0)
		if t == "hammer":
			lbl.text = "%d  Build" % (i + 1)
		else:
			lbl.text = "%d  %s\n%s" % [i + 1, TOOL_LABELS[i], Data.tool_name(t, int(s.get(t, 1)))]
	_clear(inv_box)
	var inv: Dictionary = s.get("inv", {})
	var any: bool = false
	for item_id in Data.ITEM_ORDER:
		var n: int = int(inv.get(item_id, 0))
		if n <= 0:
			continue
		any = true
		var col: Color = Color(0.75, 0.9, 1.0) if Data.MATERIALS.has(item_id) else TEXT
		inv_box.add_child(_label("%s × %d" % [Data.item_name(item_id), n], 15, col))
	if not any:
		inv_box.add_child(_label("empty — hunt, mine or chop!", 14, DIM))
	else:
		var v: int = Data.sell_value(inv, lvl)
		if v > 0:
			inv_box.add_child(_label("Loot value: %d coins" % v, 13, GOLD))
	if shop_panel.visible:
		_refresh_shop()
	if inv_panel.visible:
		_refresh_inventory()


func set_tool(idx: int) -> void:
	for i in range(tool_slots.size()):
		var sel: bool = i == idx
		var sb := _style(Color(0.3, 0.22, 0.1, 0.9) if sel else Color(0.06, 0.08, 0.07, 0.6), GOLD if sel else Color(0.85, 0.65, 0.3, 0.35))
		sb.set_content_margin_all(8)
		tool_slots[i].add_theme_stylebox_override("panel", sb)
	build_bar.visible = idx == 3


func set_build_piece(idx: int, inv: Dictionary) -> void:
	for i in range(build_slots.size()):
		var kind: String = Data.BUILD_ORDER[i]
		var piece: Dictionary = Data.PIECES[kind]
		var need: int = Data.unlock_level(kind)
		var locked: bool = need > int(last_stats.get("level", 1))
		var ok: bool = Data.can_afford(inv, piece["cost"]) and not locked
		var sel: bool = i == idx
		var lbl: Label = build_slots[i].get_child(0)
		lbl.text = String(piece["name"]) if not sel else "%s\n%s" % [piece["name"], Data.cost_text(piece["cost"])]
		if locked:
			lbl.text = "%s\nLv. %d" % [piece["name"], need]
		lbl.add_theme_color_override("font_color", TEXT if ok else Color(1.0, 0.55, 0.5))
		var sb := _style(Color(0.3, 0.22, 0.1, 0.92) if sel else Color(0.06, 0.08, 0.07, 0.6), GOLD if sel else Color(0.85, 0.65, 0.3, 0.3))
		sb.set_content_margin_all(6)
		build_slots[i].add_theme_stylebox_override("panel", sb)


func set_ammo(n: int) -> void:
	ammo_label.text = "Ammo: %d" % n


func set_health(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_text.text = "Health %d / %d" % [roundi(hp), roundi(max_hp)]


func set_prompt(text: String) -> void:
	if prompt_label.text != text:
		prompt_label.text = text


func set_swimming(value: bool) -> void:
	water_label.visible = value


func set_clock(t: float, night: bool) -> void:
	clock_label.text = "%s%s" % [Data.time_text(t), "  — night: wolves are bolder" if night else ""]


func set_server_info(text: String) -> void:
	server_label.text = text


func set_players(lines: Array) -> void:
	var txt: String = "Players (%d)" % lines.size()
	for l in lines:
		txt += "\n" + String(l)
	players_label.text = txt


func notify(text: String, color: Color = Color(1.0, 0.95, 0.8)) -> void:
	var l := _label(text, 18, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify_box.add_child(l)
	while notify_box.get_child_count() > 5:
		var old: Node = notify_box.get_child(0)
		notify_box.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func big_message(text: String) -> void:
	big_label.text = text
	big_label.modulate.a = 1.0
	big_label.scale = Vector2.ONE
	var tw := big_label.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(big_label, "modulate:a", 0.0, 0.8)


func hit_marker(killed: bool) -> void:
	hit_label.modulate = Color(1, 1, 1, 1) if not killed else Color(1.0, 0.85, 0.3, 1)
	var tw := hit_label.create_tween()
	tw.tween_property(hit_label, "modulate:a", 0.0, 0.35)


func show_death(value: bool, text: String = "") -> void:
	death_overlay.visible = value
	if value:
		death_label.text = "YOU DIED\n%s\nRespawning at the campfire..." % text


# ==================================================
# CHAT
# ==================================================

func add_chat(sender: String, text: String) -> void:
	var l: Label
	if sender.is_empty():
		l = _label(text, 14, Color(0.75, 0.9, 1.0))
	else:
		l = _label("%s: %s" % [sender, text], 15)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	chat_log.add_child(l)
	while chat_log.get_child_count() > 7:
		var old: Node = chat_log.get_child(0)
		chat_log.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


func open_chat() -> void:
	chat_input.visible = true
	chat_input.text = ""
	chat_input.call_deferred("grab_focus")
	chat_input.set_deferred("text", "")


func close_chat() -> void:
	chat_input.release_focus()
	chat_input.visible = false


func _on_chat_submitted(text: String) -> void:
	var t: String = text.strip_edges()
	close_chat()
	if not t.is_empty():
		chat_submitted.emit(t)
	chat_closed.emit()


func _on_chat_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_chat()
		chat_closed.emit()
		chat_input.accept_event()


# ==================================================
# SHOP
# ==================================================

func _build_shop() -> void:
	shop_panel = _panel(0.94)
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_panel.custom_minimum_size = Vector2(620, 0)
	_anchor(shop_panel, 0.5, 0.5, 0, 0, BOTH, BOTH)
	shop_panel.visible = false
	root.add_child(shop_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	shop_panel.add_child(v)
	var title := _label("Trader Ion", 28, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	shop_coins = _label("Coins: 0", 18, GOLD)
	shop_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(shop_coins)
	v.add_child(HSeparator.new())
	v.add_child(_label("Sell", 16, GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	shop_sell_list = VBoxContainer.new()
	shop_sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(shop_sell_list)
	var sell_row := HBoxContainer.new()
	v.add_child(sell_row)
	shop_sell_button = Button.new()
	shop_sell_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_sell_button.pressed.connect(func() -> void: sell_all_requested.emit(false))
	sell_row.add_child(shop_sell_button)
	shop_sell_everything = Button.new()
	shop_sell_everything.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_sell_everything.pressed.connect(func() -> void: sell_all_requested.emit(true))
	sell_row.add_child(shop_sell_everything)
	v.add_child(HSeparator.new())
	v.add_child(_label("Buy", 16, GOLD))
	for item in Data.SHOP:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var item_id: String = item["id"]
		b.pressed.connect(func() -> void: buy_requested.emit(item_id))
		v.add_child(b)
		shop_buy_buttons[item_id] = b
	var close := Button.new()
	close.text = "Close  (Esc)"
	close.pressed.connect(func() -> void: shop_closed.emit())
	v.add_child(close)


func show_shop() -> void:
	shop_panel.visible = true
	_refresh_shop()


func hide_shop() -> void:
	shop_panel.visible = false


func _small_button(text: String, cb: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.disabled = disabled
	b.pressed.connect(cb)
	return b


func _refresh_shop() -> void:
	var s: Dictionary = last_stats
	var lvl: int = int(s.get("level", 1))
	var coins: int = int(s.get("coins", 0))
	shop_coins.text = "Coins: %d   •   Lv. %d bonus: trader pays +%.1f%%" % [coins, lvl, (float(Data.bonuses(lvl)["sell"]) - 1.0) * 100.0]
	_clear(shop_sell_list)
	var inv: Dictionary = s.get("inv", {})
	var any: bool = false
	for item_id in Data.ITEM_ORDER:
		var n: int = int(inv.get(item_id, 0))
		if n <= 0:
			continue
		any = true
		var price: int = Data.sell_price(item_id, lvl)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var col: Color = Color(0.75, 0.9, 1.0) if Data.MATERIALS.has(item_id) else TEXT
		var l := _label("%s × %d   (%d each)" % [Data.item_name(item_id), n, price], 15, col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var iid: String = item_id
		row.add_child(_small_button("Sell 1", func() -> void: sell_requested.emit(iid, 1)))
		row.add_child(_small_button("Sell 10", func() -> void: sell_requested.emit(iid, 10), n < 10))
		row.add_child(_small_button("All (+%d)" % (n * price), func() -> void: sell_requested.emit(iid, -1)))
		shop_sell_list.add_child(row)
	if not any:
		shop_sell_list.add_child(_label("Your inventory is empty. Hunt animals and mine gold!", 14, DIM))
	var loot: int = Data.sell_value(inv, lvl, false)
	var everything: int = Data.sell_value(inv, lvl, true)
	shop_sell_button.text = "Sell all loot (+%d)" % loot
	shop_sell_button.disabled = loot == 0
	shop_sell_everything.text = "Sell EVERYTHING (+%d)" % everything
	shop_sell_everything.disabled = everything == 0

	for item in Data.SHOP:
		var item_id: String = item["id"]
		var b: Button = shop_buy_buttons[item_id]
		var price: int = Data.shop_price(item_id, s)
		var extra: String = ""
		if item_id in ["rifle", "pickaxe", "axe"]:
			var tl: int = int(s.get(item_id, 1))
			extra = "  → %s" % Data.tool_name(item_id, tl + 1) if tl < Data.MAX_TOOL_LEVEL else ""
			if item_id == "rifle" and tl < Data.MAX_TOOL_LEVEL:
				extra += " (dmg %d)" % int(Data.RIFLE_DAMAGE[tl + 1])
		if price < 0:
			b.text = "%s — MAXED" % item["name"]
			b.disabled = true
		else:
			b.text = "%s%s — %d coins" % [item["name"], extra, price]
			b.disabled = coins < price


# ==================================================
# INVENTORY & CHARACTER WINDOW
# ==================================================

func _build_inventory() -> void:
	inv_panel = _panel(0.94)
	inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	inv_panel.custom_minimum_size = Vector2(820, 0)
	_anchor(inv_panel, 0.5, 0.5, 0, 0, BOTH, BOTH)
	inv_panel.visible = false
	root.add_child(inv_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	inv_panel.add_child(outer)
	var head := _label("Inventory & Character   [I / Tab]", 24, GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(head)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	outer.add_child(h)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	h.add_child(left)
	inv_title = _label("Backpack", 18, GOLD)
	left.add_child(inv_title)
	inv_grid = GridContainer.new()
	inv_grid.columns = 3
	inv_grid.add_theme_constant_override("h_separation", 6)
	inv_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(inv_grid)

	h.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	h.add_child(right)
	char_title = _label("", 20, GOLD)
	right.add_child(char_title)
	char_xp = _bar(Color(0.95, 0.75, 0.2), 10)
	right.add_child(char_xp)
	char_info = _label("", 14)
	char_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	char_info.custom_minimum_size = Vector2(300, 0)
	right.add_child(char_info)

	var close := Button.new()
	close.text = "Close  (Esc)"
	close.pressed.connect(func() -> void: inventory_closed.emit())
	outer.add_child(close)


func show_inventory() -> void:
	inv_panel.visible = true
	_refresh_inventory()


func hide_inventory() -> void:
	inv_panel.visible = false


func _refresh_inventory() -> void:
	var s: Dictionary = last_stats
	var lvl: int = int(s.get("level", 1))
	var inv: Dictionary = s.get("inv", {})
	_clear(inv_grid)
	var total_items: int = 0
	for item_id in Data.ITEM_ORDER:
		var n: int = int(inv.get(item_id, 0))
		if n <= 0:
			continue
		total_items += n
		var card := PanelContainer.new()
		var sb := _style(Color(0.12, 0.13, 0.11, 0.95), Color(0.75, 0.9, 1.0, 0.4) if Data.MATERIALS.has(item_id) else Color(0.85, 0.65, 0.3, 0.45))
		sb.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(150, 0)
		var cv := VBoxContainer.new()
		card.add_child(cv)
		cv.add_child(_label(Data.item_name(item_id), 14, GOLD if not Data.MATERIALS.has(item_id) else Color(0.75, 0.9, 1.0)))
		cv.add_child(_label("× %d" % n, 22))
		var note: String = "worth %d each" % Data.sell_price(item_id, lvl)
		if Data.MATERIALS.has(item_id):
			note = "building material"
		cv.add_child(_label(note, 11, DIM))
		if Data.ITEMS[item_id].has("eat"):
			var iid: String = item_id
			cv.add_child(_small_button("Eat (+%d HP)" % int(Data.ITEMS[item_id]["eat"]), func() -> void: eat_requested.emit(iid)))
		inv_grid.add_child(card)
	if total_items == 0:
		inv_grid.add_child(_label("Empty — hunt, mine and chop to fill it.", 14, DIM))
	inv_title.text = "Backpack  (%d items • loot worth %d coins)" % [total_items, Data.sell_value(inv, lvl, false)]

	var ch: Dictionary = Data.CHARACTERS[clampi(int(s.get("char", 0)), 0, Data.CHARACTERS.size() - 1)]
	char_title.text = "Lv. %d %s" % [lvl, ch["name"]]
	if lvl >= Data.MAX_LEVEL:
		char_xp.value = 100
	else:
		char_xp.value = 100.0 * float(s.get("xp", 0)) / float(Data.xp_to_next(lvl))
	var txt: String = "%s\n\n" % ch["desc"]
	if lvl < Data.MAX_LEVEL:
		txt += "XP: %d / %d\n" % [int(s.get("xp", 0)), Data.xp_to_next(lvl)]
	txt += "Next: %s\n\nLevel bonuses:\n" % Data.next_milestone(lvl)
	for line in Data.bonus_lines(lvl):
		txt += "• %s\n" % line
	txt += "\nGear:\n• %s\n• %s\n• %s" % [Data.tool_name("rifle", int(s.get("rifle", 1))), Data.tool_name("pickaxe", int(s.get("pickaxe", 1))), Data.tool_name("axe", int(s.get("axe", 1)))]
	char_info.text = txt
