extends Control

## Win Banner UI - displays announcements when players finish the course.

@onready var win_label: Label = $PanelContainer/VBoxContainer/WinLabel
@onready var rank_label: Label = $PanelContainer/VBoxContainer/RankLabel
@onready var victory_sfx: AudioStreamPlayer = $VictorySFX

func _ready() -> void:
	hide()

func show_win(peer_id: int, rank: int) -> void:
	var my_id: int = multiplayer.get_unique_id()
	if peer_id == my_id:
		win_label.text = "QUALIFIED!"
		win_label.modulate = Color(0.2, 0.9, 0.4)
		rank_label.text = "You finished in #%d place!" % rank
	else:
		win_label.text = "PLAYER %d FINISHED!" % peer_id
		win_label.modulate = Color(0.9, 0.8, 0.2)
		rank_label.text = "Finished in #%d place" % rank

	if victory_sfx:
		victory_sfx.play()

	show()
	await get_tree().create_timer(4.0).timeout
	hide()
