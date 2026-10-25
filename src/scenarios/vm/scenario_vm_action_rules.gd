## Projects bounded expression outcomes for the execution runner.
class_name ScenarioVmActionRules
extends RefCounted


static func expression_failure(evaluated: Dictionary, fallback: String = "") -> ScenarioVmResult:
	var message: String = evaluated["error"] if fallback.is_empty() else evaluated.get("error", fallback)
	return ScenarioVmResult.failed(&"safe_expression_failed", message)


static func argument_values(evaluated: Dictionary) -> Dictionary:
	return evaluated["value"]
