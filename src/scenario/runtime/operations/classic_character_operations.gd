class_name ClassicCharacterOperations
extends ClassicOpcodeHandler

const CLASSIC_ALLY_RECORD_CORRECTIONS: Dictionary = {
	"scenario-tutorial": {149: 116},
}

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules


func opcode_ids() -> Array[int]:
	return [-14, 14, 15, 16, 17, 18, 30, 31, 40, 43, 50, 52, 53, 55, 69, 74, 75, 81, 82, 83, 87, 88, 89, 90, 102, 105, 108]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		-14, 14:
			return _request_character_selection(action, request_id, action.opcode == -14)
		15, 16:
			return _apply_health(action, action.opcode == 16)
		17, 18:
			return _with_age_update_interactions(apply_scenario_spell(action, action.opcode == 18), request_id)
		30:
			return _filter_character_selection(action)
		31:
			return _request_character_ability(action, request_id)
		40:
			return _branch_on_party_condition(action)
		43:
			return _apply_classic_condition(action)
		50:
			return _select_characters_by_identity(action)
		52:
			return _select_characters_by_misc(action)
		53:
			return _select_characters_by_caste(action)
		55:
			return _branch_on_picked_characters(action)
		69:
			return _set_spellcasting_flags(action)
		74:
			return _alter_selected_spell_points(action)
		75:
			return _branch_on_spell_points(action, context)
		81:
			return _branch_on_character_condition(action)
		82, 83:
			_game_state.priest_turning_allowed = action.opcode == 83
			var turning_message := "You regain your ability to turn undead and nether spawn." if _game_state.priest_turning_allowed else "You may not use your ability to turn undead or nether spawn."
			var turning_sound := 20004 if _game_state.priest_turning_allowed else 10105
			return ScenarioRuntimeOperationResult.completed(_game_state.priest_turning_allowed, [
				DomainEvent.new(&"priest_turning_availability_changed", {"allowed": _game_state.priest_turning_allowed, "source": "classic"}),
				DomainEvent.new(&"classic_notification_requested", {"text": turning_message, "soundId": turning_sound, "source": "classic-opcode-%d" % action.opcode}),
			])
		87:
			return _branch_on_ally(action)
		88:
			var removed := _remove_classic_ally(absi(action.operand_id))
			return ScenarioRuntimeOperationResult.completed(removed, [DomainEvent.new(&"allies_removed", {"classicMonsterId": absi(action.operand_id), "count": removed})])
		89:
			return _add_classic_ally(absi(action.operand_id))
		90:
			return _take_experience(action)
		102:
			return _level_selected_characters()
		105:
			_game_state.allies_suspended = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.allies_suspended, [DomainEvent.new(&"ally_participation_changed", {"suspended": _game_state.allies_suspended, "source": "classic"})])
		108:
			return _alter_selected_characters(action)
	return super.execute(action, request_id, context)


func _alter_selected_spell_points(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5 or action.extra_code[0] == 0 or action.extra_code[2] < action.extra_code[1]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_spell_point_effect", "Classic opcode 74 requires a nonzero roll count and valid five-value Extra Code range.")
	var message := _content.message_by_id(action.extra_code[4]) if action.extra_code[4] != 0 else null
	if action.extra_code[4] != 0 and message == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 74 references unavailable message %d." % action.extra_code[4])
	var changes: Array[Dictionary] = []
	for character: CharacterState in _game_state.selected_characters():
		if character.maximum_spell_points == 0:
			continue
		var rolled := 0
		for _roll: int in absi(action.extra_code[0]):
			rolled = _rng.draw_between(action.extra_code[1], action.extra_code[2], &"classic.opcode74.spell-points")
		var amount := -rolled if action.extra_code[0] < 0 else rolled
		var previous := character.spell_points
		character.spell_points = clampi(character.spell_points + amount, 0, character.maximum_spell_points)
		changes.append({"characterId": character.id, "previous": previous, "current": character.spell_points, "amount": character.spell_points - previous})
	var events: Array[DomainEvent] = [DomainEvent.new(&"spell_points_changed", {"changes": changes, "source": "classic-opcode-74"})]
	if action.extra_code[3] != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(action.extra_code[1]), "waitForCompletion": action.extra_code[1] < 0, "source": "classic-opcode-74"}))
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-opcode-74"}))
	return ScenarioRuntimeOperationResult.completed(changes, events)


