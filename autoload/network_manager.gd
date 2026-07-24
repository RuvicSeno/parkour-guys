extends Node

const DEFAULT_PORT: int = 7000
const MAX_PLAYERS: int = 8

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed_to_server
signal disconnected_from_server
signal server_created

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("Failed to create server: %s" % error)
		return error
	multiplayer.multiplayer_peer = peer
	print("Server started on port %d. My peer ID: %d" % [port, multiplayer.get_unique_id()])
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

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("Successfully connected to server. My peer ID: %d" % multiplayer.get_unique_id())
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("Connection failed.")
	multiplayer.multiplayer_peer = null
	connection_failed_to_server.emit()

func _on_server_disconnected() -> void:
	print("Server disconnected.")
	multiplayer.multiplayer_peer = null
	disconnected_from_server.emit()
