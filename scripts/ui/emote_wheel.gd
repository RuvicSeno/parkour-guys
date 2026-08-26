class_name EmoteWheel
extends Control

## EmoteWheel - Radial menu for selecting and playing character emotes.
## Supports mouse and joystick navigation, hold-to-open (release to confirm),
## toggle mode, and real-time multiplayer synchronization.

signal emote_selected(emote: Emote)
signal wheel_opened
signal wheel_closed

@export var emotes: Array[Emote] = []
@export var inner_radius: float = 45.0
@export var outer_radius: float = 160.0
@export var deadzone_radius: float = 30.0

# Styling
@export var bg_color: Color = Color(0.08, 0.09, 0.12, 0.8)
@export var segment_color: Color = Color(0.12, 0.14, 0.18, 0.85)
@export var highlight_color: Color = Color(0.22, 0.65, 0.95, 0.9)
@export var border_color: Color = Color(0.35, 0.4, 0.5, 0.7)
@export var highlight_border_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var text_color: Color = Color(0.95, 0.95, 0.95, 1.0)
@export var text_highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var center_hub_color: Color = Color(0.05, 0.06, 0.08, 0.9)

var is_open: bool = false
var selected_index: int = -1
var cursor_offset: Vector2 = Vector2.ZERO
var center_position: Vector2 = Vector2.ZERO
var open_time: float = 0.0

@onready var center_label: Label = $CenterContainer/Label if has_node("CenterContainer/Label") else null

func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Load default emotes if array is empty
	if emotes.is_empty():
		_load_default_emotes()

func _load_default_emotes() -> void:
	var default_paths: Array[String] = [
		"res://resources/emotes/flair.tres",
		"res://resources/emotes/rumba_dancing.tres",
		"res://resources/emotes/silly_dancing.tres",
		"res://resources/emotes/standing_pose.tres"
	]
	for path in default_paths:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is Emote:
				emotes.append(res)

func _process(_delta: float) -> void:
	if not is_open:
		return

	# Handle gamepad stick input
	var stick_dir: Vector2 = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X if abs(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)) > 0.3 else JOY_AXIS_LEFT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y if abs(Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)) > 0.3 else JOY_AXIS_LEFT_Y)
	)

	if stick_dir.length_squared() > 0.2:
		cursor_offset = stick_dir.normalized() * (inner_radius + outer_radius) * 0.5
		_update_selection_from_offset(cursor_offset)
		queue_redraw()

