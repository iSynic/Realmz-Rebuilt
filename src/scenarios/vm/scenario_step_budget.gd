## Bounds one uninterrupted Scenario VM run, shared by every nested VM in it (ADR 0027).

class_name ScenarioStepBudget
extends RefCounted

var _remaining: int


func _init(limit: int) -> void:
	_remaining = limit


## Returns the live budget for this runtime, or starts one for a new run. The
## runtime keeps only a weak reference, so the outermost entry's local claim
## owns the budget and the next external entry starts fresh once it returns.
static func shared(runtime_api: RealmzRuntimeApi, limit: int) -> ScenarioStepBudget:
	var live: ScenarioStepBudget = runtime_api.step_budget_ref.get_ref() if runtime_api.step_budget_ref != null else null
	if live != null:
		return live
	live = ScenarioStepBudget.new(limit)
	runtime_api.step_budget_ref = weakref(live)
	return live


func consume() -> bool:
	_remaining -= 1
	return _remaining >= 0
