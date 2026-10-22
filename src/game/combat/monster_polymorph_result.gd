## Keeps authored unsafe selections distinct from failed polymorph execution.
class_name MonsterPolymorphResult
extends RefCounted

enum Outcome { UNCHANGED, TRANSFORMED, AUTHORED_UNSAFE, FAILED }

var outcome: Outcome = Outcome.UNCHANGED
var previous_definition_id: String = ""
var error_code: StringName = &""
var error_message: String = ""


static func failed(code: StringName, message: String) -> MonsterPolymorphResult:
	var result := MonsterPolymorphResult.new()
	result.outcome = Outcome.FAILED
	result.error_code = code
	result.error_message = message
	return result
