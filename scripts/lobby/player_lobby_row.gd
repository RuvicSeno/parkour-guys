extends PanelContainer

signal color_change_requested(direction: int)

@onready var name_label: Label = $HBoxContainer/InfoVBox/NameLabel
@onready var status_label: Label = $HBoxContainer/InfoVBox/StatusLabel
@onready var prev_color_btn: Button = $HBoxContainer/PreviewContainer/PrevColorBtn
@onready var next_color_btn: Button = $HBoxContainer/PreviewContainer/NextColorBtn
@onready var sub_viewport: SubViewport = $HBoxContainer/PreviewContainer/SubViewportContainer/SubViewport
@onready var model_container: Node3D = $HBoxContainer/PreviewContainer/SubViewportContainer/SubViewport/ModelContainer

var peer_id: int = 0
var current_color_index: int = 0
var is_ready_state: bool = false
var is_local: bool = false
var stick_man_instance: Node = null

const IDLE_SCENE: PackedScene = preload("res://assets/animations/Idle.fbx")

func _ready() -> void:
	prev_color_btn.pressed.connect(func(): color_change_requested.emit(-1))
	next_color_btn.pressed.connect(func(): color_change_requested.emit(1))
	_spawn_model()

func _spawn_model() -> void:
	if stick_man_instance != null or model_container == null:
		return
	stick_man_instance = IDLE_SCENE.instantiate()
	stick_man_instance.name = "StickManPreview"
	# Position stickman in front of camera
	if stick_man_instance is Node3D:
		stick_man_instance.position = Vector3(0, -0.9, 0)
		stick_man_instance.rotation_degrees = Vector3(0, 160, 0) # Angled slightly towards camera
	model_container.add_child(stick_man_instance)
	_update_material()

func setup(p_id: int, p_name: String, c_index: int, ready_status: bool, local_user: bool, is_host: bool) -> void:
	peer_id = p_id
	current_color_index = c_index
	is_ready_state = ready_status
	is_local = local_user

	# Format Name
	var display: String = p_name if not p_name.is_empty() else ("Player %d" % p_id)
	if is_local:
		display = "[YOU] " + display
	if is_host:
		display = display + " (HOST)"
	name_label.text = display

	if is_local:
		name_label.modulate = Color(0.3, 1.0, 0.5)
	else:
		name_label.modulate = Color(1.0, 1.0, 1.0)

	# Format Ready Status
	if is_ready_state:
		status_label.text = "READY"
		status_label.modulate = Color(0.2, 0.9, 0.3)
	else:
		status_label.text = "NOT READY"
		status_label.modulate = Color(0.9, 0.6, 0.2)

	# Controls visibility: only local player can click their own color switcher
	prev_color_btn.visible = is_local
	next_color_btn.visible = is_local
	prev_color_btn.disabled = is_ready_state
	next_color_btn.disabled = is_ready_state

	_update_material()

func _update_material() -> void:
	if stick_man_instance == null:
		return
	var colors: Array[Color] = Network.PLAYER_COLORS
	var safe_idx: int = abs(current_color_index) % colors.size()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colors[safe_idx]
	mat.roughness = 0.3

	var meshes = stick_man_instance.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		if m is MeshInstance3D:
			m.material_override = mat

func _process(delta: float) -> void:
	# Gently rotate preview model for visual appeal
	if stick_man_instance and stick_man_instance is Node3D:
		stick_man_instance.rotate_y(delta * 0.8)
