class_name PackageScenarioDecoder
extends PackageDecoderBase

const SUPPORTED_SAFE_CAPABILITIES: Array[String] = RealmzRuntimeApi.SUPPORTED_SAFE_CAPABILITIES
const SUPPORTED_ACTION_CONTEXTS: Array[String] = ["action", "encounter", "spell", "item", "monster-ai", "lifecycle", "rule-modifier"]
const SUPPORTED_VALUE_TYPES: Array[String] = ["void", "bool", "int", "float", "string", "location-snapshot", "time-snapshot", "wealth-snapshot", "character-snapshot", "character-snapshot-array", "combat-snapshot", "action-outcome", "encounter-outcome", "effect-outcome", "spell-validation-outcome", "spell-cast-outcome", "spell-effect-outcome", "spell-tick-outcome", "spell-expiration-outcome", "item-outcome", "monster-decision", "rule-modifier", "bool-array", "int-array", "float-array", "string-array"]

func _construct_scenario(document: Dictionary, campaign_id: String) -> ScenarioDefinition:
	var reference_validator := PackageCrossReferenceValidator.new(_diagnostic)
	if not _has_fields(document, ["applicationHooks", "programs", "scenarioActions", "stateDefinitions", "migrations"], "scenario document"):
		return null
	if not document["stateDefinitions"] is Array or document["stateDefinitions"].size() > 4096 or not document["migrations"] is Array or document["migrations"].size() > 4096 or not _json_safe(document["stateDefinitions"], 0) or not _json_safe(document["migrations"], 0):
		_reject("Scenario state definitions or migrations are malformed.")
		return null
	var programs_value: Variant = _construct_programs(document["programs"])
	var actions_value: Variant = _construct_scenario_actions(document["scenarioActions"], campaign_id)
	var hooks_value: Variant = _construct_application_hooks(document["applicationHooks"])
	if programs_value == null or actions_value == null or hooks_value == null:
		return null
	var programs: Array[ScenarioProgramDefinition] = programs_value
	var actions: Array[ScenarioActionDefinition] = actions_value
	var hooks: ScenarioApplicationHooks = hooks_value
	var definition := ScenarioDefinition.new(programs, actions, hooks)
	for hook: StringName in [ScenarioApplicationHooks.START_GAME, ScenarioApplicationHooks.PARTY_DEATH, ScenarioApplicationHooks.END_ADVENTURE, ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE]:
		var hook_program_id := definition.application_hook_program_id(hook)
		if not hook_program_id.is_empty() and definition.program_by_id(hook_program_id) == null:
			_reject("Scenario application hook '%s' references missing program '%s'." % [hook, hook_program_id])
			return null
	for program: ScenarioProgramDefinition in programs:
		for index: int in range(program.instruction_count()):
			var instruction: Variant = program.instruction_at(index)
			if instruction is CallScenarioActionInstruction:
				var called_action := definition.action_by_id(instruction.action_id)
				var calling_context: StringName = reference_validator._program_context(program.owner_kind)
				if called_action == null or called_action.visibility != &"public" or calling_context == &"" or not called_action.allows_context(calling_context) or not reference_validator._call_arguments_match(instruction.argument_names(), instruction.result_target, called_action):
					_reject("Scenario program '%s' has an invalid public Scenario Action call to '%s'." % [program.id, instruction.action_id])
					return null
	for action: ScenarioActionDefinition in actions:
		for index: int in range(action.program.instruction_count()):
			var instruction := action.program.instruction_at(index)
			if instruction.kind == SafeInstructionDefinition.Kind.CALL_ACTION:
				var called_action := definition.action_by_id(instruction.action_id)
				if called_action == null or not reference_validator._call_arguments_match(instruction.argument_names(), instruction.result_target, called_action) or not reference_validator._contexts_are_compatible(action, called_action):
					_reject("Scenario Action '%s' has an invalid call to '%s'." % [action.id, instruction.action_id])
					return null
	return definition

