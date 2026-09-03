class_name TimedEncounterDefinition
extends RefCounted

enum LocationKind { ANY, LAND, DUNGEON }

var id: int
var day: int
var increment: int
var chance_percent: int
var classic_macro_id: int
var program_id: String
var required_level: int
var required_random_rectangle: int
var required_x: int
var required_y: int
var required_item_id: int
var required_quest_id: int
var location_kind: LocationKind


func _init(encounter_id: int, first_day: int, day_increment: int, chance: int, macro_id: int, scenario_program_id: String, level_requirement: int, random_rectangle_requirement: int, x_requirement: int, y_requirement: int, item_requirement: int, quest_requirement: int, place_kind: LocationKind) -> void:
	id = encounter_id
	day = first_day
	increment = day_increment
	chance_percent = chance
	classic_macro_id = macro_id
	program_id = scenario_program_id
	required_level = level_requirement
	required_random_rectangle = random_rectangle_requirement
	required_x = x_requirement
	required_y = y_requirement
	required_item_id = item_requirement
	required_quest_id = quest_requirement
	location_kind = place_kind
