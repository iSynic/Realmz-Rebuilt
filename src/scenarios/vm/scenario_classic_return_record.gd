## Saves exactly the code, following position and header restored by a native return.
class_name ScenarioClassicReturnRecord
extends RefCounted

enum DestinationState { ABSENT, KNOWN, UNAVAILABLE }

var code: ScenarioClassicProgramState
var cursor: int = 0
var native_slot: int = 0
var destination: TriggerDestinationDefinition
var destination_state: DestinationState = DestinationState.ABSENT


func copy() -> ScenarioClassicReturnRecord:
	var result := ScenarioClassicReturnRecord.new()
	result.code = code.copy()
	result.cursor = cursor
	result.native_slot = native_slot
	result.destination_state = destination_state
	result.destination = TriggerDestinationDefinition.new(destination.map_id, destination.coordinate) if destination != null else null
	return result


func to_data() -> Dictionary:
	return {"code": code.to_data(), "cursor": cursor, "nativeSlot": native_slot, "destination": ScenarioExecutionWire.destination_data(destination), "destinationState": destination_state}


static func from_data(value: Variant) -> ScenarioClassicReturnRecord:
	if not ScenarioExecutionWire.fields(value, ["code", "cursor", "nativeSlot", "destination", "destinationState"]):
		return null
	var data: Dictionary = value
	var result := ScenarioClassicReturnRecord.new()
	result.code = ScenarioClassicProgramState.from_data(data["code"])
	result.cursor = ScenarioExecutionWire.integer(data["cursor"], 0, 4096)
	result.native_slot = ScenarioExecutionWire.integer(data["nativeSlot"], 0, 8)
	var availability := ScenarioExecutionWire.integer(data["destinationState"], DestinationState.ABSENT, DestinationState.UNAVAILABLE)
	if availability < 0 or (availability == DestinationState.KNOWN) != (data["destination"] != null): return null
	result.destination_state = availability as DestinationState
	if result.code == null or result.cursor < 0 or result.native_slot < 0:
		return null
	if data["destination"] != null:
		result.destination = ScenarioExecutionWire.destination(data["destination"])
		if result.destination == null:
			return null
	return result