func _construct_application_hooks(value: Variant) -> Variant:
	var fields: Array[String] = ["startGame", "partyDeath", "endAdventure", "shop", "temple"]
	if not value is Dictionary or not _exact_fields(value, fields):
		_reject("Scenario application hooks are malformed.")
		return null
	var hook_ids: Array[String] = []
	for field: String in fields:
		var hook_id: Variant = value[field]
		if hook_id != null and (not hook_id is String or hook_id.is_empty() or hook_id.length() > 255):
			_reject("Scenario application hook '%s' has an invalid program ID." % field)
			return null
		hook_ids.append("" if hook_id == null else String(hook_id))
	return ScenarioApplicationHooks.new(hook_ids[0], hook_ids[1], hook_ids[2], hook_ids[3], hook_ids[4])

func _construct_programs(value: Variant) -> Variant:
	if not value is Array:
		_reject("Scenario programs must be an array.")
		return null
	var programs: Array[ScenarioProgramDefinition] = []
	var ids: Dictionary = {}
	for program: Variant in value:
		if not program is Dictionary or not _exact_fields(program, ["id", "ownerKind", "ownerId", "instructions"]) or not program["id"] is String or program["id"].is_empty() or not program["ownerKind"] is String or program["ownerKind"] not in ["trigger", "extra-action-point", "simple-encounter-result", "complex-encounter-result"] or not program["ownerId"] is String or program["ownerId"].is_empty() or not program["instructions"] is Array or program["instructions"].size() > 4096:
			_reject("Scenario program is malformed.")
			return null
		if ids.has(program["id"]):
			_reject("Scenario program '%s' is duplicated." % program["id"])
			return null
		var instructions: Array[Variant] = []
		for instruction: Variant in program["instructions"]:
			var constructed: Variant = _construct_program_instruction(instruction)
			if constructed == null:
				return null
			instructions.append(constructed)
		ids[program["id"]] = true
		programs.append(ScenarioProgramDefinition.new(program["id"], StringName(program["ownerKind"]), program["ownerId"], instructions))
	return programs

func _construct_program_instruction(instruction: Variant) -> Variant:
	if not instruction is Dictionary or not instruction.get("kind") is String:
		_reject("Scenario instruction is malformed.")
		return null
	if instruction["kind"] == "callScenarioAction":
		return _construct_call_instruction(instruction)
	if instruction["kind"] != "classicAction" or not _exact_fields(instruction, ["kind", "slot", "rawOpcode", "opcode", "id", "gosub", "extraCode"]):
		_reject("Scenario program contains an unknown instruction kind.")
		return null
	for field: String in ["slot", "rawOpcode", "opcode", "id"]:
		if not _is_integer(instruction[field]):
			_reject("Classic instruction field '%s' is not an integer." % field)
			return null
	if _integer(instruction["slot"]) < 0 or not instruction["gosub"] is bool:
		_reject("Classic instruction slot or GOSUB identity is malformed.")
		return null
	var raw_opcode := _integer(instruction["rawOpcode"])
	var normalized := ClassicOpcodeCatalog.normalize(raw_opcode)
	if normalized != _integer(instruction["opcode"]) or instruction["gosub"] != (raw_opcode < 0 and raw_opcode not in [-14, -23]):
		_reject("Classic instruction raw/normalized/GOSUB identity is inconsistent.")
		return null
	if not ClassicOpcodeCatalog.is_executable(normalized):
		_reject("Scenario program requires unsupported Classic opcode %d." % normalized)
		return null
	var extra_code: Array[int] = []
	if instruction["extraCode"] != null:
		var expected_extra_count := 10 if normalized == 92 else 5
		if not instruction["extraCode"] is Array or instruction["extraCode"].size() != expected_extra_count:
			_reject("Classic opcode %d E-code must contain %d integers." % [normalized, expected_extra_count])
			return null
		for extra: Variant in instruction["extraCode"]:
			if not _is_integer(extra):
				_reject("Classic E-code contains a non-integer.")
				return null
			extra_code.append(_integer(extra))
	return ClassicActionDefinition.new(_integer(instruction["slot"]), raw_opcode, normalized, _integer(instruction["id"]), instruction["gosub"], extra_code)

