extends Node3D

@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var players_root: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/Player.tscn")

var game_started: bool = false
var ready_peers: Array[int] = []
var finished_players: Array[int] = []

# --- CHAT & DESYNC DETECTION STATE ---
signal desync_detected(peer_id: int, drift: float, tick: int)

const DESYNC_TOLERANCE_METERS: float = 2.5
var desync_stats: Dictionary = {}
var chat_filter: ChatFilter = ChatFilter.new()
var muted_peers: Array[int] = []

func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server():
		_on_server_created()
	else:
		Network.server_created.connect(_on_server_created)

	chat_message_received.connect(_on_chat_message_received)

<<<<<<< Updated upstream
=======
<<<<<<< HEAD
	var emote_wheel = get_node_or_null("EmoteWheel/Control")
	if emote_wheel and emote_wheel.has_signal("emote_selected"):
		emote_wheel.emote_selected.connect(_on_emote_selected)

func _on_emote_selected(emote: Emote) -> void:
	if players_root == null:
		return
	var my_id: int = multiplayer.get_unique_id()
	var my_player = players_root.get_node_or_null(str(my_id))
	if my_player and my_player.has_method("play_emote"):
		my_player.play_emote(emote)
=======
>>>>>>> Stashed changes
	# Listen for join and reconnection events from the Network autoload
	if Network.has_signal("player_reconnected"):
		Network.player_reconnected.connect(_on_player_reconnected)
	if Network.has_signal("player_joined_registry"):
		Network.player_joined_registry.connect(_on_player_joined_registry)

func _on_player_joined_registry(_peer_id: int, username: String) -> void:
	if multiplayer.is_server():
		_broadcast_system_message.rpc("%s joined the game." % username)
<<<<<<< Updated upstream
=======
>>>>>>> b66373991f307a73b956aa5f0a8e2d1e066fb926
>>>>>>> Stashed changes

func _on_server_created() -> void:
	_request_spawn(multiplayer.get_unique_id())
	_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_request_spawn(peer_id)
	if not game_started:
		_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())
	else:
		_sync_game_started_to_peer.rpc_id(peer_id, true)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Save player state for potential reconnection BEFORE freeing the node
	var username: String = Network.player_names.get(peer_id, "")
	var existing: Node = players_root.get_node_or_null(str(peer_id))
	if existing and existing is CharacterBody3D and not username.is_empty():
		var state: Dictionary = {
			"position": existing.global_position,
			"color_index": existing.player_color_index,
			"respawn_position": existing.respawn_position,
		}
		Network.store_disconnected_player(username, state)

	if existing:
		existing.queue_free()
	ready_peers.erase(peer_id)
	muted_peers.erase(peer_id)
	desync_stats.erase(peer_id)

	if not game_started:
		_update_ready_ui.rpc(ready_peers.size(), _get_total_player_count())
		_check_all_ready()

	# Notify all players about the disconnect
	if not username.is_empty():
		_broadcast_system_message.rpc("%s disconnected." % username)

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
	if game_started:
		return
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
	var chat_ui = get_node_or_null("ChatUI/Control")
	if chat_ui and chat_ui.has_method("show_ui"):
		chat_ui.show_ui()
	# NOW capture the mouse for gameplay camera control
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _get_total_player_count() -> int:
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_peers().size() + 1
	return 1

# =======================================================================
# CHAT SYSTEM
# Messages flow: Client -> Server (validate, censor, command-check) -> All
# =======================================================================

signal chat_message_received(sender_id: int, sender_name: String, message: String)

const MAX_CHAT_MESSAGE_LENGTH: int = 200

## Public entry point for chat_ui.gd to call.
func send_chat_message(raw_text: String) -> void:
	if not game_started:
		return
	if multiplayer.is_server():
		_process_chat_message(multiplayer.get_unique_id(), raw_text)
	else:
		if Network.simulated_latency_ms > 0:
			get_tree().create_timer(Network.simulated_latency_ms / 1000.0).timeout.connect(func():
				if multiplayer.multiplayer_peer != null:
					_request_chat_message.rpc_id(1, raw_text)
			)
		else:
			_request_chat_message.rpc_id(1, raw_text)

