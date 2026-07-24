extends Area3D

## Finish line trigger - notifies World when local player crosses.

var _finished_peers: Array[int] = []

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.is_multiplayer_authority():
		var peer_id: int = body.get_multiplayer_authority()
		if not peer_id in _finished_peers:
			_finished_peers.append(peer_id)
			var world: Node = get_tree().current_scene
			if world.has_method("on_player_reach_finish"):
				world.on_player_reach_finish(peer_id)
