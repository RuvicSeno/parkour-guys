extends Control

## Lobby UI — lets the player host or join a LAN game.
## Replaces the old DebugConnect placeholder (Step 7).

@onready var ip_line_edit: LineEdit = $VBoxContainer/IPLineEdit
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# Listen for connection results so we can show feedback / re-enable UI.
	Network.connection_succeeded.connect(_on_connection_succeeded)
	Network.connection_failed_to_server.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	_set_buttons_enabled(false)
	var error: Error = Network.host_game()
	if error != OK:
		status_label.text = "Failed to start server (error %d)" % error
		_set_buttons_enabled(true)
		return
	status_label.text = "Server started. Waiting for players..."
	# Give a brief moment so the status is visible, then dismiss.
	_dismiss()

func _on_join_pressed() -> void:
	var ip: String = ip_line_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	_set_buttons_enabled(false)
	status_label.text = "Connecting to %s..." % ip
	var error: Error = Network.join_game(ip)
	if error != OK:
		status_label.text = "Failed to connect (error %d)" % error
		_set_buttons_enabled(true)

func _on_connection_succeeded() -> void:
	status_label.text = "Connected!"
	_dismiss()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the IP and try again."
	_set_buttons_enabled(true)

func _set_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled

func _dismiss() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
