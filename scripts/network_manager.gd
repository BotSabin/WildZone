extends Node
## Networking.
## - Browser (GitHub Pages / CrazyGames): one player hosts and gets a ROOM CODE,
##   friends join with the code. Players connect directly (WebRTC); a free public
##   MQTT broker is only used to introduce them (see mqtt_signal.gd).
## - Desktop: host over WebSocket on your network, or join a dedicated server
##   with an IP or a ws:// / wss:// address.

signal status_changed(message: String)
signal connected_to_server
signal connection_failed
signal server_lost
signal peer_left(peer_id: int)

const DEFAULT_PORT: int = 24560
const CONNECT_TIMEOUT: float = 10.0
const ONLINE_TIMEOUT: float = 25.0
const TOPIC_ROOT: String = "wildzone-botsabin-v1/"
const CODE_CHARS: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ICE_SERVERS: Array = [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
	{"urls": ["stun:stun.cloudflare.com:3478"]},
]
const SignalScript = preload("res://scripts/mqtt_signal.gd")

var peer: MultiplayerPeer
var room_code: String = ""
var online: bool = false          # true = WebRTC room-code game
var signal_client: Node = null
var my_token: String = ""
var rtc_by_token: Dictionary = {} # host: token -> {"id", "conn"}
var next_rtc_id: int = 2
var client_conn: WebRTCPeerConnection = null
var hello_timer: float = 0.0
var is_server: bool = false
var connecting: bool = false
var connect_timer: float = 0.0


static func can_host_online() -> bool:
	return OS.has_feature("web") and ClassDB.class_exists("WebRTCPeerConnection")


static func is_room_code(text: String) -> bool:
	var t: String = text.strip_edges().to_upper()
	if t.length() != 5:
		return false
	for ch in t:
		if CODE_CHARS.find(ch) < 0:
			return false
	return true


static func can_host() -> bool:
	# Browsers cannot open a server socket; web builds play solo or join a server.
	return not OS.has_feature("web")


func host(port: int) -> Error:
	close()
	var ws := WebSocketMultiplayerPeer.new()
	var err: Error = ws.create_server(port)
	if err != OK:
		status_changed.emit("Could not start the server on port %d (%s)." % [port, error_string(err)])
		return err
	peer = ws
	multiplayer.multiplayer_peer = ws
	is_server = true
	_connect_signals()
	status_changed.emit("Server running on port %d." % port)
	return OK


func connect_to(address: String, port: int) -> Error:
	close()
	address = address.strip_edges()
	if address.is_empty():
		status_changed.emit("Enter the host's IP or server address.")
		return ERR_INVALID_PARAMETER
	var url: String = address
	if not (address.begins_with("ws://") or address.begins_with("wss://")):
		url = "ws://%s:%d" % [address, port]
	var ws := WebSocketMultiplayerPeer.new()
	var err: Error = ws.create_client(url)
	if err != OK:
		status_changed.emit("Could not connect: " + error_string(err))
		return err
	peer = ws
	multiplayer.multiplayer_peer = ws
	is_server = false
	connecting = true
	connect_timer = 0.0
	_connect_signals()
	status_changed.emit("Connecting to %s ..." % url)
	return OK


func _process(delta: float) -> void:
	if connecting and online and client_conn == null and signal_client != null and signal_client.is_ready():
		hello_timer -= delta
		if hello_timer <= 0.0:
			hello_timer = 3.0
			signal_client.publish(TOPIC_ROOT + room_code + "/host", {"type": "hello", "from": my_token})
	if connecting:
		connect_timer += delta
		if connect_timer > (ONLINE_TIMEOUT if online else CONNECT_TIMEOUT):
			connecting = false
			close()
			if online:
				status_changed.emit("No game found with that room code (or your network blocks direct connections). Check the code and that your friend is still hosting.")
			else:
				status_changed.emit("The host is not answering. Check the address, port and firewall.")
			connection_failed.emit()


func _connect_signals() -> void:
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_disconnected(id: int) -> void:
	peer_left.emit(id)


func _on_connected() -> void:
	connecting = false
	if online and not is_server and signal_client != null:
		signal_client.stop()
	status_changed.emit("Connected!")
	connected_to_server.emit()


func _on_connection_failed() -> void:
	if not connecting and peer == null:
		return
	connecting = false
	close()
	status_changed.emit("Connection failed. Check the address and that the host is running.")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	connecting = false
	server_lost.emit()


func close() -> void:
	if signal_client != null:
		signal_client.stop()
	rtc_by_token.clear()
	client_conn = null
	online = false
	room_code = ""
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_server = false
	connecting = false


static func local_ips() -> Array:
	var out: Array = []
	for ip in IP.get_local_addresses():
		var s: String = ip
		if s.begins_with("192.168.") or s.begins_with("10.") or s.begins_with("172.") or s.begins_with("100."):
			if not out.has(s):
				out.append(s)
	return out



