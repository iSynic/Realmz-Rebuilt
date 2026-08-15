class_name RealmzRuntimeApi
extends RefCounted

const SUPPORTED_SAFE_CAPABILITIES: Array[String] = [
	"core.combat.start",
	"core.economy.grant-treasure",
	"core.economy.take-gold",
	"core.inventory.grant-item",
	"core.presentation.choice",
	"core.presentation.text",
	"core.state.read",
	"core.state.write",
	"core.time.advance",
]

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _action_state: ScenarioActionState
var _rules: RealmzRules
var _character_operations: ClassicCharacterOperations
var _combat_operations: ClassicCombatOperations
var _control_flow_operations: ClassicControlFlowOperations
var _inventory_operations: ClassicInventoryOperations
var _presentation_operations: ClassicPresentationOpcodeHandler
var _world_time_operations: ClassicWorldTimeOpcodeHandler
var _encounter_operations: ClassicEncounterOpcodeHandler
var _classic_handlers: ClassicOpcodeHandlerRegistry
var _handler_registration_error: String = ""


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, action_state: ScenarioActionState, rules: RealmzRules = null) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_action_state = action_state
	_rules = rules if rules != null else RealmzRules.new()
	_character_operations = ClassicCharacterOperations.new(_content, _game_state, _rng, _rules)
	_combat_operations = ClassicCombatOperations.new(_content, _game_state, _rules)
	_control_flow_operations = ClassicControlFlowOperations.new(_content, _game_state, _rng)
	_inventory_operations = ClassicInventoryOperations.new(_content, _game_state, _rules)
	_presentation_operations = ClassicPresentationOpcodeHandler.new(_content, _rng)
	_world_time_operations = ClassicWorldTimeOpcodeHandler.new(_content, _game_state, _rng)
	_encounter_operations = ClassicEncounterOpcodeHandler.new(_content, _game_state)
	_classic_handlers = ClassicOpcodeHandlerRegistry.new()
	for handler: ClassicOpcodeHandler in [_control_flow_operations, _character_operations, _inventory_operations, _combat_operations, _presentation_operations, _world_time_operations, _encounter_operations]:
		if not _classic_handlers.register(handler):
			_handler_registration_error = _classic_handlers.registration_error()
			break


func execute_classic(action: ClassicActionDefinition, request_id: String, context: Dictionary = {}) -> ScenarioRuntimeOperationResult:
	if not _handler_registration_error.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_opcode_registry", _handler_registration_error)
	if _classic_handlers.has_handler(action.opcode):
		return _classic_handlers.execute(action, request_id, context)
	match action.opcode:
		1:
			var message_id := absi(action.operand_id)
			var message := _content.message_by_id(message_id)
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 1 references unavailable message %d." % action.operand_id)
			var event := DomainEvent.new(&"message_shown", {"messageId": message_id, "text": message.text, "source": "classic", "classicClick": action.operand_id > 0})
			if action.operand_id > 0:
				var journal_eligible := GameState.journal_message_id_is_valid(message_id)
				var request := InteractionRequest.from_payload(request_id, &"acknowledge", {
					"prompt": message.text,
					"messageId": message_id,
					"presentation": "classic-textbox",
					"journalEligible": journal_eligible,
					"journalRecorded": journal_eligible and _game_state.journal_message_is_recorded(message_id),
				})
				return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.textbox(message_id), [event])
			return ScenarioRuntimeOperationResult.completed(null, [event])
		6:
			return _request_shop(action.operand_id, request_id)
		2, 48, 56, 107:
			return _start_classic_battle(action, request_id)
		10:
			return _grant_treasure(action.operand_id, request_id)
		11:
			var no_experience_items: Array[String] = []
			return _begin_reward(&"scenario", "classic.experience.%d" % action.operand_id, maxi(0, action.operand_id), WealthState.new(), no_experience_items, request_id)
		20:
			return _move_between_maps(action, false, true)
		26:
			return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"acknowledge", {"prompt": "Continue", "soundId": 30005}), ScenarioRuntimeContinuation.empty(ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE))
		29:
			return _acquire_player_map(action, request_id)
		31:
			return _request_character_ability(action, request_id)
		32:
			return _configure_temple(action)
		37:
			return _move_between_maps(action, true)
		45:
			return _move_between_maps(action, false, false)
		65:
			return _grant_random_items(action, request_id)
		73:
			return _configure_shop(action, request_id)
		82, 83:
			_game_state.priest_turning_allowed = action.opcode == 83
			var turning_message := "You regain your ability to turn undead and nether spawn." if _game_state.priest_turning_allowed else "You may not use your ability to turn undead or nether spawn."
			return ScenarioRuntimeOperationResult.completed(_game_state.priest_turning_allowed, [
				DomainEvent.new(&"priest_turning_availability_changed", {"allowed": _game_state.priest_turning_allowed, "source": "classic"}),
				DomainEvent.new(&"message_shown", {"text": turning_message, "source": "classic"}),
			])
		90:
			return _take_experience(action)
		102:
			return _level_selected_characters()
		119:
			return _revive_after_combat_macro(context)
		120:
			return _alter_combat_monsters(action)
		121:
			return _deanimate_lower_undead()
		123:
			return _cause_monsters_to_route(action, context)
		124:
			return _spawn_classic_monsters(action)
		126:
			return _branch_battle_round_macro(action)
		127:
			return _continue_if_monster_present(action)
		_:
			return ScenarioRuntimeOperationResult.failed(&"unsupported_classic_opcode", "No Realmz Runtime API operation owns Classic opcode %d." % action.opcode)


func _take_experience(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	var amount := action.operand_id
	var mode := 0
	if not action.extra_code.is_empty():
		amount = action.extra_code[0]
		mode = action.extra_code[1] if action.extra_code.size() > 1 else 0
	var targets: Array[CharacterState] = []
	match mode:
		1:
			targets = _game_state.selected_characters()
		2:
			targets = _game_state.party.characters()
			if not targets.is_empty():
				amount = int(float(amount) / float(targets.size()))
		_:
			targets = _game_state.party.characters()
	for character: CharacterState in targets:
		character.experience -= amount
	return ScenarioRuntimeOperationResult.completed(targets.size(), [DomainEvent.new(&"experience_taken", {"amountEach": amount, "mode": mode, "targetIds": targets.map(func(character: CharacterState) -> String: return character.id), "source": "classic"})])


func _grant_random_items(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 65 requires a five-value Extra Code row.")
	var count := action.extra_code[0]
	if count < 0:
		count = _rng.draw(absi(count), &"classic.random-item-count")
	if count < 0 or count > 20 or action.extra_code[1] > action.extra_code[2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_random_item_range", "Classic opcode 65 has an invalid count or item range.")
	var item_ids: Array[String] = []
	for index: int in count:
		var classic_item_id := _rng.draw_between(action.extra_code[1], action.extra_code[2], StringName("classic.random-item.%d" % index))
		var definition := _content.item_by_classic_id(classic_item_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic opcode 65 generated unavailable item %d." % classic_item_id)
		item_ids.append(definition.id)
	return _begin_reward(&"scenario", "classic.random-items", 0, WealthState.new(), item_ids, request_id)


func _level_selected_characters() -> ScenarioRuntimeOperationResult:
	var leveled: Array[String] = []
	for character: CharacterState in _game_state.selected_characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		if race == null or caste == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_character_profile", "Classic opcode 102 requires source-defined race and caste profiles.")
		character.experience = 1
		if _rules.characters.level_up(character, race, caste, _rng) == null:
			return ScenarioRuntimeOperationResult.failed(&"character_level_failed", "Classic opcode 102 could not level character '%s'." % character.id)
		leveled.append(character.id)
	return ScenarioRuntimeOperationResult.completed(leveled, [DomainEvent.new(&"characters_leveled", {"characterIds": leveled, "source": "classic"})])


func _branch_battle_round_macro(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"battle_macro_outside_combat", "Classic opcode 126 requires an active battle macro.")
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 126 requires a five-value Extra Code row.")
	var combat := _game_state.combat
	if combat.macro_id > 0:
		return ScenarioRuntimeOperationResult.completed(false, [], ScenarioVmDirective.finish())
	var mode := action.extra_code[0]
	var matched := false
	match mode:
		0:
			matched = combat.round_number - 1 == action.extra_code[1]
		1:
			matched = _rng.draw(100, &"classic.battle-round-macro-percent") <= action.extra_code[1]
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_test", "Classic opcode 126 has an invalid round test mode.")
	if not matched:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"battle_macro_tested", {"matched": false, "mode": mode, "round": combat.round_number, "source": "classic"})], ScenarioVmDirective.finish())
	if action.extra_code[2] != 1:
		combat.macro_id = 0
	var target_id := action.extra_code[3]
	if action.extra_code[2] == 2:
		target_id = _rng.draw_between(action.extra_code[3], action.extra_code[4], &"classic.battle-round-macro-target")
	if target_id <= 0:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_target", "Classic opcode 126 references an invalid Extra Action Point target.")
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"battle_macro_tested", {"matched": true, "mode": mode, "round": combat.round_number, "targetId": target_id, "repeating": action.extra_code[2] == 1, "source": "classic"})], ScenarioVmDirective.branch_xap(target_id, false))


func _continue_if_monster_present(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"monster_test_outside_combat", "Classic opcode 127 requires an active battle macro.")
	var definition := _content.monster_by_classic_id_for_set(absi(action.operand_id), _game_state.monster_set)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 127 references unavailable monster %d." % action.operand_id)
	var present := false
	for monster: MonsterState in _game_state.combat.monsters():
		var present_definition := _content.monster_by_id(monster.definition_id)
		if present_definition != null and present_definition.classic_id == definition.classic_id and monster.current_health > 0:
			present = true
			break
	var directive: ScenarioVmDirective = null if present else ScenarioVmDirective.finish()
	return ScenarioRuntimeOperationResult.completed(present, [DomainEvent.new(&"battle_monster_presence_checked", {"classicMonsterId": definition.classic_id, "present": present, "source": "classic"})], directive)


func _alter_combat_monsters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_monsters_altered", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 120 requires a five-value Extra Code row.")
	var target_kind := action.extra_code[0]
	var definition := _content.monster_by_classic_id_for_set(absi(action.extra_code[1]), _game_state.monster_set)
	var remaining := maxi(0, action.extra_code[2])
	if target_kind < 1 or target_kind > 2 or definition == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_monster_target", "Classic opcode 120 references an unavailable monster kind or identity.")
	var candidates := _game_state.party.allies() if target_kind == 1 else _game_state.combat.monsters()
	var altered: Array[String] = []
	for monster: MonsterState in candidates:
		if remaining <= 0:
			break
		var candidate_definition := _content.monster_by_id(monster.definition_id)
		if candidate_definition == null or candidate_definition.classic_id != definition.classic_id:
			continue
		if action.extra_code[3] != -1:
			monster.icon_id = action.extra_code[3]
			altered.append(monster.id)
			remaining -= 1
		elif action.extra_code[4] != -1 and monster.traitor != (action.extra_code[4] != 0):
			monster.traitor = action.extra_code[4] != 0
			altered.append(monster.id)
			remaining -= 1
	return ScenarioRuntimeOperationResult.completed(altered.size(), [DomainEvent.new(&"combat_monsters_altered", {"count": altered.size(), "monsterIds": altered, "classicMonsterId": definition.classic_id, "targetKind": target_kind, "source": "classic"})])


func _cause_monsters_to_route(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_route_applied", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 123 requires a five-value Extra Code row.")
	var source_traitor := true
	var source_id := str(context.get("combatantId", ""))
	var source_monster := _game_state.combat.monster_by_id(source_id)
	if source_monster != null:
		source_traitor = source_monster.traitor
	var definition_ids: Dictionary = {}
	for classic_id: int in action.extra_code:
		if classic_id == 0:
			continue
		var definition := _content.monster_by_classic_id_for_set(absi(classic_id), _game_state.monster_set)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 123 references unavailable monster %d." % classic_id)
		definition_ids[definition.classic_id] = true
	var routed: Array[String] = []
	for monster: MonsterState in _game_state.combat.monsters():
		var routed_definition := _content.monster_by_id(monster.definition_id)
		if routed_definition != null and monster.current_health > 0 and monster.traitor == source_traitor and definition_ids.has(routed_definition.classic_id):
			monster.conditions.set_value(ConditionRules.RUNS_AWAY, -1)
			monster.surrender_percent = 50
			routed.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(routed.size(), [DomainEvent.new(&"combat_route_applied", {"count": routed.size(), "monsterIds": routed, "traitorSide": source_traitor, "source": "classic"})])


func _revive_after_combat_macro(context: Dictionary) -> ScenarioRuntimeOperationResult:
	var living_party := 0
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			living_party += 1
	if living_party == 0:
		var revived_party: Array[String] = []
		for character: CharacterState in _game_state.party.characters():
			character.current_health = 1
			character.conditions.set_value(ConditionRules.ANIMATED, 0)
			revived_party.append(character.id)
		return ScenarioRuntimeOperationResult.completed(revived_party, [DomainEvent.new(&"party_revived", {"characterIds": revived_party, "source": "classic-death-macro"})], ScenarioVmDirective.finish())
	if _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"revival_outside_combat", "Classic opcode 119 has no combatant to revive.")
	var combatant_id := str(context.get("combatantId", ""))
	var monster := _game_state.combat.monster_by_id(combatant_id)
	if monster == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_combatant_context", "Classic opcode 119 requires its death-macro combatant identity.")
	monster.current_health = 1
	monster.traitor = false
	return ScenarioRuntimeOperationResult.completed(monster.id, [DomainEvent.new(&"monster_revived", {"monsterId": monster.id, "source": "classic-death-macro"})])


func resolve_program_id(program_id: String) -> String:
	return _control_flow_operations.resolve_program_id(program_id)


