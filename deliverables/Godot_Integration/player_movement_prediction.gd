class_name PlayerMovementPrediction
extends Node

## Controller handling Client-Side Movement Prediction and Server Reconciliation in Godot.
## Demonstrates toggling between Client Prediction Mode (ON) and Server-Authoritative (OFF).

signal prediction_mode_changed(enabled: bool)
signal reconciliation_performed(drift_error: float, remaining_replays: int)

@export var is_prediction_enabled: bool = true:
	set(val):
		is_prediction_enabled = val
		prediction_mode_changed.emit(val)

var input_buffer: PlayerInputBuffer = PlayerInputBuffer.new()
var reconciliation_threshold: float = 0.05
var hard_snap_threshold: float = 5.0
var reconciliation_speed: float = 15.0

var _is_reconciling: bool = false
var _corrected_target_pos: Vector3 = Vector3.ZERO
var _last_drift_error: float = 0.0

## Toggles client prediction mode for comparative latency testing
func toggle_prediction(enable: bool) -> void:
	is_prediction_enabled = enable
	input_buffer.clear()
	_is_reconciling = false
	print("[Client Prediction] Mode set to: %s" % ("ON (Instant Response)" if enable else "OFF (Server Delay Baseline)"))

## Captures local input, generates sequential InputCommand, applies prediction if enabled
func process_local_input(player: CharacterBody3D, input_vector: Vector2, jumped: bool, delta: float) -> Dictionary:
	var cmd: PlayerInputBuffer.InputCommand = input_buffer.enqueue_input(input_vector, jumped, delta)
	
	if is_prediction_enabled:
		# Step 3: Apply movement locally immediately on client frame
		_simulate_step(player, cmd.input_vector, cmd.jump, cmd.delta_time)
	
	return cmd.to_dict()

## Reconciles when authoritative state arrives from server (Step 5)
func reconcile_server_state(player: CharacterBody3D, last_ack_seq: int, server_pos: Vector3, _server_vel: Vector3) -> void:
	if not is_prediction_enabled:
		# Without prediction: directly set position to server state (manifesting input lag)
		player.global_position = server_pos
		return
	
	# Step 5.3: Drop acknowledged inputs
	input_buffer.remove_acknowledged(last_ack_seq)
	
	# Replay remaining unacknowledged inputs starting from server's authoritative position
	var replayed_pos: Vector3 = server_pos
	var pending: Array[PlayerInputBuffer.InputCommand] = input_buffer.get_pending_commands()
	
	for pending_cmd in pending:
		var dir = Vector3(pending_cmd.input_vector.x, 0, -pending_cmd.input_vector.y).normalized()
		replayed_pos += dir * (player.move_speed * pending_cmd.delta_time)
	
	var drift: float = player.global_position.distance_to(replayed_pos)
	_last_drift_error = drift
	
	if drift > hard_snap_threshold:
		player.global_position = replayed_pos
		_is_reconciling = false
	elif drift > reconciliation_threshold:
		_corrected_target_pos = replayed_pos
		_is_reconciling = true
		reconciliation_performed.emit(drift, pending.size())
	else:
		_is_reconciling = false

## Smooth error correction lerp in physics/process frame to prevent visual snap jitter (Step 5.4)
func update_smoothing(player: CharacterBody3D, delta: float) -> void:
	if _is_reconciling:
		player.global_position = player.global_position.lerp(_corrected_target_pos, delta * reconciliation_speed)
		if player.global_position.distance_to(_corrected_target_pos) < 0.01:
			player.global_position = _corrected_target_pos
			_is_reconciling = false

func _simulate_step(player: CharacterBody3D, input_vector: Vector2, jumped: bool, delta: float) -> void:
	if jumped and player.is_on_floor():
		player.velocity.y = player.jump_velocity
	
	if input_vector.length_squared() > 0.0:
		var dir = Vector3(input_vector.x, 0, -input_vector.y).normalized()
		player.velocity.x = dir.x * player.move_speed
		player.velocity.z = dir.z * player.move_speed
	else:
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	
	player.move_and_slide()
