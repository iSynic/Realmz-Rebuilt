class_name ConditionSet
extends RefCounted

const CHARACTER_COUNT: int = 40
const PARTY_COUNT: int = 10

var _values: Array[int] = []


func _init(count: int = CHARACTER_COUNT) -> void:
	_values.resize(maxi(1, count))
	_values.fill(0)


func size() -> int:
	return _values.size()


func value(index: int) -> int:
	return 0 if index < 0 or index >= _values.size() else _values[index]


func is_active(index: int) -> bool:
	return value(index) != 0


func set_value(index: int, amount: int) -> bool:
	if index < 0 or index >= _values.size():
		return false
	_values[index] = clampi(amount, -32_768, 32_767)
	return true


func add(index: int, amount: int) -> bool:
	return set_value(index, value(index) + amount)


func clear_positive() -> int:
	var cleared := 0
	for index: int in _values.size():
		if _values[index] <= 0:
			continue
		_values[index] = 0
		cleared += 1
	return cleared


func decay_positive() -> Array[int]:
	var expired: Array[int] = []
	for index: int in _values.size():
		if _values[index] <= 0:
			continue
		_values[index] -= 1
		if _values[index] == 0:
			expired.append(index)
	return expired


func values() -> Array[int]:
	return _values.duplicate()


func to_data() -> Dictionary:
	return {"count": _values.size(), "values": _values.duplicate()}


static func from_data(data: Variant, expected_count: int = 0) -> ConditionSet:
	if not data is Dictionary or not data.has("count") or not data.has("values"):
		return null
	var count := _integer(data["count"])
	if count < 1 or (expected_count > 0 and count != expected_count) or not data["values"] is Array or data["values"].size() != count:
		return null
	var result := ConditionSet.new(count)
	for index: int in count:
		var amount := _signed_integer(data["values"][index])
		if amount < -32_768 or amount > 32_767:
			return null
		result._values[index] = amount
	return result


static func _integer(input: Variant) -> int:
	if input is int:
		return input
	if input is float and is_equal_approx(input, round(input)):
		return int(input)
	return -1


static func _signed_integer(input: Variant) -> int:
	if input is int:
		return input
	if input is float and is_equal_approx(input, round(input)):
		return int(input)
	return -100_000
