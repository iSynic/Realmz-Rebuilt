class_name MoneyWorkspaceView
extends RefCounted

var pooled_gold: int
var pooled_gems: int
var pooled_jewelry: int
var banked_gold: int
var banked_gems: int
var banked_jewelry: int
var pool: ActionAvailabilityView
var share: ActionAvailabilityView
var characters: Array[MoneyCharacterView] = []


func character(character_id: String) -> MoneyCharacterView:
	for option: MoneyCharacterView in characters:
		if option.character_id == character_id:
			return option
	return null
