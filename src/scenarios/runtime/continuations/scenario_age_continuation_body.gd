## Carries staged character age updates and their VM resume result.

class_name ScenarioAgeContinuationBody
extends ScenarioRuntimeContinuationBody

var updates: Array[AgeUpdateRequestBody]
var index: int
var value: Variant
var directive: ScenarioVmDirective


func wire_payload() -> Dictionary:
	var serialized: Array[Dictionary] = []
	for update: AgeUpdateRequestBody in updates:
		serialized.append(update.to_data())
	var detached_value: Variant = ScenarioAgeContinuations.detached_value(value)
	return {"updates": serialized, "index": index, "value": detached_value, "directive": {} if directive == null else directive.to_data()}