func _branch_on_spell_points(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 75 requires a five-value Extra Code row.")
	var candidates: Array[CharacterState] = []
	match action.extra_code[0]:
		1: candidates = _game_state.selected_characters()
		2:
			for character: CharacterState in _game_state.party.characters():
				if character.current_health > 0 and not character.conditions.is_active(ConditionRules.ANIMATED):
					candidates.append(character)
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_spell_point_branch", "Classic opcode 75 selector must be picked or all eligible living characters.")
	var matched := candidates.any(func(character: CharacterState) -> bool: return character.spell_points >= action.extra_code[1])
	var event := DomainEvent.new(&"spell_point_branch_checked", {"selector": action.extra_code[0], "minimumSpellPoints": action.extra_code[1], "matched": matched, "characterIds": candidates.map(func(character: CharacterState) -> String: return character.id), "source": "classic"})
	if not matched:
		if action.extra_code[2] == 1:
			return ScenarioRuntimeOperationResult.completed(false, [event, DomainEvent.new(&"action_point_kept", {"triggerId": context.trigger_id, "source": "classic-opcode-75"})], ScenarioVmDirective.finish_timeline())
		return ScenarioRuntimeOperationResult.completed(false, [event])
	var branch := _branch_to_destination(action.extra_code[3], action.extra_code[4], action.gosub)
	branch.events.append(event)
	return branch


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


func _level_selected_characters() -> ScenarioRuntimeOperationResult:
	var leveled: Array[String] = []
	var balances: Dictionary = {}
	for character: CharacterState in _game_state.selected_characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		if race == null or caste == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_character_profile", "Classic opcode 102 requires source-defined race and caste profiles.")
		var threshold_index := clampi(character.level, 1, 30) - 1
		character.experience = 1 - caste.victory_threshold(threshold_index)
		if _rules.characters.level_up(character, race, caste, _rng) == null:
			return ScenarioRuntimeOperationResult.failed(&"character_level_failed", "Classic opcode 102 could not level character '%s'." % character.id)
		leveled.append(character.id)
		balances[character.id] = character.experience
	return ScenarioRuntimeOperationResult.completed(leveled, [DomainEvent.new(&"characters_leveled", {"characterIds": leveled, "experienceRemaining": balances, "source": "classic"})])


func _request_character_selection(action: ClassicActionDefinition, request_id: String, invert: bool) -> ScenarioRuntimeOperationResult:
	var count := absi(action.operand_id)
	if count < 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_count", "Classic character picker requests no characters.")
	var eligible: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if action.operand_id < 0 or character.current_health > 0:
			eligible.append({"id": character.id, "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic character picker has no eligible party members.")
	count = mini(count, eligible.size())
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"character_selection", {"count": count, "eligible": eligible, "allowDead": action.operand_id < 0}), ScenarioRuntimeContinuation.character_selection(count, action.operand_id < 0, invert))


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
			eligible.append({"id": character.id, "name": character.name, "currentHealth": character.current_health, "maximumHealth": character.maximum_health})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic ability check has no living party member.")
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.from_payload(request_id, &"character_selection", {"count": 1, "eligible": eligible, "allowDead": false}), ScenarioRuntimeContinuation.character_ability(action.extra_code, action.gosub))


