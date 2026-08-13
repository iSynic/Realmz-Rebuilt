class_name FastSpellBindingState
extends RefCounted

var spell_id: String
var power: int


func _init(binding_spell_id: String = "", power_level: int = 0) -> void:
	spell_id = binding_spell_id
	power = power_level


func is_empty() -> bool:
	return spell_id.is_empty() and power == 0


func to_data() -> Dictionary:
	return {"spellId": spell_id, "power": power}


static func from_data(data: Variant) -> FastSpellBindingState:
	if not data is Dictionary or data.size() != 2 or not data.get("spellId") is String:
		return null
	var parsed_power := _integer(data.get("power"))
	var parsed_spell_id: String = data["spellId"]
	if parsed_power < 0 or parsed_power > 7:
		return null
	if parsed_power == 0 and not parsed_spell_id.is_empty() or parsed_power > 0 and parsed_spell_id.is_empty():
		return null
	return FastSpellBindingState.new(parsed_spell_id, parsed_power)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
