## Carries one bounded Safe for-each loop without an untyped workflow payload.
class_name ScenarioSafeIterator
extends RefCounted

var begin_target: int = 0
var index: int = 0
var values: Array = []
var item_name: String
var had_previous: bool = false
var previous: Variant


func to_data() -> Dictionary:
	return {"beginTarget": begin_target, "index": index, "values": ScenarioValueCodec.encode(values, true), "itemName": item_name, "hadPrevious": had_previous, "previous": ScenarioValueCodec.encode(previous, true)}


static func from_data(value: Variant) -> ScenarioSafeIterator:
	if not ScenarioExecutionWire.fields(value, ["beginTarget", "index", "values", "itemName", "hadPrevious", "previous"]):
		return null
	var data: Dictionary = value
	if not data["itemName"] is String or not data["hadPrevious"] is bool:
		return null
	var decoded_values := ScenarioValueCodec.decode(data["values"], 0, true)
	var decoded_previous := ScenarioValueCodec.decode(data["previous"], 0, true)
	if not decoded_values["ok"] or not decoded_previous["ok"] or not decoded_values["value"] is Array:
		return null
	var result := ScenarioSafeIterator.new()
	result.begin_target = ScenarioExecutionWire.integer(data["beginTarget"], 0, 4095)
	result.index = ScenarioExecutionWire.integer(data["index"], 0, 255)
	result.item_name = data["itemName"]
	result.had_previous = data["hadPrevious"]
	result.values = decoded_values["value"]
	result.previous = decoded_previous["value"]
	if result.begin_target < 0 or result.index < 0 or result.item_name.is_empty() or result.values.size() > 256 or result.index >= result.values.size():
		return null
	return result
