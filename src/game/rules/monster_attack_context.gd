class_name MonsterAttackContext
extends RefCounted

var attacker_weapon: ItemDefinition
var realmz_day: int = 0
var behind: bool = false
var defender_luck: int = 0
var party_dragon_hide: bool = false
var defender_armor: int = -1


func _init(weapon: ItemDefinition = null, day: int = 0, attacks_from_behind: bool = false, target_luck: int = 0, dragon_hide: bool = false, target_armor: int = -1) -> void:
	attacker_weapon = weapon
	realmz_day = maxi(0, day)
	behind = attacks_from_behind
	defender_luck = target_luck
	party_dragon_hide = dragon_hide
	defender_armor = target_armor
