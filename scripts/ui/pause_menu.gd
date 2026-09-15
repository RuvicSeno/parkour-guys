extends CanvasLayer

@onready var panel: Control = $Control
@onready var resume_btn: Button = $Control/PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var menu_btn: Button = $Control/PanelContainer/MarginContainer/VBoxContainer/MenuButton
@onready var quit_btn: Button = $Control/PanelContainer/MarginContainer/VBoxContainer/QuitButton

const LOBBY_SCENE_PATH: String = "res://scenes/lobby/Lobby.tscn"

var is_paused: bool = false

func _ready() -> void:
	panel.hide()
	resume_btn.pressed.connect(resume_game)
	menu_btn.pressed.connect(_on_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()

func pause_game() -> void:
	is_paused = true
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
