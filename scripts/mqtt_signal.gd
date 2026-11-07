extends Node
## Tiny MQTT 3.1.1 client over WebSocket, used only to exchange WebRTC
## connection offers between browsers (signaling). Game traffic never goes
## through it: once two players are connected they talk directly (WebRTC).
## Works with free public brokers, so the game needs no server of its own.

signal connected
signal failed(reason: String)
signal message(topic: String, data: Dictionary)

const BROKERS: Array = [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
]

var ws := WebSocketPeer.new()
var urls: Array = []
var url_index: int = 0
var state: String = "idle"   # idle, ws, mqtt, ready
var buffer := PackedByteArray()
var subs: Array = []
var packet_id: int = 1
var ping_timer: float = 0.0
var wait_timer: float = 0.0
var client_id: String = ""


func start(custom_url: String = "") -> void:
	urls = BROKERS.duplicate()
	if not custom_url.is_empty():
		urls.insert(0, custom_url)
	url_index = 0
	client_id = "wz%d" % (randi() % 100000000)
	_open()


func _open() -> void:
	if url_index >= urls.size():
		state = "idle"
		failed.emit("Could not reach the matchmaking service. Check your internet connection.")
		return
	ws = WebSocketPeer.new()
	ws.supported_protocols = PackedStringArray(["mqtt"])
	buffer.clear()
	var err: Error = ws.connect_to_url(String(urls[url_index]))
	state = "ws"
	wait_timer = 0.0
	if err != OK:
		_next_broker()


func _next_broker() -> void:
	ws.close()
	url_index += 1
	_open()


func stop() -> void:
	if state != "idle":
		ws.close()
	state = "idle"
	subs.clear()


func is_ready() -> bool:
	return state == "ready"


func subscribe(topic: String) -> void:
	if not subs.has(topic):
		subs.append(topic)
	if state == "ready":
		_send_subscribe(topic)


func publish(topic: String, data: Dictionary) -> void:
	if state != "ready":
		return
	var payload: PackedByteArray = JSON.stringify(data).to_utf8_buffer()
	var body := PackedByteArray()
	body.append_array(_str(topic))
	body.append_array(payload)
	_send_packet(0x30, body)


func _process(delta: float) -> void:
	if state == "idle":
		return
	ws.poll()
	var ws_state: int = ws.get_ready_state()
	if ws_state == WebSocketPeer.STATE_CLOSED:
		if state == "ready":
			state = "idle"
			failed.emit("Lost the connection to the matchmaking service.")
		else:
			_next_broker()
		return
	if ws_state != WebSocketPeer.STATE_OPEN:
		wait_timer += delta
		if wait_timer > 6.0:
			_next_broker()
		return
	if state == "ws":
		state = "mqtt"
		wait_timer = 0.0
		_send_connect()
	if state == "mqtt":
		wait_timer += delta
		if wait_timer > 6.0:
			_next_broker()
			return
	while ws.get_available_packet_count() > 0:
		buffer.append_array(ws.get_packet())
	_parse()
	if state == "ready":
		ping_timer += delta
		if ping_timer > 25.0:
			ping_timer = 0.0
			ws.send(PackedByteArray([0xC0, 0x00]))


# --------------------------------------------------
# MQTT packets
# --------------------------------------------------

func _str(s: String) -> PackedByteArray:
	var b: PackedByteArray = s.to_utf8_buffer()
	var out := PackedByteArray([(b.size() >> 8) & 0xFF, b.size() & 0xFF])
	out.append_array(b)
	return out


func _send_packet(header: int, body: PackedByteArray) -> void:
	var out := PackedByteArray([header])
	var n: int = body.size()
	while true:
		var byte: int = n % 128
		n = n / 128
		if n > 0:
			byte |= 0x80
		out.append(byte)
		if n == 0:
			break
	out.append_array(body)
	ws.send(out)


func _send_connect() -> void:
	var body := PackedByteArray()
	body.append_array(_str("MQTT"))
	body.append(4)        # protocol level 3.1.1
	body.append(0x02)     # clean session
	body.append(0)
	body.append(60)       # keep alive (s)
	body.append_array(_str(client_id))
	_send_packet(0x10, body)


func _send_subscribe(topic: String) -> void:
	packet_id = (packet_id % 60000) + 1
	var body := PackedByteArray([(packet_id >> 8) & 0xFF, packet_id & 0xFF])
	body.append_array(_str(topic))
	body.append(0)
	_send_packet(0x82, body)


func _parse() -> void:
	while buffer.size() >= 2:
		var mult: int = 1
		var length: int = 0
		var i: int = 1
		var complete: bool = false
		while i < buffer.size() and i <= 4:
			var b: int = buffer[i]
			length += (b & 0x7F) * mult
			mult *= 128
			i += 1
			if (b & 0x80) == 0:
				complete = true
				break
		if not complete or buffer.size() < i + length:
			return
		var header: int = buffer[0]
		var body: PackedByteArray = buffer.slice(i, i + length)
		buffer = buffer.slice(i + length)
		_handle(header, body)


func _handle(header: int, body: PackedByteArray) -> void:
	var kind: int = header & 0xF0
	if kind == 0x20:  # CONNACK
		if body.size() >= 2 and body[1] == 0:
			state = "ready"
			for t in subs:
				_send_subscribe(t)
			connected.emit()
		else:
			_next_broker()
	elif kind == 0x30:  # PUBLISH
		if body.size() < 2:
			return
		var tlen: int = (body[0] << 8) | body[1]
		var topic: String = body.slice(2, 2 + tlen).get_string_from_utf8()
		var start: int = 2 + tlen
		if ((header >> 1) & 0x03) > 0:
			start += 2
		var parsed: Variant = JSON.parse_string(body.slice(start).get_string_from_utf8())
		if parsed is Dictionary:
			message.emit(topic, parsed)