func execute_safe(capability: String, arguments: Dictionary, request_id: String) -> ScenarioRuntimeOperationResult:
	match capability:
		"core.time.advance":
			if not _whole_number(arguments.get("minutes")) or int(arguments["minutes"]) < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Advance Time requires non-negative integer minutes.")
			return _with_age_update_interactions(ScenarioRuntimeOperationResult.completed(true, _rules.clock.advance_minutes(_game_state, _content, int(arguments["minutes"]))), request_id, ScenarioRuntimeContinuation.SAFE_AGE_UPDATES)
		"core.inventory.grant-item":
			if not arguments.get("characterId") is String or not arguments.get("itemId") is String or arguments.get("identified", false) is not bool:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Grant Item requires characterId, itemId, and optional identified bool.")
			return _grant_item(arguments["characterId"], arguments["itemId"], arguments.get("identified", false))
		"core.economy.grant-treasure":
			if not arguments.get("treasureId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Grant Treasure requires a stable treasureId.")
			var treasure := _content.treasure_by_id(arguments["treasureId"])
			if treasure == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Treasure '%s' is unavailable." % arguments["treasureId"])
			return _grant_treasure_definition(treasure, request_id)
		"core.economy.take-gold":
			if not _whole_number(arguments.get("amount")) or int(arguments["amount"]) < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Take Gold requires a non-negative integer amount.")
			var amount := int(arguments["amount"])
			var paid := _rules.economy.take(_game_state.party, amount, WealthState.Kind.GOLD)
			return ScenarioRuntimeOperationResult.completed(paid, [DomainEvent.new(&"wealth_taken", {"amount": amount, "kind": WealthState.Kind.GOLD, "paid": paid, "source": "scenario-action"})])
		"core.combat.start":
			if not arguments.get("battleId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Start Battle requires a stable battleId.")
			var battle := _content.battle_by_id(arguments["battleId"])
			if battle == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Battle '%s' is unavailable." % arguments["battleId"])
			return _start_battle_definition(battle, request_id, "scenario-action", ScenarioBattleCaller.safe_continue())
		"core.presentation.text":
			if not arguments.get("text") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Show Text requires a string 'text' argument.")
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new("message_shown", {"text": arguments["text"], "source": "scenario-action"})])
		"core.presentation.choice":
			if not arguments.get("prompt") is String or not arguments.get("options") is Array or arguments["options"].is_empty() or arguments["options"].size() > 256:
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Choice requires a prompt and one to 256 options.")
			var options: Array[Dictionary] = []
			for index: int in range(arguments["options"].size()):
				var label: Variant = arguments["options"][index]
				if not label is String:
					return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "Choice option %d is not a string." % index)
				options.append({"id": "choice:%d" % index, "label": label})
			var request := InteractionRequest.from_payload(request_id, &"scenario_choice", {"prompt": arguments["prompt"], "options": options})
			return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.safe_choice(options.size()))
		"core.state.read":
			var state_identity := _state_identity(arguments)
			if state_identity.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "State Read requires a valid scope and name or numeric ID.")
			return ScenarioRuntimeOperationResult.completed(_action_state.read(state_identity[0], state_identity[1], state_identity[2], arguments.get("default")))
		"core.state.write":
			var state_identity := _state_identity(arguments)
			if state_identity.is_empty() or not arguments.has("value"):
				return ScenarioRuntimeOperationResult.failed(&"invalid_action_arguments", "State Write requires a valid scope, name or numeric ID, and value.")
			if not _action_state.write(state_identity[0], state_identity[1], state_identity[2], arguments["value"]):
				return ScenarioRuntimeOperationResult.failed(&"scenario_state_limit", "Scenario Action state rejected an unsafe or oversized value.")
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new("scenario_state_changed", {"scope": state_identity[0], "ownerId": state_identity[1], "name": state_identity[2]})])
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_action_capability", "Scenario Action capability '%s' is not available." % capability)


