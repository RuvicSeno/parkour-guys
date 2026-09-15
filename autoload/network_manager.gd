extends Node

const DEFAULT_PORT: int = 7000
const MAX_PLAYERS: int = 8
const MAX_NAME_LENGTH: int = 16

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed_to_server
signal disconnected_from_server
signal server_created
signal player_names_updated
signal simulated_latency_changed(ms: int)
signal simulated_packet_loss_changed(loss_percent: float)

## Reconnection signals — UI subscribes to these to show reconnection overlay.
signal reconnecting(attempt: int, max_attempts: int)
signal reconnect_failed
## Emitted on the server when a player rejoins within the timeout window.
## world.gd listens for this to restore saved position/checkpoint/color.
signal player_reconnected(new_peer_id: int, saved_state: Dictionary)
signal player_joined_registry(peer_id: int, username: String)

## The name this client wants to use, set locally (e.g. from a lobby LineEdit)
## BEFORE host_game()/join_game() is called. Read by _on_server_created() and
## _on_connected_to_server() to register/announce the name.
var local_player_name: String = ""

## Authoritative peer_id -> display_name map. Only the server mutates this
## directly; clients receive it via _sync_player_names() and treat it as
## read-only.
var player_names: Dictionary = {}

## Peer ID -> Color index mapping determined in lobby and preserved across scene transitions.
var player_colors: Dictionary = {}

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2), # Red
	Color(0.2, 0.5, 0.9), # Blue
	Color(0.2, 0.8, 0.3), # Green
	Color(0.9, 0.8, 0.1), # Yellow
	Color(0.8, 0.2, 0.8), # Purple
	Color(0.1, 0.8, 0.8), # Cyan
	Color(0.9, 0.5, 0.1), # Orange
	Color(0.9, 0.4, 0.6)  # Pink
]

# --- ADMIN PERMISSION SYSTEM ---
# Admin status lives ONLY on the server. Clients never see this array.
# They send commands; the server checks permission before executing.
# The host (peer ID 1) is always an admin automatically.

## Server-only. List of peer IDs that have admin privileges.
var admin_peers: Array[int] = []

## Returns true if the given peer has admin privileges.
## Only meaningful when called on the server.
func is_admin(peer_id: int) -> bool:
	return peer_id in admin_peers

## Server-only. Grants admin privileges to a peer.
func grant_admin(peer_id: int) -> void:
	if not peer_id in admin_peers:
		admin_peers.append(peer_id)

## Server-only. Revokes admin privileges from a peer.
func revoke_admin(peer_id: int) -> void:
	admin_peers.erase(peer_id)

# --- RECONNECTION SYSTEM ---
# When a client loses connection, it automatically retries up to
# MAX_RECONNECT_ATTEMPTS times with RECONNECT_DELAY between each attempt.
# The server saves disconnected player state (position, color, checkpoint)
# keyed by username for RECONNECT_TIMEOUT seconds. If a new peer connects
# with a matching name within that window, the server restores their state.

const MAX_RECONNECT_ATTEMPTS: int = 5
const RECONNECT_DELAY: float = 3.0
const RECONNECT_TIMEOUT: float = 60.0

var _reconnecting: bool = false
var _reconnect_attempts: int = 0
var _last_server_ip: String = ""
var _last_server_port: int = DEFAULT_PORT
var was_kicked: bool = false
var kick_reason: String = ""
var kicked_names: Array[String] = []

func set_kicked(reason: String = "") -> void:
	was_kicked = true
	_reconnecting = false
	_last_server_ip = ""
	kick_reason = reason if not reason.is_empty() else "You were kicked by an admin."

@rpc("authority", "reliable")
func _notify_kicked(reason: String = "") -> void:
	set_kicked(reason)

## Tracks active session scene ("lobby" vs "world") authoritatively on server.
var current_session_scene: String = "lobby"

## Server -> Client. Syncs the active session scene ("lobby" or "world") to connecting/reconnecting clients.
@rpc("authority", "call_local", "reliable")
func _sync_session_scene(scene_type: String, colors: Dictionary) -> void:
	current_session_scene = scene_type
	if not colors.is_empty():
		player_colors = colors

	if scene_type == "world":
		var cur_scene = get_tree().current_scene
		if cur_scene == null or not cur_scene.name == "World":
			get_tree().change_scene_to_file("res://scenes/world/World.tscn")
	elif scene_type == "lobby":
		var cur_scene = get_tree().current_scene
		if cur_scene == null or not cur_scene.name == "Lobby":
			get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")

