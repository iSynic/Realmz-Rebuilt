class_name PartySetupView
extends RefCounted

var difficulty: int = 0
var monster_set: int = 0
var available_monster_sets: Array[int] = [0]
var current_party_levels: int = 0
var experience_percent: int = 0


static func difficulty_name(value: int) -> String:
	match value:
		-2:
			return "Novice"
		-1:
			return "Easy"
		0:
			return "Normal"
		1:
			return "Hard"
		2:
			return "Veteran"
		_:
			return "Unknown"


static func monster_set_name(value: int) -> String:
	match value:
		0:
			return "Normal Monsters"
		1:
			return "Monster Monsters"
		-1:
			return "Mega Monsters"
		_:
			return "Unknown Monsters"
