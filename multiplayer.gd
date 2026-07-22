extends Control

const PORT := 7777
const MAX_PLAYERS := 8

func _ready() -> void:
	$HostButton.pressed.connect(_on_host_pressed)
	$JoinButton.pressed.connect(_on_join_pressed)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_host_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		print("Failed to host: ", error)
		return
	multiplayer.multiplayer_peer = peer
	print("Hosting on port ", PORT, " as peer id ", multiplayer.get_unique_id())

func _on_join_pressed() -> void:
	var peer := ENetMultiplayerPeer.new()
	# Replace with the host's LAN IP address for a real test.
	var error := peer.create_client("127.0.0.1", PORT)
	if error != OK:
		print("Failed to create client: ", error)
		return
	multiplayer.multiplayer_peer = peer
	print("Attempting to connect...")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)

func _on_connected_to_server() -> void:
	print("Successfully connected to server! My id is ", multiplayer.get_unique_id())

func _on_connection_failed() -> void:
	print("Connection failed.")

func _on_server_disconnected() -> void:
	print("Server disconnected.")