# ==================================================
# ONLINE ROOMS (browser, WebRTC + room code)
# ==================================================

func _ensure_signal() -> void:
	if signal_client == null:
		signal_client = SignalScript.new()
		signal_client.name = "Signal"
		add_child(signal_client)
		signal_client.message.connect(_on_signal_message)
		signal_client.failed.connect(_on_signal_failed)


static func _broker_override() -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('broker') || ''", true)
	return String(v) if v != null else ""


func _new_conn() -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": ICE_SERVERS})
	return conn


func host_online() -> Error:
	close()
	var rtc := WebRTCMultiplayerPeer.new()
	var err: Error = rtc.create_server()
	if err != OK:
		status_changed.emit("Online hosting is not available in this browser.")
		return err
	peer = rtc
	multiplayer.multiplayer_peer = rtc
	is_server = true
	online = true
	room_code = ""
	for i in range(5):
		room_code += CODE_CHARS[randi() % CODE_CHARS.length()]
	_connect_signals()
	_ensure_signal()
	signal_client.subscribe(TOPIC_ROOT + room_code + "/host")
	signal_client.start(_broker_override())
	status_changed.emit("Room %s is open." % room_code)
	print("WILDZONE_ROOM ", room_code)
	return OK


func join_online(code: String) -> Error:
	close()
	room_code = code.strip_edges().to_upper()
	online = true
	is_server = false
	connecting = true
	connect_timer = 0.0
	hello_timer = 0.0
	my_token = "c%d" % (randi() % 1000000000)
	_ensure_signal()
	signal_client.subscribe(TOPIC_ROOT + room_code + "/" + my_token)
	signal_client.start(_broker_override())
	status_changed.emit("Looking for room %s ..." % room_code)
	return OK


func _send_to(target: String, data: Dictionary) -> void:
	if signal_client != null:
		signal_client.publish(TOPIC_ROOT + room_code + "/" + target, data)


func _on_signal_failed(reason: String) -> void:
	if connecting:
		connecting = false
		close()
		status_changed.emit(reason)
		connection_failed.emit()
	elif is_server and online:
		status_changed.emit(reason + " New friends can't join right now, but the game goes on.")


func _on_signal_message(_topic: String, data: Dictionary) -> void:
	var kind: String = String(data.get("type", ""))
	if is_server and online:
		var from: String = String(data.get("from", ""))
		if from.is_empty():
			return
		if kind == "hello":
			if rtc_by_token.has(from):
				_send_to(from, {"type": "welcome", "id": int(rtc_by_token[from]["id"])})
				return
			var id: int = next_rtc_id
			next_rtc_id += 1
			var conn := _new_conn()
			conn.session_description_created.connect(_on_local_sdp.bind(conn, from, false))
			conn.ice_candidate_created.connect(_on_local_ice.bind(from, false))
			(peer as WebRTCMultiplayerPeer).add_peer(conn, id)
			rtc_by_token[from] = {"id": id, "conn": conn}
			_send_to(from, {"type": "welcome", "id": id})
			conn.create_offer()
		elif rtc_by_token.has(from):
			var c: WebRTCPeerConnection = rtc_by_token[from]["conn"]
			if kind == "sdp":
				c.set_remote_description(String(data["kind"]), String(data["sdp"]))
			elif kind == "ice":
				c.add_ice_candidate(String(data["media"]), int(data["index"]), String(data["cand"]))
	elif online and connecting:
		if kind == "welcome" and client_conn == null:
			var rtc := WebRTCMultiplayerPeer.new()
			rtc.create_client(int(data["id"]))
			client_conn = _new_conn()
			client_conn.session_description_created.connect(_on_local_sdp.bind(client_conn, "host", true))
			client_conn.ice_candidate_created.connect(_on_local_ice.bind("host", true))
			rtc.add_peer(client_conn, 1)
			peer = rtc
			multiplayer.multiplayer_peer = rtc
			_connect_signals()
			status_changed.emit("Found room %s, connecting ..." % room_code)
		elif client_conn != null:
			if kind == "sdp":
				client_conn.set_remote_description(String(data["kind"]), String(data["sdp"]))
			elif kind == "ice":
				client_conn.add_ice_candidate(String(data["media"]), int(data["index"]), String(data["cand"]))


func _on_local_sdp(kind: String, sdp: String, conn: WebRTCPeerConnection, target: String, add_from: bool) -> void:
	conn.set_local_description(kind, sdp)
	var msg: Dictionary = {"type": "sdp", "kind": kind, "sdp": sdp}
	if add_from:
		msg["from"] = my_token
	_send_to(target, msg)


func _on_local_ice(media: String, index: int, cand: String, target: String, add_from: bool) -> void:
	var msg: Dictionary = {"type": "ice", "media": media, "index": index, "cand": cand}
	if add_from:
		msg["from"] = my_token
	_send_to(target, msg)
