extends CanvasLayer

@onready var loading_overlay: Control = $LoadingOverlay
@onready var loading_status_label: Label = $LoadingOverlay/VBoxContainer/StatusLabel
@onready var countdown_container: Control = $CountdownContainer
@onready var countdown_number_label: Label = $CountdownContainer/VBoxContainer/NumberLabel
@onready var countdown_sub_label: Label = $CountdownContainer/VBoxContainer/SubLabel

func _ready() -> void:
	show_loading()

func show_loading(text: String = "Loading map & synchronizing players...") -> void:
	show()
	loading_overlay.show()
	countdown_container.hide()
	loading_status_label.text = text

func hide_loading() -> void:
	loading_overlay.hide()

func show_countdown(number: int) -> void:
	show()
	loading_overlay.hide()
	countdown_container.show()

	if number > 0:
		countdown_number_label.text = str(number)
		countdown_number_label.modulate = Color(1.0, 0.88, 0.2)
		countdown_sub_label.text = "GET READY!"
		countdown_sub_label.modulate = Color(0.9, 0.9, 0.9)
	else:
		countdown_number_label.text = "GO!"
		countdown_number_label.modulate = Color(0.2, 1.0, 0.4)
		countdown_sub_label.text = "RUN!"
		countdown_sub_label.modulate = Color(0.3, 1.0, 0.5)

func hide_all() -> void:
	loading_overlay.hide()
	countdown_container.hide()
	hide()