func resume_safe(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String = "") -> ScenarioRuntimeOperationResult:
	if continuation == null or response == null or not response.is_supported_kind():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The response payload does not match its interaction kind.")
	match continuation.kind:
		ScenarioRuntimeContinuation.SAFE_AGE_UPDATES:
			return _resume_age_update_interactions(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_CHOICE:
			var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
			var option_count: int = choice_continuation.option_count
			var choice := response.body as InteractionResponse.ChoiceBody
			if response.kind != &"scenario_choice" or choice == null or choice.index < 0 or choice.index >= option_count:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Scenario choice response must identify an available option.")
			return ScenarioRuntimeOperationResult.completed(choice.index)
		ScenarioRuntimeContinuation.SAFE_COMBAT:
			return _resume_battle(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT:
			return _resume_battle_retreat(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_COMBAT_AGE:
			return _resume_combat_age_updates(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO:
			return _resume_battle_macro(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO:
			return _resume_combat_death_macro(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY:
			return _resume_ally_selection(continuation, response)
		ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE:
			return _resume_fumble_recovery(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		ScenarioRuntimeContinuation.CLASSIC_REWARD:
			return _resume_reward(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Scenario Action interaction continuation is unavailable.")


func simple_encounter_by_id(encounter_id: int) -> SimpleEncounterDefinition:
	return _content.simple_encounter_by_id(encounter_id)


func write_action_state(state_scope: String, owner_id: String, name: String, value: Variant) -> bool:
	return _action_state.write(state_scope, owner_id, name, value)


func read_action_state(state_scope: String, owner_id: String, name: String, default_value: Variant = null) -> Variant:
	return _action_state.read(state_scope, owner_id, name, default_value)


func request_available_shop(request_id: String) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_id(_game_state.active_shop_id)
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"shop_unavailable", "No configured Classic shop is available at this location.")
	return _request_shop_definition(shop, request_id, _game_state.shop_accept_ranges())


func request_available_temple(request_id: String) -> ScenarioRuntimeOperationResult:
	if not _game_state.temple_available:
		return ScenarioRuntimeOperationResult.failed(&"temple_unavailable", "No Classic temple is available at this location.")
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	var characters := _game_state.party.characters()
	var selected_character_id := "" if characters.is_empty() else characters[0].id
	var continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, _game_state.temple_cost_percent, _game_state.bank_available, selected_character_id)
	return ScenarioRuntimeOperationResult.waiting(_temple_request(_game_state.temple_cost_percent, request_id, selected_character_id), continuation, [
		DomainEvent.new(&"temple_opened", {"costPercent": _game_state.temple_cost_percent, "bankAvailable": _game_state.bank_available}),
		DomainEvent.new(&"music_requested", {"musicId": 10, "source": "classic-temple"}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-entry"}),
	])


func request_available_bank(request_id: String) -> ScenarioRuntimeOperationResult:
	if not _game_state.bank_available:
		return ScenarioRuntimeOperationResult.failed(&"bank_unavailable", "No Classic bank is available at this location.")
	return _request_banking(request_id)


func resume_classic(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if continuation == null or response == null or not response.is_supported_kind():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The response payload does not match its interaction kind.")
	match continuation.kind:
		ScenarioRuntimeContinuation.CLASSIC_AGE_UPDATES:
			return _resume_age_update_interactions(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_SIMPLE_ENCOUNTER:
			return _resume_simple_encounter(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_COMPLEX_ENCOUNTER:
			return _resume_complex_encounter(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_ACKNOWLEDGE:
			if response.kind != &"acknowledge":
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Acknowledgement response has the wrong kind.")
			return ScenarioRuntimeOperationResult.completed(true)
		ScenarioRuntimeContinuation.CLASSIC_TEXTBOX:
			var acknowledgement := response.body as InteractionResponse.AcknowledgeBody
			if response.kind != &"acknowledge" or acknowledgement == null:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic textbox response must acknowledge the displayed message.")
			if not acknowledgement.take_note:
				return ScenarioRuntimeOperationResult.completed(true)
			var message_id := (continuation.body as ScenarioRuntimeContinuation.TextBody).message_id
			if not GameState.journal_message_id_is_valid(message_id):
				return ScenarioRuntimeOperationResult.failed(&"journal_message_unrepresentable", "Classic message %d cannot be stored in the 3,000-entry journal flag table." % message_id)
			var already_recorded := _game_state.journal_message_is_recorded(message_id)
			if not _game_state.record_journal_message(message_id):
				return ScenarioRuntimeOperationResult.failed(&"journal_record_failed", "Classic message %d could not be recorded in the journal." % message_id)
			var events: Array[DomainEvent] = []
			if not already_recorded:
				events.append(DomainEvent.new(&"journal_entry_recorded", {"messageId": message_id}))
			return ScenarioRuntimeOperationResult.completed(true, events)
		ScenarioRuntimeContinuation.CLASSIC_PLAYER_MAP:
			var map_acknowledgement := response.body as InteractionResponse.AcknowledgeBody
			if response.kind != &"acknowledge" or map_acknowledgement == null or map_acknowledgement.take_note:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic player-map display requires an empty acknowledgement response.")
			var player_map_id := (continuation.body as ScenarioRuntimeContinuation.TextBody).player_map_id
			if _content.world.player_map_by_id(player_map_id) == null or not _game_state.world.has_map(player_map_id):
				return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic player-map continuation references unavailable acquired content.")
			return ScenarioRuntimeOperationResult.completed(true)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT:
			return _resume_battle(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT:
			return _resume_battle_retreat(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE:
			return _resume_combat_age_updates(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO:
			return _resume_battle_macro(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO:
			return _resume_combat_death_macro(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY:
			return _resume_ally_selection(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE:
			return _resume_fumble_recovery(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_REWARD:
			return _resume_reward(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_CHARACTER_SELECTION:
			return _resume_character_selection(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_CHARACTER_ABILITY:
			return _resume_character_ability(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_CHOICE:
			return _resume_classic_choice(continuation, response)
		ScenarioRuntimeContinuation.CLASSIC_SHOP:
			return _resume_shop(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE:
			return _resume_temple(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT:
			return _resume_temple_exit(continuation, response, request_id)
		ScenarioRuntimeContinuation.CLASSIC_BANKING:
			return _resume_banking(continuation, response, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_interaction_continuation", "Classic interaction continuation is unavailable.")


func _acquire_player_map(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var classic_id := absi(action.operand_id)
	var definition := _content.world.player_map_by_classic_id(classic_id)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_player_map", "Classic opcode 29 references unavailable player-map record %d." % classic_id)
	var already_acquired: bool = _game_state.world.has_map(definition.id)
	_game_state.world.acquire_map(definition.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"player_map_acquired", {"playerMapId": definition.id, "classicId": definition.classic_id, "name": definition.name, "alreadyAcquired": already_acquired, "source": "classic"})]
	if action.operand_id >= 0:
		events.append(DomainEvent.new(&"message_shown", {"text": "You gain a map, to view the map use Maps/Notes in the Menu.", "source": "classic-player-map"}))
		return ScenarioRuntimeOperationResult.completed(definition.id, events)
	var request := InteractionRequest.from_payload(request_id, &"acknowledge", {"prompt": definition.name, "presentation": "player-map", "playerMapId": definition.id})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.player_map(definition.id), events)


func _with_age_update_interactions(operation: ScenarioRuntimeOperationResult, request_id: String, continuation_kind: StringName) -> ScenarioRuntimeOperationResult:
	if operation == null or operation.state != ScenarioRuntimeOperationResult.State.COMPLETED:
		return operation
	var updates := CharacterAgingResult.update_bodies(operation.events)
	if updates.is_empty():
		return operation
	var continuation := ScenarioRuntimeContinuation.age_updates(continuation_kind, updates, 1, operation.value, operation.directive)
	var events: Array[DomainEvent] = []
	events.assign(operation.events)
	events.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, updates[0]), continuation, events)


func _resume_age_update_interactions(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or not response.body is InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var age := continuation.body as ScenarioRuntimeContinuation.AgeBody
	var updates := age.updates
	var index := age.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "Classic age-update continuation is invalid.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		var next_continuation := ScenarioRuntimeContinuation.age_updates(continuation.kind, updates, index + 1, age.value, age.directive)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, next_payload), next_continuation, events)
	return ScenarioRuntimeOperationResult.completed(age.value, events, age.directive)


func _resume_simple_encounter(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
	var encounter := _content.simple_encounter_by_id(choice_continuation.encounter_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Simple Encounter is unavailable.")
	var choice := response.body as InteractionResponse.ChoiceBody
	if response.kind != &"encounter_choice" or choice == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response has the wrong kind.")
	if choice.cancelled:
		if not encounter.can_back_out:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Simple Encounter cannot be cancelled.")
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "simple", "encounterId": encounter.id})], ScenarioVmDirective.finish())
	var selected_index := choice.index
	var option_indexes := choice_continuation.option_indexes
	if not option_indexes.is_empty():
		if selected_index < 0 or selected_index >= option_indexes.size() or not _whole_number(option_indexes[selected_index]):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the available choices.")
		selected_index = int(option_indexes[selected_index])
	var selected := encounter.response_at(selected_index)
	if selected == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the authored choices.")
	_game_state.record_encounter_attempt(&"simple", encounter.id)
	return ScenarioRuntimeOperationResult.completed(selected.id, [DomainEvent.new(&"encounter_response_selected", {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index})], ScenarioVmDirective.branch_program(selected.result_program_id, choice_continuation.gosub, {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index}))


func _resume_complex_encounter(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
	var encounter := _content.complex_encounter_by_id(choice_continuation.encounter_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Complex Encounter is unavailable.")
	var selection := response.body as InteractionResponse.ComplexEncounterBody
	if response.kind != &"complex_encounter" or selection == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex Encounter response requires an action.")
	var action := String(selection.action)
	var outcome := 0
	var context: Dictionary = {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": action}
	var events: Array[DomainEvent] = []
	match action:
		"back":
			if not encounter.can_back_out:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Complex Encounter cannot be cancelled.")
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "complex", "encounterId": encounter.id})], ScenarioVmDirective.finish())
		"choice":
			if selection.slot < 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action response requires an authored slot.")
			var slot := selection.slot
			var labels := encounter.action_labels()
			if slot < 0 or slot >= labels.size() or labels[slot].strip_edges() in ["", "*"]:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action slot is unavailable.")
			outcome = encounter.action_result
			context["optionSlot"] = slot
		"word":
			if selection.word.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex word response requires text.")
			outcome = _complex_word_outcome(encounter, selection.word)
		"spell":
			if selection.classic_spell_id == 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex spell response requires a Classic spell ID.")
			outcome = _complex_catalog_outcome(encounter.spell_ids(), encounter.spell_results(), selection.classic_spell_id)
		"item":
			if selection.classic_item_id == 0:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex item response requires a Classic item ID.")
			var item_id := selection.classic_item_id
			if not _party_has_classic_item(absi(item_id)):
				return ScenarioRuntimeOperationResult.failed(&"item_not_owned", "The party does not possess the selected Complex Encounter item.")
			outcome = _complex_catalog_outcome(encounter.item_ids(), encounter.item_results(), item_id)
		"thief":
			return _resume_thief_encounter(encounter, continuation, response, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex Encounter action '%s' is unavailable." % action)
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Complex Encounter produced invalid result %d." % outcome)
	_game_state.record_encounter_attempt(&"complex", encounter.id)
	events.append(DomainEvent.new(&"encounter_response_selected", {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": action, "outcome": outcome}))
	return _complex_outcome(encounter, outcome, choice_continuation.gosub, context, events)


func _complex_outcome(encounter: ComplexEncounterDefinition, outcome: int, gosub: bool, context: Dictionary, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var program_id := encounter.result_program_id(outcome)
	if program_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Complex Encounter result is outside 1 through 4.")
	return ScenarioRuntimeOperationResult.completed(outcome, events, ScenarioVmDirective.branch_program(program_id, gosub, context))


func _complex_word_outcome(encounter: ComplexEncounterDefinition, entered_word: String) -> int:
	if entered_word.is_empty() or encounter.word_result == 0:
		return 4
	var expected := encounter.expected_word().left(40)
	var first_space := expected.find(" ")
	if first_space >= 0:
		expected = expected.left(first_space)
	return encounter.word_result if entered_word.to_lower().begins_with(expected) else 4


func _complex_catalog_outcome(ids: Array[int], results: Array[int], selected_id: int) -> int:
	for index: int in mini(ids.size(), results.size()):
		if ids[index] != 0 and absi(ids[index]) == absi(selected_id):
			return results[index]
	return 4


func _resume_thief_encounter(encounter: ComplexEncounterDefinition, continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
	var selection := response.body as InteractionResponse.ComplexEncounterBody
	if thief_encounter == null or selection == null or selection.action_index < 0 or selection.character_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter response requires an available action and character.")
	var character := _game_state.party.character_by_id(selection.character_id)
	var action_index := selection.action_index
	var flags := _game_state.thief_encounter_type_flags(thief_encounter)
	if character == null or character.current_health <= 0 or action_index < 0 or action_index >= 8 or not flags[action_index]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter action or character is unavailable.")
	flags[action_index] = false
	var trap_armed := flags[9]
	if trap_armed and action_index in [4, 6, 7]:
		if action_index == 4:
			flags[action_index] = true
		return _spring_thief_trap(encounter, thief_encounter, continuation, character, flags, request_id)
	var modifiers := thief_encounter.modifiers()
	var chance := clampi(character.ability_value(action_index) + modifiers[action_index], 0, 100)
	if action_index in [2, 4, 6, 7]:
		chance = mini(chance, 90)
	var succeeded := _rng.draw(100, &"classic.thief-encounter") <= chance
	if succeeded:
		if action_index == 1 and trap_armed:
			flags[2] = true
		elif action_index == 2:
			flags[9] = false
	elif trap_armed and action_index != 1:
		return _spring_thief_trap(encounter, thief_encounter, continuation, character, flags, request_id)
	_game_state.set_thief_encounter_type_flags(thief_encounter, flags)
	var codes := thief_encounter.success_codes() if succeeded else thief_encounter.failure_codes()
	var outcome := codes[action_index]
	var text_ids := thief_encounter.success_text() if succeeded else thief_encounter.failure_text()
	var sound_ids := thief_encounter.success_sounds() if succeeded else thief_encounter.failure_sounds()
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_action_resolved", {"encounterId": encounter.id, "thiefEncounterId": thief_encounter.id, "characterId": character.id, "actionIndex": action_index, "chancePercent": chance, "succeeded": succeeded, "messageId": text_ids[action_index], "soundId": sound_ids[action_index]})]
	if outcome == 0:
		var request := _encounter_operations.complex_encounter_request(encounter, request_id)
		if request == null:
			return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after the Thief action.")
		return ScenarioRuntimeOperationResult.waiting(request, continuation, events)
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Thief Encounter produced invalid result %d." % outcome)
	_game_state.record_encounter_attempt(&"complex", encounter.id)
	return _complex_outcome(encounter, outcome, (continuation.body as ScenarioRuntimeContinuation.ChoiceBody).gosub, {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": "thief", "actionIndex": action_index, "characterId": character.id}, events)


func _spring_thief_trap(encounter: ComplexEncounterDefinition, thief_encounter: ThiefEncounterDefinition, continuation: ScenarioRuntimeContinuation, character: CharacterState, flags: Array[bool], request_id: String) -> ScenarioRuntimeOperationResult:
	flags[9] = false
	flags[1] = false
	flags[6] = true
	_game_state.set_thief_encounter_type_flags(thief_encounter, flags)
	var damage := _rng.draw_between(thief_encounter.low_damage, thief_encounter.high_damage, &"classic.thief-trap-damage") if thief_encounter.high_damage >= thief_encounter.low_damage and thief_encounter.high_damage > 0 else 0
	if damage > 0:
		character.current_health = maxi(-32_768, character.current_health - damage)
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_trap_sprung", {"encounterId": encounter.id, "thiefEncounterId": thief_encounter.id, "characterId": character.id, "damage": damage, "spellId": thief_encounter.spell_id})]
	var request := _encounter_operations.complex_encounter_request(encounter, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after its trap.")
	return ScenarioRuntimeOperationResult.waiting(request, continuation, events)


func _state_identity(arguments: Dictionary) -> Array[String]:
	var state_scope := str(arguments.get("scope", "campaign"))
	var owner_id := str(arguments.get("ownerId", ""))
	var name_value: Variant = arguments.get("name", arguments.get("id"))
	if state_scope.is_empty() or name_value == null or (not name_value is String and not name_value is int):
		return []
	return [state_scope, owner_id, str(name_value)]


func _resume_classic_choice(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != &"yes_no" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic choice response requires an accepted bool.")
	var choice_continuation := continuation.body as ScenarioRuntimeContinuation.ChoiceBody
	var values := choice_continuation.values
	if values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic choice continuation is malformed.")
	var apply_result: bool = body.accepted != (int(values[0]) != 0)
	if not apply_result:
		return ScenarioRuntimeOperationResult.completed(false)
	match int(values[1]):
		0:
			return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.finish())
		1:
			return _branch_xap(int(values[2]), choice_continuation.gosub)
		4:
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_elimination_requested")])
	return ScenarioRuntimeOperationResult.failed(&"unsupported_choice_target", "Classic choice branch mode %d is not available." % int(values[1]))


func _resume_character_selection(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != &"character_selection" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection response requires characterIds.")
	var character_continuation := continuation.body as ScenarioRuntimeContinuation.CharacterBody
	var requested: Array[String] = body.character_ids
	if requested.size() != character_continuation.count:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection returned the wrong number of characters.")
	var picked: Array[String] = []
	for value: Variant in requested:
		if not value is String or picked.has(value):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection contains an invalid or duplicate ID.")
		var character := _game_state.party.character_by_id(value)
		if character == null or not character_continuation.allow_dead and character.current_health <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection includes an ineligible party member.")
		picked.append(value)
	var selected := picked
	if character_continuation.invert:
		selected = []
		for character: CharacterState in _game_state.party.characters():
			if not picked.has(character.id):
				selected.append(character.id)
	if not _game_state.set_selected_character_ids(selected):
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_selection", "Selected character state rejected the response.")
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected", {"characterIds": selected, "inverted": character_continuation.invert})])


func _request_character_ability(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 31 requires a five-value Extra Code row.")
	var check_index := int(action.extra_code[0])
	var attribute_check := int(action.extra_code[2]) != 0
	if not attribute_check and (check_index < 0 or check_index >= 15):
		return ScenarioRuntimeOperationResult.failed(&"unsupported_character_ability_index", "Classic opcode 31 ability index %d is outside the source character record." % check_index)
	var eligible: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			eligible.append({"id": character.id, "name": character.name})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic ability check has no living party member.")
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"character_selection", {"count": 1, "eligible": eligible, "allowDead": false}), ScenarioRuntimeContinuation.character_ability(action.extra_code, action.gosub))


func _resume_character_ability(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != &"character_selection" or body == null or body.character_ids.size() != 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check requires one selected character.")
	var character := _game_state.party.character_by_id(body.character_ids[0])
	var character_continuation := continuation.body as ScenarioRuntimeContinuation.CharacterBody
	var values := character_continuation.values
	if character == null or character.current_health <= 0 or values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check selected an unavailable character.")
	_game_state.set_selected_character_ids([character.id])
	var check_index := int(values[0])
	var modifier := int(values[1])
	var attribute_check := int(values[2]) != 0
	var roll := _rng.draw(25 if attribute_check else 100, &"classic.character-ability")
	if attribute_check and check_index not in [0, 1, 2, 3, 4, 6]:
		var inert_event := DomainEvent.new(&"character_ability_checked", {"characterId": character.id, "checkIndex": check_index, "attribute": true, "modifier": modifier, "roll": roll, "branch": "none", "sourceDefined": false})
		return ScenarioRuntimeOperationResult.completed(character.id, [inert_event])
	var check_value := _character_attribute(character, check_index) if attribute_check else character.ability_value(check_index)
	var passed := roll - modifier < check_value if attribute_check else roll <= check_value + modifier
	var target_id := int(values[3] if passed else values[4])
	var event := DomainEvent.new(&"character_ability_checked", {"characterId": character.id, "checkIndex": check_index, "attribute": attribute_check, "value": check_value, "modifier": modifier, "roll": roll, "passed": passed})
	var branch := _branch_xap(target_id, character_continuation.gosub)
	branch.events.append(event)
	return branch


func _party_has_classic_item(classic_item_id: int, minimum_charges: int = -1, equipped_only: bool = false) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in _game_state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == definition.id and (minimum_charges < 0 or instance.charges >= minimum_charges) and (not equipped_only or instance.equipped):
				return true
	return false


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_xap(target_id, gosub))


func _move_between_maps(action: ClassicActionDefinition, dungeon_move: bool, activate_destination: bool = false) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic map movement requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic map movement requires the party's current map.")
	var target_type := (&"dungeon" if action.extra_code[0] == 0 else &"land") if dungeon_move else current_map.level_type
	var map_index := action.extra_code[1] if dungeon_move else current_map.level_index if action.extra_code[0] < 0 else action.extra_code[0]
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[3]) if dungeon_move else Vector2i(_game_state.party.coordinate.x if action.extra_code[1] < 0 else action.extra_code[1], _game_state.party.coordinate.y if action.extra_code[2] < 0 else action.extra_code[2])
	var target_map := _content.world.map_by_type_and_index(target_type, map_index)
	if target_map == null or target_map.topology.cell_at(coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_teleport", "Classic map movement references an unavailable destination.")
	var source_map_id := _game_state.party.map_id
	var source_coordinate := _game_state.party.coordinate
	_game_state.party.map_id = target_map.id
	_game_state.party.coordinate = coordinate
	_game_state.world.mark_visited(target_map.id, coordinate)
	var sound_id := action.extra_code[4] if dungeon_move else action.extra_code[3]
	var message_id := 0 if dungeon_move else action.extra_code[4]
	var events: Array[DomainEvent] = [DomainEvent.new(&"party_teleported", {"sourceMapId": source_map_id, "sourceX": source_coordinate.x, "sourceY": source_coordinate.y, "mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "soundId": sound_id, "messageId": message_id, "source": "classic"})]
	if sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "source": "classic-teleport"}))
	if message_id != 0:
		var message := _content.message_by_id(absi(message_id))
		if message == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic teleport references unavailable message %d." % message_id)
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-teleport"}))
	if activate_destination:
		events.append(DomainEvent.new(&"destination_trigger_recheck_requested", {"mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "source": "classic-opcode-20"}))
		return ScenarioRuntimeOperationResult.completed(target_map.id, events, ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.completed(target_map.id, events)


func _request_shop(classic_shop_id: int, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_classic_id(absi(classic_shop_id))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 6 references unavailable shop %d." % classic_shop_id)
	return _request_shop_definition(shop, request_id, accept_ranges)


func _request_shop_definition(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_shop_request(shop, request_id, accept_ranges), ScenarioRuntimeContinuation.shop(shop.id, accept_ranges), [DomainEvent.new(&"shop_opened", {"shopId": shop.id, "acceptRanges": accept_ranges.duplicate(), "bankAvailable": _game_state.bank_available})])


func _shop_request(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> InteractionRequest:
	var stock: Array[Dictionary] = []
	var characters: Array[Dictionary] = []
	var item_ids := shop.item_ids()
	for index: int in item_ids.size():
		var item := _content.item_by_id(item_ids[index])
		if item == null:
			continue
		stock.append(_shop_stock_view(item, "base:%d" % index, index, _game_state.shop_quantity(shop, index), shop))
	var buyback_items := _game_state.shop_buyback_items(shop.id)
	var buyback_ids: Array = buyback_items.keys()
	buyback_ids.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_item := _content.item_by_id(String(left))
		var right_item := _content.item_by_id(String(right))
		return left_item != null and right_item != null and left_item.classic_id < right_item.classic_id
	)
	for item_id: Variant in buyback_ids:
		if item_ids.has(String(item_id)):
			continue
		var item := _content.item_by_id(String(item_id))
		if item != null:
			stock.append(_shop_stock_view(item, "buyback:%s" % item.id, -1, int(buyback_items[item_id]), shop))
	var party_gold := _rules.economy.available(_game_state.party, WealthState.Kind.GOLD)
	for character: CharacterState in _game_state.party.characters():
		var inventory: Array[Dictionary] = []
		for instance: ItemInstance in character.inventory():
			var definition := _content.item_by_id(instance.definition_id)
			if definition != null:
				var can_sell := not instance.equipped and _shop_accepts_item(definition, accept_ranges)
				var sell_reason := ""
				if instance.equipped:
					sell_reason = "Unequip this item before selling it."
				elif not _shop_accepts_item(definition, accept_ranges):
					sell_reason = "This shop does not accept this item."
				var can_identify := not instance.identified and party_gold >= 20
				var identify_reason := ""
				if instance.identified:
					identify_reason = "This item is already identified."
				elif party_gold < 20:
					identify_reason = "Identification costs 20 gold."
				inventory.append({
					"instanceId": instance.id,
					"itemId": definition.id,
					"name": definition.name if instance.identified else definition.unidentified_name,
					"identified": instance.identified,
					"equipped": instance.equipped,
					"charges": instance.charges,
					"sellPrice": _rules.economy.shop_sell_price(definition, instance, _game_state.shop_inflation(shop)),
					"canSell": can_sell,
					"sellReason": sell_reason,
					"canIdentify": can_identify,
					"identifyReason": identify_reason,
				})
		characters.append({"id": character.id, "name": character.name, "inventory": inventory})
	return InteractionRequest.from_payload(request_id, &"shop_action", {"shopId": shop.id, "inflationPercent": _game_state.shop_inflation(shop), "partyGold": party_gold, "identifyPrice": 20, "stock": stock, "characters": characters, "acceptRanges": accept_ranges.duplicate(), "actions": ["buy", "sell", "identify", "leave"]})


func _shop_stock_view(item: ItemDefinition, stock_key: String, stock_index: int, quantity: int, shop: ShopDefinition) -> Dictionary:
	var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
	return {"stockKey": stock_key, "index": stock_index, "itemId": item.id, "name": item.name, "quantity": quantity, "buyPrice": price, "canBuy": quantity > 0 and _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) >= price, "buyReason": "Out of stock." if quantity < 1 else "The party cannot afford this item." if _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) < price else ""}


func _resume_shop(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.ShopBody
	if response.kind != &"shop_action" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop response requires an action string.")
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var shop := _content.shop_by_id(service.shop_id)
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "The pending shop is unavailable.")
	var operation := String(body.action)
	if operation == "leave":
		if _game_state.bank_available:
			_rules.economy.pool_to_bank(_game_state.party)
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_closed", {"shopId": shop.id, "pooledWealthReturnedToBank": _game_state.bank_available})])
	var events: Array[DomainEvent] = []
	match operation:
		"buy":
			if body.character_id.is_empty() or body.stock_key.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop buy requires stock identity and characterId.")
			var stock_entry := _resolve_shop_stock(shop, body.stock_key)
			if stock_entry.is_empty() or int(stock_entry.get("quantity", 0)) < 1:
				return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "The selected shop item is out of stock.")
			var character := _game_state.party.character_by_id(body.character_id)
			var item := stock_entry.get("item") as ItemDefinition
			if character == null or item == null or character.inventory().size() >= InventoryRules.MAX_ITEMS or character.carried_load + item.instance_weight(item.initial_charges) > character.maximum_load:
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The selected character cannot carry this item.")
			var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
			if not _rules.economy.take(_game_state.party, price, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "The party cannot afford this item.")
			var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("shop.item"), true)
			if instance == null:
				_game_state.party.pooled_wealth.gold += price
				return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The item could not be added after purchase validation.")
			if stock_entry.get("kind") == "base":
				var stock_index := int(stock_entry["index"])
				_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) - 1)
			else:
				_game_state.set_shop_buyback_quantity(shop.id, item.id, int(stock_entry["quantity"]) - 1)
			events.append(DomainEvent.new(&"shop_item_bought", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"sell":
			if body.character_id.is_empty() or body.instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop sell requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(body.character_id)
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The shop sale character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == body.instance_id:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The sold item instance is unavailable.")
			var item := _content.item_by_id(instance.definition_id)
			if item == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item", "The sold item definition is unavailable.")
			if instance.equipped:
				return ScenarioRuntimeOperationResult.failed(&"equipped_item", "Unequip this item before selling it.")
			var accept_ranges: Array[int] = []
			accept_ranges.assign(service.accept_ranges)
			if not _shop_accepts_item(item, accept_ranges):
				return ScenarioRuntimeOperationResult.failed(&"shop_rejects_item", "This shop does not accept the selected item.")
			var price := _rules.economy.shop_sell_price(item, instance, _game_state.shop_inflation(shop))
			if _rules.inventory.remove_item(character, instance.id, item) == null:
				return ScenarioRuntimeOperationResult.failed(&"shop_sale_failed", "The selected item could not be removed.")
			_game_state.party.pooled_wealth.gold += price
			var base_index := shop.item_ids().find(item.id)
			if base_index >= 0:
				_game_state.set_shop_quantity(shop, base_index, _game_state.shop_quantity(shop, base_index) + 1)
			else:
				_game_state.set_shop_buyback_quantity(shop.id, item.id, _game_state.shop_buyback_quantity(shop.id, item.id) + 1)
			events.append(DomainEvent.new(&"shop_item_sold", {"shopId": shop.id, "itemId": item.id, "instanceId": instance.id, "characterId": character.id, "price": price}))
		"identify":
			if body.character_id.is_empty() or body.instance_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop identification requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(body.character_id)
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The identification character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == body.instance_id:
					instance = candidate
					break
			if instance == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_item_instance", "The identification item is unavailable.")
			if instance.identified:
				return ScenarioRuntimeOperationResult.failed(&"already_identified", "This item is already identified.")
			if not _rules.economy.take(_game_state.party, 20, WealthState.Kind.GOLD):
				return ScenarioRuntimeOperationResult.failed(&"insufficient_gold", "Identification costs 20 gold.")
			instance.identified = true
			events.append(DomainEvent.new(&"item_identified", {"shopId": shop.id, "instanceId": instance.id, "characterId": character.id, "price": 20, "source": "classic-shop"}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 683, "waitForCompletion": false, "source": "classic-shop-identify"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_shop_action", "Shop action '%s' is unavailable." % operation)
	var ranges: Array[int] = []
	ranges.assign(service.accept_ranges)
	return ScenarioRuntimeOperationResult.waiting(_shop_request(shop, request_id, ranges), continuation, events)


func _resolve_shop_stock(shop: ShopDefinition, stock_key: String) -> Dictionary:
	if stock_key.begins_with("base:"):
		var index_text := stock_key.trim_prefix("base:")
		if not index_text.is_valid_int():
			return {}
		var index := index_text.to_int()
		var item_ids := shop.item_ids()
		if index < 0 or index >= item_ids.size():
			return {}
		return {"kind": "base", "index": index, "item": _content.item_by_id(item_ids[index]), "quantity": _game_state.shop_quantity(shop, index)}
	if stock_key.begins_with("buyback:"):
		var item_id := stock_key.trim_prefix("buyback:")
		var quantity := _game_state.shop_buyback_quantity(shop.id, item_id)
		return {} if quantity < 1 else {"kind": "buyback", "index": -1, "item": _content.item_by_id(item_id), "quantity": quantity}
	return {}


func _configure_shop(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 73 requires a five-value Extra Code row.")
	var shop := _content.shop_by_classic_id(absi(action.extra_code[0]))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 73 references unavailable shop %d." % action.extra_code[0])
	var accept_ranges: Array[int] = [action.extra_code[1], action.extra_code[2], action.extra_code[3], action.extra_code[4]]
	if not _game_state.set_active_shop(shop.id, accept_ranges):
		return ScenarioRuntimeOperationResult.failed(&"invalid_shop_configuration", "Classic opcode 73 shop restrictions are invalid.")
	if action.extra_code[0] < 0:
		return _request_shop(action.extra_code[0], request_id, accept_ranges)
	return ScenarioRuntimeOperationResult.completed(shop.id, [DomainEvent.new(&"shop_available", {"shopId": shop.id, "acceptRanges": accept_ranges})])


static func _shop_accepts_item(item: ItemDefinition, accept_ranges: Array[int]) -> bool:
	if item == null or accept_ranges.is_empty():
		return accept_ranges.is_empty()
	if accept_ranges.size() != 4:
		return false
	var failures := 0
	if accept_ranges[0] != 0 and not (accept_ranges[0] <= item.classic_id and item.classic_id <= accept_ranges[1]):
		failures += 1
	if accept_ranges[2] != 0 and not (accept_ranges[2] <= item.classic_id and item.classic_id <= accept_ranges[3]):
		failures += 1
	return failures < 2


func _configure_temple(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if not _game_state.set_active_temple(action.operand_id):
		return ScenarioRuntimeOperationResult.failed(&"invalid_temple_cost", "Classic opcode 32 temple cost is outside signed 16-bit range.")
	return ScenarioRuntimeOperationResult.completed(action.operand_id, [
		DomainEvent.new(&"temple_available", {"costPercent": action.operand_id}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-offer"}),
	])


func _temple_request(cost_percent: int, request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var conditions: Array[Dictionary] = []
		for index: int in character.conditions.size():
			if character.conditions.value(index) != 0:
				conditions.append({"index": index, "name": _rules.temple.condition_name(index), "value": character.conditions.value(index)})
				if conditions.size() == 5:
					break
		characters.append({
			"id": character.id,
			"name": character.name,
			"currentHealth": character.current_health,
			"maximumHealth": character.maximum_health,
			"personalGold": character.money.gold,
			"availableGold": character.money.gold + _game_state.party.pooled_wealth.gold,
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
			"portraitId": character.portrait_id,
			"conditions": conditions,
		})
	return InteractionRequest.from_payload(request_id, InteractionRequest.TEMPLE, {
		"costPercent": cost_percent,
		"characters": characters,
		"services": _rules.temple.service_rows(cost_percent),
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankAvailable": _game_state.bank_available,
		"selectedCharacterId": selected_character_id,
		"actions": ["service", "pool", "share", "leave"],
	})


func _resume_temple(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.TempleBody
	if response.kind != InteractionRequest.TEMPLE or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple response requires an action.")
	var operation := String(body.action)
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var cost_percent := service.cost_percent
	var selected_character_id := service.selected_character_id
	if not body.character_id.is_empty():
		if _game_state.party.character_by_id(body.character_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected temple character is unavailable.")
		selected_character_id = body.character_id
	var next_continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, cost_percent, service.bank_available, selected_character_id)
	match operation:
		"leave":
			if service.bank_available:
				_rules.economy.pool_to_bank(_game_state.party)
				return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": true})])
			if _has_pooled_wealth():
				var prompt := "Pooled wealth remains. Return to the temple to distribute it before leaving?"
				var request := InteractionRequest.yes_no(request_id, prompt, "Return", "Leave it behind")
				return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE_EXIT, cost_percent, false, selected_character_id))
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": false})])
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var pool_probe := _rules.economy.pool_probe(_game_state.party)
			if not pool_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", pool_probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			return ScenarioRuntimeOperationResult.waiting(_temple_request(cost_percent, request_id, selected_character_id), next_continuation, [
				DomainEvent.new(&"wealth_pooled", {"source": "classic-temple"}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-pool"}),
			])
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var share_probe := _rules.economy.share_probe(_game_state.party)
			if not share_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", share_probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			return ScenarioRuntimeOperationResult.waiting(_temple_request(cost_percent, request_id, selected_character_id), next_continuation, [
				DomainEvent.new(&"wealth_shared", {"source": "classic-temple", "remaining": _game_state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-share"}),
			])
		"service":
			return _apply_temple_service(next_continuation, body, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_temple_action", "Temple action '%s' is unavailable." % operation)


func _apply_temple_service(continuation: ScenarioRuntimeContinuation, body: InteractionResponse.TempleBody, request_id: String) -> ScenarioRuntimeOperationResult:
	if body.character_id.is_empty() or body.service_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple service requires characterId and serviceId.")
	var character := _game_state.party.character_by_id(body.character_id)
	var service_id := StringName(body.service_id)
	if character == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_character", "Temple service target is unavailable.")
	if not TempleRules.SERVICE_IDS.has(service_id):
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
	var cost := _rules.temple.service_cost(service_id, service.cost_percent)
	var next_continuation := ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, service.cost_percent, service.bank_available, character.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 10129, "waitForCompletion": false, "source": "classic-temple-service"})]
	if cost > _game_state.party.pooled_wealth.gold + character.money.gold:
		events.append(DomainEvent.new(&"temple_service_rejected", {"serviceId": String(service_id), "characterId": character.id, "cost": cost, "reason": "insufficient_gold"}))
		return ScenarioRuntimeOperationResult.waiting(_temple_request(service.cost_percent, request_id, character.id), next_continuation, events)
	if not _rules.economy.take_from_pool_and_character(_game_state.party, character, cost, WealthState.Kind.GOLD):
		return ScenarioRuntimeOperationResult.failed(&"temple_payment_failed", "Temple payment could not be committed after affordability validation.")
	var result := _rules.temple.apply_service(character, service_id, _rng, _content.item_definitions())
	if result == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	events.append(DomainEvent.new(&"temple_service_completed", result.to_event_data(character.id, cost)))
	return ScenarioRuntimeOperationResult.waiting(_temple_request(service.cost_percent, request_id, character.id), next_continuation, events)


func _resume_temple_exit(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple exit requires a yes/no response.")
	if body.accepted:
		var service := continuation.body as ScenarioRuntimeContinuation.ServiceBody
		return ScenarioRuntimeOperationResult.waiting(
			_temple_request(service.cost_percent, request_id, service.selected_character_id),
			ScenarioRuntimeContinuation.temple(ScenarioRuntimeContinuation.CLASSIC_TEMPLE, service.cost_percent, false, service.selected_character_id),
			[DomainEvent.new(&"temple_exit_cancelled", {"reason": "pooled_wealth"})]
		)
	var discarded := _game_state.party.pooled_wealth.to_data()
	_game_state.party.pooled_wealth = WealthState.new()
	return ScenarioRuntimeOperationResult.completed(true, [
		DomainEvent.new(&"pooled_wealth_discarded", {"source": "classic-temple-exit", "wealth": discarded}),
		DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": false}),
	])


func _has_pooled_wealth() -> bool:
	return _game_state.party.pooled_wealth.gold != 0 or _game_state.party.pooled_wealth.gems != 0 or _game_state.party.pooled_wealth.jewelry != 0


func _request_banking(request_id: String) -> ScenarioRuntimeOperationResult:
	_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id), ScenarioRuntimeContinuation.banking(), [
		DomainEvent.new(&"bank_opened", {"pooledWealth": _game_state.party.pooled_wealth.to_data()}),
		DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-button"}),
		DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "source": "classic-bank-swap-open"}),
	])


func _bank_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var characters: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		var transfers: Array[Dictionary] = []
		for denomination: String in ["gold", "gems", "jewelry"]:
			var kind := _wealth_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, true)
			transfers.append({
				"denomination": denomination,
				"amount": amount,
				"toPool": _economy_probe_data(to_pool),
				"toCharacter": _economy_probe_data(to_character),
			})
		characters.append({
			"id": character.id,
			"name": character.name,
			"wealth": character.money.to_data(),
			"load": character.carried_load,
			"maximumLoad": character.maximum_load,
			"transfers": transfers,
		})
	if selected_character_id.is_empty() and not characters.is_empty():
		selected_character_id = String(characters[0]["id"])
	return InteractionRequest.from_payload(request_id, InteractionRequest.BANK, {
		"selectedCharacterId": selected_character_id,
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankedWealth": _game_state.party.banked_wealth.to_data(),
		"pool": _economy_probe_data(_rules.economy.pool_probe(_game_state.party)),
		"share": _economy_probe_data(_rules.economy.share_probe(_game_state.party)),
		"characters": characters,
		"actions": ["pool", "share", "to-pool", "to-character", "leave"],
	})


func _resume_banking(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.BankBody
	if response.kind != InteractionRequest.BANK or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank response requires an action.")
	var action := String(body.action)
	if action == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [
			DomainEvent.new(&"bank_closed", {"pooledWealthReturnedToBank": false}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-done"}),
		])
	var selected_character_id := body.character_id
	var events: Array[DomainEvent] = []
	match action:
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var probe := _rules.economy.pool_probe(_game_state.party)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-bank", "wealth": _game_state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-pool"}))
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var probe := _rules.economy.share_probe(_game_state.party)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-bank", "remaining": _game_state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-share"}))
		"to-pool", "to-character":
			if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank-backed Swap requires character, denomination, and amount.")
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var character := _game_state.party.character_by_id(body.character_id)
			var kind := _wealth_kind(body.denomination)
			var amount := body.amount
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected bank character is unavailable.")
			if kind < 0:
				return ScenarioRuntimeOperationResult.failed(&"unknown_wealth_kind", "The selected bank denomination is unavailable.")
			if amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character := action == "to-character"
			var probe := _rules.economy.transfer_probe(_game_state.party, character, kind as WealthState.Kind, amount, to_character)
			if not probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", probe.reason)
			var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, amount) if to_character else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, amount)
			if not transferred:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", "The selected bank transfer is no longer available.")
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-bank", "characterId": character.id, "direction": action, "kind": body.denomination, "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-bank-swap"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_bank_action", "Bank action '%s' is unavailable." % action)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id, selected_character_id), continuation, events)


static func _economy_probe_data(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}


func _character_has_classic_item(character: CharacterState, classic_item_id: int, equipped_only: bool) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for instance: ItemInstance in character.inventory():
		if instance.definition_id == definition.id and (not equipped_only or instance.equipped):
			return true
	return false


static func _character_attribute(character: CharacterState, index: int) -> int:
	match index:
		0: return character.brawn
		1: return character.knowledge
		2: return character.judgment
		3: return character.agility
		4: return character.vitality
		5, 6: return character.luck
	return 0


func _start_classic_battle(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var battle_id := action.operand_id
	var prelude: Array[DomainEvent] = []
	if not action.extra_code.is_empty():
		var low := action.extra_code[0]
		var high := action.extra_code[1] if action.extra_code.size() > 1 else 0
		battle_id = absi(low)
		if high != 0:
			battle_id = _rng.draw_between(absi(low), absi(high), StringName("classic.opcode-%d.battle" % action.opcode))
		var sound_id := action.extra_code[3] if action.opcode == 56 else action.extra_code[2]
		var message_id := action.extra_code[4] if action.opcode == 56 else action.extra_code[3]
		if sound_id != 0:
			prelude.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "source": "classic-battle"}))
		if message_id != 0:
			var message := _content.message_by_id(absi(message_id))
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode %d references unavailable battle message %d." % [action.opcode, message_id])
			prelude.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle"}))
	var caller := ScenarioBattleCaller.classic(action.opcode, action.gosub, action.extra_code[4] if action.opcode == 2 and action.extra_code.size() > 4 else 0, action.extra_code[4] if action.opcode == 107 and action.extra_code.size() > 4 else action.extra_code[2] if action.opcode == 56 and action.extra_code.size() > 2 else 0)
	var battle := _content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Classic opcode %d references unavailable battle %d." % [action.opcode, battle_id])
	var operation := _start_battle_definition(battle, request_id, "classic", caller)
	if operation.state != ScenarioRuntimeOperationResult.State.FAILED:
		operation.events = prelude + operation.events
	return operation


static func party_defeat_handoff_is_valid(content: RealmzContent, state: GameState, handoff: ScenarioRuntimeHandoff) -> bool:
	if content == null or state == null or state.combat == null or handoff == null or handoff.caller == null:
		return false
	if handoff.kind != ScenarioRuntimeHandoff.PARTY_DEFEAT or handoff.battle_id != state.combat.battle_id or handoff.source_kind not in [ScenarioRuntimeHandoff.CLASSIC_COMBAT, ScenarioRuntimeHandoff.SAFE_COMBAT]:
		return false
	if not state.combat.completed or state.combat.outcome != &"defeat":
		return false
	var caller := handoff.caller
	if handoff.source_kind == ScenarioRuntimeHandoff.SAFE_COMBAT:
		return caller.kind == ScenarioBattleCaller.SAFE
	if caller.kind != ScenarioBattleCaller.CLASSIC:
		return false
	var opcode := caller.opcode
	var target := caller.branch_target
	if opcode == 107 or opcode == 56 and target >= 0:
		return content.scenario.program_by_id("xap:%d" % target) != null
	return true


func complete_party_defeat_handoff(handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	if not party_defeat_handoff_is_valid(_content, _game_state, handoff):
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_defeat_handoff", "The suspended total-party defeat no longer matches its battle caller.")
	var caller := handoff.caller
	if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 10:
		return ScenarioRuntimeOperationResult.failed(&"classic_mode_10_defeat_unresolved", "Classic battle mode 10 revives and restarts its caller without running Party Death; that source-specific restart is not yet available.")
	if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 56 and caller.branch_target == -1:
		return ScenarioRuntimeOperationResult.failed(&"classic_battle_loss_return_unresolved", "Classic opcode 56 uses a distinct experience-loss and party-backup return that is not yet available.")
	var combat := _game_state.combat
	var battle_id := combat.battle_id
	var directive: ScenarioVmDirective
	if caller.kind == ScenarioBattleCaller.CLASSIC:
		match caller.opcode:
			56:
				directive = ScenarioVmDirective.branch_xap(caller.branch_target, caller.gosub)
			107:
				directive = ScenarioVmDirective.branch_xap(caller.branch_target, false)
	combat.outcome = &"retreated"
	_game_state.last_battle_outcome = &"retreated"
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"party_defeat_revived", {"battleId": battle_id, "source": "classic-party-death-hook", "callerOpcode": caller.opcode if caller.kind == ScenarioBattleCaller.CLASSIC else 0}),
		DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "retreated"}),
	]
	_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(battle_id, events, directive)


func _start_battle_definition(battle: BattleDefinition, request_id: String, source: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeOperationResult:
	var result := _rules.combat_flow.start_battle(_game_state, _content, battle, _rng)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	var events: Array[DomainEvent] = []
	if battle.message_before_id != 0:
		var before := _content.message_by_id(absi(battle.message_before_id))
		if before == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Battle '%s' references unavailable before-message %d." % [battle.id, battle.message_before_id])
		events.append(DomainEvent.new(&"message_shown", {"messageId": before.id, "text": before.text, "source": "classic-battle-definition"}))
	events.append_array(result.events)
	var continuation_kind := ScenarioRuntimeContinuation.SAFE_COMBAT if source == "scenario-action" else ScenarioRuntimeContinuation.CLASSIC_COMBAT
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation_kind, caller, request_id, events, _game_state.combat.round_number)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation_kind, caller, events, request_id)
	if result.completed:
		return _finish_battle_with_allies(continuation_kind, caller, request_id, events)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(continuation_kind, battle.id, caller), events)


func _resume_battle(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.CombatBody
	if response.kind != &"combat_action" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat response requires actorId, action, and optional targetId strings.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle is unavailable.")
	var previous_round := _game_state.combat.round_number
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle lost its originating caller.")
	var result: CombatFlowResult
	if body.action == &"set_auto":
		if _game_state.party.character_by_id(body.actor_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Persistent Auto requires a party character and an enabled boolean.")
		var auto_state_checkpoint := _game_state.to_data()
		var auto_rng_checkpoint := _rng.checkpoint()
		if not _game_state.set_combat_auto(body.actor_id, body.enabled):
			return ScenarioRuntimeOperationResult.failed(&"invalid_combat_auto_character", "Persistent Auto could not be changed for this character.")
		var toggle_sound := 147 if body.enabled else 139
		var auto_events: Array[DomainEvent] = [
			DomainEvent.new(&"sound_requested", {"soundId": toggle_sound, "waitForCompletion": false, "source": "classic-combat-auto-toggle"}),
			DomainEvent.new(&"combat_auto_changed", {"characterId": body.actor_id, "enabled": body.enabled, "source": "classic"}),
		]
		if not body.enabled or _game_state.combat.active_actor_id() != body.actor_id:
			return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, auto_events)
		auto_events.append(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
		result = _rules.combat_flow.run_persistent_auto_characters(_game_state, _content, _rng)
		if not result.ok:
			if not _game_state.restore_from_data(auto_state_checkpoint) or not _rng.rollback(auto_rng_checkpoint):
				return ScenarioRuntimeOperationResult.failed(&"combat_auto_rollback_failed", "Persistent Auto failed and could not restore its toggle transaction.")
			return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
		if result.ok:
			var combined_events: Array[DomainEvent] = []
			combined_events.append_array(auto_events)
			combined_events.append_array(result.events)
			result.events = combined_events
	elif body.action == &"retreat":
		var retreat_probe: Variant = _rules.combat_flow.probe_character_retreat(_game_state.combat, _game_state.party.characters(), body.actor_id)
		if not retreat_probe.allowed:
			return ScenarioRuntimeOperationResult.failed(retreat_probe.reason, retreat_probe.reason_text)
		return _wait_for_battle_retreat(continuation, body.actor_id, &"explicit", Vector2i(-100_000, -100_000), request_id)
	elif body.action == &"retreat_edge":
		var edge_destination := body.destination if body.has_destination else CombatFlow.INVALID_COORDINATE
		var edge_probe: Variant = _rules.combat_flow.probe_edge_retreat(_game_state.combat, body.actor_id, edge_destination)
		if not edge_probe.allowed:
			return ScenarioRuntimeOperationResult.failed(edge_probe.reason, edge_probe.reason_text)
		if not edge_probe.forced:
			return _wait_for_battle_retreat(continuation, body.actor_id, &"edge", edge_destination, request_id)
		result = _rules.combat_flow.retreat_character(_game_state, _content, body.actor_id, &"edge", edge_destination, _rng)
	elif body.action == &"move":
		if not body.has_destination:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat movement requires a two-integer destination.")
		result = _rules.combat_flow.move_character(_game_state, _content, body.actor_id, body.destination, _rng, body.auto_switch_to_melee)
	elif body.action == &"cast_spell":
		if body.spell_id.is_empty():
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat spell casting requires a spellId string and integer power.")
		var target_coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
		result = _rules.combat_flow.cast_spell(_game_state, _content, body.actor_id, body.target_id, body.spell_id, body.power, _rng, target_coordinate, body.rotation, body.target_ids)
	elif body.action == &"use_item":
		if body.item_instance_id.is_empty():
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat item use requires an itemInstanceId string.")
		result = _rules.combat_flow.use_spell_item(_game_state, _content, body.actor_id, body.target_id, body.item_instance_id, _rng)
	elif body.action == &"use_scroll":
		if body.scroll_slot < 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat scroll use requires an integer scrollSlot.")
		var scroll_target_coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
		result = _rules.combat_flow.use_combat_scroll(_game_state, _content, body.actor_id, body.scroll_slot, body.target_id, _rng, scroll_target_coordinate, body.rotation, body.target_ids)
	else:
		result = _rules.combat_flow.submit_action(_game_state, _content, body.actor_id, body.action, body.target_id, _rng)
	if not result.ok:
		if body.action == &"move" and result.error_code == &"melee_weapon_mode_required":
			var warning_events: Array[DomainEvent] = [
				DomainEvent.new(&"sound_requested", {"soundId": 6000, "waitForCompletion": false, "source": "classic-auto-weapon-switch-warning"}),
				DomainEvent.new(&"combat_action_unavailable", {"actorId": body.actor_id, "action": "move", "reason": String(result.error_code), "message": result.error_message, "source": "classic"}),
			]
			return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, warning_events)
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation.kind, caller, request_id, result.events, previous_round)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation.kind, caller, result.events, request_id)
	if result.completed:
		var completed_events: Array[DomainEvent] = []
		completed_events.assign(result.events)
		return _finish_battle_with_allies(continuation.kind, caller, request_id, completed_events)
	if _game_state.combat.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(continuation.kind, caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, result.events)


func _wait_for_battle_retreat(continuation: ScenarioRuntimeContinuation, actor_id: String, mode: StringName, destination: Vector2i, request_id: String) -> ScenarioRuntimeOperationResult:
	var source_kind := continuation.kind
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	var retreat_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT
	var next_continuation := ScenarioRuntimeContinuation.combat_retreat(retreat_kind, source_kind, _game_state.combat.battle_id, combat_continuation.caller, actor_id, mode, destination)
	var request := InteractionRequest.yes_no(request_id, "Will this character flee from battle?", "Embrace Cowardice", "Stay and Fight")
	return ScenarioRuntimeOperationResult.waiting(request, next_continuation)


func _resume_battle_retreat(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id or _game_state.combat.active_actor_id() != combat_continuation.actor_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The character awaiting Escape confirmation is unavailable.")
	var source_kind := combat_continuation.source_kind
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending retreat lost its originating battle caller.")
	var mode := combat_continuation.mode
	var destination := combat_continuation.destination
	var probe: Variant = _rules.combat_flow.probe_character_retreat(_game_state.combat, _game_state.party.characters(), combat_continuation.actor_id) if mode == &"explicit" else _rules.combat_flow.probe_edge_retreat(_game_state.combat, combat_continuation.actor_id, destination) if mode == &"edge" else null
	if probe == null or not probe.allowed or probe.forced:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The saved Escape confirmation no longer represents a promptable Classic action.")
	if not body.accepted:
		return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat_continuation.battle_id, caller), [DomainEvent.new(&"combat_retreat_declined", {"actorId": combat_continuation.actor_id, "mode": String(mode), "source": "classic"})])
	var previous_round := _game_state.combat.round_number
	var result := _rules.combat_flow.retreat_character(_game_state, _content, combat_continuation.actor_id, mode, destination, _rng)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(source_kind, caller, request_id, result.events, previous_round)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(source_kind, caller, result.events, request_id)
	if result.completed:
		var completed_events: Array[DomainEvent] = []
		completed_events.assign(result.events)
		return _finish_battle_with_allies(source_kind, caller, request_id, completed_events)
	if _game_state.combat.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(source_kind, caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat_continuation.battle_id, caller), result.events)


func _append_battle_after_message(battle: BattleDefinition, events: Array[DomainEvent]) -> void:
	if battle.message_after_id == 0:
		return
	var after := _content.message_by_id(absi(battle.message_after_id))
	if after != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": after.id, "text": after.text, "source": "classic-battle-definition"}))


func _finish_battle_with_allies(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle ally selection requires a completed battle.")
	if combat.outcome == &"defeat":
		if caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 10:
			return ScenarioRuntimeOperationResult.failed(&"classic_mode_10_defeat_unresolved", "Classic battle mode 10 bypasses Party Death and restarts its encounter; that caller-specific path is unresolved.")
		return ScenarioRuntimeOperationResult.suspended(ScenarioRuntimeHandoff.party_defeat(combat.battle_id, source_kind, caller), events)
	var payload := _rules.combat_flow.ally_selection_payload(_game_state, _content)
	if not payload.is_empty():
		var ally_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"ally_selection", payload), ScenarioRuntimeContinuation.combat_terminal(ally_kind, source_kind, combat.battle_id, caller), events)
	return _finish_battle_with_fumbles(source_kind, caller, request_id, events)


func _finish_battle_with_fumbles(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle fumbled-weapon recovery requires a completed battle.")
	var payload := _rules.combat_flow.fumble_recovery_payload(_game_state, _content)
	if not payload.is_empty():
		var fumble_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, payload), ScenarioRuntimeContinuation.combat_terminal(fumble_kind, source_kind, combat.battle_id, caller), events)
	var reward := begin_completed_battle_reward(request_id)
	reward.events = events + reward.events
	return reward


func _resume_ally_selection(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.AllySelectionBody
	if response.kind != &"ally_selection" or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Ally selection requires selectedIds.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for ally selection.")
	if _rules.combat_flow.ally_selection_payload(_game_state, _content).is_empty():
		return _finish_battle_with_fumbles(combat_continuation.source_kind, combat_continuation.caller, String(response.request_id), [])
	var selected := _rules.combat_flow.apply_ally_selection(_game_state, _content, body.selected_ids)
	if not selected.ok:
		return ScenarioRuntimeOperationResult.failed(selected.error_code, selected.error_message)
	var events: Array[DomainEvent] = []
	events.assign(selected.events)
	return _finish_battle_with_fumbles(combat_continuation.source_kind, combat_continuation.caller, String(response.request_id), events)


func _resume_fumble_recovery(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var recovered := _rules.combat_flow.apply_fumble_recovery(_game_state, _content, body.action, body.instance_id, body.character_id)
	if not recovered.ok:
		return ScenarioRuntimeOperationResult.failed(recovered.error_code, recovered.error_message)
	var events: Array[DomainEvent] = []
	events.assign(recovered.events)
	return _finish_battle_with_fumbles(combat_continuation.source_kind, combat_continuation.caller, request_id, events)


func _run_battle_macro(source_kind: StringName, caller: ScenarioBattleCaller, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or combat.completed or combat.macro_id >= 0:
		return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat.battle_id, caller), preceding_events)
	var program_id := "xap:%d" % absi(combat.macro_id)
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	var started := vm.start_program(program_id, {"callingContext": "battle-macro", "battleId": combat.battle_id})
	if started.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(started.error_code, started.error_message)
	var result := vm.run(self)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"battle_macro_started", {"battleId": combat.battle_id, "programId": program_id, "round": combat.round_number}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A battle macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var macro_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO
		return ScenarioRuntimeOperationResult.waiting(result.interaction, ScenarioRuntimeContinuation.combat_macro(macro_kind, source_kind, combat.battle_id, caller, program_id, vm.snapshot()), events)
	return _continue_after_battle_macro(source_kind, caller, request_id, program_id, events)


func _resume_battle_macro(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle macro is unavailable.")
	var snapshot := combat_continuation.macro_vm
	if snapshot == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_continuation", "The pending battle macro state is invalid.")
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	if not vm.restore(snapshot):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_continuation", "The pending battle macro cannot be restored.")
	var result := vm.resume(response, self)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A resumed battle macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var next_continuation := ScenarioRuntimeContinuation.combat_macro(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, combat_continuation.program_id, vm.snapshot())
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_battle_macro(combat_continuation.source_kind, combat_continuation.caller, request_id, combat_continuation.program_id, result.events)


func _continue_after_battle_macro(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, program_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"battle_macro_completed", {"battleId": _game_state.combat.battle_id, "programId": program_id, "round": _game_state.combat.round_number}))
	if _game_state.combat.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, committed)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, _game_state.combat.battle_id, caller), committed)


func _run_combat_death_macro(source_kind: StringName, caller: ScenarioBattleCaller, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	var request := _death_macro_request(preceding_events)
	var combat := _game_state.combat
	if request.is_empty() or combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Monster death-macro execution requires an active combatant request.")
	var combatant_id := str(request.get("combatantId", ""))
	var program_id := str(request.get("programId", ""))
	var monster := combat.monster_by_id(combatant_id)
	if monster == null or program_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Monster death-macro execution references unavailable content.")
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	var started := vm.start_program(program_id, {
		"callingContext": "monster-death-macro",
		"battleId": combat.battle_id,
		"combatantId": combatant_id,
		"classicMonsterId": int(request.get("classicMonsterId", 0)),
		"traitor": bool(request.get("traitor", monster.traitor)),
	})
	if started.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(started.error_code, started.error_message)
	var result := vm.run(self)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"monster_death_macro_started", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A monster death macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var macro_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO
		return ScenarioRuntimeOperationResult.waiting(result.interaction, ScenarioRuntimeContinuation.combat_macro(macro_kind, source_kind, combat.battle_id, caller, program_id, vm.snapshot(), combatant_id, bool(request.get("resetTraitorOnComplete", true))), events)
	return _continue_after_combat_death_macro(source_kind, caller, request_id, combatant_id, program_id, events, bool(request.get("resetTraitorOnComplete", true)))


func _resume_combat_death_macro(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending monster death macro is unavailable.")
	var snapshot := combat_continuation.macro_vm
	if snapshot == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_continuation", "The pending monster death-macro state is invalid.")
	var vm := ScenarioVm.new()
	vm.configure(_content.scenario)
	if not vm.restore(snapshot):
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_continuation", "The pending monster death macro cannot be restored.")
	var result := vm.resume(response, self)
	if result.state == ScenarioVmResult.State.FAILED:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioRuntimeOperationResult.failed(&"nested_host_handoff", "A resumed monster death macro cannot suspend a second battle into the application host.")
	if result.state == ScenarioVmResult.State.WAITING:
		var next_continuation := ScenarioRuntimeContinuation.combat_macro(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, combat_continuation.program_id, vm.snapshot(), combat_continuation.combatant_id, combat_continuation.reset_traitor_on_complete)
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_combat_death_macro(combat_continuation.source_kind, combat_continuation.caller, request_id, combat_continuation.combatant_id, combat_continuation.program_id, result.events, combat_continuation.reset_traitor_on_complete)


func _continue_after_combat_death_macro(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, combatant_id: String, program_id: String, events: Array[DomainEvent], reset_traitor_on_complete: bool = true) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Monster death-macro completion lost its battle.")
	var monster := combat.monster_by_id(combatant_id)
	if monster != null and reset_traitor_on_complete:
		monster.traitor = false
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"monster_death_macro_completed", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id, "revived": monster != null and monster.current_health > 0}))
	var previous_round := combat.round_number
	var continued := _rules.combat_flow.continue_after_monster_death_macro(_game_state, _content, _rng, combatant_id)
	if not continued.ok:
		return ScenarioRuntimeOperationResult.failed(continued.error_code, continued.error_message)
	committed.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _wait_for_combat_age_updates(source_kind, caller, request_id, committed, previous_round)
	if not _death_macro_request(continued.events).is_empty():
		return _run_combat_death_macro(source_kind, caller, committed, request_id)
	if continued.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, committed)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, combat.battle_id, caller), committed)


