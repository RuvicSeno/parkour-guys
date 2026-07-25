extends Control

## Leaderboard UI - Displays final rankings, Menu and Quit buttons when all players finish.

@onready var rank_list_container: VBoxContainer = $PanelContainer/VBoxContainer/RankListContainer
@onready var menu_button: Button = $PanelContainer/VBoxContainer/HBoxContainer/MenuButton
@onready var quit_button: Button = $PanelContainer/VBoxContainer/HBoxContainer/QuitButton

func _ready() -> void:
	hide()
	menu_button.pressed.connect(_on_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func display_leaderboard(finished_ranks: Array) -> void:
	# Clear previous entries
	for child in rank_list_container.get_children():
		child.queue_free()

	var my_id: int = multiplayer.get_unique_id()

	for i in range(finished_ranks.size()):
		var peer_id: int = finished_ranks[i]
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)

		var rank_str = "#%d: " % (i + 1)
		if peer_id == my_id:
			rank_str += "YOU (Player %d)" % peer_id
			label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		else:
			rank_str += "Player %d" % peer_id
			label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

		label.text = rank_str
		rank_list_container.add_child(label)

	# Show mouse cursor so player can click menu/quit
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()

func _on_menu_pressed() -> void:
	Network.disconnect_from_game()
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().quit()
