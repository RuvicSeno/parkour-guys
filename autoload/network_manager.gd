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
var kicked_names: Array[String] = []

func set_kicked() -> void:
	was_kicked = true
	_reconnecting = false
	_last_server_ip = ""

@rpc("authority", "reliable")
func _notify_kicked() -> void:
	set_kicked()

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
	multiplayer.multiplayer_peer = null

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	player_connected.emit(id)
	# A new peer just joined; make sure they (and everyone else) have the
	# current name map. Harmless no-op if nothing has changed.
	if multiplayer.is_server():
		_broadcast_names()

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	player_disconnected.emit(id)
	if multiplayer.is_server() and player_names.has(id):
		player_names.erase(id)
		admin_peers.erase(id)
		_broadcast_names()

func _on_connected_to_server() -> void:
	print("Successfully connected to server. My peer ID: %d" % multiplayer.get_unique_id())
	_reconnecting = false
	_reconnect_attempts = 0
	_request_set_name.rpc_id(1, local_player_name)
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
		_notify_kicked.rpc_id(sender_id)
		get_tree().create_timer(0.1).timeout.connect(func():
			if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.has_peer(sender_id):
				multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		)
		return

	_register_name(sender_id, desired_name)
	_broadcast_names()

	var is_reconnect: bool = _check_reconnection(sender_id)
	if not is_reconnect and sender_id != 1:
		var registered_name: String = player_names.get(sender_id, "Player %d" % sender_id)
		player_joined_registry.emit(sender_id, registered_name)

## Runs on the server only. Validates and stores a single name entry.
func _register_name(peer_id: int, desired_name: String) -> void:
	var clean_name: String = desired_name.strip_edges().left(MAX_NAME_LENGTH)
	if clean_name.is_empty():
		clean_name = "Player %d" % peer_id
	player_names[peer_id] = clean_name

## Server -> All (including itself via call_local). Sends the full current
## name map. Full-map broadcast (rather than deltas) keeps late-join and
## disconnect handling correct with a single code path at this player count.
@rpc("authority", "call_local", "reliable")
func _sync_player_names(names: Dictionary) -> void:
	player_names = names
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
