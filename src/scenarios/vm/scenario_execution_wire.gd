## Strict scalar and field admission shared by the closed execution codecs.
class_name ScenarioExecutionWire
extends RefCounted


static func fields(value: Variant, names: Array[String]) -> bool:
	if not value is Dictionary:
		return false
	var data: Dictionary = value
	return data.size() == names.size() and data.has_all(names)


static func integer(value: Variant, minimum: int = 0, maximum: int = 2_147_483_647) -> int:
	if value is int:
		var number: int = value
		return number if number >= minimum and number <= maximum else minimum - 1
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum:
			return int(number)
	return minimum - 1


static func destination(value: Variant) -> TriggerDestinationDefinition:
	if not fields(value, ["mapId", "x", "y"]):
		return null
	var data: Dictionary = value
	if not data["mapId"] is String:
		return null
	var map_id: String = data["mapId"]
	var x := integer(data["x"], -2_147_483_648)
	var y := integer(data["y"], -2_147_483_648)
	if map_id.is_empty() or x < -2_147_483_648 or y < -2_147_483_648:
		return null
	return TriggerDestinationDefinition.new(map_id, Vector2i(x, y))


static func destination_data(value: TriggerDestinationDefinition) -> Variant:
	return null if value == null else {"mapId": value.map_id, "x": value.coordinate.x, "y": value.coordinate.y}
