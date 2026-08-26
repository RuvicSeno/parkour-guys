extends CharacterBody3D

@export var move_speed: float = 5.5
@export var jump_velocity: float = 6.0
@export var rotation_speed: float = 10.0
@export var mouse_sensitivity: float = 0.003
@export var camera_pitch_min_deg: float = -60.0
@export var camera_pitch_max_deg: float = 10.0

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2),
	Color(0.2, 0.5, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.8, 0.1),
	Color(0.8, 0.2, 0.8),
	Color(0.1, 0.8, 0.8),
	Color(0.9, 0.5, 0.1),
	Color(0.9, 0.4, 0.6)
]

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var visual: Node3D = $CollisionShape3D/Visual
@onready var stick_man: Node3D = $CollisionShape3D/Visual/StickMan
@onready var name_label: Label3D = $NameLabel3D
@onready var chat_bubbles: Node3D = $ChatBubbles
@onready var jump_sfx: AudioStreamPlayer3D = $JumpSFX
@onready var running_sfx: AudioStreamPlayer3D = $RunningSFX

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var respawn_position: Vector3
var animation_player: AnimationPlayer

# Desync detection state & history
var physics_tick: int = 0
var state_history: Array[Dictionary] = []
const MAX_STATE_HISTORY: int = 120
const DESYNC_CHECK_INTERVAL: int = 10

# Synchronized transform properties (replicated via MultiplayerSynchronizer)
var sync_position: Vector3 = Vector3.ZERO: set = _set_sync_position
var sync_velocity: Vector3 = Vector3.ZERO
var sync_rotation: Vector3 = Vector3.ZERO: set = _set_sync_rotation

# Latency simulation playback buffer for remote instances
var _latency_buffer: Array[Dictionary] = []
const MAX_LATENCY_BUFFER_SIZE: int = 180

func _set_sync_position(val: Vector3) -> void:
	sync_position = val
	if not is_multiplayer_authority():
		_latency_buffer.append({
			"time": Time.get_ticks_msec() / 1000.0,
			"pos": val,
			"rot": sync_rotation,
			"vel": sync_velocity
		})
		if _latency_buffer.size() > MAX_LATENCY_BUFFER_SIZE:
			_latency_buffer.pop_front()

func _set_sync_rotation(val: Vector3) -> void:
	sync_rotation = val

# NEW: replicated animation state. Every peer reads this and plays it locally.
# Add ".:anim_state" to the MultiplayerSynchronizer's replication config
# (spawn: true, mode: sync/on change) alongside position/velocity.
var anim_state: String = "idle": set = _set_anim_state
var current_emote: Emote = null
var is_emoting: bool = false

func _ready() -> void:
	respawn_position = global_position
	sync_position = global_position
	if visual:
		sync_rotation = visual.rotation

	_setup_animations()
	_setup_visuals()
	_apply_animation(anim_state)

	# Name may arrive after this node spawns (e.g. late-join race), so
	# refresh the label whenever the registry updates.
	if not Network.player_names_updated.is_connected(_setup_visuals):
		Network.player_names_updated.connect(_setup_visuals)
	
	if animation_player and not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)

	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		set_process(true)
		camera.current = false
		return

	set_process(false)
	camera.current = true

