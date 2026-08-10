class_name MoneyCharacterView
extends RefCounted

var character_id: String
var name: String
var gold: int
var gems: int
var jewelry: int
var carried_load: int
var maximum_load: int
var transfers: Array[MoneyTransferView] = []


func _init(character: CharacterState) -> void:
	character_id = character.id
	name = character.name
	gold = character.money.gold
	gems = character.money.gems
	jewelry = character.money.jewelry
	carried_load = character.carried_load
	maximum_load = character.maximum_load


func transfer(denomination: StringName) -> MoneyTransferView:
	for option: MoneyTransferView in transfers:
		if option.denomination == denomination:
			return option
	return null
