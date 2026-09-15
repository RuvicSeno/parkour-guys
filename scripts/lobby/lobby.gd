extends Control

const ROW_SCENE: PackedScene = preload("res://scenes/lobby/PlayerLobbyRow.tscn")
const WORLD_SCENE_PATH: String = "res://scenes/world/World.tscn"

# Panels
@onready var connect_panel: Control = $ConnectPanel
@onready var room_panel: Control = $RoomPanel

# Connect Panel Nodes
@onready var name_line_edit: LineEdit = $ConnectPanel/VBoxContainer/NameLineEdit
@onready var ip_line_edit: LineEdit = $ConnectPanel/VBoxContainer/IPLineEdit
@onready var host_btn: Button = $ConnectPanel/VBoxContainer/HostButton
@onready var join_btn: Button = $ConnectPanel/VBoxContainer/JoinButton
@onready var connect_status_label: Label = $ConnectPanel/VBoxContainer/StatusLabel

# Room Panel Nodes
@onready var room_title_label: Label = $RoomPanel/MarginContainer/VBox/Header/TitleLabel
@onready var player_count_label: Label = $RoomPanel/MarginContainer/VBox/Header/PlayerCountLabel
@onready var leave_btn: Button = $RoomPanel/MarginContainer/VBox/Header/LeaveButton
@onready var player_list_container: VBoxContainer = $RoomPanel/MarginContainer/VBox/ScrollContainer/PlayerListContainer
@onready var status_label: Label = $RoomPanel/MarginContainer/VBox/Footer/StatusLabel
@onready var ready_btn: Button = $RoomPanel/MarginContainer/VBox/Footer/ActionButtons/ReadyButton
@onready var start_game_btn: Button = $RoomPanel/MarginContainer/VBox/Footer/ActionButtons/StartGameButton

## Authoritative lobby state on server:
## peer_id -> { "name": String, "color_index": int, "is_ready": bool }
var lobby_players: Dictionary = {}
var is_counting_down: bool = false
var countdown_cancel_requested: bool = false

