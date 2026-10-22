## Retains Castle's shared infodoor destination and selected placed AP.
class_name ClassicExecutionState
extends RefCounted

var header_replaced: bool = false
var map_id: String = ""
var coordinate: Vector2i = Vector2i.ZERO
var trigger_id: String = ""


func begin_trigger(trigger: TriggerDefinition, preserve_replacement: bool = false) -> void:
	if not preserve_replacement: header_replaced = false
	trigger_id = trigger.id
	map_id = trigger.map_id if trigger.post_action_location == null else trigger.post_action_location.map_id
	coordinate = trigger.coordinate if trigger.post_action_location == null else trigger.post_action_location.coordinate


func begin_timer(current_map_id: String, current_coordinate: Vector2i) -> void:
	header_replaced = true
	map_id = current_map_id
	coordinate = current_coordinate


func observe(opcode: int, events: Array[DomainEvent]) -> void:
	if opcode not in [20, 45, 61, 70]: return
	for event: DomainEvent in events:
		if event.kind not in [&"party_teleported", &"party_shifted", &"party_position_restored"]: continue
		header_replaced = true
		if opcode != 61 or map_id.is_empty(): map_id = event.payload["mapId"]
		coordinate = Vector2i(event.payload["x"], event.payload["y"])


func copy() -> ClassicExecutionState:
	return from_data(to_data())


func is_valid(content: RealmzContent) -> bool:
	if map_id.is_empty(): return not header_replaced and trigger_id.is_empty() and coordinate == Vector2i.ZERO
	var trigger := content.scenario_records.trigger_by_id(trigger_id) if not trigger_id.is_empty() else null
	if not trigger_id.is_empty() and trigger == null: return false
	# An authored unusable header remains a deferred source fact, not a forged
	# saved destination. Its eventual consumer still bounds the actual access.
	if trigger != null:
		var authored_map := trigger.map_id if trigger.post_action_location == null else trigger.post_action_location.map_id
		var authored_coordinate := trigger.coordinate if trigger.post_action_location == null else trigger.post_action_location.coordinate
		if map_id == authored_map and coordinate == authored_coordinate: return true
	var map := content.world.map_by_id(map_id)
	return map != null and map.topology.cell_at(coordinate) != null


func to_data() -> Dictionary:
	return {"headerReplaced": header_replaced, "mapId": map_id, "x": coordinate.x, "y": coordinate.y, "triggerId": trigger_id}


static func from_data(value: Variant) -> ClassicExecutionState:
	if not value is Dictionary or value.size() != 5 or not value.get("headerReplaced") is bool or not value.get("mapId") is String or not value.get("triggerId") is String: return null
	for field: String in ["x", "y"]:
		var number: Variant = value.get(field)
		if not (number is int or number is float and is_finite(number) and number == floor(number)) or number < -2_147_483_648 or number > 2_147_483_647: return null
	if value["headerReplaced"] and value["mapId"].is_empty(): return null
	var result := ClassicExecutionState.new()
	result.header_replaced = value["headerReplaced"]
	result.map_id = value["mapId"]
	result.coordinate = Vector2i(value["x"], value["y"])
	result.trigger_id = value["triggerId"]
	return result