func _construct_call_instruction(record: Dictionary) -> CallScenarioActionInstruction:
	if not _exact_fields(record, ["kind", "actionId", "arguments", "result"]) or not record["actionId"] is String or record["actionId"].is_empty() or not record["arguments"] is Dictionary or record["result"] != null and not record["result"] is String:
		_reject("Scenario Action call instruction is malformed.")
		return null
	var arguments: Dictionary = {}
	var count := [0]
	for name: Variant in record["arguments"].keys():
		if not name is String or name.is_empty():
			_reject("Scenario Action call contains an invalid argument name.")
			return null
		var expression := _construct_safe_expression(record["arguments"][name], count, 0)
		if expression == null:
			return null
		arguments[name] = expression
	return CallScenarioActionInstruction.new(record["actionId"], arguments, "" if record["result"] == null else record["result"])

func _construct_scenario_actions(value: Variant, campaign_id: String) -> Variant:
	if not value is Array:
		_reject("Scenario Actions must be an array.")
		return null
	var actions: Array[ScenarioActionDefinition] = []
	var ids: Dictionary = {}
	var required_prefix := "scenario.%s." % campaign_id
	for record: Variant in value:
		var fields: Array[String] = ["id", "name", "description", "visibility", "category", "abiVersion", "implementationVersion", "stateSchemaVersion", "parameters", "returnType", "allowedContexts", "requiredCapabilities", "persistentState", "backend", "program"]
		if not record is Dictionary or not _exact_fields(record, fields) or not record["id"] is String or record["id"].is_empty() or not record["name"] is String or record["name"].is_empty() or not record["description"] is String or record["visibility"] not in ["public", "private"] or not record["category"] is String or record["category"].is_empty() or not record["returnType"] is String or not SUPPORTED_VALUE_TYPES.has(record["returnType"]) or record["backend"] != "safe" or not record["persistentState"] is Dictionary or not _json_safe(record["persistentState"], 0):
			_reject("Scenario Action definition is malformed or uses an unavailable backend.")
			return null
		if record["id"].begins_with("realmz.") or not record["id"].begins_with(required_prefix) or ids.has(record["id"]):
			_reject("Scenario Action ID '%s' has an invalid or duplicate namespace." % record["id"])
			return null
		for version_field: String in ["abiVersion", "implementationVersion", "stateSchemaVersion"]:
			if _integer(record[version_field]) < 1:
				_reject("Scenario Action '%s' has invalid version field '%s'." % [record["id"], version_field])
				return null
		if not record["parameters"] is Array or record["parameters"].size() > 256:
			_reject("Scenario Action '%s' parameters are malformed." % record["id"])
			return null
		var parameters: Array[ScenarioActionParameter] = []
		var parameter_names: Dictionary = {}
		for parameter: Variant in record["parameters"]:
			if not parameter is Dictionary or not _exact_fields(parameter, ["name", "valueType", "maxLength"]) or not parameter["name"] is String or not _safe_identifier(parameter["name"]) or parameter_names.has(parameter["name"]) or not parameter["valueType"] is String or not SUPPORTED_VALUE_TYPES.has(parameter["valueType"]) or parameter["valueType"] == "void" or (parameter["maxLength"] != null and (_integer(parameter["maxLength"]) < 1 or _integer(parameter["maxLength"]) > 256)):
				_reject("Scenario Action '%s' contains a malformed or duplicate parameter." % record["id"])
				return null
			parameter_names[parameter["name"]] = true
			parameters.append(ScenarioActionParameter.new(parameter["name"], StringName(parameter["valueType"]), -1 if parameter["maxLength"] == null else _integer(parameter["maxLength"])))
		var contexts_value: Variant = _string_array(record["allowedContexts"], "Scenario Action allowed contexts")
		var capabilities_value: Variant = _string_array(record["requiredCapabilities"], "Scenario Action required capabilities")
		if contexts_value == null or capabilities_value == null:
			return null
		var context_strings: Array[String] = contexts_value
		if context_strings.is_empty():
			_reject("Scenario Action '%s' has no allowed calling context." % record["id"])
			return null
		var contexts: Array[StringName] = []
		for context: String in context_strings:
			if not SUPPORTED_ACTION_CONTEXTS.has(context) or contexts.has(StringName(context)):
				_reject("Scenario Action '%s' has an unknown or duplicate calling context '%s'." % [record["id"], context])
				return null
			contexts.append(StringName(context))
		var capabilities: Array[String] = capabilities_value
		for capability: String in capabilities:
			if not SUPPORTED_SAFE_CAPABILITIES.has(capability) or capabilities.count(capability) > 1:
				_reject("Scenario Action '%s' requires unknown capability '%s'." % [record["id"], capability])
				return null
		var program := _construct_safe_program(record["program"], capabilities)
		if program == null:
			return null
		ids[record["id"]] = true
		actions.append(ScenarioActionDefinition.new(record["id"], record["name"], record["description"], StringName(record["visibility"]), StringName(record["category"]), _integer(record["abiVersion"]), _integer(record["implementationVersion"]), _integer(record["stateSchemaVersion"]), parameters, StringName(record["returnType"]), contexts, capabilities, &"safe", program))
	return actions