func _setup_animations() -> void:
	if not stick_man:
		return

	animation_player = stick_man.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if not animation_player:
		animation_player = AnimationPlayer.new()
		animation_player.name = "AnimationPlayer"
		stick_man.add_child(animation_player)

	var anim_sources = {
		"idle": preload("res://assets/animations/Idle.fbx"),
		"running": preload("res://assets/animations/Running.fbx"),
		"running_jump": preload("res://assets/animations/Jump.fbx"),
		"falling_idle": preload("res://assets/animations/Falling Idle.fbx")
	}

	var lib := AnimationLibrary.new()
	for anim_key in anim_sources:
		var scene: PackedScene = anim_sources[anim_key]
		if scene:
			var inst = scene.instantiate()
			var source_ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if source_ap and source_ap.get_animation_list().size() > 0:
				var list = source_ap.get_animation_list()
				var src_name: String = ""
				
				# 1. Prefer exact match for key if present
				if anim_key in list:
					src_name = anim_key
				# 2. Prefer "mixamo_com" (default FBX imported clip name)
				elif "mixamo_com" in list:
					src_name = "mixamo_com"
				# 3. Look for partial match (case insensitive)
				else:
					for a_name in list:
						if anim_key.replace("running_jump", "jump") in a_name.to_lower():
							src_name = a_name
							break

				if src_name == "":
					src_name = list[0]

				var anim: Animation = source_ap.get_animation(src_name).duplicate()
				anim.loop_mode = Animation.LOOP_LINEAR if anim_key in ["idle", "running", "falling_idle"] else Animation.LOOP_NONE
				lib.add_animation(anim_key, anim)
			inst.queue_free()

	# Dynamically load default emote animations
	var default_emote_paths: Array[String] = [
		"res://resources/emotes/flair.tres",
		"res://resources/emotes/rumba_dancing.tres",
		"res://resources/emotes/silly_dancing.tres",
		"res://resources/emotes/standing_pose.tres"
	]
	for ep in default_emote_paths:
		if ResourceLoader.exists(ep):
			var em_res = load(ep)
			if em_res is Emote and em_res.animation_scene and em_res.animation_name != "":
				var inst = em_res.animation_scene.instantiate()
				var source_ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
				if source_ap and source_ap.get_animation_list().size() > 0:
					var list = source_ap.get_animation_list()
					var src_name: String = ""
					if em_res.animation_name in list:
						src_name = em_res.animation_name
					elif "mixamo_com" in list:
						src_name = "mixamo_com"
					else:
						src_name = list[0]

					var anim: Animation = source_ap.get_animation(src_name).duplicate()
					anim.loop_mode = Animation.LOOP_LINEAR if em_res.is_looping else Animation.LOOP_NONE
					lib.add_animation(em_res.animation_name, anim)
				inst.queue_free()

	if animation_player.has_animation_library(""):
		var main_lib = animation_player.get_animation_library("")
		for anim_key in lib.get_animation_list():
			main_lib.add_animation(anim_key, lib.get_animation(anim_key))
	else:
		animation_player.add_animation_library("", lib)

# Replicated player color index assigned by world spawner
var player_color_index: int = 0: set = _set_player_color_index

func _set_player_color_index(val: int) -> void:
	player_color_index = val
	if is_inside_tree():
		_setup_visuals()

