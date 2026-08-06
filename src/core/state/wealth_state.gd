class_name WealthState
extends RefCounted

enum Kind {
	GOLD,
	GEMS,
	JEWELRY,
}

var gold: int = 0
var gems: int = 0
var jewelry: int = 0


func _init(gold_amount: int = 0, gem_amount: int = 0, jewelry_amount: int = 0) -> void:
	gold = maxi(0, gold_amount)
	gems = maxi(0, gem_amount)
	jewelry = maxi(0, jewelry_amount)


func amount(kind: Kind) -> int:
	match kind:
		Kind.GOLD:
			return gold
		Kind.GEMS:
			return gems
		Kind.JEWELRY:
			return jewelry
	return 0


func set_amount(kind: Kind, value: int) -> void:
	match kind:
		Kind.GOLD:
			gold = maxi(0, value)
		Kind.GEMS:
			gems = maxi(0, value)
		Kind.JEWELRY:
			jewelry = maxi(0, value)


func add(kind: Kind, value: int) -> void:
	set_amount(kind, amount(kind) + value)


func to_data() -> Dictionary:
	return {"gold": gold, "gems": gems, "jewelry": jewelry}


static func from_data(data: Variant) -> WealthState:
	if not data is Dictionary:
		return null
	var amounts: Array[int] = []
	for field: String in ["gold", "gems", "jewelry"]:
		if not data.has(field):
			return null
		var value := _integer(data[field])
		if value < 0:
			return null
		amounts.append(value)
	return WealthState.new(amounts[0], amounts[1], amounts[2])


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
