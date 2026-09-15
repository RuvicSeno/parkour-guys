extends Control

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var reason_label: Label = $VBoxContainer/ReasonLabel
@onready var menu_button: Button = $VBoxContainer/HBoxContainer/MenuButton
@onready var quit_button: Button = $VBoxContainer/HBoxContainer/QuitButton

const LOBBY_SCENE_PATH: String = "res://scenes/lobby/Lobby.tscn"

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_button.pressed.connect(_on_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	if not Network.kick_reason.is_empty():
		reason_label.text = Network.kick_reason
	else:
		reason_label.text = "You were kicked by an admin."

func _on_menu_pressed() -> void:
	Network.disconnect_from_game()
	get_tree().change_scene_to_file(LOBBY_SCENE_PATH)

func _on_quit_pressed() -> void:
	get_tree().quit()
