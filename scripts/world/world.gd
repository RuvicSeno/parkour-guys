extends Node3D

@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var players_root: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")

var game_started: bool = false
var ready_peers: Array[int] = []
var finished_players: Array[int] = []

func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		_on_server_created()
	else:
		Network.server_created.connect(_on_server_created)

func _on_server_created() -> void:
	_request_spawn(multiplayer.get_unique_id())
	_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_request_spawn(peer_id)
	_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var existing: Node = players_root.get_node_or_null(str(peer_id))
	if existing:
		existing.queue_free()
	ready_peers.erase(peer_id)
	_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())
	_check_all_ready()

func _request_spawn(peer_id: int) -> void:
	var spawn_index: int = players_root.get_child_count() % spawn_points.get_child_count()
	var data: Dictionary = {"peer_id": peer_id, "spawn_index": spawn_index}
	player_spawner.spawn(data)

func _spawn_player(data: Dictionary) -> Node:
	var peer_id: int = data["peer_id"]
	var spawn_index: int = data["spawn_index"]

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.player_color_index = spawn_index
	player.set_meta("spawn_index", spawn_index)

	var spawn_point: Node3D = spawn_points.get_child(spawn_index)
	player.position = players_root.to_local(spawn_point.global_position)

	player.set_multiplayer_authority(peer_id)

	return player

# --- READY SYSTEM ---

func request_set_ready() -> void:
	if multiplayer.is_server():
		_server_set_ready(multiplayer.get_unique_id())
	else:
		_server_set_ready.rpc_id(1, multiplayer.get_unique_id())

@rpc("any_peer", "call_local", "reliable")
func _server_set_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not peer_id in ready_peers:
		ready_peers.append(peer_id)

	_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())
	_check_all_ready()

func _check_all_ready() -> void:
	if game_started:
		return
	var total := _get_total_player_count()
	if ready_peers.size() >= total and total > 0:
		_begin_countdown()

func _begin_countdown() -> void:
	for i in range(3, 0, -1):
		_update_countdown.rpc(i)
		await get_tree().create_timer(1.0).timeout
	_update_countdown.rpc(0)
	await get_tree().create_timer(0.5).timeout
	_start_match.rpc()

@rpc("authority", "call_local", "reliable")
func _update_ready_ui(ready_count: int, total_count: int) -> void:
	var ready_ui = get_node_or_null("ReadyUI/Control")
	if ready_ui and ready_ui.has_method("update_status"):
		ready_ui.update_status(ready_count, total_count)

@rpc("authority", "call_local", "reliable")
func _update_countdown(number: int) -> void:
	var ready_ui = get_node_or_null("ReadyUI/Control")
	if ready_ui and ready_ui.has_method("show_countdown"):
		ready_ui.show_countdown(number)

@rpc("authority", "call_local", "reliable")
func _start_match() -> void:
	game_started = true
	var ready_ui = get_node_or_null("ReadyUI/Control")
	if ready_ui and ready_ui.has_method("hide_ui"):
		ready_ui.hide_ui()
	# NOW capture the mouse for gameplay camera control
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _get_total_player_count() -> int:
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_peers().size() + 1
	return 1

# --- FINISH & LEADERBOARD SYSTEM ---

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

		if finished_players.size() >= _get_total_player_count():
			await get_tree().create_timer(1.5).timeout
			_show_leaderboard.rpc(finished_players)

@rpc("authority", "call_local", "reliable")
func _announce_win(peer_id: int, rank: int) -> void:
	var win_banner_ui: Node = get_node_or_null("WinBanner/Control")
	if win_banner_ui and win_banner_ui.has_method("show_win"):
		win_banner_ui.show_win(peer_id, rank)

@rpc("authority", "call_local", "reliable")
func _show_leaderboard(ranks: Array) -> void:
	var leaderboard_ui: Node = get_node_or_null("LeaderboardUI/Control")
	if leaderboard_ui and leaderboard_ui.has_method("display_leaderboard"):
		leaderboard_ui.display_leaderboard(ranks)