func _ready() -> void:
	name_line_edit.text = Network.local_player_name if not Network.local_player_name.is_empty() else "Player"
	
	# Connect UI buttons
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	ready_btn.pressed.connect(_on_ready_pressed)
	start_game_btn.pressed.connect(_on_start_game_pressed)

	# Network signals
	Network.connection_succeeded.connect(_on_connection_succeeded)
	Network.connection_failed_to_server.connect(_on_connection_failed)
	Network.disconnected_from_server.connect(_on_disconnected_from_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Only show room if returning from an active networked ENet session
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_show_room()
		if multiplayer.is_server():
			if not lobby_players.has(1):
				_server_add_player(1, Network.local_player_name)
			_server_broadcast_state()
	else:
		_show_connect()

var _is_connecting: bool = false
const MAROON_COLOR: Color = Color(1.0, 0.244, 0.199, 1.0)

func _reset_join_button() -> void:
	_is_connecting = false
	join_btn.text = "Join Game"
	join_btn.modulate = Color(1, 1, 1, 1)

func _show_connect() -> void:
	connect_panel.show()
	room_panel.hide()
	connect_status_label.text = ""
	_reset_join_button()
	_set_connect_buttons_enabled(true)

func _show_room() -> void:
	_reset_join_button()
	connect_panel.hide()
	room_panel.show()
	_update_local_action_buttons()

func _set_connect_buttons_enabled(enabled: bool) -> void:
	host_btn.disabled = not enabled
	join_btn.disabled = not enabled
	name_line_edit.editable = enabled
	ip_line_edit.editable = enabled

# --- CONNECT ACTIONS ---

func _on_host_pressed() -> void:
	var player_name: String = name_line_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	Network.set_local_player_name(player_name)
	_set_connect_buttons_enabled(false)
	connect_status_label.text = "Starting server..."

	var err: Error = Network.host_game()
	if err != OK:
		connect_status_label.text = "Failed to host: Error %d" % err
		_set_connect_buttons_enabled(true)
		return

	Network.current_session_scene = "lobby"
	lobby_players.clear()
	_server_add_player(1, Network.local_player_name)
	_show_room()
	_server_broadcast_state()

func _on_join_pressed() -> void:
	if _is_connecting:
		# Player pressed Cancel while attempting to connect
		Network.disconnect_from_game()
		_reset_join_button()
		_set_connect_buttons_enabled(true)
		connect_status_label.text = "Connection cancelled."
		return

	var player_name: String = name_line_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	Network.set_local_player_name(player_name)

	var ip: String = ip_line_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"

	_is_connecting = true
	join_btn.text = "Cancel"
	join_btn.modulate = MAROON_COLOR
	host_btn.disabled = true
	name_line_edit.editable = false
	ip_line_edit.editable = false
	join_btn.disabled = false
	connect_status_label.text = "Connecting to %s..." % ip

	var err: Error = Network.join_game(ip)
	if err != OK:
		connect_status_label.text = "Failed to initiate join: Error %d" % err
		_reset_join_button()
		_set_connect_buttons_enabled(true)

func _on_connection_succeeded() -> void:
	_reset_join_button()
	if Network.current_session_scene == "lobby":
		_show_room()
		status_label.text = "Connected! Joining lobby..."
		# Request server to register our lobby entry
		_server_register_peer.rpc_id(1, Network.local_player_name)
	else:
		status_label.text = "Game in progress! Joining match..."

func _on_connection_failed() -> void:
	_reset_join_button()
	_show_connect()
	connect_status_label.text = "Connection failed. Check host IP and port."

func _on_disconnected_from_server() -> void:
	_reset_join_button()
	_show_connect()
	connect_status_label.text = "Disconnected from host."

func _on_leave_pressed() -> void:
	Network.disconnect_from_game()
	lobby_players.clear()
	is_counting_down = false
	_show_connect()

# --- SERVER AUTHORITY METHODS ---

func _server_add_player(peer_id: int, p_name: String) -> void:
	var clean_name: String = p_name.strip_edges().left(Network.MAX_NAME_LENGTH)
	if clean_name.is_empty():
		clean_name = "Player %d" % peer_id

	var unique_name: String = clean_name
	var counter: int = 2
	while _is_lobby_name_taken(unique_name, peer_id):
		var suffix: String = str(counter)
		var max_base_len: int = maxi(1, Network.MAX_NAME_LENGTH - suffix.length())
		var base_trimmed: String = clean_name.left(max_base_len)
		unique_name = base_trimmed + suffix
		counter += 1

	var available_color: int = _get_first_available_color()
	lobby_players[peer_id] = {
		"name": unique_name,
		"color_index": available_color,
		"is_ready": false
	}
	Network._register_name(peer_id, unique_name)

func _is_lobby_name_taken(candidate: String, peer_id: int) -> bool:
	for pid in lobby_players:
		if pid != peer_id and lobby_players[pid]["name"].to_lower() == candidate.to_lower():
			return true
	return false

func _get_first_available_color() -> int:
	var used_colors: Array = []
	for p_data in lobby_players.values():
		used_colors.append(p_data["color_index"])

	for c_idx in range(Network.PLAYER_COLORS.size()):
		if not c_idx in used_colors:
			return c_idx
	return 0

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if lobby_players.has(peer_id):
		lobby_players.erase(peer_id)
		if is_counting_down:
			countdown_cancel_requested = true
		_server_broadcast_state()

@rpc("any_peer", "reliable")
func _server_register_peer(p_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_server_add_player(sender_id, p_name)
	_server_broadcast_state()

func _server_broadcast_state() -> void:
	if not multiplayer.is_server():
		return
	_sync_lobby_state.rpc(lobby_players)

@rpc("any_peer", "reliable")
func request_change_color(direction: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if not lobby_players.has(sender_id) or is_counting_down:
		return

	var current: int = lobby_players[sender_id]["color_index"]
	var total_colors: int = Network.PLAYER_COLORS.size()

	var used_colors: Array = []
	for p_id in lobby_players:
		if p_id != sender_id:
			used_colors.append(lobby_players[p_id]["color_index"])

	var next_color: int = current
	for i in range(1, total_colors + 1):
		var candidate: int = posmod(current + (direction * i), total_colors)
		if not candidate in used_colors:
			next_color = candidate
			break

	lobby_players[sender_id]["color_index"] = next_color
	# Changing color unreadies the player
	lobby_players[sender_id]["is_ready"] = false
	_server_broadcast_state()

@rpc("any_peer", "reliable")
func request_toggle_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if not lobby_players.has(sender_id) or is_counting_down:
		return

	lobby_players[sender_id]["is_ready"] = not lobby_players[sender_id]["is_ready"]
	_server_broadcast_state()

@rpc("any_peer", "reliable")
func request_start_game() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if sender_id != 1:
		return

	if not _server_are_all_ready():
		return

	# Disable buttons and notify peers
	_sync_status.rpc("Starting game... Loading map...")

	# Store colors in Network autoload before transitioning
	for p_id in lobby_players:
		Network.player_colors[p_id] = lobby_players[p_id]["color_index"]

	_load_game_scene.rpc(Network.player_colors)

func _server_are_all_ready() -> bool:
	if lobby_players.is_empty():
		return false
	for p_data in lobby_players.values():
		if not p_data.get("is_ready", false):
			return false
	return true

# --- RPC CLIENT SYNCS ---

@rpc("authority", "call_local", "reliable")
func _sync_lobby_state(synced_players: Dictionary) -> void:
	lobby_players = synced_players
	_rebuild_player_rows()
	_update_local_action_buttons()

@rpc("authority", "call_local", "reliable")
func _sync_countdown(sec: int) -> void:
	is_counting_down = true
	ready_btn.disabled = true
	start_game_btn.disabled = true
	if sec > 0:
		status_label.text = "Game starting in %d..." % sec
		status_label.modulate = Color(0.9, 0.8, 0.2)
	else:
		status_label.text = "GO!"
		status_label.modulate = Color(0.2, 0.9, 0.3)

@rpc("authority", "call_local", "reliable")
func _sync_status(msg: String) -> void:
	status_label.text = msg
	status_label.modulate = Color(1.0, 1.0, 1.0)
	is_counting_down = false
	_update_local_action_buttons()

@rpc("authority", "call_local", "reliable")
func _load_game_scene(synced_colors: Dictionary) -> void:
	Network.current_session_scene = "world"
	Network.player_colors = synced_colors
	get_tree().change_scene_to_file(WORLD_SCENE_PATH)

# --- UI REBUILD & REFRESH ---

func _rebuild_player_rows() -> void:
	# Clear existing children immediately
	for child in player_list_container.get_children():
		player_list_container.remove_child(child)
		child.queue_free()

	var my_id: int = multiplayer.get_unique_id()
	var sorted_ids: Array = lobby_players.keys()
	sorted_ids.sort()

	for p_id in sorted_ids:
		var p_data: Dictionary = lobby_players[p_id]
		var row = ROW_SCENE.instantiate()
		player_list_container.add_child(row)

		var is_local: bool = (p_id == my_id)
		var is_host: bool = (p_id == 1)

		row.setup(
			p_id,
			p_data.get("name", "Player %d" % p_id),
			p_data.get("color_index", 0),
			p_data.get("is_ready", false),
			is_local,
			is_host
		)

		if is_local:
			row.color_change_requested.connect(_on_local_color_change_requested)

	player_count_label.text = "Players: %d/%d" % [lobby_players.size(), Network.MAX_PLAYERS]

func _update_local_action_buttons() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var is_host: bool = (my_id == 1)

	# Ready button state
	var my_data: Dictionary = lobby_players.get(my_id, {})
	var is_ready: bool = my_data.get("is_ready", false)

	if is_ready:
		ready_btn.text = "UNREADY"
		ready_btn.modulate = Color(0.9, 0.6, 0.2)
	else:
		ready_btn.text = "READY UP"
		ready_btn.modulate = Color(0.2, 0.9, 0.3)

	ready_btn.disabled = is_counting_down

	# Host Start Game button
	start_game_btn.visible = is_host
	if is_host:
		var all_ready: bool = true
		if lobby_players.is_empty():
			all_ready = false
		else:
			for p in lobby_players.values():
				if not p.get("is_ready", false):
					all_ready = false
					break
		start_game_btn.disabled = (not all_ready) or is_counting_down

	# Default status text when not counting down
	if not is_counting_down:
		var ready_count: int = 0
		for p in lobby_players.values():
			if p.get("is_ready", false):
				ready_count += 1
		status_label.text = "Waiting for players... (%d/%d Ready)" % [ready_count, lobby_players.size()]
		status_label.modulate = Color(0.8, 0.8, 0.8)

# --- LOCAL USER INPUT CALLBACKS ---

func _on_local_color_change_requested(dir: int) -> void:
	if is_counting_down:
		return
	if multiplayer.is_server():
		request_change_color(dir)
	else:
		request_change_color.rpc_id(1, dir)

func _on_ready_pressed() -> void:
	if is_counting_down:
		return
	if multiplayer.is_server():
		request_toggle_ready()
	else:
		request_toggle_ready.rpc_id(1)

func _on_start_game_pressed() -> void:
	if is_counting_down:
		return
	if multiplayer.is_server():
		request_start_game()
	else:
		request_start_game.rpc_id(1)