func _apply_health(action: ClassicActionDefinition, whole_party: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_health_effect", "Classic health action requires a valid Extra Code roll range.")
	var message: MessageDefinition = null
	if action.extra_code[4] != 0:
		message = _content.message_by_id(absi(action.extra_code[4]))
		if message == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 15 references unavailable message %d." % action.extra_code[4])
	var targets := _game_state.party.characters() if whole_party else _game_state.selected_characters()
	var hits: Array[Dictionary] = []
	var events: Array[DomainEvent] = []
	for character: CharacterState in targets:
		if action.extra_code[3] != 0:
			events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(action.extra_code[3]), "waitForCompletion": action.extra_code[3] < 0, "source": "classic-opcode-15"}))
		var roll := _rng.draw_between_classic(action.extra_code[1], action.extra_code[2], &"classic.health-effect")
		var amount := action.extra_code[0] * roll
		var previous := character.current_health
		character.current_health = mini(character.maximum_health, maxi(-32_768, character.current_health + amount))
		hits.append({"characterId": character.id, "previousHealth": previous, "health": character.current_health, "amount": character.current_health - previous})
		events.append(DomainEvent.new(&"character_effect_requested", {"characterId": character.id, "resourceType": "cicn", "firstResourceId": 12112, "frameCount": 8, "source": "classic-opcode-15"}))
	events.append(DomainEvent.new(&"party_health_changed", {"targets": "party" if whole_party else "selected", "hits": hits}))
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-opcode-15", "classicClick": action.extra_code[4] > 0}))
	return ScenarioRuntimeOperationResult.completed(hits, events)


func _filter_character_selection(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 30 requires a five-value Extra Code row.")
	var values := action.extra_code
	var candidates := _game_state.selected_characters()
	if int(values[2]) in [1, 2]:
		candidates = []
		for character: CharacterState in _game_state.party.characters():
			if int(values[2]) == 1 or character.current_health > 0:
				candidates.append(character)
	var selected: Array[String] = []
	var checks: Array[Dictionary] = []
	var attribute_check := int(values[3]) != 0
	var check_index := absi(int(values[0]))
	for character: CharacterState in candidates:
		var check_value := _character_attribute(character, check_index) if attribute_check else character.ability_value(check_index)
		var roll := _rng.draw(25 if attribute_check else 100, &"classic.filter-character")
		var passed := roll - int(values[1]) < check_value if attribute_check else roll <= check_value + int(values[1])
		if passed != (int(values[0]) < 0):
			selected.append(character.id)
		checks.append({"characterId": character.id, "roll": roll, "value": check_value, "passed": passed})
	_game_state.set_selected_character_ids(selected)
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"character_selection_filtered", {"characterIds": selected, "checks": checks})])


func _branch_on_party_condition(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 40 requires a five-value Extra Code row.")
	var required_state := action.extra_code[0]
	var condition_index := action.extra_code[3]
	if required_state not in [1, 2] or condition_index < 0 or condition_index >= ConditionSet.PARTY_COUNT:
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_condition", "Classic party-condition branch has an invalid state or condition.")
	var active := _game_state.party.conditions.is_active(condition_index)
	if required_state == 1 and not active or required_state == 2 and active:
		return ScenarioRuntimeOperationResult.completed(false)
	return _branch_target_mode(action.extra_code[1] - 1, action.extra_code[2], action.gosub)


func _apply_classic_condition(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 43 requires a five-value Extra Code row.")
	var target_mode := action.extra_code[0]
	var condition_index := action.extra_code[1]
	var duration := action.extra_code[2]
	if target_mode < 0 or target_mode > 2 or condition_index < 0 or condition_index >= ConditionSet.CHARACTER_COUNT:
		return ScenarioRuntimeOperationResult.failed(&"invalid_condition", "Classic opcode 43 has an invalid target or condition index.")
	var targets: Array[CharacterState] = []
	if target_mode == 1:
		targets = _game_state.selected_characters()
	else:
		for character: CharacterState in _game_state.party.characters():
			if target_mode == 0 or character.current_health > 0:
				targets.append(character)
	var ids: Array[String] = []
	var events: Array[DomainEvent] = []
	for character: CharacterState in targets:
		character.conditions.set_value(condition_index, duration)
		ids.append(character.id)
		if action.extra_code.size() > 3 and action.extra_code[3] != 0:
			events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(action.extra_code[3]), "waitForCompletion": action.extra_code[3] < 0, "source": "classic-opcode-43"}))
		events.append(DomainEvent.new(&"character_effect_requested", {"characterId": character.id, "resourceType": "cicn", "firstResourceId": 12032, "frameCount": 8, "source": "classic-opcode-43"}))
	events.append(DomainEvent.new(&"condition_applied", {"characterIds": ids, "condition": condition_index, "duration": duration}))
	return ScenarioRuntimeOperationResult.completed(ids, events)


