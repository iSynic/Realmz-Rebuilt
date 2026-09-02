class_name ScenarioApplicationHooks
extends RefCounted

const START_GAME: StringName = &"start-game"
const PARTY_DEATH: StringName = &"party-death"
const END_ADVENTURE: StringName = &"end-adventure"
const SHOP: StringName = &"shop"
const TEMPLE: StringName = &"temple"

var _start_game_program_id: String
var _party_death_program_id: String
var _end_adventure_program_id: String
var _shop_program_id: String
var _temple_program_id: String


func _init(start_game: String = "", party_death: String = "", end_adventure: String = "", shop: String = "", temple: String = "") -> void:
	_start_game_program_id = start_game
	_party_death_program_id = party_death
	_end_adventure_program_id = end_adventure
	_shop_program_id = shop
	_temple_program_id = temple


func program_id(hook: StringName) -> String:
	match hook:
		START_GAME:
			return _start_game_program_id
		PARTY_DEATH:
			return _party_death_program_id
		END_ADVENTURE:
			return _end_adventure_program_id
		SHOP:
			return _shop_program_id
		TEMPLE:
			return _temple_program_id
		_:
			return ""
