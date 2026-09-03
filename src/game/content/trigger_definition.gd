class_name TriggerDefinition
extends RefCounted

var id: String
var program_id: String
var map_id: String
var coordinate: Vector2i
var active: bool
var chance_percent: int
var post_action_location: TriggerDestinationDefinition
var classic_record_index: int


func _init(trigger_id: String, trigger_program_id: String, owner_map_id: String, trigger_coordinate: Vector2i, is_active: bool, chance: int, destination: TriggerDestinationDefinition = null, record_index: int = -1) -> void:
	id = trigger_id
	program_id = trigger_program_id
	map_id = owner_map_id
	coordinate = trigger_coordinate
	active = is_active
	chance_percent = chance
	post_action_location = destination
	classic_record_index = record_index
