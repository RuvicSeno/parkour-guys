extends CanvasLayer

@onready var panel: Control = $Control
@onready var resume_btn: Button = $Control/PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var interp_check: CheckBox = $Control/PanelContainer/MarginContainer/VBoxContainer/NetOptionsBox/InterpCheck
@onready var extrap_check: CheckBox = $Control/PanelContainer/MarginContainer/VBoxContainer/NetOptionsBox/ExtrapCheck
@onready var menu_btn: Button = $Control/PanelContainer/MarginContainer/VBoxContainer/MenuButton
@onready var quit_btn: Button = $Control/PanelContainer/MarginContainer/VBoxContainer/QuitButton

const LOBBY_SCENE_PATH: String = "res://scenes/lobby/Lobby.tscn"

var is_paused: bool = false

func _ready() -> void:
	panel.hide()
	resume_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	interp_check.button_pressed = Network.interpolation_enabled
	extrap_check.button_pressed = Network.extrapolation_enabled
	interp_check.toggled.connect(_on_interp_toggled)
	extrap_check.toggled.connect(_on_extrap_toggled)

	Network.interpolation_changed.connect(func(enabled: bool):
		if interp_check and interp_check.button_pressed != enabled:
			interp_check.button_pressed = enabled
	)
	Network.extrapolation_changed.connect(func(enabled: bool):
		if extrap_check and extrap_check.button_pressed != enabled:
			extrap_check.button_pressed = enabled
	)

func _on_interp_toggled(toggled_on: bool) -> void:
	Network.set_interpolation(toggled_on)

func _on_extrap_toggled(toggled_on: bool) -> void:
	Network.set_extrapolation(toggled_on)

func toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()

func pause_game() -> void:
	is_paused = true
	interp_check.button_pressed = Network.interpolation_enabled
	extrap_check.button_pressed = Network.extrapolation_enabled
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume_game() -> void:
	is_paused = false
	panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_menu_pressed() -> void:
	is_paused = false
	panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		Network.host_return_to_lobby()
	else:
		Network.disconnect_from_game()
		get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _on_quit_pressed() -> void:
	get_tree().quit()
