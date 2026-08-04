extends Node3D

@onready var sub_viewport: SubViewport = $SubViewport
@onready var panel_container: PanelContainer = $SubViewport/PanelContainer
@onready var sprite_3d: Sprite3D = $Sprite3D
@onready var label: Label = $SubViewport/PanelContainer/MarginContainer/Label

const MIN_WIDTH := 140
const MAX_WIDTH := 320
const MIN_HEIGHT := 44

var message_text: String = ""

func set_text(msg: String) -> void:
	message_text = msg

	if is_node_ready():
		await _update_bubble_size()

func _ready() -> void:
	sprite_3d.texture = sub_viewport.get_texture()

	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if !message_text.is_empty():
		await _update_bubble_size()

func _update_bubble_size() -> void:
	label.text = message_text

	# Force the label to wrap after MAX_WIDTH.
	label.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	label.size.x = MAX_WIDTH

	# Wait one frame so Godot recalculates the layout.
	await get_tree().process_frame

	var size := panel_container.get_combined_minimum_size()

	size.x = clamp(size.x, MIN_WIDTH, MAX_WIDTH)
	size.y = max(size.y, MIN_HEIGHT)

	sub_viewport.size = Vector2i(ceil(size.x), ceil(size.y))

func get_bubble_height_3d() -> float:
	return sub_viewport.size.y * sprite_3d.pixel_size

func fade_out_and_free(duration := 0.5) -> void:
	var tween := create_tween()
	tween.tween_property(sprite_3d, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)
