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

# NEW: replicated animation state. Every peer reads this and plays it locally.
# Add ".:anim_state" to the MultiplayerSynchronizer's replication config
# (spawn: true, mode: sync/on change) alongside position/velocity.
var anim_state: String = "idle": set = _set_anim_state

func _ready() -> void:
	respawn_position = global_position
	_setup_animations()
	_setup_visuals()
	_apply_animation(anim_state)

	# Name may arrive after this node spawns (e.g. late-join race), so
	# refresh the label whenever the registry updates.
	if not Network.player_names_updated.is_connected(_setup_visuals):
		Network.player_names_updated.connect(_setup_visuals)
	
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		camera.current = false
		return

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
	# Always apply gravity first so move_and_slide maintains solid floor contact
	velocity.y -= gravity * delta

	var world_node = get_tree().current_scene
	var chat_ui = world_node.get_node_or_null("ChatUI/Control") if world_node else null
	var chat_focused: bool = chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused()

	if (world_node and "game_started" in world_node and not world_node.game_started) or chat_focused:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		anim_state = "idle"
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

	if input_dir.length_squared() > 0.0:
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

	_update_animation_and_audio(input_dir.length_squared() > 0.0, jumped)
# Void Area
	if global_position.y < -10.0:
		velocity = Vector3.ZERO
		global_position = respawn_position

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