## Called by pause_menu.gd when the host chooses to return to lobby.
## Notifies all connected clients to return to lobby before closing the server.
func host_return_to_lobby() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Send RPC to remote clients only
		_notify_client_return_to_lobby.rpc()
		# Use timer on the persistent Network autoload so packets are flushed over UDP
		await get_tree().create_timer(0.15).timeout
	current_session_scene = "lobby"
	disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")

## Server -> Remote Clients. Tells clients that the match ended and host returned to lobby.
@rpc("authority", "reliable")
func _notify_client_return_to_lobby() -> void:
	print("Host returned to lobby. Returning to lobby...")
	_reconnecting = false
	_last_server_ip = ""
	current_session_scene = "lobby"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")

# --- LIVE PING-PONG PROBE SYSTEM ---
var current_real_ping: int = 0
var _last_ping_send_time: int = 0

## Sends an immediate lightweight UDP ping probe to server (peer 1).
func send_ping_probe() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_last_ping_send_time = Time.get_ticks_msec()
		_ping_server_req.rpc_id(1, _last_ping_send_time)

@rpc("any_peer", "unreliable")
func _ping_server_req(client_send_time: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_pong_client_resp.rpc_id(sender_id, client_send_time)

@rpc("authority", "unreliable")
func _pong_client_resp(client_send_time: int) -> void:
	var now: int = Time.get_ticks_msec()
	current_real_ping = maxi(0, now - client_send_time)

## Server-only. Stores state for recently disconnected players so they can
## be restored on reconnection. Keyed by username (String).
## Value: { "position": Vector3, "color_index": int, "respawn_position": Vector3,
##          "disconnect_time": float (seconds since engine start) }
var disconnected_players: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

## Call this from lobby UI before hosting/joining, e.g.:
##   Network.set_local_player_name(name_line_edit.text)
##   Network.host_game()
func set_local_player_name(desired_name: String) -> void:
	local_player_name = desired_name.strip_edges().left(MAX_NAME_LENGTH)

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("Failed to create server: %s" % error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Server started on port %d. My peer ID: %d" % [port, multiplayer.get_unique_id()])
	_register_name(1, local_player_name)
	# Host is always admin
	grant_admin(1)
	player_names_updated.emit()
	server_created.emit()
	return OK

func join_game(ip_address: String, port: int = DEFAULT_PORT) -> Error:
	# Save connection details for potential reconnection later
	_last_server_ip = ip_address
	_last_server_port = port
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip_address, port)
	if error != OK:
		push_error("Failed to create client: %s" % error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to %s:%d ..." % [ip_address, port])
	return OK

func disconnect_from_game() -> void:
	_reconnecting = false
	_reconnect_attempts = 0
	was_kicked = false
	kick_reason = ""
	player_colors.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	player_connected.emit(id)
	# A new peer just joined; make sure they (and everyone else) have the
	# current name map. Harmless no-op if nothing has changed.
	if multiplayer.is_server():
		_broadcast_names()
		if simulated_latency_ms > 0:
			_sync_simulated_latency.rpc_id(id, simulated_latency_ms)
		if simulated_packet_loss_percent > 0.0:
			_sync_simulated_packet_loss.rpc_id(id, simulated_packet_loss_percent)

var last_disconnected_names: Dictionary = {}

func get_disconnected_player_name(id: int) -> String:
	return last_disconnected_names.get(id, "")

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	var p_name: String = player_names.get(id, "Player %d" % id)
	last_disconnected_names[id] = p_name
	player_disconnected.emit(id)
	player_colors.erase(id)
	if multiplayer.is_server() and player_names.has(id):
		player_names.erase(id)
		admin_peers.erase(id)
		_broadcast_names()

func _on_connected_to_server() -> void:
	print("Successfully connected to server. My peer ID: %d" % multiplayer.get_unique_id())
	_reconnecting = false
	_reconnect_attempts = 0
	_request_set_name.rpc_id(1, local_player_name)
	send_ping_probe()
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("Connection failed.")
	multiplayer.multiplayer_peer = null
	if _reconnecting:
		# Retry after a delay
		get_tree().create_timer(RECONNECT_DELAY).timeout.connect(_attempt_reconnect, CONNECT_ONE_SHOT)
	else:
		connection_failed_to_server.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	multiplayer.multiplayer_peer = null
	if was_kicked:
		was_kicked = false
		_reconnecting = false
		_last_server_ip = ""
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/ui/KickedScreen.tscn")
		disconnected_from_server.emit()
		return

	# If we have a saved server address, try to reconnect automatically
	if not _last_server_ip.is_empty() and not _reconnecting:
		_reconnecting = true
		_reconnect_attempts = 0
		_attempt_reconnect()
	else:
		disconnected_from_server.emit()

func _attempt_reconnect() -> void:
	_reconnect_attempts += 1
	if _reconnect_attempts > MAX_RECONNECT_ATTEMPTS:
		_reconnecting = false
		reconnect_failed.emit()
		disconnected_from_server.emit()
		return

	print("Reconnection attempt %d/%d ..." % [_reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	reconnecting.emit(_reconnect_attempts, MAX_RECONNECT_ATTEMPTS)

	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(_last_server_ip, _last_server_port)
	if error != OK:
		# Could not even create the peer; retry after delay
		get_tree().create_timer(RECONNECT_DELAY).timeout.connect(_attempt_reconnect, CONNECT_ONE_SHOT)
		return
	multiplayer.multiplayer_peer = peer
	# _on_connected_to_server or _on_connection_failed will fire next

# --- PLAYER NAME REGISTRY ---
# Server is the sole source of truth for player_names. Clients only ever
# read it locally and receive updates via _sync_player_names().

## Client -> Server. Client asks to register/change its display name.
## Server re-validates rather than trusting the client's local validation.
@rpc("any_peer", "reliable")
func _request_set_name(desired_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var clean_name: String = desired_name.strip_edges().left(MAX_NAME_LENGTH)
	if clean_name.to_lower() in kicked_names:
		print("Rejecting kicked player connection request from %s (peer %d)" % [clean_name, sender_id])
		_notify_kicked.rpc_id(sender_id, "You are kicked from this session.")
		get_tree().create_timer(0.1).timeout.connect(func():
			if multiplayer.multiplayer_peer != null and sender_id in multiplayer.get_peers():
				multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		)
		return

	_register_name(sender_id, desired_name)
	_broadcast_names()

	# Sync current session scene so the client is in the same scene as the server
	if sender_id != 1:
		_sync_session_scene.rpc_id(sender_id, current_session_scene, player_colors)

	var is_reconnect: bool = _check_reconnection(sender_id)
	if not is_reconnect and sender_id != 1:
		var registered_name: String = player_names.get(sender_id, "Player %d" % sender_id)
		player_joined_registry.emit(sender_id, registered_name)

## Runs on the server only. Validates and stores a single name entry,
## disambiguating duplicates by appending numbers (e.g. "Player" -> "Player2").
func _register_name(peer_id: int, desired_name: String) -> void:
	var clean_name: String = desired_name.strip_edges().left(MAX_NAME_LENGTH)
	if clean_name.is_empty():
		clean_name = "Player %d" % peer_id

	var unique_name: String = clean_name
	var counter: int = 2
	while _is_name_taken_by_other(unique_name, peer_id):
		var suffix: String = str(counter)
		var max_base_len: int = maxi(1, MAX_NAME_LENGTH - suffix.length())
		var base_trimmed: String = clean_name.left(max_base_len)
		unique_name = base_trimmed + suffix
		counter += 1

	player_names[peer_id] = unique_name
	if multiplayer != null and multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id():
		local_player_name = unique_name

func _is_name_taken_by_other(candidate: String, peer_id: int) -> bool:
	for pid in player_names:
		if pid != peer_id and player_names[pid].to_lower() == candidate.to_lower():
			return true
	return false

## Server -> All (including itself via call_local). Sends the full current
## name map. Full-map broadcast (rather than deltas) keeps late-join and
## disconnect handling correct with a single code path at this player count.
@rpc("authority", "call_local", "reliable")
func _sync_player_names(names: Dictionary) -> void:
	player_names = names
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		var my_id: int = multiplayer.get_unique_id()
		if player_names.has(my_id):
			local_player_name = player_names[my_id]
	player_names_updated.emit()

func _broadcast_names() -> void:
	_sync_player_names.rpc(player_names)

# --- RECONNECTION (SERVER-SIDE) ---

## Called by world.gd when a player disconnects, to save their state for
## potential reconnection.
func store_disconnected_player(username: String, state: Dictionary) -> void:
	state["disconnect_time"] = Time.get_ticks_msec() / 1000.0
	disconnected_players[username] = state

## Checks if a newly connected player matches a recently disconnected one.
## Returns true if reconnected, false otherwise.
func _check_reconnection(new_peer_id: int) -> bool:
	var username: String = player_names.get(new_peer_id, "")
	if username.is_empty():
		return false
	if not disconnected_players.has(username):
		return false
	var saved: Dictionary = disconnected_players[username]
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - saved.get("disconnect_time", 0.0)
	if elapsed <= RECONNECT_TIMEOUT:
		disconnected_players.erase(username)
		player_reconnected.emit(new_peer_id, saved)
		return true
	else:
		# Expired — discard
		disconnected_players.erase(username)
		return false

# --- ARTIFICIAL CONNECTION LATENCY & PACKET LOSS SIMULATION ---
# Allows admins to simulate network conditions (ping and packet loss) for testing in runtime/release builds.
# simulated_latency_ms represents the simulated round-trip ping in milliseconds (e.g. 150ms).
# simulated_packet_loss_percent represents the dropped packet percentage (e.g. 10.0 for 10%).
var simulated_latency_ms: int = 0
var simulated_packet_loss_percent: float = 0.0

## Returns the simulated one-way transit delay in seconds (half-RTT ping).
func get_simulated_one_way_latency_sec() -> float:
	return (simulated_latency_ms / 2.0) / 1000.0

## Sets the artificial ping latency (ms) and broadcasts it to all connected peers if called on the server.
func set_simulated_latency(ms: int) -> void:
	ms = maxi(0, ms)
	simulated_latency_ms = ms
	simulated_latency_changed.emit(ms)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_sync_simulated_latency.rpc(ms)

@rpc("authority", "call_local", "reliable")
func _sync_simulated_latency(ms: int) -> void:
	simulated_latency_ms = ms
	simulated_latency_changed.emit(ms)

## Sets the artificial packet loss percentage (0.0% to 100.0%) and broadcasts it if called on the server.
func set_simulated_packet_loss(percent: float) -> void:
	percent = clampf(percent, 0.0, 100.0)
	simulated_packet_loss_percent = percent
	simulated_packet_loss_changed.emit(percent)
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_sync_simulated_packet_loss.rpc(percent)

@rpc("authority", "call_local", "reliable")
func _sync_simulated_packet_loss(percent: float) -> void:
	simulated_packet_loss_percent = percent
	simulated_packet_loss_changed.emit(percent)

# --- PLAYER IDENTIFIER LOOKUP ---
## Finds a peer ID given a string identifier.
## Handles:
## - Direct numeric ID: "2" or "#2"
## - Full display names with spaces: "Player 2", "John Doe"
## - Quoted strings: "\"Player 2\""
## - Case-insensitive matching
## Returns -1 if no matching connected peer is found.
func find_peer_by_identifier(target: String) -> int:
	var clean := target.strip_edges()
	if clean.is_empty():
		return -1

	# Strip outer quotes if present
	if (clean.begins_with("\"") and clean.ends_with("\"")) or (clean.begins_with("'") and clean.ends_with("'")):
		if clean.length() >= 2:
			clean = clean.substr(1, clean.length() - 2).strip_edges()

	# 1. Check if numeric peer ID (e.g. "2" or "#2")
	var id_candidate := clean
	if id_candidate.begins_with("#"):
		id_candidate = id_candidate.substr(1).strip_edges()
	if id_candidate.is_valid_int():
		var pid := id_candidate.to_int()
		if pid == 1 or player_names.has(pid) or (multiplayer.multiplayer_peer != null and pid in multiplayer.get_peers()):
			return pid

	# 2. Check exact case-insensitive match against player_names
	for pid in player_names:
		if player_names[pid].to_lower() == clean.to_lower():
			return pid

	# 3. Check spaceless comparison (e.g. "Player2" matches "Player 2")
	var clean_spaceless := clean.replace(" ", "").to_lower()
	for pid in player_names:
		var name_spaceless: String = player_names[pid].replace(" ", "").to_lower()
		if name_spaceless == clean_spaceless:
			return pid

	# 4. Check "Player <pid>" default format match
	for pid in player_names:
		if clean_spaceless == ("player" + str(pid)):
			return pid

	return -1
