class_name TreasureRoll
extends RefCounted

var experience: int
var wealth: WealthState
var item_ids: Array[String]


func _init(experience_amount: int, rolled_wealth: WealthState, items: Array[String]) -> void:
	experience = experience_amount
	wealth = rolled_wealth
	item_ids = items.duplicate()
