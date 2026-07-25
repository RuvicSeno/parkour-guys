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
	# Tell the NEW peer about every player that already exists,
	# before spawning their own — bypasses the buggy automatic
	# late-join replication of pre-existing spawned nodes.
	for existing_player in players_root.get_children():
		var existing_id: int = int(existing_player.name)
		var existing_spawn_index: int = existing_player.get_meta("spawn_index")
		_replicate_existing_player.rpc_id(peer_id, existing_id, existing_spawn_index)

	_request_spawn(peer_id)

@rpc("authority", "call_remote", "reliable")
func _replicate_existing_player(peer_id: int, spawn_index: int) -> void:
	# Runs ONLY on the newly-joined client. Manually instantiates
	# a local copy of an already-existing player, with correct
	# authority, bypassing MultiplayerSpawner's auto-replication.
	if players_root.has_node(str(peer_id)):
		return
	var data: Dictionary = {"peer_id": peer_id, "spawn_index": spawn_index}
	var player: Node = _spawn_player(data)
	players_root.add_child(player)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var existing: Node = players_root.get_node_or_null(str(peer_id))
	if existing:
		existing.queue_free()

func _request_spawn(peer_id: int) -> void:
	
	print("[REQUEST_SPAWN] requesting spawn for peer_id=%d | my_id=%d" % [peer_id, multiplayer.get_unique_id()])
	
	var spawn_index: int = players_root.get_child_count() % spawn_points.get_child_count()
	var data: Dictionary = {"peer_id": peer_id, "spawn_index": spawn_index}
	player_spawner.spawn(data)

func _spawn_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var spawn_index: int = data["spawn_index"]

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_meta("spawn_index", spawn_index)

	var spawn_point: Node3D = spawn_points.get_child(spawn_index)
	player.position = players_root.to_local(spawn_point.global_position)

	player.set_multiplayer_authority(peer_id)

	return player

var finished_players: Array[int] = []

func on_player_reach_finish(peer_id: int) -> void:
	if not multiplayer.is_server():
		_notify_server_finish.rpc_id(1, peer_id)
	else:
		_process_finish(peer_id)

@rpc("any_peer", "call_local", "reliable")
func _notify_server_finish(peer_id: int) -> void:
	if multiplayer.is_server():
		_process_finish(peer_id)

func _process_finish(peer_id: int) -> void:
	if not peer_id in finished_players:
		finished_players.append(peer_id)
		var rank: int = finished_players.size()
		_announce_win.rpc(peer_id, rank)

@rpc("authority", "call_local", "reliable")
func _announce_win(peer_id: int, rank: int) -> void:
	var win_banner_ui: Node = get_node_or_null("WinBanner/Control")
	if win_banner_ui and win_banner_ui.has_method("show_win"):
		win_banner_ui.show_win(peer_id, rank)
