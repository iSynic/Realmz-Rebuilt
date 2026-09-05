## Carries one application lifecycle decision without owning host state.

class_name LifecycleRequestBody
extends InteractionRequestBody

var operation: StringName
var prompt: String
var has_active_session: bool
var in_combat: bool
var includes_active_session: bool
var options: Array[InteractionRequestValue.LifecycleOption] = []


func to_data() -> Dictionary:
	var data := {"operation": String(operation), "prompt": prompt, "inCombat": in_combat, "options": options.map(func(value: InteractionRequestValue.LifecycleOption) -> Dictionary: return value.to_data())}
	if includes_active_session: data["hasActiveSession"] = has_active_session
	return data


func prompt_text() -> String:
	return prompt
