## Defines the safe expression evaluator contract for scenario execution.

class_name SafeExpressionEvaluator
extends RefCounted

## Evaluates bounded Safe Scenario Action expressions against one VM frame.


static func evaluate(expression: SafeExpressionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	if expression == null:
		return {"ok": false, "error": "Safe expression is missing."}
	match expression.kind:
		SafeExpressionDefinition.Kind.LITERAL:
			return {"ok": true, "value": expression.value}
		SafeExpressionDefinition.Kind.VARIABLE:
			return _evaluate_variable(expression, frame, runtime_api)
		SafeExpressionDefinition.Kind.ARRAY:
			var values: Array = []
			for child: SafeExpressionDefinition in expression.values():
				var evaluated := evaluate(child, frame, runtime_api)
				if not evaluated["ok"]:
					return evaluated
				values.append(evaluated["value"])
			return {"ok": true, "value": values}
		SafeExpressionDefinition.Kind.RECORD:
			var fields: Dictionary = {}
			for field_name: String in expression.field_names():
				var evaluated := evaluate(expression.field(field_name), frame, runtime_api)
				if not evaluated["ok"]:
					return evaluated
				fields[field_name] = evaluated["value"]
			return {"ok": true, "value": fields}
		SafeExpressionDefinition.Kind.UNARY:
			return _evaluate_unary(expression, frame, runtime_api)
		SafeExpressionDefinition.Kind.BINARY:
			var left_result := evaluate(expression.left, frame, runtime_api)
			var right_result := evaluate(expression.right, frame, runtime_api)
			if not left_result["ok"]:
				return left_result
			if not right_result["ok"]:
				return right_result
			return _evaluate_binary(expression.operator, left_result["value"], right_result["value"])
		SafeExpressionDefinition.Kind.MEMBER:
			var object_result := evaluate(expression.object, frame, runtime_api)
			if not object_result["ok"]:
				return object_result
			if not object_result["value"] is Dictionary or not object_result["value"].has(expression.member):
				return {"ok": false, "error": "Safe member '%s' is unavailable." % expression.member}
			return {"ok": true, "value": object_result["value"][expression.member]}
		SafeExpressionDefinition.Kind.COLLECTION:
			return _evaluate_collection(expression, frame, runtime_api)
	return {"ok": false, "error": "Safe expression kind is unavailable."}


static func evaluate_call_arguments(action_call: CallScenarioActionInstruction, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var result: Dictionary = {}
	for name: String in action_call.argument_names():
		var evaluated := evaluate(action_call.argument(name), frame, runtime_api)
		if not evaluated["ok"]:
			return evaluated
		result[name] = evaluated["value"]
	return {"ok": true, "value": result}


static func evaluate_instruction_arguments(instruction: SafeInstructionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var result: Dictionary = {}
	for name: String in instruction.argument_names():
		var evaluated := evaluate(instruction.argument(name), frame, runtime_api)
		if not evaluated["ok"]:
			return evaluated
		result[name] = evaluated["value"]
	return {"ok": true, "value": result}


static func value_matches_type(value: Variant, value_type: StringName, max_length: int = -1) -> bool:
	match value_type:
		&"void":
			return value == null
		&"bool":
			return value is bool
		&"int":
			return value is int
		&"float":
			return value is int or value is float
		&"string":
			return value is String and (max_length < 0 or value.length() <= max_length)
		&"bool-array", &"int-array", &"float-array", &"string-array", &"character-snapshot-array":
			if not value is Array or value.size() > 256 or (max_length >= 0 and value.size() > max_length):
				return false
			var element_type := StringName(String(value_type).trim_suffix("-array"))
			for entry: Variant in value:
				if not value_matches_type(entry, element_type):
					return false
			return true
		&"location-snapshot", &"time-snapshot", &"wealth-snapshot", &"character-snapshot", &"combat-snapshot", &"action-outcome", &"encounter-outcome", &"effect-outcome", &"spell-validation-outcome", &"spell-cast-outcome", &"spell-effect-outcome", &"spell-tick-outcome", &"spell-expiration-outcome", &"item-outcome", &"monster-decision", &"rule-modifier":
			return value is Dictionary
	return false


static func _evaluate_variable(expression: SafeExpressionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	match expression.scope:
		&"parameter":
			return {"ok": true, "value": frame.parameter(expression.name)}
		&"local":
			if not frame.has_local(expression.name):
				return {"ok": false, "error": "Safe local '%s' is undefined." % expression.name}
			return {"ok": true, "value": frame.local(expression.name)}
		&"context":
			return {"ok": true, "value": frame.context_value(expression.name)}
		&"persistent":
			var state_scope := expression.state_scope if not expression.state_scope.is_empty() else "campaign"
			var owner_id := expression.owner_id if not expression.owner_id.is_empty() else frame.definition_id
			return {"ok": true, "value": runtime_api.read_action_state(state_scope, owner_id, expression.name)}
	return {"ok": false, "error": "Safe variable scope '%s' is unavailable." % expression.scope}


static func _evaluate_unary(expression: SafeExpressionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var operand := evaluate(expression.operand, frame, runtime_api)
	if not operand["ok"]:
		return operand
	if expression.operator == &"not" and operand["value"] is bool:
		return {"ok": true, "value": not operand["value"]}
	if expression.operator == &"-" and _is_number(operand["value"]):
		return {"ok": true, "value": -operand["value"]}
	return {"ok": false, "error": "Safe unary operator '%s' received an invalid operand." % expression.operator}


static func _evaluate_binary(operator: StringName, left: Variant, right: Variant) -> Dictionary:
	match operator:
		&"==": return {"ok": true, "value": left == right}
		&"!=": return {"ok": true, "value": left != right}
		&"and", &"or":
			if left is bool and right is bool:
				return {"ok": true, "value": left and right if operator == &"and" else left or right}
		&"+":
			if _is_number(left) and _is_number(right) or left is String and right is String:
				return {"ok": true, "value": left + right}
		&"-", &"*", &"/":
			if _is_number(left) and _is_number(right) and not (operator == &"/" and right == 0):
				match operator:
					&"-": return {"ok": true, "value": left - right}
					&"*": return {"ok": true, "value": left * right}
					&"/": return {"ok": true, "value": left / right}
		&"<", &"<=", &">", &">=":
			if _is_number(left) and _is_number(right):
				match operator:
					&"<": return {"ok": true, "value": left < right}
					&"<=": return {"ok": true, "value": left <= right}
					&">": return {"ok": true, "value": left > right}
					&">=": return {"ok": true, "value": left >= right}
	return {"ok": false, "error": "Safe binary operator '%s' received incompatible values." % operator}


static func _evaluate_collection(expression: SafeExpressionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var collection_result := evaluate(expression.collection, frame, runtime_api)
	if not collection_result["ok"] or not collection_result["value"] is Array:
		return {"ok": false, "error": "Safe collection expression input is not an array."}
	var values: Array = collection_result["value"]
	if values.size() > 256:
		return {"ok": false, "error": "Safe collection exceeds 256 entries."}
	if expression.operator == &"count":
		return {"ok": true, "value": values.size()}
	if expression.operator == &"first" and expression.predicate == null:
		return {"ok": true, "value": values[0] if not values.is_empty() else null}
	var had_previous := frame.has_local(expression.item_name)
	var previous: Variant = frame.local(expression.item_name)
	var matches: Array = []
	for value: Variant in values:
		frame.set_local(expression.item_name, value)
		var predicate := evaluate(expression.predicate, frame, runtime_api)
		if not predicate["ok"] or not predicate["value"] is bool:
			_restore_local(frame, expression.item_name, had_previous, previous)
			return {"ok": false, "error": "Safe collection predicate did not evaluate to bool."}
		matches.append(predicate["value"])
	_restore_local(frame, expression.item_name, had_previous, previous)
	match expression.operator:
		&"any": return {"ok": true, "value": matches.has(true)}
		&"all": return {"ok": true, "value": not matches.has(false)}
		&"first":
			for index: int in range(matches.size()):
				if matches[index]:
					return {"ok": true, "value": values[index]}
			return {"ok": true, "value": null}
	return {"ok": false, "error": "Safe collection operation '%s' is unavailable." % expression.operator}


static func _restore_local(frame: ScenarioFrame, name: String, had_previous: bool, previous: Variant) -> void:
	if had_previous:
		frame.set_local(name, previous)
	else:
		frame.erase_local(name)


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