func _construct_safe_program(value: Variant, declared_capabilities: Array[String]) -> SafeProgramDefinition:
	if not value is Dictionary or not _exact_fields(value, ["format", "instructions"]) or value["format"] != "realmz.safe-bytecode.v1" or not value["instructions"] is Array or value["instructions"].size() > 4096:
		_reject("Safe Scenario Action bytecode is malformed or exceeds 4,096 instructions.")
		return null
	var instructions: Array[SafeInstructionDefinition] = []
	var node_count := [value["instructions"].size()]
	for record: Variant in value["instructions"]:
		var instruction := _construct_safe_instruction(record, node_count)
		if instruction == null:
			return null
		if instruction.kind == SafeInstructionDefinition.Kind.OPERATION and not declared_capabilities.has(instruction.capability):
			_reject("Safe program uses undeclared capability '%s'." % instruction.capability)
			return null
		instructions.append(instruction)
	for index: int in range(instructions.size()):
		var instruction := instructions[index]
		if instruction.kind in [SafeInstructionDefinition.Kind.JUMP, SafeInstructionDefinition.Kind.JUMP_IF_FALSE, SafeInstructionDefinition.Kind.BEGIN_FOR_EACH] and instruction.target > instructions.size():
			_reject("Safe instruction %d jumps outside its program." % index)
			return null
		if instruction.kind == SafeInstructionDefinition.Kind.NEXT_FOR_EACH and (instruction.target < 0 or instruction.target >= instructions.size() or instructions[instruction.target].kind != SafeInstructionDefinition.Kind.BEGIN_FOR_EACH):
			_reject("Safe for-each continuation at %d has an invalid begin target." % index)
			return null
		if instruction.kind == SafeInstructionDefinition.Kind.BEGIN_FOR_EACH and (instruction.target <= index + 1 or instructions[instruction.target - 1].kind != SafeInstructionDefinition.Kind.NEXT_FOR_EACH or instructions[instruction.target - 1].target != index):
			_reject("Safe for-each beginning at %d has an invalid bounded loop target." % index)
			return null
	return SafeProgramDefinition.new(instructions)