func _select_characters_by_identity(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 50 requires a five-value Extra Code row.")
	var selector := action.extra_code[0]
	if selector < 0 or selector > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_identity_selector", "Classic opcode 50 has an invalid identity selector.")
	var selected: Array[String] = []
	for character: CharacterState in _game_state.party.characters():
		if action.extra_code[4] != 0 and character.current_health <= 0:
			continue
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		var matches := false
		match selector:
			0:
				matches = race != null and race.classic_id == action.extra_code[2]
			1:
				matches = character.gender == action.extra_code[1]
			2:
				matches = caste != null and caste.classic_id == action.extra_code[2]
			3:
				if action.extra_code[2] < 1 or action.extra_code[2] > 32:
					return ScenarioRuntimeOperationResult.failed(&"invalid_race_descriptor", "Classic opcode 50 race descriptor is outside 1 through 32.")
				matches = race != null and (race.descriptor_flags & (1 << (action.extra_code[2] - 1))) != 0
			4:
				matches = caste != null and caste.caste_class == action.extra_code[2]
		if matches:
			selected.append(character.id)
	_game_state.set_selected_character_ids(selected)
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected_by_identity", {"selector": selector, "characterIds": selected, "livingOnly": action.extra_code[4] != 0, "source": "classic"})])


func _select_characters_by_misc(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 52 requires a five-value Extra Code row.")
	var selector := action.extra_code[0]
	var value := action.extra_code[1]
	var source_mode := action.extra_code[2]
	if selector < 0 or selector > 8 or source_mode < 0 or source_mode > 2:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_selector", "Classic miscellaneous character selector is invalid.")
	var candidates := _game_state.selected_characters()
	if source_mode != 2:
		candidates = []
		for character: CharacterState in _game_state.party.characters():
			if source_mode == 0 or character.current_health > 0:
				candidates.append(character)
	var selected: Array[String] = []
	var party := _game_state.party.characters()
	for character: CharacterState in candidates:
		var matches := false
		match selector:
			0:
				matches = character.movement < value
			1:
				matches = party.find(character) < value
			2:
				matches = _character_has_classic_item(character, absi(value), false)
			3:
				matches = _rng.draw(100, &"classic.misc-character-percent") <= value
			4:
				matches = _rng.draw(25, &"classic.misc-character-attribute") >= _character_attribute(character, absi(value))
			5:
				matches = _rng.draw(100, &"classic.misc-character-save") > character.save_value(absi(value))
			6:
				matches = not _game_state.selected_character_ids().is_empty() and _game_state.selected_character_ids()[0] == character.id
			7:
				matches = _character_has_classic_item(character, absi(value), true)
			8:
				matches = party.find(character) == value
		if matches:
			selected.append(character.id)
	_game_state.set_selected_character_ids(selected)
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected_by_rule", {"selector": selector, "value": value, "characterIds": selected})])


func _select_characters_by_caste(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 53 requires a five-value Extra Code row.")
	var exact_caste := action.extra_code[0]
	var caste_group := action.extra_code[1]
	var source_mode := action.extra_code[2]
	if caste_group < 0 or caste_group > 3 or source_mode < 0 or source_mode > 2:
		return ScenarioRuntimeOperationResult.failed(&"invalid_caste_selection", "Classic opcode 53 has an invalid caste group or source mode.")
	var selected: Array[String] = []
	if source_mode != 2:
		for character: CharacterState in _game_state.party.characters():
			if source_mode == 1 and character.current_health <= 0:
				continue
			var caste := _content.caste_by_id(character.caste_id)
			if caste == null:
				continue
			var matches := caste.classic_id == exact_caste
			if caste_group == 1:
				matches = matches or caste.classic_id in [1, 3, 4]
			elif caste_group == 2:
				matches = matches or caste.classic_id in [3, 6, 7, 8]
			elif caste_group == 3:
				matches = matches or caste.classic_id in [2, 5]
			if matches:
				selected.append(character.id)
	_game_state.set_selected_character_ids(selected)
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected_by_caste", {"exactCaste": exact_caste, "casteGroup": caste_group, "sourceMode": source_mode, "characterIds": selected, "source": "classic"})])


func _branch_on_picked_characters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 55 requires a five-value Extra Code row.")
	var selector := action.extra_code[0]
	var failure_behavior := action.extra_code[1]
	if failure_behavior < 0 or failure_behavior > 2:
		return ScenarioRuntimeOperationResult.failed(&"invalid_picked_branch", "Classic opcode 55 has an invalid failure behavior.")
	var selected_ids := _game_state.selected_character_ids()
	var matched := not selected_ids.is_empty() if selector == 0 else selected_ids.size() == absi(selector)
	if selector >= 1 and selector <= 6:
		var party := _game_state.party.characters()
		var party_index := selector - 1
		matched = party_index < party.size() and selected_ids.has(party[party_index].id)
	var event := DomainEvent.new(&"picked_characters_tested", {"selector": selector, "matched": matched, "characterIds": selected_ids, "failureBehavior": failure_behavior, "source": "classic"})
	if matched:
		var success := _branch_xap(action.extra_code[3], action.gosub)
		success.events.append(event)
		return success
	if failure_behavior == 1:
		var failure := _branch_xap(action.extra_code[4], action.gosub)
		failure.events.append(event)
		return failure
	if failure_behavior == 2:
		var message := _content.message_by_id(action.extra_code[4])
		if message == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 55 references unavailable message %d." % action.extra_code[4])
		return ScenarioRuntimeOperationResult.completed(false, [event, DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-picked-branch"})], ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.completed(false, [event], ScenarioVmDirective.finish())


func _set_spellcasting_flags(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.operand_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 69 requires a five-value Extra Code row.")
	_game_state.character_spellcasting_blocked = action.extra_code[0] != 0
	_game_state.monster_spellcasting_blocked = action.extra_code[1] != 0
	_game_state.spell_charging = action.extra_code[2] != 0
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"spellcasting_flags_changed", {"characterCastingBlocked": _game_state.character_spellcasting_blocked, "monsterCastingBlocked": _game_state.monster_spellcasting_blocked, "charging": _game_state.spell_charging, "source": "classic"})])


func _branch_on_character_condition(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 81 requires a five-value Extra Code row.")
	var condition_index := action.extra_code[0]
	var candidate_mode := action.extra_code[1]
	if condition_index < 0 or condition_index >= ConditionSet.CHARACTER_COUNT:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_condition", "Classic opcode 81 references an invalid character condition.")
	var candidates: Array[CharacterState] = []
	if candidate_mode == 0:
		candidates = _game_state.party.characters()
	elif candidate_mode == -1:
		candidates = _game_state.selected_characters()
	else:
		var party := _game_state.party.characters()
		if candidate_mode < 0 or candidate_mode >= party.size():
			return ScenarioRuntimeOperationResult.failed(&"invalid_party_position", "Classic opcode 81 references an unavailable source-indexed party position.")
		candidates.append(party[candidate_mode])
	var matched := true
	for character: CharacterState in candidates:
		if not character.conditions.is_active(condition_index):
			matched = false
			break
	var branch := _branch_xap(action.extra_code[3] if matched else action.extra_code[4], action.gosub)
	branch.events.append(DomainEvent.new(&"character_condition_tested", {"condition": condition_index, "candidateMode": candidate_mode, "characterIds": candidates.map(func(character: CharacterState) -> String: return character.id), "matched": matched, "source": "classic"}))
	return branch


func _branch_on_ally(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 87 requires a five-value Extra Code row.")
	var monster := _content.monster_by_classic_id_for_set(absi(action.extra_code[0]), _game_state.monster_set)
	var present := false
	if monster != null:
		for ally: MonsterState in _game_state.party.allies():
			var ally_definition := _content.monster_by_id(ally.definition_id)
			if ally_definition != null and ally_definition.classic_id == monster.classic_id:
				present = true
				break
	var event := DomainEvent.new(&"ally_branch_checked", {"classicMonsterId": absi(action.extra_code[0]), "present": present})
	if present:
		var matched := _branch_target_mode(action.extra_code[1], action.extra_code[3], action.gosub)
		matched.events.append(event)
		return matched
	match action.extra_code[2]:
		0:
			var missing := _branch_target_mode(action.extra_code[1], action.extra_code[4], action.gosub)
			missing.events.append(event)
			return missing
		1:
			return ScenarioRuntimeOperationResult.completed(false, [event])
		2:
			var message := _content.message_by_id(action.extra_code[4])
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 87 references unavailable message %d." % action.extra_code[4])
			return ScenarioRuntimeOperationResult.completed(false, [event, DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-ally-check"})], ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.failed(&"invalid_ally_branch", "Classic opcode 87 has an invalid absent-ally behavior.")


func _remove_classic_ally(classic_monster_id: int) -> int:
	var removed := 0
	var retained: Array[MonsterState] = []
	for ally: MonsterState in _game_state.party.allies():
		var definition := _content.monster_by_id(ally.definition_id)
		if definition != null and definition.classic_id == classic_monster_id:
			removed += 1
		else:
			retained.append(ally)
	_game_state.party.set_allies(retained)
	return removed


func _add_classic_ally(classic_monster_id: int) -> ScenarioRuntimeOperationResult:
	var definition := _resolve_classic_ally_definition(classic_monster_id)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 89 references unavailable monster %d." % classic_monster_id)
	var ally := _rules.monsters.build_monster(definition, _game_state.next_instance_id("party.ally"), 0, _game_state.difficulty, _game_state.clock.day(), _rng)
	if ally == null or not _game_state.party.add_ally(ally):
		return ScenarioRuntimeOperationResult.failed(&"ally_add_failed", "The ally could not join the party.")
	return ScenarioRuntimeOperationResult.completed(ally.id, [DomainEvent.new(&"ally_added", {"allyId": ally.id, "monsterId": definition.id, "requestedClassicMonsterId": classic_monster_id, "resolvedClassicMonsterId": definition.classic_id})])


func _resolve_classic_ally_definition(classic_monster_id: int) -> MonsterDefinition:
	var definition := _content.monster_by_classic_id_for_set(classic_monster_id, _game_state.monster_set)
	if definition != null:
		return definition
	var campaign_corrections: Variant = CLASSIC_ALLY_RECORD_CORRECTIONS.get(_content.campaign_id)
	if campaign_corrections is Dictionary and campaign_corrections.has(classic_monster_id):
		return _content.monster_by_classic_id_for_set(int(campaign_corrections[classic_monster_id]), _game_state.monster_set)
	return null


func _alter_selected_characters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 108 requires a five-value Extra Code row.")
	var alteration := action.extra_code[0]
	var amount := action.extra_code[1]
	if alteration < 1 or alteration > 12:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_alteration", "Classic opcode 108 references alteration %d outside 1 through 12." % alteration)
	var targets := _game_state.selected_characters()
	for character: CharacterState in targets:
		match alteration:
			1:
				character.attack_bonus = maxi(0, character.attack_bonus + amount)
			2:
				if character.maximum_spell_attacks != 0:
					character.maximum_spell_attacks = maxi(1, character.maximum_spell_attacks + amount)
			3:
				character.maximum_movement = maxi(3, character.maximum_movement + amount)
				character.movement = mini(character.movement, character.maximum_movement)
			4:
				character.damage_bonus = maxi(0, character.damage_bonus + amount)
			5:
				if character.maximum_spell_points != 0:
					character.maximum_spell_points = maxi(1, character.maximum_spell_points + amount)
					character.spell_points = mini(character.spell_points, character.maximum_spell_points)
			6:
				if character.hand_to_hand != 0:
					character.hand_to_hand = maxi(1, character.hand_to_hand + amount)
			7:
				character.maximum_health = maxi(2, character.maximum_health + amount)
				character.current_health = mini(character.current_health, character.maximum_health)
			8:
				character.armor = maxi(0, character.armor + amount)
			9:
				character.to_hit = maxi(2, character.to_hit + amount)
			10:
				character.missile = maxi(2, character.missile + amount)
			11:
				character.magic_resistance = maxi(0, character.magic_resistance + amount)
			12:
				character.prestige_penalty -= amount
	return ScenarioRuntimeOperationResult.completed(targets.size(), [DomainEvent.new(&"selected_characters_altered", {"alteration": alteration, "amount": amount, "characterIds": targets.map(func(character: CharacterState) -> String: return character.id), "source": "classic"})])


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


func _branch_target_mode(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if mode == 0:
		return _branch_xap(target_id, gosub)
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is not available in this execution context." % mode)


func _branch_to_destination(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	match mode:
		0: return _branch_xap(target_id, gosub)
		1: return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.enter_encounter(&"simple", target_id, gosub))
		2: return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.enter_encounter(&"complex", target_id, gosub))
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is unavailable." % mode)


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_xap(target_id, gosub))


func _with_age_update_interactions(operation: ScenarioRuntimeOperationResult, request_id: String) -> ScenarioRuntimeOperationResult:
	if operation == null or operation.state != ScenarioRuntimeOperationResult.State.COMPLETED:
		return operation
	var updates := CharacterAgingResult.update_bodies(operation.events)
	if updates.is_empty():
		return operation
	var continuation := ScenarioRuntimeContinuation.age_updates(ScenarioRuntimeContinuation.CLASSIC_AGE_UPDATES, updates, 1, operation.value, operation.directive)
	var events: Array[DomainEvent] = []
	events.assign(operation.events)
	events.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update_body(request_id, updates[0]), continuation, events)


func apply_scenario_spell(action: ClassicActionDefinition, entire_party: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode %d requires a four-value Extra Code row." % action.opcode)
	var spell := _content.spell_by_classic_id(int(action.extra_code[0]))
	if spell == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_spell", "Classic opcode %d references unavailable packed spell %d." % [action.opcode, int(action.extra_code[0])])
	var targets := _game_state.party.characters() if entire_party else _game_state.selected_characters()
	if targets.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_selected_characters", "Classic opcode %d has no selected character targets." % action.opcode)
	var events: Array[DomainEvent] = []
	for character: CharacterState in targets:
		var before_health := character.current_health
		var before_conditions := character.conditions.values()
		var caste := _content.caste_by_id(character.caste_id)
		var race := _content.race_by_id(character.race_id)
		var resolution := _rules.magic.resolve_scenario_spell(character, spell, int(action.extra_code[1]), int(action.extra_code[2]), int(action.extra_code[3]) != 0, _rng, caste, race)
		if resolution == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_spell_effect", "Classic scenario spell inputs are invalid.")
		var event_source := "classic-opcode-%d" % action.opcode
		if spell.sound_end + 600 != 0:
			events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(spell.sound_end + 600), "waitForCompletion": false, "source": event_source}))
		var first_effect_resource := 12032 if spell.look_start == 0 else 11992 + spell.look_start * 8
		events.append(DomainEvent.new(&"character_effect_requested", {"characterId": character.id, "resourceType": "cicn", "firstResourceId": first_effect_resource, "frameCount": 8, "source": event_source}))
		events.append(DomainEvent.new(&"scenario_spell_applied", {
			"spellId": spell.id,
			"classicSpellId": spell.classic_id,
			"characterId": character.id,
			"powerLevel": int(action.extra_code[1]),
			"saved": resolution.saved,
			"damage": resolution.damage,
			"duration": resolution.duration,
			"healthBefore": before_health,
			"healthAfter": character.current_health,
			"conditionsChanged": before_conditions != character.conditions.values(),
			"source": "classic",
		}))
		if resolution.aging != null and resolution.aging.changed_group():
			events.append(DomainEvent.new(&"character_age_changed", resolution.aging.event_payload(character, race)))
	return ScenarioRuntimeOperationResult.completed(targets.size(), events)
