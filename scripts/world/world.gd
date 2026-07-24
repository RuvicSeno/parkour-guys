extends Node3D

@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var players_root: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")

func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		# World was (re)loaded while a server already exists (scene transition).
		_on_server_created()
	else:
		# No server yet — wait for the host to click "Host".
		# Only connect if we didn't already call it above, otherwise
		# the host's player gets spawned TWICE.
		Network.server_created.connect(_on_server_created)

func _on_server_created() -> void:
	_request_spawn(multiplayer.get_unique_id())

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_request_spawn(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var existing: Node = players_root.get_node_or_null(str(peer_id))
	if existing:
		existing.queue_free()

func _request_spawn(peer_id: int) -> void:
	var spawn_index: int = peer_id % spawn_points.get_child_count()
	var data: Dictionary = {"peer_id": peer_id, "spawn_index": spawn_index}
	player_spawner.spawn(data)

func _spawn_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var spawn_index: int = data["spawn_index"]

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)

	var spawn_point: Node3D = spawn_points.get_child(spawn_index)
	player.position = players_root.to_local(spawn_point.global_position)

	player.set_multiplayer_authority(peer_id)

	return player
