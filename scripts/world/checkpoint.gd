extends Area3D

## Checkpoint script - updates local player's respawn position when entered.

@onready var sfx: AudioStreamPlayer3D = $CheckpointSFX

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.has_method("set_checkpoint"):
		# Spawn slightly above the checkpoint pad
		body.set_checkpoint(global_position + Vector3(0, 1.0, 0))
		if body.is_multiplayer_authority() and sfx:
			sfx.play()
