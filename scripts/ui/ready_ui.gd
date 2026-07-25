extends Control

## Ready UI - Overlay displaying the "Ready" button and countdown.

@onready var ready_button: Button = $PanelContainer/VBoxContainer/ReadyButton
@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel

func _ready() -> void:
	# Hide by default while in the main menu
	hide()
	ready_button.pressed.connect(_on_ready_pressed)

	# Show UI when server is created or connection succeeds
	if Network.has_signal("server_created"):
		Network.server_created.connect(show)
	if Network.has_signal("connection_succeeded"):
		Network.connection_succeeded.connect(show)

func _on_ready_pressed() -> void:
	ready_button.disabled = true
	ready_button.text = "READY!"
	var world = get_tree().current_scene
	if world and world.has_method("request_set_ready"):
		world.request_set_ready()

func update_status(ready_count: int, total_count: int) -> void:
	status_label.text = "Waiting for players... (%d/%d Ready)" % [ready_count, total_count]
	show()

func show_countdown(number: int) -> void:
	status_label.text = "%d..." % number if number > 0 else "GO!"
	show()

func hide_ui() -> void:
	hide()
