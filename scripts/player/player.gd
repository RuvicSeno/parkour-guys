extends CharacterBody3D

@export var move_speed: float = 6.0
@export var jump_velocity: float = 8.0
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
	
	print("[player %s] my_id=%d node_authority=%d is_auth=%s" % [
		name, multiplayer.get_unique_id(), get_multiplayer_authority(), is_multiplayer_authority()
	])
	
	if not is_multiplayer_authority():
		set_physics_process(false)
		set_process_unhandled_input(false)
		camera.current = false
		set_process(true)  # NEW: remote peers still need _process to react to anim_state changes
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
				var src_name: String = source_ap.get_animation_list()[0]
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

	# NEW: debug print so you can verify track paths resolve against stick_man.
	# Delete this block once animations are confirmed working.
	if animation_player.has_animation_library(""):
		var check_lib := animation_player.get_animation_library("")
		for key in check_lib.get_animation_list():
			var a: Animation = check_lib.get_animation(key)
			if a.get_track_count() > 0:
				print("[anim debug] '%s' track 0 path: %s" % [key, a.track_get_path(0)])
			else:
				print("[anim debug] '%s' has NO tracks after duplicate!" % key)

func _setup_visuals() -> void:
	var auth_id: int = get_multiplayer_authority()
	var color_idx: int = abs(auth_id) % PLAYER_COLORS.size()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLAYER_COLORS[color_idx]
	mat.roughness = 0.3

	if stick_man:
		var meshes = stick_man.find_children("*", "MeshInstance3D", true, false)
		for mesh_node in meshes:
			if mesh_node is MeshInstance3D:
				mesh_node.material_override = mat

	if auth_id == multiplayer.get_unique_id():
		name_label.text = "YOU (P%d)" % auth_id
		name_label.modulate = Color(0.3, 1.0, 0.5)
	else:
		name_label.text = "Player %d" % auth_id
		name_label.modulate = Color(1.0, 1.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	if not is_on_floor():
		velocity.y -= gravity * delta

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

	# CHANGED: authority sets the replicated var (which triggers _set_anim_state
	# locally too, so the authority's own screen still animates as before).
	anim_state = target_anim

# NEW: setter fires on the authority (local change) AND on remote peers
# (when MultiplayerSynchronizer applies an incoming value).
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
