class_name RandomEncounterRegion
extends RefCounted

var id: String
var bounds: Rect2i
var chance_ten_thousand: int
var battle_minimum: int
var battle_maximum: int
var only: bool
var option: int
var sound_id: int
var text_id: int
var _random_doors: Array[int]
var _random_door_percents: Array[int]


func _init(region_id: String, region_bounds: Rect2i, chance: int, battle_min: int, battle_max: int, door_ids: Array[int], door_percents: Array[int], region_only: bool, region_option: int, region_sound_id: int, region_text_id: int) -> void:
	id = region_id
	bounds = region_bounds
	chance_ten_thousand = chance
	battle_minimum = battle_min
	battle_maximum = battle_max
	_random_doors = door_ids.duplicate()
	_random_door_percents = door_percents.duplicate()
	only = region_only
	option = region_option
	sound_id = region_sound_id
	text_id = region_text_id


func random_doors() -> Array[int]:
	return _random_doors.duplicate()


func random_door_percents() -> Array[int]:
	return _random_door_percents.duplicate()
