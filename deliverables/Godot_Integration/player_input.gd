class_name PlayerInputBuffer
extends RefCounted

## Data structure for a timestamped, sequence-numbered player input command.
class InputCommand:
	var sequence_number: int = 0
	var timestamp: float = 0.0
	var input_vector: Vector2 = Vector2.ZERO
	var jump: bool = false
	var delta_time: float = 0.0

	func _init(p_seq: int, p_time: float, p_input: Vector2, p_jump: bool, p_delta: float) -> void:
		sequence_number = p_seq
		timestamp = p_time
		input_vector = p_input
		jump = p_jump
		delta_time = p_delta

	func to_dict() -> Dictionary:
		return {
			"seq": sequence_number,
			"time": timestamp,
			"input": input_vector,
			"jump": jump,
			"dt": delta_time
		}

	static func from_dict(d: Dictionary) -> InputCommand:
		return InputCommand.new(
			d.get("seq", 0),
			d.get("time", 0.0),
			d.get("input", Vector2.ZERO),
			d.get("jump", false),
			d.get("dt", 0.0)
		)

var buffer: Array[InputCommand] = []
var max_buffer_size: int = 256
var next_sequence: int = 1

func enqueue_input(input_vector: Vector2, jump: bool, delta_time: float) -> InputCommand:
	var cmd = InputCommand.new(
		next_sequence,
		Time.get_ticks_usec() / 1000000.0,
		input_vector,
		jump,
		delta_time
	)
	next_sequence += 1
	buffer.append(cmd)
	if buffer.size() > max_buffer_size:
		buffer.pop_front()
	return cmd

## Drops all commands with sequence <= last_ack_sequence (Step 5.3)
func remove_acknowledged(last_ack_sequence: int) -> void:
	var i = 0
	while i < buffer.size():
		if buffer[i].sequence_number <= last_ack_sequence:
			buffer.remove_at(i)
		else:
			i += 1

func get_pending_commands() -> Array[InputCommand]:
	return buffer

func clear() -> void:
	buffer.clear()
	next_sequence = 1
