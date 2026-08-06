class_name TriggerDefinition
extends RefCounted

var id: String
var map_id: String
var coordinate: Vector2i
var active: bool
var chance_percent: int
var _actions: Array[ClassicActionDefinition]


func _init(trigger_id: String, owner_map_id: String, trigger_coordinate: Vector2i, is_active: bool, chance: int, trigger_actions: Array[ClassicActionDefinition]) -> void:
	id = trigger_id
	map_id = owner_map_id
	coordinate = trigger_coordinate
	active = is_active
	chance_percent = chance
	_actions = trigger_actions.duplicate()


func actions() -> Array[ClassicActionDefinition]:
	return _actions.duplicate()
