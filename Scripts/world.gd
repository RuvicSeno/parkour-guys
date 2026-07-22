extends Node3D

const PLAYER_SCENE := preload("res://Player.tscn")

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)

	# If we are already the server when this scene loads, spawn ourselves too.
	if multiplayer.is_server():
		_spawn_player(multiplayer.get_unique_id())

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)

func _spawn_player(id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	$Players.add_child(player)
