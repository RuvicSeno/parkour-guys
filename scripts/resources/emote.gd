class_name Emote
extends Resource

## Emote data resource defining animation source, UI display details, and playback behavior.

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
@export var animation_scene: PackedScene
@export var animation_name: String = ""
@export var is_looping: bool = true
@export var lock_movement: bool = false
