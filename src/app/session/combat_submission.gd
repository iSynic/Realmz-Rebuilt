## Distinguishes accepted host work from a committed gameplay step.
class_name CombatSubmission
extends RefCounted

var job_id: int = 0
var rejection: SessionStep


func accepted() -> bool:
	return job_id > 0 and rejection == null


static func queued(id: int) -> CombatSubmission:
	var result := CombatSubmission.new()
	result.job_id = id
	return result


static func rejected(step: SessionStep) -> CombatSubmission:
	var result := CombatSubmission.new()
	result.rejection = step
	return result
