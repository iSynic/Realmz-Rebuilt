class_name RealmzRngState
extends RefCounted

var generator_state: int
var draw_count: int


func _init(state_value: int, completed_draws: int) -> void:
	generator_state = state_value
	draw_count = completed_draws


func to_data() -> Dictionary:
	return {"generatorState": generator_state, "drawCount": draw_count}


static func from_data(data: Variant) -> RealmzRngState:
	if not data is Dictionary or not data.has("generatorState") or not data.has("drawCount"):
		return null
	var generator := _integer(data["generatorState"])
	var draws := _integer(data["drawCount"])
	if generator < 0 or draws < 0:
		return null
	if generator <= 0 or generator >= RealmzRng.MODULUS:
		return null
	return RealmzRngState.new(generator, draws)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