func _wait_for_combat_age_updates(source_kind: StringName, caller: ScenarioBattleCaller, request_id: String, events: Array[DomainEvent], round_before: int) -> ScenarioRuntimeOperationResult:
	var updates := CharacterAgingResult.update_bodies(events)
	if updates.is_empty() or _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_age_update", "Monster aging did not provide a valid combat continuation.")
	var age_kind := ScenarioRuntimeContinuation.SAFE_COMBAT_AGE if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE
	var continuation := ScenarioRuntimeContinuation.combat_age(age_kind, source_kind, _game_state.combat.battle_id, caller, updates, 1, round_before)
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, updates[0]), continuation, committed)


func _resume_combat_age_updates(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic combat age updates require an empty acknowledgement.")
	var combat_continuation := continuation.body as ScenarioRuntimeContinuation.CombatBody
	if _game_state.combat == null or _game_state.combat.battle_id != combat_continuation.battle_id or _game_state.combat.pending_monster_attack == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The monster age-update battle is unavailable.")
	var updates := combat_continuation.updates
	var index := combat_continuation.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "The combat age-update queue is invalid.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		var next_continuation := ScenarioRuntimeContinuation.combat_age(continuation.kind, combat_continuation.source_kind, combat_continuation.battle_id, combat_continuation.caller, updates, index + 1, combat_continuation.round_before)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, next_payload), next_continuation, events)
	var source_kind := combat_continuation.source_kind
	var caller := combat_continuation.caller
	if caller == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The combat age update lost its originating battle caller.")
	var round_before := combat_continuation.round_before
	var continued := _rules.combat_flow.continue_after_age_update(_game_state, _content, _rng)
	if not continued.ok:
		return ScenarioRuntimeOperationResult.failed(continued.error_code, continued.error_message)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _wait_for_combat_age_updates(source_kind, caller, request_id, events, round_before)
	if not _death_macro_request(continued.events).is_empty():
		return _run_combat_death_macro(source_kind, caller, events, request_id)
	if continued.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, events)
	if _game_state.combat.round_number > round_before and _game_state.combat.macro_id < 0:
		return _run_battle_macro(source_kind, caller, events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), ScenarioRuntimeContinuation.combat(source_kind, _game_state.combat.battle_id, caller), events)


