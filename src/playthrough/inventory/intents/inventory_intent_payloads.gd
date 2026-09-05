## Defines the typed values carried by inventory and carried-item intents.

class_name InventoryIntentPayloads
extends RefCounted


class Use:
	extends PlayerIntentPayload
	var item_id: String
	var actor_id: String

	func _init(item: String, actor: String) -> void:
		item_id = item
		actor_id = actor


class Target:
	extends PlayerIntentPayload
	var item_id: String
	var actor_id: String
	var target_id: String
	var target_ids: Array[String]
	var target_coordinates: Array[Vector2i]
	var coordinate: Vector2i
	var rotation: int

	func _init(item: String, actor: String, target: String, targets: Array[String], target_coordinate: Vector2i, area_rotation: int, coordinates: Array[Vector2i] = []) -> void:
		item_id = item
		actor_id = actor
		target_id = target
		target_ids = targets.duplicate()
		target_coordinates = coordinates.duplicate()
		coordinate = target_coordinate
		rotation = area_rotation


class Action:
	extends PlayerIntentPayload
	var item_id: String
	var actor_id: String
	var destination_character_id: String
	var quantity: int

	func _init(item: String, actor: String, count: int = 1, destination: String = "") -> void:
		item_id = item
		actor_id = actor
		quantity = maxi(1, count)
		destination_character_id = destination
