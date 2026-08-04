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

## The name this client wants to use, set locally (e.g. from a lobby LineEdit)
## BEFORE host_game()/join_game() is called. Read by _on_server_created() and
## _on_connected_to_server() to register/announce the name.
var local_player_name: String = ""

## Authoritative peer_id -> display_name map. Only the server mutates this
## directly; clients receive it via _sync_player_names() and treat it as
## read-only.
var player_names: Dictionary = {}

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
	player_names_updated.emit()
	server_created.emit()
	return OK

func join_game(ip_address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip_address, port)
	if error != OK:
		push_error("Failed to create client: %s" % error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to %s:%d ..." % [ip_address, port])
	return OK

func disconnect_from_game() -> void:
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
		_broadcast_names()

func _on_connected_to_server() -> void:
	print("Successfully connected to server. My peer ID: %d" % multiplayer.get_unique_id())
	_request_set_name.rpc_id(1, local_player_name)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("Connection failed.")
	multiplayer.multiplayer_peer = null
	connection_failed_to_server.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	multiplayer.multiplayer_peer = null
	disconnected_from_server.emit()

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
	_register_name(sender_id, desired_name)
	_broadcast_names()

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
