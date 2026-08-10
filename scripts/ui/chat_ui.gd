extends Control

## ChatUI - Bottom-left chat window with scrollable history and '/' hotkey.

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

@onready var rich_text_label: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/RichTextLabel
@onready var line_edit: LineEdit = $PanelContainer/MarginContainer/VBoxContainer/LineEdit

func _ready() -> void:
	# Hide by default; shown only when match starts
	hide()

	line_edit.text_submitted.connect(_on_line_edit_text_submitted)
	line_edit.focus_entered.connect(_on_line_edit_focus_entered)
	line_edit.focus_exited.connect(_on_line_edit_focus_exited)

func show_ui() -> void:
	show()

func hide_ui() -> void:
	hide()
	if line_edit and line_edit.has_focus():
		line_edit.release_focus()

func is_chat_focused() -> bool:
	return line_edit != null and line_edit.has_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if not is_chat_focused():
			if event.keycode == KEY_SLASH:
				get_viewport().set_input_as_handled()
				open_chat()
		else:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				close_chat()

func open_chat() -> void:
	line_edit.text = ""
	line_edit.grab_focus()
	call_deferred("_clear_line_edit")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _clear_line_edit() -> void:
	if line_edit and line_edit.has_focus():
		if line_edit.text == "/":
			line_edit.text = ""
			line_edit.set_caret_column(0)

func close_chat() -> void:
	line_edit.text = ""
	line_edit.release_focus()
	var world = get_tree().current_scene
	if world and "game_started" in world and world.game_started:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_line_edit_text_submitted(new_text: String) -> void:
	var clean_text: String = new_text.strip_edges()
	if not clean_text.is_empty():
		var world = get_tree().current_scene
		if world and world.has_method("send_chat_message"):
			world.send_chat_message(clean_text)
	
	close_chat()

func _on_line_edit_focus_entered() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_line_edit_focus_exited() -> void:
	pass

func add_message(sender_id: int, sender_name: String, message: String) -> void:
	if rich_text_label == null:
		return

	# Determine player color (mirroring player color assignment if available)
	var world = get_tree().current_scene
	var color_idx: int = 0
	if world and "players_root" in world and world.players_root:
		var p_node = world.players_root.get_node_or_null(str(sender_id))
		if p_node and "player_color_index" in p_node:
			color_idx = abs(p_node.player_color_index) % PLAYER_COLORS.size()
		else:
			color_idx = abs(sender_id) % PLAYER_COLORS.size()
	else:
		color_idx = abs(sender_id) % PLAYER_COLORS.size()

	var color: Color = PLAYER_COLORS[color_idx]
	var hex_color: String = color.to_html(false)

	# Format with BBCode: [color=#hex][b]Name[/b][/color]: message
	var formatted_msg: String = "[color=#%s][b]%s[/b][/color]: %s\n" % [hex_color, sender_name.xml_escape(), message.xml_escape()]
	rich_text_label.append_text(formatted_msg)

## Displays a system message (not from a player) in the chat log.
## Used for admin actions, join/leave notifications, reconnection info, etc.
func add_system_message(message: String) -> void:
	if rich_text_label == null:
		return
	var formatted: String = "[color=#aaaaaa][i]%s[/i][/color]\n" % message.xml_escape()
	rich_text_label.append_text(formatted)

## Clears all messages from the chat display. Called by the /clear admin command.
func clear_messages() -> void:
	if rich_text_label == null:
		return
	rich_text_label.clear()
