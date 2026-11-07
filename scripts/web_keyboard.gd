extends Node
## Phone keyboard for the browser build.
## Phones only open their keyboard when a real HTML text box is focused during
## the tap itself, so the page (see head_include in export_presets.cfg) keeps a
## small text bar ready. We tell the page where our text fields are; when a
## finger taps one, the page opens the bar + keyboard right away, and we copy
## what is typed back into the game.

var main = null
var hud = null
var kb = null                 # JavaScriptObject window.wzkb
var last_fields: String = ""
var last_submit: int = 0
var last_closed: int = 0
var was_open: bool = false
var field_timer: float = 0.0


func _ready() -> void:
	kb = JavaScriptBridge.get_interface("wzkb")
	# The page's own text bar does the typing; if Godot focused these fields too,
	# its hidden IME box would steal the focus and the keyboard would close.
	for le in [hud.name_input, hud.ip_input, hud.chat_input]:
		if le != null:
			le.focus_mode = Control.FOCUS_NONE
	if kb != null:
		last_submit = int(kb.submit)
		last_closed = int(kb.closed)


func _process(delta: float) -> void:
	if kb == null:
		return
	field_timer -= delta
	if field_timer <= 0.0:
		field_timer = 0.2
		_send_fields()
	var open: bool = bool(kb.open)
	var active: String = str(kb.active)
	if open:
		_mirror(active, str(kb.text))
	var submit: int = int(kb.submit)
	var closed: int = int(kb.closed)
	if submit != last_submit:
		last_submit = submit
		_finish(active, str(kb.text), true)
	elif closed != last_closed:
		last_closed = closed
		_finish(active, str(kb.text), false)
	was_open = open


func _mirror(active: String, text: String) -> void:
	match active:
		"name":
			hud.name_input.text = text
		"ip":
			hud.ip_input.text = text
		"chat", "chatline":
			if not main.chat_open:
				main._open_chat()
			hud.chat_input.text = text


func _finish(active: String, text: String, submitted: bool) -> void:
	match active:
		"name":
			hud.name_input.text = text
			hud.name_input.release_focus()
		"ip":
			hud.ip_input.text = text
			hud.ip_input.release_focus()
		"chat", "chatline":
			if not main.chat_open:
				return
			if submitted:
				hud._on_chat_submitted(text)
			else:
				hud.close_chat()
				hud.chat_closed.emit()


func _norm(r: Rect2) -> Dictionary:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return {"x": r.position.x / vs.x, "y": r.position.y / vs.y, "w": r.size.x / vs.x, "h": r.size.y / vs.y}


func _field(id: String, c: Control, placeholder: String, max_len: int) -> Dictionary:
	var d: Dictionary = _norm(c.get_global_rect())
	d["id"] = id
	d["text"] = c.text
	d["ph"] = placeholder
	d["max"] = max_len
	return d


func _send_fields() -> void:
	var fields: Array = []
	if not main.in_game:
		if hud.name_input != null and hud.name_input.is_visible_in_tree():
			fields.append(_field("name", hud.name_input, "Your name", hud.name_input.max_length))
		if hud.ip_input != null and hud.ip_input.is_visible_in_tree():
			fields.append(_field("ip", hud.ip_input, "Room code", 64))
	else:
		if hud.chat_input.is_visible_in_tree():
			fields.append(_field("chatline", hud.chat_input, "Message", hud.chat_input.max_length))
		elif main.touch != null and main.touch.active():
			var r: Rect2 = main.touch.button_rect("chat")
			if r.size != Vector2.ZERO:
				var d: Dictionary = _norm(r)
				d["id"] = "chat"
				d["text"] = ""
				d["ph"] = "Message"
				d["max"] = hud.chat_input.max_length
				fields.append(d)
	var js: String = JSON.stringify(fields)
	if js != last_fields:
		last_fields = js
		JavaScriptBridge.eval("if (window.wzkb) { window.wzkb.fields = %s; }" % js)
