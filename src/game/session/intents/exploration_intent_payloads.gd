## Defines the typed values carried by world movement and exploration intents.

class_name ExplorationIntentPayloads
extends RefCounted


class Move:
	extends PlayerIntentPayload
	var direction: Vector2i
	var aligns_dungeon_heading: bool

	func _init(value: Vector2i, align_heading: bool = false) -> void:
		direction = value
		aligns_dungeon_heading = align_heading


class DungeonTurn:
	extends PlayerIntentPayload
	var delta: int

	func _init(value: int) -> void:
		delta = value


class LocationNote:
	extends PlayerIntentPayload
	var text: String

	func _init(value: String) -> void:
		text = value
