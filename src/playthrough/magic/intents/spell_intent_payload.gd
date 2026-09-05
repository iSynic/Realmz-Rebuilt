## Carries one field or combat spell operation across the session boundary.

class_name SpellIntentPayload
extends PlayerIntentPayload

var operation: StringName
var spell_id: String
var caster_id: String
var target_id: String
var target_ids: Array[String]
var target_coordinates: Array[Vector2i]
var power: int
var coordinate: Vector2i
var rotation: int
var scroll_slot: int


func _init(operation_value: StringName, spell: String, caster: String, target: String = "", targets: Array[String] = [], power_value: int = 1, target_coordinate: Vector2i = Vector2i(-100_000, -100_000), area_rotation: int = 0, slot: int = -1, coordinates: Array[Vector2i] = []) -> void:
	operation = operation_value
	spell_id = spell
	caster_id = caster
	target_id = target
	target_ids = targets.duplicate()
	target_coordinates = coordinates.duplicate()
	power = power_value
	coordinate = target_coordinate
	rotation = area_rotation
	scroll_slot = slot