@rpc("any_peer", "reliable")
func _request_chat_message(raw_text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_chat_message(sender_id, raw_text)

## SERVER-ONLY. The central validation point for ALL chat messages.
## This is where we check commands, apply mute, and run censorship.
func _process_chat_message(sender_id: int, raw_text: String) -> void:
	if not game_started:
		return
	var clean_text: String = raw_text.strip_edges().left(MAX_CHAT_MESSAGE_LENGTH)
	if clean_text.is_empty():
		return

	# --- COMMAND HANDLING ---
	# If the message starts with '/', route it to the command parser.
	# Commands are never broadcast as normal chat messages.
	if clean_text.begins_with("/"):
		_handle_command(sender_id, clean_text)
		return

	# --- MUTE CHECK ---
	# If the player is muted, silently drop their message and notify them.
	if sender_id in muted_peers:
		_server_send_system_message(sender_id, "You are muted. Your message was not sent.")
		return

	# --- CENSORSHIP ---
	# Apply the server-side word filter before broadcasting.
	# Clients cannot bypass this because they never see the raw text.
	clean_text = chat_filter.filter(clean_text)

	var sender_name: String = Network.player_names.get(sender_id, "Player %d" % sender_id)
	_broadcast_chat_message.rpc(sender_id, sender_name, clean_text)

@rpc("authority", "call_local", "reliable")
func _broadcast_chat_message(sender_id: int, sender_name: String, message: String) -> void:
	if not multiplayer.is_server() and Network.simulated_latency_ms > 0:
		get_tree().create_timer(Network.simulated_latency_ms / 1000.0).timeout.connect(func():
			chat_message_received.emit(sender_id, sender_name, message)
		)
	else:
		chat_message_received.emit(sender_id, sender_name, message)

func _on_chat_message_received(sender_id: int, sender_name: String, message: String) -> void:
	var chat_ui = get_node_or_null("ChatUI/Control")
	if chat_ui and chat_ui.has_method("add_message"):
		chat_ui.add_message(sender_id, sender_name, message)

	if players_root:
		var p_node = players_root.get_node_or_null(str(sender_id))
		if p_node and p_node.has_method("add_chat_bubble"):
			p_node.add_chat_bubble(message)

# =======================================================================
# SYSTEM MESSAGES
# Gray italic messages for admin actions, join/leave, reconnection, etc.
# =======================================================================

## Server -> ALL clients (including self). Use for public announcements.
@rpc("authority", "call_local", "reliable")
func _broadcast_system_message(message: String) -> void:
	_on_system_message_received(message)

## Server -> ONE specific client. Use for private feedback (errors, ping).
@rpc("authority", "reliable")
func _send_system_message_to(message: String) -> void:
	_on_system_message_received(message)

## Server-side helper that correctly handles sending to self (host) vs remote.
## Use this instead of calling _send_system_message_to.rpc_id() directly,
## because the host (peer 1) needs a local call, not an RPC to itself.
func _server_send_system_message(target_id: int, message: String) -> void:
	if target_id == multiplayer.get_unique_id():
		# We ARE the target (host sending to itself) — call handler directly
		_on_system_message_received(message)
	else:
		_send_system_message_to.rpc_id(target_id, message)

func _on_system_message_received(message: String) -> void:
	var chat_ui = get_node_or_null("ChatUI/Control")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message(message)

# =======================================================================
# COMMAND PARSER & HANDLERS
# All commands are parsed and executed on the server.
# /ping is available to everyone. All others require admin permission.
# =======================================================================

func _parse_command_tokens(command_text: String) -> PackedStringArray:
	var tokens: PackedStringArray = []
	var regex := RegEx.new()
	# Matches "double-quoted", 'single-quoted', or unquoted words
	regex.compile("\"([^\"]*)\"|'([^']*)'|(\\S+)")
	for result in regex.search_all(command_text):
		for i in range(1, 4):
			var match_str: String = result.get_string(i)
			if match_str != "":
				tokens.append(match_str)
				break
	return tokens

func _handle_command(sender_id: int, command_text: String) -> void:
	var parts: PackedStringArray = _parse_command_tokens(command_text)
	if parts.size() == 0:
		return
	var cmd: String = parts[0].to_lower()

	match cmd:
		"/ping":
			_cmd_ping(sender_id)
		"/nick":
			_cmd_nick(sender_id, parts)
		"/clear":
			_cmd_clear(sender_id)
		"/kick":
			_cmd_kick(sender_id, parts)
		"/mute":
			_cmd_mute(sender_id, parts)
		"/unmute":
			_cmd_unmute(sender_id, parts)
		"/kill":
			_cmd_kill(sender_id, parts)
		"/latency", "/lag", "/simlag":
			_cmd_latency(sender_id, parts)
		"/desync", "/syncstatus", "/checksync":
			_cmd_desync(sender_id, parts)
		"/resync":
			_cmd_resync(sender_id, parts)
		_:
			_server_send_system_message(sender_id, "Unknown command: %s" % cmd)

## Resolves a target peer identifier from command tokens.
## Handles single tokens, multi-word unquoted names (e.g. "Player 2"), and numeric IDs.
func _extract_target_id(parts: PackedStringArray, start_index: int = 1) -> int:
	if parts.size() <= start_index:
		return -1
	var single_target: String = parts[start_index]
	var pid: int = Network.find_peer_by_identifier(single_target)
	if pid != -1:
		return pid
	if parts.size() > start_index + 1:
		var full_target: String = " ".join(parts.slice(start_index))
		return Network.find_peer_by_identifier(full_target)
	return -1

## Returns -1 if no player with that identifier is currently connected.
func _find_peer_by_name(target_name: String) -> int:
	return Network.find_peer_by_identifier(target_name)

## Helper that checks admin permission and sends an error message if denied.
## Returns true if the sender IS an admin.
func _require_admin(sender_id: int) -> bool:
	if Network.is_admin(sender_id):
		return true
	_server_send_system_message(sender_id, "Permission denied. Admin only.")
	return false

# --- /ping ---
# Available to ALL players. Uses ENet's round-trip-time statistic and includes simulated latency.
func _cmd_ping(sender_id: int) -> void:
	var base_rtt: float = 0.0
	var found_rtt: bool = false
	if sender_id != 1:
		var enet_peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet_peer:
			var packet_peer: ENetPacketPeer = enet_peer.get_peer(sender_id)
			if packet_peer:
				base_rtt = packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
				found_rtt = true

	var sim_lat: int = Network.simulated_latency_ms
	var total_ping: int = int(base_rtt + (sim_lat * 2))

	if sender_id == 1:
		if sim_lat > 0:
			_server_send_system_message(sender_id, "Your ping: 0 ms (Host) | Global simulated latency: %d ms (%d ms RTT)" % [sim_lat, sim_lat * 2])
		else:
			_server_send_system_message(sender_id, "Your ping: 0 ms (you are the host)")
		return

	if found_rtt or sim_lat > 0:
		if sim_lat > 0:
			_server_send_system_message(sender_id, "Your ping: %d ms (%d ms real + %d ms simulated RTT)" % [total_ping, int(base_rtt), sim_lat * 2])
		else:
			_server_send_system_message(sender_id, "Your ping: %d ms" % total_ping)
		return

	_server_send_system_message(sender_id, "Could not determine ping.")

# --- /nick <current_name|id> <new_name> ---
# Admin only. Changes another player's display name.
func _cmd_nick(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return
	if parts.size() < 3:
		_server_send_system_message(sender_id, "Usage: /nick <current_name|player_id> <new_name>")
		return

	var target_id: int = -1
	var new_name: String = ""

	if parts.size() == 3:
		target_id = Network.find_peer_by_identifier(parts[1])
		new_name = parts[2].strip_edges().left(Network.MAX_NAME_LENGTH)
	else:
		# If unquoted multi-word arguments: test possible split points
		for split_idx in range(parts.size() - 1, 0, -1):
			var target_candidate: String = " ".join(parts.slice(1, split_idx))
			var pid: int = Network.find_peer_by_identifier(target_candidate)
			if pid != -1:
				target_id = pid
				new_name = " ".join(parts.slice(split_idx)).strip_edges().left(Network.MAX_NAME_LENGTH)
				break

	if target_id == -1:
		_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
		return
	if new_name.is_empty():
		_server_send_system_message(sender_id, "New name cannot be empty.")
		return

	# Check for duplicate names
	for pid in Network.player_names:
		if Network.player_names[pid].to_lower() == new_name.to_lower() and pid != target_id:
			_server_send_system_message(sender_id, "Name '%s' is already taken." % new_name)
			return

	var old_name: String = Network.player_names.get(target_id, "Player %d" % target_id)
	Network.player_names[target_id] = new_name
	Network._broadcast_names()
	_broadcast_system_message.rpc("%s was renamed to %s by admin." % [old_name, new_name])

# --- /clear ---
# Admin only. Clears the chat for all connected clients.
func _cmd_clear(sender_id: int) -> void:
	if not _require_admin(sender_id):
		return
	_clear_chat.rpc()

@rpc("authority", "call_local", "reliable")
func _clear_chat() -> void:
	var chat_ui = get_node_or_null("ChatUI/Control")
	if chat_ui and chat_ui.has_method("clear_messages"):
		chat_ui.clear_messages()

# --- /kick <username|player_id> ---
# Admin only. Disconnects a player from the session.
func _cmd_kick(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return
	if parts.size() < 2:
		_server_send_system_message(sender_id, "Usage: /kick <username|player_id>")
		return

	var target_id: int = _extract_target_id(parts, 1)
	if target_id == -1:
		_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
		return
	if target_id == sender_id:
		_server_send_system_message(sender_id, "You cannot kick yourself.")
		return
	if target_id == 1:
		_server_send_system_message(sender_id, "You cannot kick the host.")
		return

	var kicked_name: String = Network.player_names.get(target_id, "Player %d" % target_id)
	# Tell target client it is being kicked so it disables auto-reconnection
	Network._notify_kicked.rpc_id(target_id)
	# Send the kicked player a message before disconnecting them
	_server_send_system_message(target_id, "You have been kicked by an admin.")
	# Small delay so the message and RPC arrive before the disconnect
	await get_tree().create_timer(0.1).timeout
	_broadcast_system_message.rpc("%s was kicked from the game." % kicked_name)
	# Prevent the kicked player from reconnecting by removing their saved state and adding to blacklist
	Network.disconnected_players.erase(kicked_name)
	if not kicked_name.to_lower() in Network.kicked_names:
		Network.kicked_names.append(kicked_name.to_lower())
	multiplayer.multiplayer_peer.disconnect_peer(target_id)

# --- /mute <username|player_id> ---
# Admin only. Server-side mute — the server silently drops their messages.
func _cmd_mute(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return
	if parts.size() < 2:
		_server_send_system_message(sender_id, "Usage: /mute <username|player_id>")
		return

	var target_id: int = _extract_target_id(parts, 1)
	if target_id == -1:
		_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
		return
	if target_id in muted_peers:
		_server_send_system_message(sender_id, "%s is already muted." % Network.player_names.get(target_id, "Player %d" % target_id))
		return

	muted_peers.append(target_id)
	_broadcast_system_message.rpc("%s has been muted by an admin." % Network.player_names.get(target_id, "Player %d" % target_id))

# --- /unmute <username|player_id> ---
# Admin only. Restores a muted player's ability to chat.
func _cmd_unmute(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return
	if parts.size() < 2:
		_server_send_system_message(sender_id, "Usage: /unmute <username|player_id>")
		return

	var target_id: int = _extract_target_id(parts, 1)
	if target_id == -1:
		_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
		return
	if not target_id in muted_peers:
		_server_send_system_message(sender_id, "%s is not muted." % Network.player_names.get(target_id, "Player %d" % target_id))
		return

	muted_peers.erase(target_id)
	_broadcast_system_message.rpc("%s has been unmuted by an admin." % Network.player_names.get(target_id, "Player %d" % target_id))

# --- /kill <username|player_id> ---
# Admin only. Respawns a player at their last checkpoint.
# The RPC goes to all clients; only the authority for that player executes.
func _cmd_kill(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return
	if parts.size() < 2:
		_server_send_system_message(sender_id, "Usage: /kill <username|player_id>")
		return

	var target_id: int = _extract_target_id(parts, 1)
	if target_id == -1:
		_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
		return

	var killed_name: String = Network.player_names.get(target_id, "Player %d" % target_id)
	_admin_respawn_player.rpc(target_id)
	_broadcast_system_message.rpc("%s was killed by an admin." % killed_name)

## Sent to all clients. Each client checks if they are the authority for the
## target player and, if so, resets that player to their last checkpoint.
@rpc("authority", "call_local", "reliable")
func _admin_respawn_player(target_peer_id: int) -> void:
	var p_node = players_root.get_node_or_null(str(target_peer_id))
	if p_node and p_node is CharacterBody3D:
		if p_node.is_multiplayer_authority():
			p_node.velocity = Vector3.ZERO
			p_node.global_position = p_node.respawn_position

# --- /latency <0|50|150|300|ms|off> ---
# Admin only. Sets simulated artificial network latency globally for testing.
func _cmd_latency(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return

	if parts.size() < 2:
		var current_ms: int = Network.simulated_latency_ms
		_server_send_system_message(sender_id, "Simulated latency: %d ms (Presets: 0ms/off, 50ms, 150ms, 300ms). Usage: /latency <ms>" % current_ms)
		return

	var arg: String = parts[1].to_lower().strip_edges()
	var latency_ms: int = 0
	if arg == "off":
		latency_ms = 0
	elif arg.is_valid_int():
		latency_ms = maxi(0, arg.to_int())
	else:
		_server_send_system_message(sender_id, "Invalid latency '%s'. Presets: 0ms, 50ms, 150ms, 300ms." % arg)
		return

	Network.set_simulated_latency(latency_ms)
	if latency_ms == 0:
		_broadcast_system_message.rpc("Admin disabled artificial network latency (0 ms).")
	else:
		_broadcast_system_message.rpc("Admin set artificial network latency to %d ms (Presets: 0ms, 50ms, 150ms, 300ms)." % latency_ms)

# --- /desync [player_name|id] ---
# Admin only. Displays desync detection statistics for all players or a specific player.
func _cmd_desync(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return

	if parts.size() >= 2:
		var target_id: int = _extract_target_id(parts, 1)
		if target_id == -1:
			_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
			return
		_show_player_desync_stats(sender_id, target_id)
	else:
		_show_all_desync_stats(sender_id)

func _show_all_desync_stats(admin_id: int) -> void:
	var msg: String = "=== DESYNC DETECTION STATUS ===\n"
	if Network.player_names.is_empty():
		msg += "No players connected."
	else:
		for pid in Network.player_names:
			var p_name: String = Network.player_names[pid]
			var stats: Dictionary = desync_stats.get(pid, {})
			var status: String = stats.get("status", "SYNCED")
			var desync_count: int = stats.get("desync_count", 0)
			var total_checks: int = stats.get("total_checks", 0)
			var last_drift: float = stats.get("last_drift", 0.0)
			var max_drift: float = stats.get("max_drift", 0.0)

			msg += "[%s] %s (ID %d): %s | Desyncs: %d/%d | Last Drift: %.2fm | Max Drift: %.2fm\n" % [
				status, p_name, pid, "OK" if desync_count == 0 else "WARNING", desync_count, total_checks, last_drift, max_drift
			]
	_server_send_system_message(admin_id, msg.strip_edges())

func _show_player_desync_stats(admin_id: int, target_id: int) -> void:
	var p_name: String = Network.player_names.get(target_id, "Player %d" % target_id)
	var stats: Dictionary = desync_stats.get(target_id, {})
	var status: String = stats.get("status", "SYNCED")
	var desync_count: int = stats.get("desync_count", 0)
	var total_checks: int = stats.get("total_checks", 0)
	var last_drift: float = stats.get("last_drift", 0.0)
	var max_drift: float = stats.get("max_drift", 0.0)
	var last_tick: int = stats.get("last_check_tick", 0)
	var cur_tol: float = DESYNC_TOLERANCE_METERS + (Network.simulated_latency_ms / 1000.0 * 6.0)
	var msg: String = "=== SYNC STATS: %s (ID %d) ===\nStatus: %s\nDesync Count: %d / %d checks\nLast Drift: %.3fm\nMax Drift: %.3fm\nLast Verified Tick: %d\nTolerance: %.2fm" % [
		p_name, target_id, status, desync_count, total_checks, last_drift, max_drift, last_tick, cur_tol
	]
	_server_send_system_message(admin_id, msg)

# --- /resync <player_name|id> ---
# Admin only. Forces an authoritative state reconciliation for a desynced player.
func _cmd_resync(sender_id: int, parts: PackedStringArray) -> void:
	if not _require_admin(sender_id):
		return
	if parts.size() < 2:
		_server_send_system_message(sender_id, "Usage: /resync <player_name|player_id>")
		return

	var target_id: int = _extract_target_id(parts, 1)
	if target_id == -1:
		_server_send_system_message(sender_id, "Player '%s' not found." % parts[1])
		return

	var p_node = players_root.get_node_or_null(str(target_id))
	if p_node and p_node is CharacterBody3D:
		if p_node.has_method("_force_reconcile_state"):
			p_node._force_reconcile_state.rpc_id(target_id, p_node.global_position, p_node.velocity)
		if desync_stats.has(target_id):
			desync_stats[target_id]["desync_count"] = 0
			desync_stats[target_id]["status"] = "SYNCED"

		var target_name: String = Network.player_names.get(target_id, "Player %d" % target_id)
		_server_send_system_message(sender_id, "Forced state resync for %s (Peer %d)." % [target_name, target_id])
		_broadcast_system_message.rpc("%s was resynchronized to server state by admin." % target_name)
	else:
		_server_send_system_message(sender_id, "Player node not found.")

# =======================================================================
# DESYNC DETECTION VERIFICATION (SERVER-SIDE)
# =======================================================================

func verify_desync_report(peer_id: int, tick: int, client_hash: int, client_pos: Vector3, _client_vel: Vector3) -> void:
	if not multiplayer.is_server():
		return

	if not desync_stats.has(peer_id):
		desync_stats[peer_id] = {
			"total_checks": 0,
			"desync_count": 0,
			"max_drift": 0.0,
			"last_drift": 0.0,
			"last_check_tick": 0,
			"last_check_time": 0.0,
			"status": "SYNCED"
		}

	var stats: Dictionary = desync_stats[peer_id]
	stats["total_checks"] += 1
	stats["last_check_tick"] = tick
	stats["last_check_time"] = Time.get_ticks_msec() / 1000.0

	var p_node = players_root.get_node_or_null(str(peer_id))
	if p_node and p_node is CharacterBody3D:
		var drift: float = p_node.global_position.distance_to(client_pos)
		stats["last_drift"] = drift
		stats["max_drift"] = maxf(stats["max_drift"], drift)

		var server_snapshot: Dictionary = p_node.get_state_snapshot(tick)
		var server_hash: int = p_node.compute_state_hash(server_snapshot)

		var max_allowed_drift: float = DESYNC_TOLERANCE_METERS + (Network.simulated_latency_ms / 1000.0 * 6.0)

		# Check if drift exceeds allowable physics/network window or severe state divergence occurs
		if drift > max_allowed_drift or (client_hash != server_hash and drift > 1.2):
			stats["desync_count"] += 1
			stats["status"] = "DESYNC WARNING"
			var player_name: String = Network.player_names.get(peer_id, "Player %d" % peer_id)
			print("[Desync Detection] Desync detected for %s (Peer %d) at tick %d! Drift: %.2fm (Tolerance: %.2fm), Client Hash: %d, Server Hash: %d" % [
				player_name, peer_id, tick, drift, max_allowed_drift, client_hash, server_hash
			])
			desync_detected.emit(peer_id, drift, tick)
		else:
			stats["status"] = "SYNCED"

# =======================================================================
# RECONNECTION (SERVER-SIDE STATE RESTORATION)
# When a player reconnects within Network.RECONNECT_TIMEOUT seconds,
# restore their position, color, and checkpoint.
# =======================================================================

func _on_player_reconnected(new_peer_id: int, saved_state: Dictionary) -> void:
	# The player was already spawned by _on_peer_connected -> _request_spawn.
	# Now we override their state with the saved values.
	# Use call_deferred to ensure the spawn has fully completed.
	call_deferred("_apply_reconnect_state", new_peer_id, saved_state)

func _apply_reconnect_state(new_peer_id: int, saved_state: Dictionary) -> void:
	var p_node = players_root.get_node_or_null(str(new_peer_id))
	if p_node and p_node is CharacterBody3D:
		p_node.player_color_index = saved_state.get("color_index", 0)

	# Tell the reconnecting client to restore their position and checkpoint.
	# We can't set position from the server because the client is the authority
	# for their own CharacterBody3D (position is replicated FROM authority).
	var pos: Vector3 = saved_state.get("position", Vector3.ZERO)
	var respawn_pos: Vector3 = saved_state.get("respawn_position", pos)
	_restore_player_state.rpc_id(new_peer_id, pos, respawn_pos)

	var username: String = Network.player_names.get(new_peer_id, "Player %d" % new_peer_id)
	_broadcast_system_message.rpc("%s reconnected to the game!" % username)

	# If the game already started, auto-ready them and show chat
	if game_started:
		if not new_peer_id in ready_peers:
			ready_peers.append(new_peer_id)
		_sync_game_started_to_peer.rpc_id(new_peer_id, true)

## Client-side: restore position and checkpoint after reconnection.
@rpc("authority", "reliable")
func _restore_player_state(pos: Vector3, respawn_pos: Vector3) -> void:
	var my_id: int = multiplayer.get_unique_id()
	var p_node = players_root.get_node_or_null(str(my_id))
	if p_node and p_node is CharacterBody3D:
		p_node.global_position = pos
		p_node.velocity = Vector3.ZERO
		p_node.respawn_position = respawn_pos

## Client-side: sync match-in-progress state for late joiners and reconnected peers.
@rpc("authority", "reliable")
func _sync_game_started_to_peer(is_started: bool) -> void:
	game_started = is_started
	var ready_ui = get_node_or_null("ReadyUI/Control")
	if ready_ui and ready_ui.has_method("hide_ui"):
		ready_ui.hide_ui()
	var chat_ui = get_node_or_null("ChatUI/Control")
	if chat_ui and chat_ui.has_method("show_ui"):
		chat_ui.show_ui()
	if is_started:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