func _setup_visuals() -> void:
	if not is_inside_tree() or multiplayer == null:
		return

	var auth_id: int = get_multiplayer_authority()
	var color_idx: int = abs(player_color_index) % PLAYER_COLORS.size()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLAYER_COLORS[color_idx]
	mat.roughness = 0.3

	if stick_man:
		var meshes = stick_man.find_children("*", "MeshInstance3D", true, false)
		for mesh_node in meshes:
			if mesh_node is MeshInstance3D:
				mesh_node.material_override = mat

	if name_label:
		var display_name: String = Network.player_names.get(auth_id, "Player %d" % auth_id)
		if auth_id == multiplayer.get_unique_id():
			name_label.text = "YOU (%s)" % display_name
			name_label.modulate = Color(0.3, 1.0, 0.5)
		else:
			name_label.text = display_name
			name_label.modulate = Color(1.0, 1.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	var world_node = get_tree().current_scene
	var match_active: bool = world_node and "game_started" in world_node and world_node.game_started

	var chat_ui = world_node.get_node_or_null("ChatUI/Control") if world_node else null
	if chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused():
		return

	var emote_wheel = world_node.get_node_or_null("EmoteWheel/Control") if world_node else null
	if emote_wheel and "is_open" in emote_wheel and emote_wheel.is_open:
		return

	# During gameplay: ESC releases cursor, click re-captures it
	if match_active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		if event is InputEventMouseButton and event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		spring_arm.rotation.x -= event.relative.y * mouse_sensitivity
		spring_arm.rotation.x = clamp(
			spring_arm.rotation.x,
			deg_to_rad(camera_pitch_min_deg),
			deg_to_rad(camera_pitch_max_deg)
		)

func _physics_process(delta: float) -> void:
	physics_tick += 1

	# Always apply gravity first so move_and_slide maintains solid floor contact
	velocity.y -= gravity * delta

	var world_node = get_tree().current_scene
	var chat_ui = world_node.get_node_or_null("ChatUI/Control") if world_node else null
	var chat_focused: bool = chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused()

	if (world_node and "game_started" in world_node and not world_node.game_started) or chat_focused:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()

		if is_emoting:
			stop_emote()
		else:
			anim_state = "idle"
		_record_state_and_report()
		return

	var jumped: bool = false
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		jumped = true
		if jump_sfx:
			jump_sfx.play()

	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var has_movement_input: bool = input_dir.length_squared() > 0.0

	# Emote cancellation / movement handling
	if is_emoting:
		if current_emote and current_emote.lock_movement:
			# Locked emote: cancel movement vector
			has_movement_input = false
			input_dir = Vector2.ZERO
			if jumped:
				stop_emote()
		else:
			# Normal emote: moving or jumping immediately cancels emote
			if has_movement_input or jumped or not is_on_floor():
				is_emoting = false
				current_emote = null

	if has_movement_input:
		var forward: Vector3 = -camera_pivot.global_transform.basis.z
		var right: Vector3 = camera_pivot.global_transform.basis.x

		var direction: Vector3 = (right * input_dir.x - forward * input_dir.y)
		direction.y = 0.0
		direction = direction.normalized()

		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

		var target_angle: float = atan2(direction.x, direction.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()

	if not is_emoting:
		_update_animation_and_audio(has_movement_input, jumped)
	else:
		if running_sfx and running_sfx.playing:
			running_sfx.stop()

	sync_position = global_position
	sync_velocity = velocity
	if visual:
		sync_rotation = visual.rotation

	_record_state_and_report()

	# Void Area
	if global_position.y < -10.0:
		velocity = Vector3.ZERO
		global_position = respawn_position
		sync_position = global_position
		if is_emoting:
			stop_emote()

func play_emote(emote: Emote) -> void:
	if not is_multiplayer_authority() or emote == null:
		return
	current_emote = emote
	is_emoting = true
	anim_state = emote.animation_name

func stop_emote() -> void:
	if not is_multiplayer_authority():
		return
	current_emote = null
	is_emoting = false
	anim_state = "idle"

func _on_animation_finished(anim_name: StringName) -> void:
	if not is_multiplayer_authority():
		return
	if is_emoting and anim_state == String(anim_name):
		if current_emote and not current_emote.is_looping:
			stop_emote()

func _process(_delta: float) -> void:
	if is_multiplayer_authority():
		return

	# If no artificial latency or empty buffer, apply latest replicated state immediately
	if Network.simulated_latency_ms <= 0 or _latency_buffer.is_empty():
		global_position = sync_position
		if visual:
			visual.rotation = sync_rotation
		return

	var current_time: float = Time.get_ticks_msec() / 1000.0
	var render_time: float = current_time - (Network.simulated_latency_ms / 1000.0)

	# Clean up older snapshots beyond render_time window
	while _latency_buffer.size() > 2 and _latency_buffer[1]["time"] < render_time:
		_latency_buffer.pop_front()

	if _latency_buffer.is_empty():
		global_position = sync_position
		if visual:
			visual.rotation = sync_rotation
		return

	if render_time <= _latency_buffer[0]["time"]:
		global_position = _latency_buffer[0]["pos"]
		if visual:
			visual.rotation = _latency_buffer[0]["rot"]
		return

	if render_time >= _latency_buffer[-1]["time"]:
		global_position = _latency_buffer[-1]["pos"]
		if visual:
			visual.rotation = _latency_buffer[-1]["rot"]
		return

	# Interpolate between the two snapshots surrounding render_time
	for i in range(_latency_buffer.size() - 1):
		var s0: Dictionary = _latency_buffer[i]
		var s1: Dictionary = _latency_buffer[i + 1]
		if s0["time"] <= render_time and render_time <= s1["time"]:
			var duration: float = s1["time"] - s0["time"]
			var factor: float = 0.0 if duration <= 0.0001 else (render_time - s0["time"]) / duration
			if s0["pos"].distance_squared_to(s1["pos"]) > 25.0:
				global_position = s1["pos"]
			else:
				global_position = s0["pos"].lerp(s1["pos"], factor)

			if visual:
				var r0: Vector3 = s0["rot"]
				var r1: Vector3 = s1["rot"]
				visual.rotation.y = lerp_angle(r0.y, r1.y, factor)
				visual.rotation.x = lerp(r0.x, r1.x, factor)
				visual.rotation.z = lerp(r0.z, r1.z, factor)
			break

func _update_animation_and_audio(is_moving: bool, just_jumped: bool) -> void:
	var target_anim: String = "idle"

	if is_on_floor():
		if is_moving:
			target_anim = "running"
			if running_sfx and not running_sfx.playing:
				running_sfx.play()
		else:
			target_anim = "idle"
			if running_sfx and running_sfx.playing:
				running_sfx.stop()
	else:
		if running_sfx and running_sfx.playing:
			running_sfx.stop()

		if velocity.y > 0.0 or just_jumped:
			target_anim = "running_jump"
		else:
			target_anim = "falling_idle"

	anim_state = target_anim

func _set_anim_state(value: String) -> void:
	anim_state = value
	_apply_animation(value)

func _apply_animation(target_anim: String) -> void:
	if animation_player and animation_player.has_animation(target_anim):
		if animation_player.current_animation != target_anim:
			animation_player.play(target_anim)

func set_checkpoint(new_pos: Vector3) -> void:
	if is_multiplayer_authority():
		respawn_position = new_pos
		# Notify the server of our new checkpoint so it can save it
		# for potential reconnection state restoration.
		if not multiplayer.is_server():
			_sync_checkpoint.rpc_id(1, new_pos)

## Client -> Server. Keeps the server's copy of respawn_position up to date.
@rpc("any_peer", "reliable")
func _sync_checkpoint(pos: Vector3) -> void:
	if multiplayer.is_server():
		respawn_position = pos

# --- DESYNC DETECTION (STATE SNAPSHOT & HASHING) ---

func get_state_snapshot(tick: int) -> Dictionary:
	return {
		"tick": tick,
		"pos": global_position,
		"vel": velocity,
		"anim": anim_state,
		"respawn": respawn_position
	}

func compute_state_hash(snapshot: Dictionary) -> int:
	var pos: Vector3 = snapshot.get("pos", Vector3.ZERO)
	var vel: Vector3 = snapshot.get("vel", Vector3.ZERO)
	var anim: String = snapshot.get("anim", "")
	# Quantize values to 1 decimal place (10cm precision) for stable network replication verification
	var state_str: String = "%d|%.1f,%.1f,%.1f|%.1f,%.1f,%.1f|%s" % [
		snapshot.get("tick", 0),
		snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(pos.z, 0.1),
		snappedf(vel.x, 0.1), snappedf(vel.y, 0.1), snappedf(vel.z, 0.1),
		anim
	]
	return hash(state_str)

func _record_state_and_report() -> void:
	var snapshot: Dictionary = get_state_snapshot(physics_tick)
	var current_hash: int = compute_state_hash(snapshot)
	snapshot["hash"] = current_hash
	state_history.append(snapshot)
	if state_history.size() > MAX_STATE_HISTORY:
		state_history.pop_front()

	if not is_multiplayer_authority():
		return

	# Periodically report state checksum to server
	if physics_tick % DESYNC_CHECK_INTERVAL == 0 and multiplayer != null and multiplayer.multiplayer_peer != null:
		var world_node = get_tree().current_scene
		if multiplayer.is_server():
			if world_node and world_node.has_method("verify_desync_report"):
				world_node.verify_desync_report(1, physics_tick, current_hash, global_position, velocity)
		else:
			_report_state_hash.rpc_id(1, physics_tick, current_hash, global_position, velocity)

## Client -> Server. Sends state checksum and position snapshot to server for desync verification.
@rpc("any_peer", "unreliable")
func _report_state_hash(tick: int, client_hash: int, pos: Vector3, vel: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	var world_node = get_tree().current_scene
	if world_node and world_node.has_method("verify_desync_report"):
		world_node.verify_desync_report(sender_id, tick, client_hash, pos, vel)

## Server -> Client. Forces player to reconcile state if severe desync occurs or admin runs /resync.
@rpc("authority", "call_local", "reliable")
func _force_reconcile_state(new_pos: Vector3, new_vel: Vector3) -> void:
	if is_multiplayer_authority():
		global_position = new_pos
		velocity = new_vel

const SPEECH_BUBBLE_SCENE: PackedScene = preload("res://scenes/ui/SpeechBubble3D.tscn")
var active_bubbles: Array[Node3D] = []

# --- FLOATING CHAT BUBBLES ---

func add_chat_bubble(message: String) -> void:
	if chat_bubbles == null:
		return

	# Stack up to 3: drop the oldest bubble if limit reached
	if active_bubbles.size() >= 3:
		var oldest: Node3D = active_bubbles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var bubble: Node3D = SPEECH_BUBBLE_SCENE.instantiate()
	if bubble.has_method("set_text"):
		bubble.set_text(message)

	chat_bubbles.add_child(bubble)
	active_bubbles.append(bubble)

	_update_bubble_positions()

	# Lifespan: 5s total (stay visible 4.5s, fade out over 0.5s)
	var timer := get_tree().create_timer(4.5)
	timer.timeout.connect(func():
		if is_instance_valid(bubble):
			if bubble.has_method("fade_out_and_free"):
				_remove_bubble_from_stack(bubble)
				bubble.fade_out_and_free(0.5)
			else:
				_remove_bubble_from_stack(bubble)
				bubble.queue_free()
	)

func _remove_bubble_from_stack(bubble: Node3D) -> void:
	if bubble in active_bubbles:
		active_bubbles.erase(bubble)
		_update_bubble_positions()

func _update_bubble_positions() -> void:
	var total: int = active_bubbles.size()
	var current_y: float = 0.0
	for i in range(total - 1, -1, -1):
		var bubble: Node3D = active_bubbles[i]
		if is_instance_valid(bubble):
			var pos_tween := create_tween()
			pos_tween.tween_property(bubble, "position:y", current_y, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			var bubble_height: float = 0.3
			if bubble.has_method("get_bubble_height_3d"):
				bubble_height = bubble.get_bubble_height_3d()
			current_y += bubble_height + 0.08
