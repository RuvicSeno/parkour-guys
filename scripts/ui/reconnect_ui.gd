extends Control

@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var return_button: Button = $PanelContainer/VBoxContainer/ReturnButton

func _ready() -> void:
	hide()
	return_button.pressed.connect(_on_return_pressed)
	
	if Network.has_signal("reconnecting"):
		Network.reconnecting.connect(_on_reconnecting)
	if Network.has_signal("reconnect_failed"):
		Network.reconnect_failed.connect(_on_reconnect_failed)
	if Network.has_signal("connection_succeeded"):
		Network.connection_succeeded.connect(_on_connection_succeeded)

func _on_reconnecting(attempt: int, max_attempts: int) -> void:
	show()
	status_label.text = "Connection lost. Reconnecting... (attempt %d/%d)" % [attempt, max_attempts]
	return_button.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_reconnect_failed() -> void:
	status_label.text = "Reconnection failed."
	return_button.show()

func _on_connection_succeeded() -> void:
	hide()

func _on_return_pressed() -> void:
	Network.disconnect_from_game()
	get_tree().reload_current_scene()