func _input(event: InputEvent) -> void:
	# Toggle/open on 'R' or 'emote_wheel' action
	if event.is_action_pressed("emote_wheel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R):
		var world_node = get_tree().current_scene
		var chat_ui = world_node.get_node_or_null("ChatUI/Control") if world_node else null
		if chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused():
			return

		if not is_open:
			get_viewport().set_input_as_handled()
			open_wheel()
			return
		else:
			# Pressing R again closes / confirms
			get_viewport().set_input_as_handled()
			_confirm_and_close()
			return

	if not is_open:
		return

	# Close on ESC
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_wheel(false)
		return

	# Track mouse motion
	if event is InputEventMouseMotion:
		cursor_offset = event.position - center_position
		_update_selection_from_offset(cursor_offset)
		queue_redraw()

	# Confirm on Left Mouse Click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_viewport().set_input_as_handled()
		_confirm_and_close()
		return

	# Release 'R' to confirm (Hold-to-open mode)
	if event.is_action_released("emote_wheel") or (event is InputEventKey and not event.pressed and event.keycode == KEY_R):
		# If user held R and dragged to a slice, release confirms and closes
		var hold_duration: float = (Time.get_ticks_msec() / 1000.0) - open_time
		if hold_duration > 0.18 and selected_index >= 0:
			get_viewport().set_input_as_handled()
			_confirm_and_close()

func open_wheel() -> void:
	if is_open or emotes.is_empty():
		return

	is_open = true
	selected_index = -1
	cursor_offset = Vector2.ZERO
	open_time = Time.get_ticks_msec() / 1000.0

	# Center on screen
	center_position = get_viewport_rect().size * 0.5
	position = Vector2.ZERO
	size = get_viewport_rect().size

	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	wheel_opened.emit()
	queue_redraw()

func close_wheel(trigger_selected: bool = true) -> void:
	if not is_open:
		return

	is_open = false
	hide()

	var world_node = get_tree().current_scene
	var match_active: bool = world_node and "game_started" in world_node and world_node.game_started
	if match_active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	wheel_closed.emit()

	if trigger_selected and selected_index >= 0 and selected_index < emotes.size():
		var chosen: Emote = emotes[selected_index]
		emote_selected.emit(chosen)

func _confirm_and_close() -> void:
	close_wheel(selected_index >= 0)

func _update_selection_from_offset(offset: Vector2) -> void:
	var dist: float = offset.length()
	if dist < deadzone_radius or emotes.is_empty():
		selected_index = -1
		return

	var angle: float = offset.angle() # [-PI, PI]
	var n: int = emotes.size()
	var step: float = (2.0 * PI) / float(n)

	# Align top (-PI/2) as the center of slice 0
	# Shift angle so slice 0 starts at -PI/2 - step/2
	var shifted: float = wrapf(angle + (PI * 0.5) + (step * 0.5), 0.0, 2.0 * PI)
	var idx: int = int(floor(shifted / step)) % n
	selected_index = clamp(idx, 0, n - 1)

func _draw() -> void:
	if not is_open or emotes.is_empty():
		return

	var center: Vector2 = center_position
	var n: int = emotes.size()
	var step: float = (2.0 * PI) / float(n)

	# 1. Dark background overlay
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.4))

	# 2. Draw each radial slice
	for i in range(n):
		var start_ang: float = (-PI * 0.5) - (step * 0.5) + (float(i) * step)
		var end_ang: float = start_ang + step
		var is_selected: bool = (i == selected_index)

		var cur_outer: float = outer_radius + (12.0 if is_selected else 0.0)
		var cur_inner: float = inner_radius

		var col: Color = highlight_color if is_selected else segment_color
		var b_col: Color = highlight_border_color if is_selected else border_color

		_draw_arc_segment(center, cur_inner, cur_outer, start_ang, end_ang, col, b_col, 2.5 if is_selected else 1.5)

		# Draw icon or text
		var mid_ang: float = (start_ang + end_ang) * 0.5
		var mid_rad: float = (cur_inner + cur_outer) * 0.5
		var item_pos: Vector2 = center + Vector2(cos(mid_ang), sin(mid_ang)) * mid_rad

		var emote_data: Emote = emotes[i]
		if emote_data.icon:
			var icon_sz: Vector2 = Vector2(36, 36)
			var icon_rect: Rect2 = Rect2(item_pos - icon_sz * 0.5, icon_sz)
			draw_texture_rect(emote_data.icon, icon_rect, false, Color.WHITE)
		else:
			var font := ThemeDB.fallback_font
			var font_size: int = 15 if not is_selected else 17
			var text_str: String = emote_data.display_name
			var str_sz: Vector2 = font.get_string_size(text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var t_pos: Vector2 = item_pos - Vector2(str_sz.x * 0.5, -str_sz.y * 0.3)

			# Drop shadow
			draw_string(font, t_pos + Vector2(1, 1), text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, 0.8))
			draw_string(font, t_pos, text_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_highlight_color if is_selected else text_color)

	# 3. Center Hub Circle
	draw_circle(center, inner_radius - 2.0, center_hub_color)
	draw_arc(center, inner_radius - 2.0, 0, 2.0 * PI, 64, border_color, 2.0)

	# 4. Center Label & Direction Indicator
	var c_font := ThemeDB.fallback_font
	if selected_index >= 0 and selected_index < emotes.size():
		var sel_emote: Emote = emotes[selected_index]
		var name_sz: Vector2 = c_font.get_string_size(sel_emote.display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		var center_text_pos: Vector2 = center - Vector2(name_sz.x * 0.5, -name_sz.y * 0.3)
		draw_string(c_font, center_text_pos, sel_emote.display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, highlight_color)

		# Small pointer arrow
		var pointer_ang: float = (-PI * 0.5) + (float(selected_index) * step)
		var p_start: Vector2 = center + Vector2(cos(pointer_ang), sin(pointer_ang)) * (inner_radius - 12.0)
		var p_end: Vector2 = center + Vector2(cos(pointer_ang), sin(pointer_ang)) * (inner_radius - 4.0)
		draw_line(p_start, p_end, highlight_color, 3.0)
	else:
		var prompt: String = "Select"
		var p_sz: Vector2 = c_font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var center_text_pos: Vector2 = center - Vector2(p_sz.x * 0.5, -p_sz.y * 0.3)
		draw_string(c_font, center_text_pos, prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.6, 0.6, 0.6, 0.8))

## Helper to draw an anti-aliased annular sector (pie slice) with borders
func _draw_arc_segment(center: Vector2, r_inner: float, r_outer: float, a_start: float, a_end: float, fill_col: Color, stroke_col: Color, stroke_width: float) -> void:
	var segments_count: int = max(6, int(abs(a_end - a_start) / (PI / 16.0)))
	var pts_outer: PackedVector2Array = PackedVector2Array()
	var pts_inner: PackedVector2Array = PackedVector2Array()

	for i in range(segments_count + 1):
		var t: float = float(i) / float(segments_count)
		var ang: float = lerp_angle(a_start, a_end, t)
		pts_outer.append(center + Vector2(cos(ang), sin(ang)) * r_outer)
		pts_inner.append(center + Vector2(cos(ang), sin(ang)) * r_inner)

	var poly_pts: PackedVector2Array = PackedVector2Array()
	poly_pts.append_array(pts_outer)
	for j in range(pts_inner.size() - 1, -1, -1):
		poly_pts.append(pts_inner[j])

	draw_colored_polygon(poly_pts, fill_col)

	# Draw border lines
	var outline_pts: PackedVector2Array = poly_pts.duplicate()
	outline_pts.append(poly_pts[0])
	draw_polyline(outline_pts, stroke_col, stroke_width, true)
