## Carries detached money workspace data from gameplay into presentation.

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
var changing_available: bool = false
var changing_reason: String = ""
var changes: Array[MoneyChangeView] = []
var characters: Array[MoneyCharacterView] = []


func character(character_id: String) -> MoneyCharacterView:
	for option: MoneyCharacterView in characters:
		if option.character_id == character_id:
			return option
	return null


func pooled_amount(denomination: StringName) -> int:
	match denomination:
		&"gold": return pooled_gold
		&"gems": return pooled_gems
		&"jewelry": return pooled_jewelry
	return 0