static func _death_macro_request(events: Array[DomainEvent]) -> Dictionary:
	for index: int in range(events.size() - 1, -1, -1):
		var event := events[index]
		if event.kind == &"monster_death_macro_requested":
			return event.payload
	return {}


func _combat_request(request_id: String) -> InteractionRequest:
	var combat := _game_state.combat
	var combat_view := CombatView.new(combat, _game_state.party.characters(), _content, _rules.inventory, _rules.battlefield, _rules.combat_flow, _game_state)
	var actions: Array[String] = []
	for action: StringName in combat_view.legal_actions:
		actions.append(String(action))
	var weapon_switch := {
		"enabled": combat_view.weapon_switch_available,
		"targetMode": String(combat_view.weapon_switch_target_mode),
		"reason": combat_view.weapon_switch_unavailable_reason,
	}
	var ranged_attack := {"enabled": combat_view.weapon_mode == &"missile" and combat_view.legal_actions.has(&"attack"), "reason": combat_view.ranged_attack_unavailable_reason}
	var targets: Array[Dictionary] = []
	for monster: MonsterView in combat_view.targets:
		targets.append({"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health})
	for character: CharacterView in combat_view.character_targets:
		targets.append({"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health})
	var combatants_by_id: Dictionary = {}
	var terrain_set := _combat_terrain_set()
	for character_state: CharacterState in _game_state.party.characters():
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(character_state.id):
			continue
		var character := CharacterView.new(character_state, _content)
		var equipment := _rules.inventory.combat_equipment(character_state, _content.item_definitions())
		character.apply_equipment(equipment)
		var payload := _character_combatant_payload(character)
		_append_combatant_position_facts(payload, combat_view.active_actor_id, character.id, terrain_set)
		_append_character_weapon_facts(payload, character_state, equipment, combat_view.weapon_mode if character.id == combat_view.active_actor_id else &"melee")
		combatants_by_id[character.id] = payload
	for monster: MonsterView in combat_view.monsters:
		if _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(monster.id):
			continue
		var payload := _monster_combatant_payload(monster)
		_append_combatant_position_facts(payload, combat_view.active_actor_id, monster.id, terrain_set)
		combatants_by_id[monster.id] = payload
	var combatants: Array[Dictionary] = []
	for combatant_id: String in combat_view.turn_order:
		if combatants_by_id.has(combatant_id):
			combatants.append(combatants_by_id[combatant_id])
			combatants_by_id.erase(combatant_id)
	for remaining: Dictionary in combatants_by_id.values():
		combatants.append(remaining)
	var movement: Array[Dictionary] = []
	for option: CombatMoveOptionView in combat_view.movement_options:
		movement.append({"direction": [option.direction.x, option.direction.y], "destination": [option.destination.x, option.destination.y], "cost": option.movement_cost, "enabled": option.enabled, "reasonCode": String(option.reason), "reason": option.reason_text, "retreat": option.retreats_from_battle, "forcedRetreat": option.forced_retreat, "attackTargetId": option.attack_target_id, "attackTargetName": option.attack_target_name})
	var spell_casts: Array[Dictionary] = []
	for option: CombatSpellOptionView in _rules.combat_flow.character_spell_options(_game_state, _content, combat_view.active_actor_id):
		var spell_cast := {"spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "cost": option.cost, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		if option.target_mode == &"sequence":
			spell_cast["maximumTargets"] = option.maximum_targets
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			spell_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			spell_cast["areaShape"] = option.area_shape
			spell_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			spell_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
			spell_cast["legalTargetCoordinates"] = option.legal_target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])
		spell_casts.append(spell_cast)
	if not spell_casts.is_empty():
		actions.append("cast_spell")
	var spell_cast_reason := _rules.combat_flow.character_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var fast_spells: Array[Dictionary] = []
	var active_character := _game_state.party.character_by_id(combat_view.active_actor_id)
	if active_character != null:
		for index: int in active_character.fast_spells().size():
			var binding := active_character.fast_spell_at(index)
			var bound_spell := _content.spell_by_id(binding.spell_id) if binding != null and not binding.is_empty() else null
			var binding_enabled := false
			if bound_spell != null:
				for cast: Dictionary in spell_casts:
					if cast.get("spellId") == binding.spell_id and int(cast.get("power", 0)) == binding.power:
						binding_enabled = true
						break
			var binding_reason := "This Fast Spell slot is undefined." if binding == null or binding.is_empty() else "The stored spell is unavailable to this character." if bound_spell == null or not active_character.known_spells().has(binding.spell_id) else "No legal target or casting action is currently available."
			fast_spells.append({"slot": index, "spellId": binding.spell_id if binding != null else "", "spellName": bound_spell.name if bound_spell != null else "Undefined Spell", "power": binding.power if binding != null else 0, "enabled": binding_enabled, "reason": "" if binding_enabled else binding_reason})
	var item_casts: Array[Dictionary] = []
	for option: CombatItemOptionView in _rules.combat_flow.character_item_spell_options(_game_state, _content, combat_view.active_actor_id):
		item_casts.append({"itemInstanceId": option.item_instance_id, "itemId": option.item_definition_id, "itemName": option.item_name, "charges": option.charges, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)})
	if not item_casts.is_empty():
		actions.append("use_item")
	var item_cast_reason := _rules.combat_flow.character_item_spell_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var scroll_casts: Array[Dictionary] = []
	for option: Variant in _rules.combat_flow.character_scroll_options(_game_state, _content, combat_view.active_actor_id):
		var scroll_cast := {"scrollSlot": option.scroll_slot, "spellId": option.spell_id, "spellName": option.spell_name, "power": option.power, "targetId": option.target_id, "targetName": option.target_name, "targetCurrentHealth": option.target_current_health, "targetMaximumHealth": option.target_maximum_health, "targetMode": String(option.target_mode)}
		if option.target_mode == &"sequence":
			scroll_cast["maximumTargets"] = option.maximum_targets
			var candidates: Array[Dictionary] = []
			for candidate: CombatSpellTargetView in option.target_candidates:
				candidates.append({"id": candidate.id, "kind": String(candidate.kind), "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
			scroll_cast["targetCandidates"] = candidates
		if option.target_mode == &"area":
			scroll_cast["areaShape"] = option.area_shape
			scroll_cast["defaultTargetCoordinate"] = [option.default_target_coordinate.x, option.default_target_coordinate.y]
			scroll_cast["areaOffsets"] = option.area_offsets.map(func(offset: Vector2i) -> Array[int]: return [offset.x, offset.y])
			scroll_cast["legalTargetCoordinates"] = option.legal_target_coordinates.map(func(coordinate: Vector2i) -> Array[int]: return [coordinate.x, coordinate.y])
		scroll_casts.append(scroll_cast)
	if not scroll_casts.is_empty():
		actions.append("use_scroll")
	var scroll_cast_reason := _rules.combat_flow.character_scroll_unavailable_reason(_game_state, _content, combat_view.active_actor_id)
	var retreat := {"enabled": combat_view.retreat_available, "reason": combat_view.retreat_unavailable_reason, "nearestEnemyRange": combat_view.nearest_enemy_range}
	var enemies_remaining := combat_view.hostile_actor_ids.size()
	var bandage_targets: Array[Dictionary] = []
	for candidate: CharacterView in combat_view.bandage_candidates:
		bandage_targets.append({"id": candidate.id, "name": candidate.name, "currentHealth": candidate.current_health, "maximumHealth": candidate.maximum_health})
	var turn_targets: Array[Dictionary] = []
	for target: MonsterView in combat_view.turn_undead_targets:
		turn_targets.append({"id": target.id, "name": target.name, "hitDice": target.hit_dice, "magicResistance": target.magic_resistance})
	return InteractionRequest.from_payload(request_id, &"combat_action", {"battleId": combat_view.battle_id, "round": combat_view.round_number, "actorId": combat_view.active_actor_id, "attackUnitsRemaining": combat_view.attack_units_remaining, "movementRemaining": combat_view.movement_remaining, "enemiesRemaining": enemies_remaining, "actions": actions, "weaponMode": String(combat_view.weapon_mode), "weaponSwitch": weapon_switch, "rangedAttack": ranged_attack, "retreat": retreat, "meleeAttackReason": combat_view.melee_attack_unavailable_reason, "targets": targets, "combatants": combatants, "movement": movement, "spellCasts": spell_casts, "spellCastReason": spell_cast_reason, "fastSpells": fast_spells, "itemCasts": item_casts, "itemCastReason": item_cast_reason, "scrollCasts": scroll_casts, "scrollCastReason": scroll_cast_reason, "autoTurn": {"enabled": combat_view.auto_turn.enabled, "reason": combat_view.auto_turn.reason}, "autoCharacterIds": combat_view.auto_character_ids.duplicate(), "delay": {"enabled": combat_view.delay.enabled, "reason": combat_view.delay.reason}, "bandage": {"enabled": combat_view.bandage.enabled, "reason": combat_view.bandage.reason, "targets": bandage_targets}, "turnUndead": {"enabled": combat_view.turn_undead.enabled, "reason": combat_view.turn_undead.reason, "targets": turn_targets}, "undo": {"enabled": combat_view.undo.enabled, "reason": combat_view.undo.reason}})


static func _character_combatant_payload(character: CharacterView) -> Dictionary:
	return {"id": character.id, "kind": "character", "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health, "spellPoints": character.spell_points, "maximumSpellPoints": character.maximum_spell_points, "armor": character.armor, "magicResistance": character.magic_resistance, "attacks": character.attacks_per_round, "movement": character.movement, "maximumMovement": character.maximum_movement, "traitor": character.traitor, "helpless": character.condition_values[ConditionRules.HELPLESS] != 0, "conditions": character.conditions.map(func(condition: CharacterMetricView) -> String: return condition.name)}


static func _monster_combatant_payload(monster: MonsterView) -> Dictionary:
	return {"id": monster.id, "kind": "monster", "name": monster.name, "currentHealth": monster.current_health, "maximumHealth": monster.maximum_health, "spellPoints": monster.spell_points, "maximumSpellPoints": monster.maximum_spell_points, "armor": monster.armor, "magicResistance": monster.magic_resistance, "hitDice": monster.hit_dice, "attacks": str(monster.attack_count), "movement": monster.movement_maximum, "maximumMovement": monster.movement_maximum, "traitor": monster.traitor, "helpless": monster.helpless, "conditions": monster.conditions.duplicate(), "immunities": monster.immunities.duplicate(), "vulnerabilities": monster.vulnerabilities.duplicate(), "weapon": monster.weapon_name}


func _append_combatant_position_facts(payload: Dictionary, active_actor_id: String, combatant_id: String, terrain_set: BattleTerrainSetDefinition) -> void:
	if _game_state.combat == null or _game_state.combat.battlefield == null or active_actor_id.is_empty() or combatant_id.is_empty():
		return
	payload["range"] = _rules.battlefield.classic_range(_game_state.combat.battlefield, active_actor_id, combatant_id)
	payload["blocked"] = terrain_set == null or not _rules.battlefield.has_line_of_sight(_game_state.combat.battlefield, terrain_set, active_actor_id, combatant_id)


func _append_character_weapon_facts(payload: Dictionary, character: CharacterState, equipment: CharacterCombatEquipment, weapon_mode: StringName) -> void:
	if equipment == null or not equipment.valid:
		return
	var weapon := equipment.missile_weapon if weapon_mode == &"missile" else equipment.melee_weapon
	var instance_id := equipment.missile_weapon_instance_id if weapon_mode == &"missile" else equipment.melee_weapon_instance_id
	payload["weapon"] = weapon.name if weapon != null else "Unarmed"
	payload["weaponCharges"] = -1
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			payload["weaponCharges"] = instance.charges
			break


func _combat_terrain_set() -> BattleTerrainSetDefinition:
	if _game_state.combat == null or _game_state.combat.battlefield == null:
		return null
	var map := _content.world.map_by_id(_game_state.combat.battlefield.map_id)
	return _content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null


static func _combat_destination(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2 or not value[0] is int or not value[1] is int:
		return Vector2i(-100_000, -100_000)
	return Vector2i(value[0], value[1])


func _grant_treasure(classic_treasure_id: int, request_id: String) -> ScenarioRuntimeOperationResult:
	var treasure := _content.treasure_by_classic_id(absi(classic_treasure_id))
	if treasure == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Classic opcode 10 references unavailable treasure %d." % classic_treasure_id)
	return _grant_treasure_definition(treasure, request_id)


func _grant_treasure_definition(treasure: TreasureDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var roll := _rules.economy.roll_treasure(treasure, _rng)
	return _begin_reward(&"scenario", treasure.id, roll.experience, roll.wealth, roll.item_ids, request_id)


func begin_completed_battle_reward(request_id: String) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Battle rewards require a completed battle.")
	if combat.rewards_completed:
		return ScenarioRuntimeOperationResult.completed(String(combat.outcome))
	if combat.rewards_started:
		return ScenarioRuntimeOperationResult.failed(&"battle_reward_already_started", "The completed battle already has an active reward continuation.")
	var defeated_monsters: Array[Dictionary] = []
	var pending_item_count := 0
	if combat.outcome == &"victory":
		for monster: MonsterState in combat.monsters():
			var definition := _content.monster_by_id(monster.definition_id)
			if definition == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Battle reward references unavailable monster content.")
			if not monster.traitor or monster.current_health >= 1:
				continue
			var loot := monster.loot_item_ids()
			if loot.is_empty():
				loot = definition.item_ids()
				if not loot.is_empty() and definition.random_weapon_table > 0:
					loot[0] = monster.weapon_id
			for item_id: String in loot:
				if item_id.is_empty():
					continue
				if _content.item_by_id(item_id) == null:
					return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle reward references unavailable item '%s'." % item_id)
				pending_item_count += 1
				if pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
					return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
			defeated_monsters.append({"monster": monster, "definition": definition, "loot": loot})
	# Validate the whole source-owned reward before consuming RNG or claiming its
	# one-shot battle continuation. A malformed package therefore remains retryable.
	combat.rewards_started = true
	var item_ids: Array[String] = []
	var wealth := WealthState.new()
	var experience := 0
	var events: Array[DomainEvent] = []
	if combat.outcome == &"victory":
		for row: Dictionary in defeated_monsters:
			var monster: MonsterState = row["monster"]
			var definition: MonsterDefinition = row["definition"]
			var money := definition.money_values()
			for kind: WealthState.Kind in [WealthState.Kind.GOLD, WealthState.Kind.GEMS, WealthState.Kind.JEWELRY]:
				var maximum := maxi(0, money[kind] if kind < money.size() else 0)
				if maximum > 0:
					wealth.add(kind, _rng.draw_between(0, maximum, StringName("battle.reward.%s.money.%d" % [monster.id, kind])))
			experience += _monster_reward_experience(monster, definition)
			for item_id: String in row["loot"]:
				if not item_id.is_empty():
					item_ids.append(item_id)
		events.append(DomainEvent.new(&"battle_reward_constructed", {"battleId": combat.battle_id, "experience": experience, "wealth": wealth.to_data(), "itemCount": item_ids.size()}))
	var operation := _begin_reward(&"battle", combat.battle_id, experience, wealth, item_ids, request_id)
	operation.events = events + operation.events
	return operation


func _begin_reward(origin: StringName, source_id: String, total_experience: int, wealth: WealthState, item_ids: Array[String], request_id: String) -> ScenarioRuntimeOperationResult:
	if wealth == null or item_ids.size() > ClassicRewardState.MAX_PENDING_ITEMS:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward exceeds the supported Classic reward bounds.")
	var experience_multiplier := _game_state.experience_multiplier
	if experience_multiplier < 0.0:
		var campaign := _content.campaign_definition()
		var current_levels := 0
		for party_character: CharacterState in _game_state.party.characters():
			current_levels += party_character.level
		experience_multiplier = PartySetupRules.experience_multiplier(campaign.recommended_party_levels, current_levels, _game_state.difficulty) if campaign != null and campaign.guidance_authored and campaign.recommended_party_levels > 0 else 1.0
	var scaled_experience := PartySetupRules.scale_experience_by_multiplier(total_experience, experience_multiplier)
	var scaled_wealth := WealthState.new(
		PartySetupRules.scale_money(wealth.gold, _game_state.difficulty),
		PartySetupRules.scale_money(wealth.gems, _game_state.difficulty),
		PartySetupRules.scale_money(wealth.jewelry, _game_state.difficulty),
	)
	var reward_definitions: Array[ItemDefinition] = []
	var unique_owned: Dictionary = {}
	for character: CharacterState in _game_state.party.characters():
		for carried: ItemInstance in character.inventory():
			unique_owned[carried.definition_id] = true
	for item_id: String in item_ids:
		var definition := _content.item_by_id(item_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Reward '%s' references unavailable item '%s'." % [source_id, item_id])
		if definition.cost < 0 and unique_owned.has(definition.id):
			continue
		reward_definitions.append(definition)
		if definition.cost < 0:
			unique_owned[definition.id] = true
	var reward := ClassicRewardState.new(origin, source_id, scaled_experience, scaled_wealth)
	var items: Array[ItemInstance] = []
	for definition: ItemDefinition in reward_definitions:
		var identified := absi(definition.item_type) == 24
		items.append(ItemInstance.new(_game_state.next_instance_id("reward.item"), definition.id, definition.initial_charges, false, identified))
	if not reward.set_items(items):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward contains invalid item instances.")
	var awards: Dictionary = {}
	var recipients := _reward_experience_recipients(origin)
	var share := 0 if recipients.is_empty() else int(float(reward.experience_pool) / float(recipients.size()))
	reward.experience_share = share
	for character: CharacterState in recipients:
		var race := _content.race_by_id(character.race_id)
		var awarded := _rules.characters.battle_experience(character, race, share)
		awards[character.id] = awarded
	if not reward.set_experience_awards(awards):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The reward experience recipients are invalid.")
	_game_state.party.pooled_wealth.gold += scaled_wealth.gold
	_game_state.party.pooled_wealth.gems += scaled_wealth.gems
	_game_state.party.pooled_wealth.jewelry += scaled_wealth.jewelry
	for character: CharacterState in recipients:
		character.experience += int(awards[character.id])
	var events: Array[DomainEvent] = [DomainEvent.new(&"reward_opened", {"origin": String(origin), "sourceId": source_id, "experiencePool": reward.experience_pool, "experienceShare": reward.experience_share, "experienceByCharacter": awards, "wealth": scaled_wealth.to_data(), "itemCount": items.size()})]
	if items.is_empty() and scaled_wealth.gold == 0 and scaled_wealth.gems == 0 and scaled_wealth.jewelry == 0 and scaled_experience == 0:
		return _complete_reward(reward, events)
	return _wait_for_reward(reward, request_id, events)


func _reward_experience_recipients(origin: StringName) -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health <= 0 or character.conditions.value(ConditionRules.ANIMATED) < 0:
			continue
		if origin == &"battle" and (_game_state.combat == null or _game_state.combat.battlefield == null or not _game_state.combat.battlefield.has_actor(character.id)):
			continue
		result.append(character)
	return result


func _wait_for_reward(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var request := _reward_request(reward, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward has no valid interaction for its current phase.")
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.reward(reward), events)


func _reward_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _level_result_request(reward, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _reward_spell_request(reward, request_id)
	if reward.completion_pending:
		var summary := "%d unclaimed item%s and %d gold, %d gems, %d jewelry will be left behind." % [reward.items().size(), "" if reward.items().size() == 1 else "s", _game_state.party.pooled_wealth.gold, _game_state.party.pooled_wealth.gems, _game_state.party.pooled_wealth.jewelry]
		return InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "prompt": "Leave the remaining treasure behind?", "summary": summary})
	var pending := reward.first_item()
	var item_payload: Variant = null
	if pending != null:
		var definition := _content.item_by_id(pending.definition_id)
		if definition == null:
			return null
		item_payload = {
			"instanceId": pending.id,
			"definitionId": pending.definition_id,
			"name": definition.name if pending.identified else definition.unidentified_name,
			"charges": pending.charges,
			"identified": pending.identified,
			"magical": reward.magic_detected and definition.magical,
		}
	var characters: Array[Dictionary] = []
	var has_share_capacity := false
	for character: CharacterState in _game_state.party.characters():
		var enabled := false
		var reason := ""
		if pending != null:
			var definition := _content.item_by_id(pending.definition_id)
			enabled = _rules.inventory.can_restore_item(character, pending, definition)
			if character.inventory().size() >= InventoryRules.MAX_ITEMS:
				reason = "Inventory is full."
			elif character.carried_load + definition.instance_weight(pending.charges) > character.maximum_load:
				reason = "The item would exceed maximum load."
			elif not enabled:
				reason = "This character cannot receive the item."
		characters.append({
			"id": character.id,
			"name": character.name,
			"enabled": enabled,
			"reason": reason,
			"wealth": character.money.to_data(),
			"canTakeGold": _game_state.party.pooled_wealth.gold >= 5 and character.carried_load + 5 <= character.maximum_load,
			"canTakeGems": _game_state.party.pooled_wealth.gems >= 1 and character.carried_load + 1 <= character.maximum_load,
			"canTakeJewelry": _game_state.party.pooled_wealth.jewelry >= 1 and character.carried_load + 15 <= character.maximum_load,
			"goldReason": "The pool has fewer than 5 gold or the character cannot carry it.",
			"gemsReason": "The pool has no gems or the character cannot carry one.",
			"jewelryReason": "The pool has no jewelry or the character cannot carry one.",
		})
		has_share_capacity = has_share_capacity or character.carried_load < character.maximum_load
	var detect_rows := _reward_caster_rows(63, 5)
	var identify_rows := _reward_caster_rows(48, 25)
	return InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {
		"mode": "ordinary",
		"prompt": "Distribute the treasure, then choose Done.",
		"origin": String(reward.origin),
		"sourceId": reward.source_id,
		"experiencePool": reward.experience_pool,
		"experienceShare": reward.experience_share,
		"wealth": _game_state.party.pooled_wealth.to_data(),
		"item": item_payload,
		"remaining": reward.items().size(),
		"characters": characters,
		"hasShareCapacity": has_share_capacity,
		"detect": {"visible": pending != null and not reward.magic_detected, "casters": detect_rows, "reason": "No living caster knows Detect Magic with 5 spell points."},
		"identify": {"visible": pending != null and not reward.identified, "casters": identify_rows, "reason": "No living caster knows Identify with 25 spell points."},
	})


func _resume_reward(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if continuation == null or continuation.kind != ScenarioRuntimeContinuation.CLASSIC_REWARD:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward continuation is malformed.")
	var reward_body := continuation.body as ScenarioRuntimeContinuation.RewardBody
	var reward := ClassicRewardState.from_data(reward_body.state.to_data()) if reward_body != null and reward_body.state != null else null
	if reward == null or not _reward_state_is_valid(reward):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The saved reward state is invalid.")
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _resume_reward_level(reward, response, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _resume_reward_spells(reward, response, request_id)
	var body := response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Treasure distribution requires a typed action.")
	var action := String(body.action)
	var events: Array[DomainEvent] = []
	if reward.completion_pending:
		if action == "cancel-completion":
			reward.completion_pending = false
			return _wait_for_reward(reward, request_id)
		if action != "confirm-completion":
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Treasure completion must be confirmed or cancelled.")
		var abandoned := reward.items().size()
		var no_items: Array[ItemInstance] = []
		reward.set_items(no_items)
		var forfeited := _game_state.party.pooled_wealth.to_data()
		_game_state.party.pooled_wealth = WealthState.new()
		reward.completion_pending = false
		events.append(DomainEvent.new(&"reward_remainder_left", {"itemCount": abandoned, "wealth": forfeited}))
		return _begin_reward_progression(reward, request_id, events)
	match action:
		"assign":
			var mutation := _assign_reward_item(reward, body)
			if not mutation.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(mutation["code"]), mutation["message"])
			events.append(DomainEvent.new(&"reward_item_assigned", {"instanceId": body.instance_id, "characterId": body.character_id}))
		"discard":
			var pending := reward.first_item()
			if pending == null or body.instance_id != pending.id or reward.remove_item(pending.id) == null:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The item being left behind is not the current reward item.")
			events.append(DomainEvent.new(&"reward_item_left", {"instanceId": pending.id, "itemId": pending.definition_id}))
		"pool":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var pool_probe := _rules.economy.pool_probe(_game_state.party)
			if not pool_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", pool_probe.reason)
			_rules.economy.pool_party_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"reward_wealth_pooled", _game_state.party.pooled_wealth.to_data()))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-reward-pool"}))
		"share":
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var share_probe := _rules.economy.share_probe(_game_state.party)
			if not share_probe.allowed:
				return ScenarioRuntimeOperationResult.failed(&"money_action_unavailable", share_probe.reason)
			_rules.economy.share_pooled_wealth(_game_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"reward_wealth_shared", _game_state.party.pooled_wealth.to_data()))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-reward-share"}))
		"transfer":
			var transfer_error := _transfer_reward_wealth(body)
			if not transfer_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(transfer_error["code"]), transfer_error["message"])
			events.append(DomainEvent.new(&"reward_wealth_transferred", body.to_data()))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if body.direction == &"to-character" else 663, "waitForCompletion": false, "source": "classic-reward-swap"}))
		"detect", "identify":
			var detection_error := _apply_reward_detection(reward, action, body)
			if not detection_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(detection_error["code"]), detection_error["message"])
			events.append(DomainEvent.new(&"reward_magic_%s" % ("detected" if action == "detect" else "identified"), {"characterId": body.character_id}))
		"done":
			if not reward.items().is_empty() or _reward_has_pooled_wealth():
				reward.completion_pending = true
				return _wait_for_reward(reward, request_id)
			return _begin_reward_progression(reward, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The treasure action is unavailable.")
	return _wait_for_reward(reward, request_id, events)


func _assign_reward_item(reward: ClassicRewardState, body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.instance_id.is_empty() or body.character_id.is_empty():
		return {"code": "invalid_interaction_response", "message": "Treasure assignment requires item and character IDs."}
	var pending := reward.first_item()
	var character := _game_state.party.character_by_id(body.character_id)
	var definition: ItemDefinition = null if pending == null else _content.item_by_id(pending.definition_id)
	if pending == null or pending.id != body.instance_id or character == null or definition == null or not _rules.inventory.can_restore_item(character, pending, definition):
		return {"code": "reward_assignment_unavailable", "message": "The selected character cannot receive the pending item."}
	if not _rules.inventory.restore_item(character, pending, definition):
		return {"code": "reward_assignment_failed", "message": "The item assignment could not be committed."}
	if reward.identified:
		pending.identified = true
	if reward.remove_item(pending.id) == null:
		_rules.inventory.remove_item(character, pending.id, definition)
		return {"code": "reward_assignment_failed", "message": "The committed item could not be removed from the reward queue."}
	return {}


func _transfer_reward_wealth(body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.character_id.is_empty() or body.direction.is_empty() or body.wealth_kind.is_empty() or body.amount < 1:
		return {"code": "invalid_interaction_response", "message": "Treasure transfer requires character, direction, denomination, and amount."}
	var character := _game_state.party.character_by_id(body.character_id)
	var kind := _wealth_kind(String(body.wealth_kind))
	var amount := body.amount
	if character == null or kind < 0 or amount != (5 if kind == WealthState.Kind.GOLD else 1):
		return {"code": "invalid_interaction_response", "message": "The requested Classic wealth increment is invalid."}
	var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, amount) if body.direction == &"to-character" else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, amount) if body.direction == &"to-pool" else false
	if transferred:
		_recalculate_party_movement()
	return {} if transferred else {"code": "reward_transfer_unavailable", "message": "The selected wealth transfer is no longer available."}


func _apply_reward_detection(reward: ClassicRewardState, action: String, body: InteractionResponse.TreasureBody) -> Dictionary:
	if body.character_id.is_empty():
		return {"code": "invalid_interaction_response", "message": "Magic detection requires a caster."}
	var special := 63 if action == "detect" else 48
	var cost := 5 if action == "detect" else 25
	var caster_id := body.character_id
	var available := false
	for row: Dictionary in _reward_caster_rows(special, cost):
		if row["id"] == caster_id:
			available = true
			break
	if not available or reward.first_item() == null or (reward.magic_detected if action == "detect" else reward.identified):
		return {"code": "reward_spell_unavailable", "message": "The selected treasure spell is unavailable."}
	var caster := _game_state.party.character_by_id(caster_id)
	caster.spell_points -= cost
	if action == "detect":
		reward.magic_detected = true
	else:
		reward.identified = true
		for item: ItemInstance in reward.items():
			item.identified = true
	return {}


func _reward_caster_rows(special: int, cost: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if not _character_can_cast_reward_spell(character) or character.spell_points < cost:
			continue
		var knows := false
		for spell_id: String in character.known_spells():
			var spell := _content.spell_by_id(spell_id)
			if spell != null and spell.special == special:
				knows = true
				break
		if knows:
			result.append({"id": character.id, "name": character.name, "spellPoints": character.spell_points, "cost": cost})
	return result


static func _character_can_cast_reward_spell(character: CharacterState) -> bool:
	return character != null and character.current_health > 0 and character.spell_points > 0 and character.conditions.value(ConditionRules.CONFUSED) == 0 and character.conditions.value(ConditionRules.SILENCED) == 0 and character.conditions.value(ConditionRules.HELPLESS) == 0 and character.conditions.value(ConditionRules.STUPID) == 0 and character.conditions.value(ConditionRules.ANIMATED) == 0


func _begin_reward_progression(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	reward.phase = ClassicRewardState.LEVEL_PHASE
	var character_ids: Array[String] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0 and character.experience > 0:
			character_ids.append(character.id)
	if not reward.set_level_character_ids(character_ids):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "The level-up queue is invalid.")
	return _advance_reward_levels(reward, request_id, events)


func _advance_reward_levels(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var ids := reward.level_character_ids()
	while reward.level_index < ids.size():
		var character := _game_state.party.character_by_id(ids[reward.level_index])
		var race: RaceDefinition = null if character == null else _content.race_by_id(character.race_id)
		var caste: CasteDefinition = null if character == null else _content.caste_by_id(character.caste_id)
		if character == null or race == null or caste == null or character.current_health <= 0 or character.experience <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "A character in the level-up queue is no longer eligible.")
		var threshold_index := clampi(character.level, 1, 30) - 1
		character.experience -= caste.victory_threshold(threshold_index)
		var level_result := _rules.characters.level_up(character, race, caste, _rng)
		if level_result == null:
			return ScenarioRuntimeOperationResult.failed(&"character_level_failed", "Character '%s' could not level." % character.id)
		reward.pending_level_result = {"characterId": character.id, "characterName": character.name, "level": character.level, "stamina": level_result.stamina_gained, "spellPoints": level_result.spell_points_gained, "toHit": level_result.to_hit_gained, "magicResistance": level_result.magic_resistance_gained}
		if character.spellcaster_type > 0 and character.maximum_spell_points > 0:
			var spell_ids := reward.spell_character_ids()
			spell_ids.append(character.id)
			reward.set_spell_character_ids(spell_ids)
		events.append(DomainEvent.new(&"character_leveled", reward.pending_level_result))
		return _wait_for_reward(reward, request_id, events)
	reward.phase = ClassicRewardState.SPELL_PHASE
	return _advance_reward_spells(reward, request_id, events)


func _level_result_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	if reward.pending_level_result.is_empty():
		return null
	var result := reward.pending_level_result
	return InteractionRequest.from_payload(request_id, InteractionRequest.LEVEL_UP, {"mode": "result", "prompt": "Review the level gained.", "characterId": result["characterId"], "characterName": result["characterName"], "level": result["level"], "gains": {"stamina": result["stamina"], "spellPoints": result["spellPoints"], "toHit": result["toHit"], "magicResistance": result["magicResistance"]}})


func _resume_reward_level(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var body := response.body as InteractionResponse.LevelUpBody
	if response.kind != InteractionRequest.LEVEL_UP or body == null or body.action != &"continue" or body.character_id != reward.pending_level_result.get("characterId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The level result must be acknowledged by its character ID.")
	var character_id := String(reward.pending_level_result.get("characterId", ""))
	reward.pending_level_result.clear()
	reward.level_index += 1
	return _advance_reward_levels(reward, request_id, [DomainEvent.new(&"level_result_acknowledged", {"characterId": character_id})])


func _advance_reward_spells(reward: ClassicRewardState, request_id: String, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	if reward.spell_index >= reward.spell_character_ids().size():
		return _complete_reward(reward, events)
	return _wait_for_reward(reward, request_id, events)


func _reward_spell_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	var ids := reward.spell_character_ids()
	if reward.spell_index < 0 or reward.spell_index >= ids.size():
		return null
	var character := _game_state.party.character_by_id(ids[reward.spell_index])
	var caste: CasteDefinition = null if character == null else _content.caste_by_id(character.caste_id)
	if character == null or caste == null:
		return null
	var spells: Array[Dictionary] = []
	for spell: SpellDefinition in _reward_spell_candidates(character, caste):
		spells.append({"id": spell.id, "name": spell.name, "classicId": spell.classic_id, "cost": _rules.characters.spell_selection_cost(spell), "selected": character.known_spells().has(spell.id)})
	return InteractionRequest.from_payload(request_id, InteractionRequest.LEVEL_UP, {"mode": "spell-selection", "prompt": "Choose the spells this character knows.", "characterId": character.id, "characterName": character.name, "pointTotal": _rules.characters.spell_selection_total(character, caste), "spells": spells})


func _resume_reward_spells(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var ids := reward.spell_character_ids()
	var body := response.body as InteractionResponse.LevelUpBody
	if response.kind != InteractionRequest.LEVEL_UP or body == null or body.action != &"confirm-spells" or reward.spell_index < 0 or reward.spell_index >= ids.size() or body.character_id != ids[reward.spell_index]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Spell selection requires the pending character and spell IDs.")
	var character := _game_state.party.character_by_id(ids[reward.spell_index])
	var caste: CasteDefinition = null if character == null else _content.caste_by_id(character.caste_id)
	if character == null or caste == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_progression", "The spell-selection character is unavailable.")
	var candidates: Dictionary = {}
	for spell: SpellDefinition in _reward_spell_candidates(character, caste):
		candidates[spell.id] = spell
	var selected: Array[String] = []
	var spent := 0
	for value: String in body.spell_ids:
		if selected.has(value) or not candidates.has(value):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The selected spell list contains an unavailable or duplicate spell.")
		selected.append(value)
		spent += _rules.characters.spell_selection_cost(candidates[value])
	var total := _rules.characters.spell_selection_total(character, caste)
	if spent > total:
		return ScenarioRuntimeOperationResult.failed(&"spell_selection_budget_exceeded", "The selected spells exceed the Classic point budget.")
	character.set_known_spells(selected)
	reward.spell_index += 1
	return _advance_reward_spells(reward, request_id, [DomainEvent.new(&"level_spells_selected", {"characterId": character.id, "spellIds": selected, "pointsRemaining": total - spent})])


func _reward_spell_candidates(character: CharacterState, caste: CasteDefinition) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	var maximum_level := _rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in _content.spell_definitions():
		if int(float(spell.classic_id) / 1000.0) == character.spellcaster_type and spell.classic_tier() >= 0 and spell.classic_tier() < maximum_level and spell.classic_slot() >= 1 and spell.classic_slot() <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


func _complete_reward(reward: ClassicRewardState, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var completed_events: Array[DomainEvent] = []
	completed_events.assign(events)
	completed_events.append(DomainEvent.new(&"reward_completed", {"origin": String(reward.origin), "sourceId": reward.source_id, "experienceByCharacter": reward.experience_awards()}))
	if reward.origin == &"battle":
		if _game_state.combat == null or _game_state.combat.battle_id != reward.source_id or not _game_state.combat.rewards_started:
			return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The battle reward no longer matches its completed battle.")
		var combat := _game_state.combat
		combat.rewards_completed = true
		var outcome := combat.outcome
		var battle := _content.battle_by_id(reward.source_id)
		if battle != null:
			_append_battle_after_message(battle, completed_events)
		completed_events.append(DomainEvent.new(&"battle_returned", {"battleId": reward.source_id, "outcome": String(outcome)}))
		# The completed battle remains session-owned through every ally, fumble,
		# treasure, level, and spell boundary. Release it only after the terminal
		# reward transaction has committed so both direct and VM callers return once.
		_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(reward.source_id, completed_events)


func _reward_state_is_valid(reward: ClassicRewardState) -> bool:
	if reward.source_id.is_empty() or reward.origin not in [&"scenario", &"battle"]:
		return false
	if reward.origin == &"battle" and (_game_state.combat == null or not _game_state.combat.completed or not _game_state.combat.rewards_started or _game_state.combat.rewards_completed or _game_state.combat.battle_id != reward.source_id):
		return false
	for item: ItemInstance in reward.items():
		if _content.item_by_id(item.definition_id) == null:
			return false
	for character_id: Variant in reward.experience_awards():
		if _game_state.party.character_by_id(String(character_id)) == null:
			return false
	for character_id: String in reward.level_character_ids():
		if _game_state.party.character_by_id(character_id) == null:
			return false
	for character_id: String in reward.spell_character_ids():
		if _game_state.party.character_by_id(character_id) == null:
			return false
	if not reward.pending_level_result.is_empty() and _game_state.party.character_by_id(String(reward.pending_level_result.get("characterId", ""))) == null:
		return false
	return true


func _reward_has_pooled_wealth() -> bool:
	return _game_state.party.pooled_wealth.gold > 0 or _game_state.party.pooled_wealth.gems > 0 or _game_state.party.pooled_wealth.jewelry > 0


static func _wealth_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1


func _money_movement_context_error() -> String:
	for character: CharacterState in _game_state.party.characters():
		if _content.race_by_id(character.race_id) == null or _content.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func _recalculate_party_movement() -> void:
	for character: CharacterState in _game_state.party.characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)


static func _monster_reward_experience(monster: MonsterState, definition: MonsterDefinition) -> int:
	var base_values: Array[int] = [15, 30, 45, 65, 80, 100, 140, 200, 300, 450, 700, 1100, 1800, 2300, 2800, 3200, 3700, 4200, 4700, 5200, 5700]
	var increment_values: Array[int] = [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 50, 55, 60, 65, 70, 75]
	var index := clampi(monster.hit_dice, 0, 20)
	var base := base_values[index] if monster.hit_dice <= 20 else 6200
	var increment := increment_values[index] if monster.hit_dice <= 20 else 80
	return base + definition.experience + monster.maximum_health * increment


func _grant_item(character_id: String, item_id: String, identified: bool) -> ScenarioRuntimeOperationResult:
	var character := _game_state.party.character_by_id(character_id)
	var item := _content.item_by_id(item_id)
	if character == null or item == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item_target", "Grant Item references an unavailable character or item.")
	var instance := _rules.inventory.add_item(character, item, _game_state.next_instance_id("scenario.item"), identified)
	if instance == null:
		return ScenarioRuntimeOperationResult.failed(&"inventory_full", "The character cannot carry the granted item.")
	return ScenarioRuntimeOperationResult.completed(instance.id, [DomainEvent.new(&"item_granted", {"characterId": character.id, "itemId": item.id, "instanceId": instance.id, "identified": identified})])


func _deanimate_lower_undead() -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"no_active_battle", "Classic opcode 121 requires an active battle.")
	var affected: Array[String] = []
	for monster: MonsterState in _game_state.combat.monsters():
		var definition := _content.monster_by_id(monster.definition_id)
		if definition != null and definition.type_flag(1) and not definition.type_flag(5) and monster.current_health > 0:
			monster.current_health = 0
			affected.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(affected, [DomainEvent.new(&"lower_undead_deanimated", {"monsterIds": affected})])


func _spawn_classic_monsters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"no_active_battle", "Classic opcode 124 requires an active battle.")
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 124 requires a five-value Extra Code row.")
	var definition := _content.monster_by_classic_id_for_set(absi(action.extra_code[1]), _game_state.monster_set)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 124 references unavailable monster %d." % action.extra_code[1])
	var authored_count := action.extra_code[2]
	var count := _rng.draw(absi(authored_count), &"classic.combat.spawn-count") if authored_count < 0 else authored_count
	var spawned: Array[String] = []
	for _index: int in maxi(0, count):
		var monster := _rules.monsters.build_monster(definition, _game_state.next_instance_id("combat.spawn"), -1, _game_state.difficulty, _game_state.clock.day(), _rng)
		if monster != null and _game_state.combat.add_monster(monster):
			_game_state.combat.append_turn_actor(monster.id)
			spawned.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(spawned, [DomainEvent.new(&"combat_monsters_spawned", {"monsterId": definition.id, "instanceIds": spawned, "soundId": action.extra_code[3] if action.extra_code.size() > 3 else 0})])


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))