func _construct_safe_instruction(value: Variant, node_count: Array) -> SafeInstructionDefinition:
	if not value is Dictionary or not value.get("kind") is String:
		_reject("Safe instruction is malformed.")
		return null
	match value["kind"]:
		"operation":
			if not _exact_fields(value, ["kind", "capability", "arguments", "result"]) or not value["capability"] is String or not SUPPORTED_SAFE_CAPABILITIES.has(value["capability"]) or not value["arguments"] is Dictionary or value["result"] != null and not value["result"] is String:
				_reject("Safe operation instruction is malformed or unavailable.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.OPERATION)
			instruction.capability = value["capability"]
			instruction.result_target = "" if value["result"] == null else value["result"]
			var arguments: Variant = _construct_safe_arguments(value["arguments"], node_count)
			if arguments == null:
				return null
			instruction.set_arguments(arguments)
			return instruction
		"callScenarioAction":
			if not _exact_fields(value, ["kind", "actionId", "arguments", "result"]) or not value["actionId"] is String or value["actionId"].is_empty() or not value["arguments"] is Dictionary or value["result"] != null and not value["result"] is String:
				_reject("Safe Scenario Action call is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.CALL_ACTION)
			instruction.action_id = value["actionId"]
			instruction.result_target = "" if value["result"] == null else value["result"]
			var arguments: Variant = _construct_safe_arguments(value["arguments"], node_count)
			if arguments == null:
				return null
			instruction.set_arguments(arguments)
			return instruction
		"setValue":
			if not _exact_fields(value, ["kind", "scope", "stateScope", "ownerId", "name", "value"]) or value["scope"] not in ["local", "persistent"] or value["stateScope"] != null and not value["stateScope"] is String or value["ownerId"] != null and not value["ownerId"] is String or not value["name"] is String or value["name"].is_empty():
				_reject("Safe value assignment is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.SET_VALUE)
			instruction.scope = StringName(value["scope"])
			instruction.state_scope = "" if value["stateScope"] == null else value["stateScope"]
			instruction.owner_id = "" if value["ownerId"] == null else value["ownerId"]
			instruction.name = value["name"]
			instruction.value = _construct_safe_expression(value["value"], node_count, 0)
			return instruction if instruction.value != null else null
		"jumpIfFalse":
			if not _exact_fields(value, ["kind", "condition", "target"]) or _integer(value["target"]) < 0:
				_reject("Safe conditional jump is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.JUMP_IF_FALSE)
			instruction.condition = _construct_safe_expression(value["condition"], node_count, 0)
			instruction.target = _integer(value["target"])
			return instruction if instruction.condition != null else null
		"jump":
			if not _exact_fields(value, ["kind", "target"]) or _integer(value["target"]) < 0:
				_reject("Safe jump is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.JUMP)
			instruction.target = _integer(value["target"])
			return instruction
		"beginForEach":
			if not _exact_fields(value, ["kind", "itemName", "collection", "endTarget"]) or not value["itemName"] is String or value["itemName"].is_empty() or _integer(value["endTarget"]) < 0:
				_reject("Safe for-each beginning is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.BEGIN_FOR_EACH)
			instruction.item_name = value["itemName"]
			instruction.collection = _construct_safe_expression(value["collection"], node_count, 0)
			instruction.target = _integer(value["endTarget"])
			return instruction if instruction.collection != null else null
		"nextForEach":
			if not _exact_fields(value, ["kind", "beginTarget"]) or _integer(value["beginTarget"]) < 0:
				_reject("Safe for-each continuation is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.NEXT_FOR_EACH)
			instruction.target = _integer(value["beginTarget"])
			return instruction
		"return":
			if not _exact_fields(value, ["kind", "value"]):
				_reject("Safe return instruction is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.RETURN)
			if value["value"] != null:
				instruction.value = _construct_safe_expression(value["value"], node_count, 0)
				if instruction.value == null:
					return null
			return instruction
		"halt":
			if not _exact_fields(value, ["kind", "outcome"]):
				_reject("Safe halt instruction is malformed.")
				return null
			var instruction := SafeInstructionDefinition.new(SafeInstructionDefinition.Kind.HALT)
			instruction.outcome = value["outcome"]
			return instruction
	_reject("Safe program contains unknown instruction kind '%s'." % value["kind"])
	return null

func _construct_safe_arguments(value: Dictionary, node_count: Array) -> Variant:
	var result: Dictionary = {}
	for name: Variant in value.keys():
		if not name is String or name.is_empty():
			_reject("Safe instruction contains an invalid argument name.")
			return null
		var expression := _construct_safe_expression(value[name], node_count, 0)
		if expression == null:
			return null
		result[name] = expression
	return result

func _construct_safe_expression(value: Variant, node_count: Array, depth: int) -> SafeExpressionDefinition:
	node_count[0] += 1
	if node_count[0] > 4096 or depth > 64 or not value is Dictionary or not value.get("kind") is String:
		_reject("Safe expression is malformed or exceeds its complexity limit.")
		return null
	match value["kind"]:
		"literal":
			if not _exact_fields(value, ["kind", "value"]) or not _json_safe(value["value"], depth + 1):
				_reject("Safe literal expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.LITERAL)
			expression.value = value["value"]
			return expression
		"variable":
			if not _exact_fields(value, ["kind", "scope", "stateScope", "ownerId", "name"]) or value["scope"] not in ["parameter", "local", "persistent", "context"] or value["stateScope"] != null and not value["stateScope"] is String or value["ownerId"] != null and not value["ownerId"] is String or not value["name"] is String or value["name"].is_empty():
				_reject("Safe variable expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.VARIABLE)
			expression.scope = StringName(value["scope"])
			expression.state_scope = "" if value["stateScope"] == null else value["stateScope"]
			expression.owner_id = "" if value["ownerId"] == null else value["ownerId"]
			expression.name = value["name"]
			return expression
		"array":
			if not _exact_fields(value, ["kind", "values"]) or not value["values"] is Array or value["values"].size() > 256:
				_reject("Safe array expression is malformed or exceeds 256 entries.")
				return null
			var entries: Array[SafeExpressionDefinition] = []
			for child: Variant in value["values"]:
				var entry := _construct_safe_expression(child, node_count, depth + 1)
				if entry == null:
					return null
				entries.append(entry)
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.ARRAY)
			expression.set_values(entries)
			return expression
		"record":
			if not _exact_fields(value, ["kind", "fields"]) or not value["fields"] is Dictionary or value["fields"].size() > 256:
				_reject("Safe record expression is malformed or oversized.")
				return null
			var fields: Dictionary = {}
			for field_name: Variant in value["fields"].keys():
				if not field_name is String:
					_reject("Safe record field name is malformed.")
					return null
				var field := _construct_safe_expression(value["fields"][field_name], node_count, depth + 1)
				if field == null:
					return null
				fields[field_name] = field
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.RECORD)
			expression.set_fields(fields)
			return expression
		"unary":
			if not _exact_fields(value, ["kind", "operator", "operand"]) or value["operator"] not in ["not", "-"]:
				_reject("Safe unary expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.UNARY)
			expression.operator = StringName(value["operator"])
			expression.operand = _construct_safe_expression(value["operand"], node_count, depth + 1)
			return expression if expression.operand != null else null
		"binary":
			if not _exact_fields(value, ["kind", "operator", "left", "right"]) or value["operator"] not in ["==", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/", "and", "or"]:
				_reject("Safe binary expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.BINARY)
			expression.operator = StringName(value["operator"])
			expression.left = _construct_safe_expression(value["left"], node_count, depth + 1)
			expression.right = _construct_safe_expression(value["right"], node_count, depth + 1)
			return expression if expression.left != null and expression.right != null else null
		"member":
			if not _exact_fields(value, ["kind", "object", "member"]) or not value["member"] is String or value["member"].is_empty():
				_reject("Safe member expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.MEMBER)
			expression.object = _construct_safe_expression(value["object"], node_count, depth + 1)
			expression.member = value["member"]
			return expression if expression.object != null else null
		"collection":
			if not _exact_fields(value, ["kind", "operation", "collection", "itemName", "predicate"]) or value["operation"] not in ["count", "any", "all", "first"] or value["itemName"] != null and not value["itemName"] is String:
				_reject("Safe collection expression is malformed.")
				return null
			var expression := SafeExpressionDefinition.new(SafeExpressionDefinition.Kind.COLLECTION)
			expression.operator = StringName(value["operation"])
			expression.collection = _construct_safe_expression(value["collection"], node_count, depth + 1)
			expression.item_name = "" if value["itemName"] == null else value["itemName"]
			if value["operation"] == "count" and (value["itemName"] != null or value["predicate"] != null) or value["operation"] in ["any", "all"] and (expression.item_name.is_empty() or value["predicate"] == null) or value["operation"] == "first" and ((value["predicate"] == null) != expression.item_name.is_empty()):
				_reject("Safe collection expression has an inconsistent predicate contract.")
				return null
			if value["predicate"] != null:
				expression.predicate = _construct_safe_expression(value["predicate"], node_count, depth + 1)
			return expression if expression.collection != null and (value["predicate"] == null or expression.predicate != null) else null
	_reject("Safe program contains unknown expression kind '%s'." % value["kind"])
	return null
