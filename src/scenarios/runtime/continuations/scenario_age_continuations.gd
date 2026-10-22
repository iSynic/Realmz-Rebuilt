## Creates staged age-update scenario runtime continuations.

class_name ScenarioAgeContinuations
extends RefCounted


static func updates(kind: StringName, updates: Array[AgeUpdateRequestBody], index: int, result_value: Variant, directive: ScenarioVmDirective) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_AGE_UPDATES, ScenarioRuntimeContinuation.SAFE_AGE_UPDATES])
	var body := ScenarioAgeContinuationBody.new()
	for update: AgeUpdateRequestBody in updates:
		body.updates.append(copy_update(update))
	body.index = index
	body.value = detached_value(result_value)
	body.directive = directive.copy() if directive != null else null
	return ScenarioRuntimeContinuation.new(kind, body)


static func copy_update(update: AgeUpdateRequestBody) -> AgeUpdateRequestBody:
	return update_from_data(update.to_data()) if update != null else null


static func update_from_data(value: Variant) -> AgeUpdateRequestBody:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	var request := InteractionRequest.age_update("continuation.age", data)
	return null if request == null else request.body as AgeUpdateRequestBody


static func detached_value(value: Variant) -> Variant:
	if value is Array:
		var items: Array = value
		return items.duplicate(true)
	if value is Dictionary:
		var record: Dictionary = value
		return record.duplicate(true)
	return value
