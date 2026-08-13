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


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, action_state: ScenarioActionState, rules: RealmzRules = null) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_action_state = action_state
	_rules = rules if rules != null else RealmzRules.new()
	_character_operations = ClassicCharacterOperations.new(_content, _game_state, _rng, _rules)
	_combat_operations = ClassicCombatOperations.new(_content, _game_state, _rules)
	_control_flow_operations = ClassicControlFlowOperations.new(_content, _game_state)
	_inventory_operations = ClassicInventoryOperations.new(_content, _game_state, _rules)


func execute_classic(action: ClassicActionDefinition, request_id: String, context: Dictionary = {}) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		-23, 23:
			return _mutate_random_region(action, action.opcode == -23)
		-14, 14:
			return _request_character_selection(action, request_id, action.opcode == -14)
		1:
			var message_id := absi(action.operand_id)
			var message := _content.message_by_id(message_id)
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 1 references unavailable message %d." % action.operand_id)
			var event := DomainEvent.new(&"message_shown", {"messageId": message_id, "text": message.text, "source": "classic", "classicClick": action.operand_id > 0})
			if action.operand_id > 0:
				var journal_eligible := GameState.journal_message_id_is_valid(message_id)
				var request := InteractionRequest.new(request_id, &"acknowledge", {
					"prompt": message.text,
					"messageId": message_id,
					"presentation": "classic-textbox",
					"journalEligible": journal_eligible,
					"journalRecorded": journal_eligible and _game_state.journal_message_is_recorded(message_id),
				})
				return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-textbox", "messageId": message_id}, [event])
			return ScenarioRuntimeOperationResult.completed(null, [event])
		4:
			var encounter := _content.simple_encounter_by_id(action.operand_id)
			if encounter == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic opcode 4 references unavailable Simple Encounter %d." % action.operand_id)
			var prompt := _content.message_by_id(absi(encounter.prompt_message_id))
			if prompt == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Simple Encounter %d references unavailable prompt message %d." % [encounter.id, encounter.prompt_message_id])
			var options: Array[Dictionary] = []
			var option_indexes: Array[int] = []
			var responses := encounter.responses()
			for option_index: int in responses.size():
				if _game_state.simple_option_is_eliminated(encounter.id, option_index):
					continue
				var response: SimpleEncounterResponse = responses[option_index]
				options.append({"id": response.id, "label": response.label})
				option_indexes.append(option_index)
			if options.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Simple Encounter %d has no remaining responses." % encounter.id)
			var request := InteractionRequest.new(request_id, &"encounter_choice", {"encounterKind": "simple", "encounterId": encounter.id, "prompt": prompt.text, "options": options, "canBackOut": encounter.can_back_out})
			return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-simple-encounter", "encounterId": encounter.id, "gosub": action.gosub, "optionIndexes": option_indexes})
		5:
			return _request_complex_encounter(action, request_id)
		3:
			return _request_classic_choice(action, request_id)
		6:
			return _request_shop(action.operand_id, request_id)
		7:
			return _control_flow_operations.replace_scenario_program(action, context)
		8:
			return _control_flow_operations.branch_to_trigger_program(action, context)
		2, 48, 56, 107:
			return _start_classic_battle(action, request_id)
		9:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"sound_requested", {"soundId": absi(action.operand_id), "waitForCompletion": action.operand_id < 0, "source": "classic"})])
		10:
			return _grant_treasure(action.operand_id, request_id)
		11:
			var no_experience_items: Array[String] = []
			return _begin_reward(&"scenario", "classic.experience.%d" % action.operand_id, maxi(0, action.operand_id), WealthState.new(), no_experience_items, request_id)
		12:
			return _mutate_tile(action)
		13:
			return _mutate_triggers(action)
		15, 16:
			return _apply_health(action, action.opcode == 16)
		17, 18:
			return _with_age_update_interactions(_character_operations.apply_scenario_spell(action, action.opcode == 18), request_id, "classic-age-updates")
		19:
			return _show_random_message(action)
		20:
			return _move_between_maps(action, false, true)
		21:
			return _branch_on_item(action)
		22:
			return _mutate_items(action)
		24:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"action_point_kept", {"triggerId": String(context.get("triggerId", "")), "source": "classic"})], {"kind": "finish"})
		25:
			var trigger_id := String(context.get("triggerId", ""))
			if trigger_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"missing_trigger_context", "Classic opcode 25 requires an Action Point origin.")
			_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"trigger_disabled", {"triggerId": trigger_id, "source": "classic"})])
		26:
			return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"acknowledge", {"prompt": "Continue", "soundId": 30005}), {"kind": "classic-acknowledge"})
		27:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"picture_requested", {"pictureId": absi(action.operand_id), "source": "classic"})])
		28:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"map_redraw_requested", {"source": "classic"})])
		29:
			return _acquire_player_map(action, request_id)
		30:
			return _filter_character_selection(action)
		31:
			return _request_character_ability(action, request_id)
		32:
			return _configure_temple(action)
		33:
			var values := action.extra_code
			var amount := absi(action.operand_id) if values.is_empty() else absi(values[0])
			var kind := WealthState.Kind.GOLD if values.size() < 2 else clampi(values[1], WealthState.Kind.GOLD, WealthState.Kind.JEWELRY) as WealthState.Kind
			var paid := _rules.economy.take(_game_state.party, amount, kind)
			return ScenarioRuntimeOperationResult.completed(paid, [DomainEvent.new(&"wealth_taken", {"amount": amount, "kind": kind, "paid": paid, "source": "classic"})])
		34:
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_loop_finished", {"source": "classic"})], {"kind": "finish"})
		35:
			var encounter_id := int(context.get("encounterId", -1))
			if context.get("encounterKind") != "simple" or not _game_state.eliminate_simple_option(encounter_id, action.operand_id - 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_context", "Classic opcode 35 requires a Simple Encounter response context.")
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_eliminated", {"encounterId": encounter_id, "optionIndex": action.operand_id - 1})])
		36:
			return _inventory_operations.toggle_equipment_storage(action.operand_id != 0)
		37:
			return _move_between_maps(action, true)
		38:
			return _branch_on_item_result(action)
		40:
			return _branch_on_party_condition(action)
		42:
			return _percent_branch(action, context)
		43:
			return _apply_classic_condition(action)
		45:
			return _move_between_maps(action, false, false)
		46:
			return _branch_on_quest(action)
		47:
			var quest_id := absi(action.operand_id)
			if not _game_state.set_quest_value(quest_id, 0 if action.operand_id < 0 else 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 47 references quest %d outside 0 through 99." % quest_id)
			return ScenarioRuntimeOperationResult.completed(_game_state.quest_value(quest_id), [DomainEvent.new(&"quest_changed", {"questId": quest_id, "value": _game_state.quest_value(quest_id)})])
		49:
			return _configure_banking()
		50:
			return _select_characters_by_identity(action)
		51:
			return _mutate_shop(action)
		52:
			return _select_characters_by_misc(action)
		54:
			return _mutate_timed_encounter(action)
		60:
			return _clear_character_money(action)
		61:
			return _shift_party(action)
		62:
			var scrolling_message := _content.message_by_id(absi(action.operand_id))
			if scrolling_message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 62 references unavailable scrolling text %d." % action.operand_id)
			return ScenarioRuntimeOperationResult.completed(scrolling_message.id, [DomainEvent.new(&"scrolling_text_requested", {"messageId": scrolling_message.id, "text": scrolling_message.text, "source": "classic"})])
		63:
			return _alter_game_time(action)
		64:
			return _branch_on_game_time(action)
		65:
			return _grant_random_items(action, request_id)
		66:
			_game_state.camping_allowed = action.operand_id == 0
			return ScenarioRuntimeOperationResult.completed(_game_state.camping_allowed, [DomainEvent.new(&"camping_availability_changed", {"allowed": _game_state.camping_allowed, "source": "classic"})])
		69:
			if action.operand_id == 0:
				return ScenarioRuntimeOperationResult.completed(false)
			if action.extra_code.size() < 3:
				return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 69 requires a five-value Extra Code row.")
			_game_state.character_spellcasting_blocked = action.extra_code[0] != 0
			_game_state.monster_spellcasting_blocked = action.extra_code[1] != 0
			_game_state.spell_charging = action.extra_code[2] != 0
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"spellcasting_flags_changed", {"characterCastingBlocked": _game_state.character_spellcasting_blocked, "monsterCastingBlocked": _game_state.monster_spellcasting_blocked, "charging": _game_state.spell_charging, "source": "classic"})])
		73:
			return _configure_shop(action, request_id)
		76:
			return _adjust_quest_value(action)
		77:
			return _branch_on_quest_value(action)
		82, 83:
			_game_state.priest_turning_allowed = action.opcode == 83
			var turning_message := "You regain your ability to turn undead and nether spawn." if _game_state.priest_turning_allowed else "You may not use your ability to turn undead or nether spawn."
			return ScenarioRuntimeOperationResult.completed(_game_state.priest_turning_allowed, [
				DomainEvent.new(&"priest_turning_availability_changed", {"allowed": _game_state.priest_turning_allowed, "source": "classic"}),
				DomainEvent.new(&"message_shown", {"text": turning_message, "source": "classic"}),
			])
		86:
			return _branch_on_misc(action)
		87:
			return _branch_on_ally(action)
		88:
			var removed := _remove_classic_ally(absi(action.operand_id))
			return ScenarioRuntimeOperationResult.completed(removed, [DomainEvent.new(&"allies_removed", {"classicMonsterId": absi(action.operand_id), "count": removed})])
		89:
			return _add_classic_ally(absi(action.operand_id))
		90:
			return _take_experience(action)
		91:
			var dropped := 0
			for character: CharacterState in _game_state.party.characters():
				dropped += character.inventory().size()
				character.set_inventory([])
				character.carried_load = 0
			return ScenarioRuntimeOperationResult.completed(dropped, [DomainEvent.new(&"party_equipment_dropped", {"count": dropped, "source": "classic"})])
		98, 99:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"classic_control_marker", {"opcode": action.opcode, "operandId": action.operand_id})])
		101:
			return _back_up_party()
		102:
			return _level_selected_characters()
		103:
			return _test_or_set_party_mode(action)
		104:
			_game_state.random_encounters_enabled = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.random_encounters_enabled, [DomainEvent.new(&"random_encounters_changed", {"enabled": _game_state.random_encounters_enabled})])
		105:
			_game_state.allies_suspended = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.allies_suspended, [DomainEvent.new(&"ally_participation_changed", {"suspended": _game_state.allies_suspended, "source": "classic"})])
		106:
			return _set_map_darkness(action)
		108:
			return _alter_selected_characters(action)
		119:
			return _revive_after_combat_macro(context)
		120:
			return _alter_combat_monsters(action)
		121:
			return _deanimate_lower_undead()
		122:
			return _combat_operations.cause_fumble(action, context)
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


func _clear_character_money(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 60 requires a five-value Extra Code row.")
	var classic_kind := action.extra_code[0]
	if classic_kind < 1 or classic_kind > 3:
		return ScenarioRuntimeOperationResult.failed(&"invalid_wealth_kind", "Classic opcode 60 references wealth kind %d outside 1 through 3." % classic_kind)
	var kind := (classic_kind - 1) as WealthState.Kind
	var targets := _game_state.party.characters() if action.extra_code[1] == 0 else _game_state.selected_characters()
	var removed := 0
	for character: CharacterState in targets:
		var amount := character.money.amount(kind)
		removed += amount
		character.carried_load = maxi(0, character.carried_load - amount * (15 if kind == WealthState.Kind.JEWELRY else 1))
		character.money.set_amount(kind, 0)
	return ScenarioRuntimeOperationResult.completed(removed, [DomainEvent.new(&"character_wealth_cleared", {"kind": kind, "amount": removed, "characterIds": targets.map(func(character: CharacterState) -> String: return character.id), "source": "classic"})])


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
		return ScenarioRuntimeOperationResult.completed(false, [], {"kind": "finish"})
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
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"battle_macro_tested", {"matched": false, "mode": mode, "round": combat.round_number, "source": "classic"})], {"kind": "finish"})
	if action.extra_code[2] != 1:
		combat.macro_id = 0
	var target_id := action.extra_code[3]
	if action.extra_code[2] == 2:
		target_id = _rng.draw_between(action.extra_code[3], action.extra_code[4], &"classic.battle-round-macro-target")
	if target_id <= 0:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_target", "Classic opcode 126 references an invalid Extra Action Point target.")
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"battle_macro_tested", {"matched": true, "mode": mode, "round": combat.round_number, "targetId": target_id, "repeating": action.extra_code[2] == 1, "source": "classic"})], {"kind": "branch-xap", "targetId": target_id, "gosub": false})


func _continue_if_monster_present(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"monster_test_outside_combat", "Classic opcode 127 requires an active battle macro.")
	var definition := _content.monster_by_classic_id(absi(action.operand_id))
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 127 references unavailable monster %d." % action.operand_id)
	var present := false
	for monster: MonsterState in _game_state.combat.monsters():
		if monster.definition_id == definition.id and monster.current_health > 0:
			present = true
			break
	var directive: Dictionary = {} if present else {"kind": "finish"}
	return ScenarioRuntimeOperationResult.completed(present, [DomainEvent.new(&"battle_monster_presence_checked", {"classicMonsterId": definition.classic_id, "present": present, "source": "classic"})], directive)


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
					character.maximum_spell_points = maxi(0, character.maximum_spell_points + amount)
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


func _alter_combat_monsters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_monsters_altered", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 120 requires a five-value Extra Code row.")
	var target_kind := action.extra_code[0]
	var definition := _content.monster_by_classic_id(absi(action.extra_code[1]))
	var remaining := maxi(0, action.extra_code[2])
	if target_kind < 1 or target_kind > 2 or definition == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_monster_target", "Classic opcode 120 references an unavailable monster kind or identity.")
	var candidates := _game_state.party.allies() if target_kind == 1 else _game_state.combat.monsters()
	var altered: Array[String] = []
	for monster: MonsterState in candidates:
		if remaining <= 0:
			break
		if monster.definition_id != definition.id:
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
		var definition := _content.monster_by_classic_id(absi(classic_id))
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 123 references unavailable monster %d." % classic_id)
		definition_ids[definition.id] = true
	var routed: Array[String] = []
	for monster: MonsterState in _game_state.combat.monsters():
		if monster.current_health > 0 and monster.traitor == source_traitor and definition_ids.has(monster.definition_id):
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
		return ScenarioRuntimeOperationResult.completed(revived_party, [DomainEvent.new(&"party_revived", {"characterIds": revived_party, "source": "classic-death-macro"})], {"kind": "finish"})
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
			return _with_age_update_interactions(ScenarioRuntimeOperationResult.completed(true, _rules.clock.advance_minutes(_game_state, _content, int(arguments["minutes"]))), request_id, "safe-age-updates")
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
			return _start_battle_definition(battle, request_id, "scenario-action", {"kind": "safe", "policy": "continue"})
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
			var request := InteractionRequest.new(request_id, &"scenario_choice", {"prompt": arguments["prompt"], "options": options})
			return ScenarioRuntimeOperationResult.waiting(request, {"kind": "safe-choice", "optionCount": options.size()})
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


func resume_safe(continuation: Dictionary, response: InteractionResponse, request_id: String = "") -> ScenarioRuntimeOperationResult:
	match continuation.get("kind"):
		"safe-age-updates":
			return _resume_age_update_interactions(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"safe-choice":
			var option_count: int = int(continuation.get("optionCount", 0))
			if response.kind != &"scenario_choice" or not response.payload.get("index") is int or response.payload["index"] < 0 or response.payload["index"] >= option_count:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Scenario choice response must identify an available option.")
			return ScenarioRuntimeOperationResult.completed(response.payload["index"])
		"safe-combat":
			return _resume_battle(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"safe-combat-retreat-confirmation":
			return _resume_battle_retreat(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"safe-combat-age-updates":
			return _resume_combat_age_updates(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"safe-combat-macro":
			return _resume_battle_macro(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"safe-combat-death-macro":
			return _resume_combat_death_macro(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"safe-combat-ally-selection":
			return _resume_ally_selection(continuation, response)
		"safe-combat-fumble-recovery":
			return _resume_fumble_recovery(continuation, response, request_id if not request_id.is_empty() else String(response.request_id))
		"classic-reward":
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
	var continuation := {"kind": "classic-temple", "costPercent": _game_state.temple_cost_percent, "bankAvailable": _game_state.bank_available, "selectedCharacterId": selected_character_id}
	return ScenarioRuntimeOperationResult.waiting(_temple_request(_game_state.temple_cost_percent, request_id, selected_character_id), continuation, [
		DomainEvent.new(&"temple_opened", {"costPercent": _game_state.temple_cost_percent, "bankAvailable": _game_state.bank_available}),
		DomainEvent.new(&"music_requested", {"musicId": 10, "source": "classic-temple"}),
		DomainEvent.new(&"sound_requested", {"soundId": 10105, "waitForCompletion": false, "source": "classic-temple-entry"}),
	])


func request_available_bank(request_id: String) -> ScenarioRuntimeOperationResult:
	if not _game_state.bank_available:
		return ScenarioRuntimeOperationResult.failed(&"bank_unavailable", "No Classic bank is available at this location.")
	return _request_banking(request_id)


func resume_classic(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	match continuation.get("kind"):
		"classic-age-updates":
			return _resume_age_update_interactions(continuation, response, request_id)
		"classic-simple-encounter":
			return _resume_simple_encounter(continuation, response)
		"classic-complex-encounter":
			return _resume_complex_encounter(continuation, response, request_id)
		"classic-acknowledge":
			if response.kind != &"acknowledge":
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Acknowledgement response has the wrong kind.")
			return ScenarioRuntimeOperationResult.completed(true)
		"classic-textbox":
			if response.kind != &"acknowledge":
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic textbox response must acknowledge the displayed message.")
			for key: Variant in response.payload:
				if key != "takeNote":
					return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic textbox acknowledgement contains an unknown field.")
			if response.payload.has("takeNote") and not response.payload["takeNote"] is bool:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic textbox take-note selection must be boolean.")
			if not bool(response.payload.get("takeNote", false)):
				return ScenarioRuntimeOperationResult.completed(true)
			var message_id := int(continuation.get("messageId", -1))
			if not GameState.journal_message_id_is_valid(message_id):
				return ScenarioRuntimeOperationResult.failed(&"journal_message_unrepresentable", "Classic message %d cannot be stored in the 3,000-entry journal flag table." % message_id)
			var already_recorded := _game_state.journal_message_is_recorded(message_id)
			if not _game_state.record_journal_message(message_id):
				return ScenarioRuntimeOperationResult.failed(&"journal_record_failed", "Classic message %d could not be recorded in the journal." % message_id)
			var events: Array[DomainEvent] = []
			if not already_recorded:
				events.append(DomainEvent.new(&"journal_entry_recorded", {"messageId": message_id}))
			return ScenarioRuntimeOperationResult.completed(true, events)
		"classic-player-map":
			if response.kind != &"acknowledge" or not response.payload.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic player-map display requires an empty acknowledgement response.")
			var player_map_id := String(continuation.get("playerMapId", ""))
			if _content.world.player_map_by_id(player_map_id) == null or not _game_state.world.has_map(player_map_id):
				return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic player-map continuation references unavailable acquired content.")
			return ScenarioRuntimeOperationResult.completed(true)
		"classic-combat":
			return _resume_battle(continuation, response, request_id)
		"classic-combat-retreat-confirmation":
			return _resume_battle_retreat(continuation, response, request_id)
		"classic-combat-age-updates":
			return _resume_combat_age_updates(continuation, response, request_id)
		"classic-combat-macro":
			return _resume_battle_macro(continuation, response, request_id)
		"classic-combat-death-macro":
			return _resume_combat_death_macro(continuation, response, request_id)
		"classic-combat-ally-selection":
			return _resume_ally_selection(continuation, response)
		"classic-combat-fumble-recovery":
			return _resume_fumble_recovery(continuation, response, request_id)
		"classic-reward":
			return _resume_reward(continuation, response, request_id)
		"classic-character-selection":
			return _resume_character_selection(continuation, response)
		"classic-character-ability":
			return _resume_character_ability(continuation, response)
		"classic-choice":
			return _resume_classic_choice(continuation, response)
		"classic-shop":
			return _resume_shop(continuation, response, request_id)
		"classic-temple":
			return _resume_temple(continuation, response, request_id)
		"classic-temple-exit":
			return _resume_temple_exit(continuation, response, request_id)
		"classic-banking":
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
	var request := InteractionRequest.new(request_id, &"acknowledge", {"prompt": definition.name, "presentation": "player-map", "playerMapId": definition.id})
	return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-player-map", "playerMapId": definition.id}, events)


func _with_age_update_interactions(operation: ScenarioRuntimeOperationResult, request_id: String, continuation_kind: String) -> ScenarioRuntimeOperationResult:
	if operation == null or operation.state != ScenarioRuntimeOperationResult.State.COMPLETED:
		return operation
	var updates := CharacterAgingResult.update_payloads(operation.events)
	if updates.is_empty():
		return operation
	var continuation := {
		"kind": continuation_kind,
		"updates": updates,
		"index": 1,
		"value": operation.value,
		"directive": operation.directive.duplicate(true),
	}
	var events: Array[DomainEvent] = []
	events.assign(operation.events)
	events.append(CharacterAgingResult.sound_event(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update(request_id, updates[0]), continuation, events)


func _resume_age_update_interactions(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or not response.payload.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var updates: Variant = continuation.get("updates", [])
	var index := int(continuation.get("index", -1))
	if not updates is Array or updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "Classic age-update continuation is invalid.")
	var acknowledged: Dictionary = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.get("characterId", "")})]
	if index < updates.size():
		var next_payload: Dictionary = updates[index]
		var next_continuation := continuation.duplicate(true)
		next_continuation["index"] = index + 1
		events.append(CharacterAgingResult.sound_event(next_payload))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update(request_id, next_payload), next_continuation, events)
	var directive: Variant = continuation.get("directive", {})
	return ScenarioRuntimeOperationResult.completed(continuation.get("value"), events, directive if directive is Dictionary else {})


func _resume_simple_encounter(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var encounter := _content.simple_encounter_by_id(int(continuation.get("encounterId", -1)))
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Simple Encounter is unavailable.")
	if response.kind != &"encounter_choice":
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response has the wrong kind.")
	if response.payload.get("cancelled", false) == true:
		if not encounter.can_back_out:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Simple Encounter cannot be cancelled.")
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "simple", "encounterId": encounter.id})], {"kind": "finish"})
	if not _whole_number(response.payload.get("index")):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response must contain a choice index.")
	var selected_index := int(response.payload["index"])
	var option_indexes: Variant = continuation.get("optionIndexes", [])
	if option_indexes is Array and not option_indexes.is_empty():
		if selected_index < 0 or selected_index >= option_indexes.size() or not _whole_number(option_indexes[selected_index]):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the available choices.")
		selected_index = int(option_indexes[selected_index])
	var selected := encounter.response_at(selected_index)
	if selected == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Simple Encounter response index is outside the authored choices.")
	_game_state.record_encounter_attempt(&"simple", encounter.id)
	return ScenarioRuntimeOperationResult.completed(selected.id, [DomainEvent.new(&"encounter_response_selected", {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index})], {"kind": "branch-program", "programId": selected.result_program_id, "gosub": bool(continuation.get("gosub", false)), "context": {"encounterKind": "simple", "encounterId": encounter.id, "responseId": selected.id, "optionIndex": selected_index}})


func _request_complex_encounter(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var encounter := _content.complex_encounter_by_id(action.operand_id)
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "Classic opcode 5 references unavailable Complex Encounter %d." % action.operand_id)
	var request := _complex_encounter_request(encounter, request_id)
	if request == null:
		return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter %d has no available responses." % encounter.id)
	return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-complex-encounter", "encounterId": encounter.id, "gosub": action.gosub})


func _complex_encounter_request(encounter: ComplexEncounterDefinition, request_id: String) -> InteractionRequest:
	var prompt := _content.message_by_id(absi(encounter.prompt_message_id))
	if prompt == null:
		return null
	var actions: Array[Dictionary] = []
	if encounter.action_result != 0:
		var labels := encounter.action_labels()
		for slot: int in labels.size():
			var label := labels[slot].strip_edges()
			if not label.is_empty() and label != "*":
				actions.append({"id": "choice:%d" % slot, "kind": "choice", "slot": slot, "label": label})
	if encounter.word_result != 0:
		actions.append({"id": "word", "kind": "word", "label": "Speak a word"})
	for spell_id: int in encounter.spell_ids():
		if spell_id != 0:
			actions.append({"id": "spell", "kind": "spell", "label": "Cast a spell"})
			break
	for item_id: int in encounter.item_ids():
		if item_id != 0:
			actions.append({"id": "item", "kind": "item", "label": "Use an item"})
			break
	if encounter.thief:
		var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
		if thief_encounter != null:
			var flags := _game_state.thief_encounter_type_flags(thief_encounter)
			var labels: Array[String] = ["Acrobatics", "Detect Trap", "Disarm Trap", "Hear Noise", "Force Lock", "Move Silently", "Pick Lock", "Pick Pocket"]
			for index: int in labels.size():
				if flags[index]:
					actions.append({"id": "thief:%d" % index, "kind": "thief", "actionIndex": index, "label": labels[index]})
	if encounter.can_back_out:
		actions.append({"id": "back", "kind": "back", "label": "Back out"})
	if actions.is_empty():
		return null
	var characters: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	var spells: Array[Dictionary] = []
	var seen_items: Dictionary = {}
	var seen_spells: Dictionary = {}
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			characters.append({"id": character.id, "name": character.name})
		for instance: ItemInstance in character.inventory():
			var item := _content.item_by_id(instance.definition_id)
			if item != null and not seen_items.has(item.classic_id):
				seen_items[item.classic_id] = true
				items.append({"classicItemId": item.classic_id, "name": item.name})
		for spell_id: String in character.known_spells():
			var spell := _content.spell_by_id(spell_id)
			if spell != null and not seen_spells.has(spell.classic_id):
				seen_spells[spell.classic_id] = true
				spells.append({"classicSpellId": spell.classic_id, "name": spell.name})
	return InteractionRequest.new(request_id, &"complex_encounter", {"encounterKind": "complex", "encounterId": encounter.id, "prompt": prompt.text, "actions": actions, "characters": characters, "items": items, "spells": spells, "canBackOut": encounter.can_back_out})


func _resume_complex_encounter(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var encounter := _content.complex_encounter_by_id(int(continuation.get("encounterId", -1)))
	if encounter == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_encounter", "The pending Complex Encounter is unavailable.")
	if response.kind != &"complex_encounter" or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex Encounter response requires an action.")
	var action: String = response.payload["action"]
	var outcome := 0
	var context: Dictionary = {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": action}
	var events: Array[DomainEvent] = []
	match action:
		"back":
			if not encounter.can_back_out:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "This Complex Encounter cannot be cancelled.")
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"encounter_cancelled", {"encounterKind": "complex", "encounterId": encounter.id})], {"kind": "finish"})
		"choice":
			if not _whole_number(response.payload.get("slot")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action response requires an authored slot.")
			var slot := int(response.payload["slot"])
			var labels := encounter.action_labels()
			if slot < 0 or slot >= labels.size() or labels[slot].strip_edges() in ["", "*"]:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex action slot is unavailable.")
			outcome = encounter.action_result
			context["optionSlot"] = slot
		"word":
			if not response.payload.get("word") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex word response requires text.")
			outcome = _complex_word_outcome(encounter, response.payload["word"])
		"spell":
			if not _whole_number(response.payload.get("classicSpellId")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex spell response requires a Classic spell ID.")
			outcome = _complex_catalog_outcome(encounter.spell_ids(), encounter.spell_results(), int(response.payload["classicSpellId"]))
		"item":
			if not _whole_number(response.payload.get("classicItemId")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Complex item response requires a Classic item ID.")
			var item_id := int(response.payload["classicItemId"])
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
	return _complex_outcome(encounter, outcome, bool(continuation.get("gosub", false)), context, events)


func _complex_outcome(encounter: ComplexEncounterDefinition, outcome: int, gosub: bool, context: Dictionary, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var program_id := encounter.result_program_id(outcome)
	if program_id.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Complex Encounter result is outside 1 through 4.")
	return ScenarioRuntimeOperationResult.completed(outcome, events, {"kind": "branch-program", "programId": program_id, "gosub": gosub, "context": context})


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


func _resume_thief_encounter(encounter: ComplexEncounterDefinition, continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var thief_encounter := _content.thief_encounter_by_id(encounter.thief_success)
	if thief_encounter == null or not _whole_number(response.payload.get("actionIndex")) or not response.payload.get("characterId") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Thief Encounter response requires an available action and character.")
	var character := _game_state.party.character_by_id(response.payload["characterId"])
	var action_index := int(response.payload["actionIndex"])
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
		var request := _complex_encounter_request(encounter, request_id)
		if request == null:
			return ScenarioRuntimeOperationResult.failed(&"encounter_has_no_options", "Complex Encounter has no available responses after the Thief action.")
		return ScenarioRuntimeOperationResult.waiting(request, continuation, events)
	if outcome < 1 or outcome > 4:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_outcome", "Thief Encounter produced invalid result %d." % outcome)
	_game_state.record_encounter_attempt(&"complex", encounter.id)
	return _complex_outcome(encounter, outcome, bool(continuation.get("gosub", false)), {"encounterKind": "complex", "encounterId": encounter.id, "responseKind": "thief", "actionIndex": action_index, "characterId": character.id}, events)


func _spring_thief_trap(encounter: ComplexEncounterDefinition, thief_encounter: ThiefEncounterDefinition, continuation: Dictionary, character: CharacterState, flags: Array[bool], request_id: String) -> ScenarioRuntimeOperationResult:
	flags[9] = false
	flags[1] = false
	flags[6] = true
	_game_state.set_thief_encounter_type_flags(thief_encounter, flags)
	var damage := _rng.draw_between(thief_encounter.low_damage, thief_encounter.high_damage, &"classic.thief-trap-damage") if thief_encounter.high_damage >= thief_encounter.low_damage and thief_encounter.high_damage > 0 else 0
	if damage > 0:
		character.current_health = maxi(-32_768, character.current_health - damage)
	var events: Array[DomainEvent] = [DomainEvent.new(&"thief_trap_sprung", {"encounterId": encounter.id, "thiefEncounterId": thief_encounter.id, "characterId": character.id, "damage": damage, "spellId": thief_encounter.spell_id})]
	var request := _complex_encounter_request(encounter, request_id)
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


func _request_classic_choice(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 3 requires a five-value Extra Code row.")
	var yes_id := action.extra_code[3]
	var no_id := action.extra_code[4]
	var yes_label_value: Variant
	var no_label_value: Variant
	if yes_id == 0:
		yes_label_value = "Yes"
		no_label_value = "No"
	else:
		yes_label_value = _classic_choice_label(yes_id)
		no_label_value = _classic_choice_label(no_id)
	if yes_label_value == null or no_label_value == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_option_label", "Classic opcode 3 references an unavailable option label.")
	var request := InteractionRequest.new(request_id, &"yes_no", {"yesId": yes_id, "yesLabel": yes_label_value, "noId": no_id, "noLabel": no_label_value})
	return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-choice", "values": action.extra_code.duplicate(), "gosub": action.gosub})


func _classic_choice_label(label_id: int) -> Variant:
	if _content.has_option_labels():
		var option_label := _content.option_label_by_id(absi(label_id))
		if option_label == null:
			return null
		return option_label.text
	var message := _content.message_by_id(absi(label_id))
	if message == null:
		return null
	return message.text


func _resume_classic_choice(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"yes_no" or response.payload.get("accepted") is not bool:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic choice response requires an accepted bool.")
	var values: Array = continuation.get("values", [])
	if values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_vm_continuation", "Classic choice continuation is malformed.")
	var apply_result: bool = bool(response.payload["accepted"]) != (int(values[0]) != 0)
	if not apply_result:
		return ScenarioRuntimeOperationResult.completed(false)
	match int(values[1]):
		0:
			return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "finish"})
		1:
			return _branch_xap(int(values[2]), bool(continuation.get("gosub", false)))
		4:
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"encounter_option_elimination_requested")])
	return ScenarioRuntimeOperationResult.failed(&"unsupported_choice_target", "Classic choice branch mode %d is not available." % int(values[1]))


func _request_character_selection(action: ClassicActionDefinition, request_id: String, invert: bool) -> ScenarioRuntimeOperationResult:
	var count := absi(action.operand_id)
	if count < 1:
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_count", "Classic character picker requests no characters.")
	var eligible: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if action.operand_id < 0 or character.current_health > 0:
			eligible.append({"id": character.id, "name": character.name, "currentHealth": character.current_health})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic character picker has no eligible party members.")
	count = mini(count, eligible.size())
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"character_selection", {"count": count, "eligible": eligible, "allowDead": action.operand_id < 0}), {"kind": "classic-character-selection", "count": count, "allowDead": action.operand_id < 0, "invert": invert})


func _resume_character_selection(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"character_selection" or response.payload.get("characterIds") is not Array:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection response requires characterIds.")
	var requested: Array = response.payload["characterIds"]
	if requested.size() != int(continuation.get("count", 0)):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection returned the wrong number of characters.")
	var picked: Array[String] = []
	for value: Variant in requested:
		if not value is String or picked.has(value):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection contains an invalid or duplicate ID.")
		var character := _game_state.party.character_by_id(value)
		if character == null or not bool(continuation.get("allowDead", false)) and character.current_health <= 0:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Character selection includes an ineligible party member.")
		picked.append(value)
	var selected := picked
	if bool(continuation.get("invert", false)):
		selected = []
		for character: CharacterState in _game_state.party.characters():
			if not picked.has(character.id):
				selected.append(character.id)
	if not _game_state.set_selected_character_ids(selected):
		return ScenarioRuntimeOperationResult.failed(&"invalid_character_selection", "Selected character state rejected the response.")
	return ScenarioRuntimeOperationResult.completed(selected, [DomainEvent.new(&"characters_selected", {"characterIds": selected, "inverted": bool(continuation.get("invert", false))})])


func _request_character_ability(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 31 requires a five-value Extra Code row.")
	var eligible: Array[Dictionary] = []
	for character: CharacterState in _game_state.party.characters():
		if character.current_health > 0:
			eligible.append({"id": character.id, "name": character.name})
	if eligible.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"no_eligible_characters", "Classic ability check has no living party member.")
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"character_selection", {"count": 1, "eligible": eligible, "allowDead": false}), {"kind": "classic-character-ability", "values": action.extra_code.duplicate(), "gosub": action.gosub})


func _resume_character_ability(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"character_selection" or response.payload.get("characterIds") is not Array or response.payload["characterIds"].size() != 1 or not response.payload["characterIds"][0] is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check requires one selected character.")
	var character := _game_state.party.character_by_id(response.payload["characterIds"][0])
	var values: Array = continuation.get("values", [])
	if character == null or character.current_health <= 0 or values.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic ability check selected an unavailable character.")
	_game_state.set_selected_character_ids([character.id])
	var check_index := int(values[0])
	var modifier := int(values[1])
	var attribute_check := int(values[2]) != 0
	var check_value := _character_attribute(character, check_index) if attribute_check else character.ability_value(check_index)
	var roll := _rng.draw(25 if attribute_check else 100, &"classic.character-ability")
	var passed := roll - modifier < check_value if attribute_check else roll <= check_value + modifier
	var target_id := int(values[3] if passed else values[4])
	var event := DomainEvent.new(&"character_ability_checked", {"characterId": character.id, "checkIndex": check_index, "attribute": attribute_check, "value": check_value, "modifier": modifier, "roll": roll, "passed": passed})
	var branch := _branch_xap(target_id, bool(continuation.get("gosub", false)))
	branch.events.append(event)
	return branch


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


func _apply_health(action: ClassicActionDefinition, whole_party: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5 or action.extra_code[2] < action.extra_code[1]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_health_effect", "Classic health action requires a valid Extra Code roll range.")
	var targets := _game_state.party.characters() if whole_party else _game_state.selected_characters()
	var hits: Array[Dictionary] = []
	for character: CharacterState in targets:
		var roll := _rng.draw_between(action.extra_code[1], action.extra_code[2], &"classic.health-effect")
		var amount := action.extra_code[0] * roll
		var previous := character.current_health
		character.current_health = mini(character.maximum_health, maxi(-32_768, character.current_health + amount))
		hits.append({"characterId": character.id, "previousHealth": previous, "health": character.current_health, "amount": character.current_health - previous})
	return ScenarioRuntimeOperationResult.completed(hits, [DomainEvent.new(&"party_health_changed", {"targets": "party" if whole_party else "selected", "hits": hits, "soundId": action.extra_code[3], "messageId": action.extra_code[4]})])


func _show_random_message(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	var message_ids: Array[int] = []
	for value: int in action.extra_code:
		if value != 0 and _content.message_by_id(value) != null:
			message_ids.append(value)
	if message_ids.is_empty() and _content.message_by_id(action.operand_id) != null:
		message_ids.append(action.operand_id)
	if message_ids.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 19 has no available message.")
	var selected_id := message_ids[_rng.draw_between(0, message_ids.size() - 1, &"classic.random-message")]
	return ScenarioRuntimeOperationResult.completed(selected_id, [DomainEvent.new(&"message_shown", {"messageId": selected_id, "text": _content.message_by_id(selected_id).text, "source": "classic-random"})])


func _branch_on_item(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 21 requires a five-value Extra Code row.")
	var values := action.extra_code
	var possessed := _party_has_classic_item(absi(values[0]))
	if possessed:
		return _branch_target_mode(values[1], values[3], action.gosub)
	match int(values[2]):
		0:
			return _branch_target_mode(values[1], values[4], action.gosub)
		1:
			return ScenarioRuntimeOperationResult.completed(false)
		2:
			var message := _content.message_by_id(values[4])
			if message == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic item branch references unavailable message %d." % values[4])
			return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-item-check"})], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.failed(&"invalid_item_branch", "Classic item possession branch has an invalid failure mode.")


func _branch_on_item_result(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 38 requires a five-value Extra Code row.")
	var possessed := _party_has_classic_item(absi(action.extra_code[0]))
	var test_mode := action.extra_code[1]
	if test_mode == 2 or test_mode == 0 and not possessed or test_mode == 1 and possessed:
		return _branch_from_values(action.extra_code, false)
	if test_mode not in [0, 1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_item_branch", "Classic item result branch has an invalid test mode.")
	return ScenarioRuntimeOperationResult.completed(false)


func _mutate_items(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 22 requires a five-value Extra Code row.")
	var source := _content.item_by_classic_id(absi(action.extra_code[0]))
	if source == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic item mutation references unavailable item %d." % action.extra_code[0])
	var operation := action.extra_code[2]
	var maximum := action.extra_code[1]
	if maximum < 0 or operation not in [1, 2, 3]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_item_mutation", "Classic item mutation has an invalid count or operation.")
	var replacement := _content.item_by_classic_id(absi(action.extra_code[4])) if operation == 3 else null
	if operation == 3 and replacement == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic item replacement is unavailable.")
	var changed := 0
	for character: CharacterState in _game_state.party.characters():
		var items := character.inventory()
		for index: int in range(items.size() - 1, -1, -1):
			if maximum > 0 and changed >= maximum:
				break
			var instance: ItemInstance = items[index]
			if instance.definition_id != source.id:
				continue
			match operation:
				1:
					_rules.inventory.remove_item(character, instance.id, source)
				2:
					var previous_weight := source.instance_weight(instance.charges)
					instance.charges = clampi(instance.charges + action.extra_code[3], -1, 32_767)
					character.carried_load = maxi(0, character.carried_load - previous_weight + source.instance_weight(instance.charges))
				3:
					var was_equipped := instance.equipped
					_rules.inventory.remove_item(character, instance.id, source)
					var replacement_instance := _rules.inventory.add_item(character, replacement, _game_state.next_instance_id("classic.replacement"), false)
					if replacement_instance == null:
						return ScenarioRuntimeOperationResult.failed(&"inventory_full", "Classic replacement item no longer fits the character inventory.")
					if was_equipped and _rules.inventory.can_equip(character, replacement):
						replacement_instance.equipped = true
			changed += 1
		if maximum > 0 and changed >= maximum:
			break
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"party_items_changed", {"itemId": source.id, "operation": operation, "changed": changed})])


func _party_has_classic_item(classic_item_id: int, minimum_charges: int = -1, equipped_only: bool = false) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in _game_state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.definition_id == definition.id and (minimum_charges < 0 or instance.charges >= minimum_charges) and (not equipped_only or instance.equipped):
				return true
	return false


func _percent_branch(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 42 requires a five-value Extra Code row.")
	var roll := _rng.draw(100, &"classic.percent-branch")
	if roll > action.extra_code[0]:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": false})])
	var event := DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": true})
	match action.extra_code[1]:
		-2:
			var trigger_id := String(context.get("triggerId", ""))
			if not trigger_id.is_empty():
				_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [event], {"kind": "finish"})
		1:
			var branch := _branch_from_values(action.extra_code, false)
			branch.events.append(event)
			return branch
		2:
			return ScenarioRuntimeOperationResult.completed(true, [event], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.completed(true, [event])


func _branch_on_quest(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 46 requires a five-value Extra Code row.")
	var is_set := _game_state.quest_is_set(action.extra_code[0])
	var condition := action.extra_code[1]
	var should_branch := condition == 2 or condition == 1 and is_set or condition == 0 and not is_set
	if not should_branch:
		return ScenarioRuntimeOperationResult.completed(false)
	return _branch_from_values(action.extra_code, action.gosub)


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


func _branch_from_values(values: Array[int], gosub: bool) -> ScenarioRuntimeOperationResult:
	match values[2]:
		0:
			return _branch_xap(values[3], gosub)
		3:
			return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_mode", "Classic branch mode %d is not available in this execution context." % values[2])


func _branch_target_mode(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if mode == 0:
		return _branch_xap(target_id, gosub)
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is not available in this execution context." % mode)


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(false)
	return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "branch-xap", "targetId": target_id, "gosub": gosub})


func _mutate_random_region(action: ClassicActionDefinition, dungeon: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic random-region mutation requires a five-value Extra Code row.")
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic random-region mutation references unavailable map %d." % action.extra_code[0])
	var region := map.random_region_by_index(action.extra_code[1])
	if region == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_random_region", "Classic random-region mutation references unavailable rectangle %d." % action.extra_code[1])
	var previous := _game_state.world.random_region(region)
	var battle_min := previous.battle_minimum if action.extra_code[3] < 0 else action.extra_code[3]
	var battle_max := previous.battle_maximum if action.extra_code[4] < 0 else action.extra_code[4]
	var updated := RandomRegionState.new(region.id, action.extra_code[2], battle_min, battle_max, previous.random_door_percents())
	_game_state.world.set_random_region(updated)
	return ScenarioRuntimeOperationResult.completed(updated.id, [DomainEvent.new(&"random_region_changed", {"regionId": updated.id, "chanceTenThousand": updated.chance_ten_thousand, "battleMinimum": updated.battle_minimum, "battleMaximum": updated.battle_maximum})])


func _mutate_tile(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 12 requires a five-value Extra Code row.")
	var dungeon := action.extra_code[4] != 0
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[1]) if dungeon else Vector2i(action.extra_code[1], action.extra_code[2])
	if map == null or map.topology.cell_at(coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map_cell", "Classic tile mutation references an unavailable map cell.")
	var terrain_id := "classic.terrain.%d" % action.extra_code[3]
	_game_state.world.replace_terrain(map.id, coordinate, terrain_id)
	return ScenarioRuntimeOperationResult.completed(terrain_id, [DomainEvent.new(&"tile_replaced", {"mapId": map.id, "x": coordinate.x, "y": coordinate.y, "terrainId": terrain_id, "source": "classic"})])


func _mutate_triggers(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 13 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	var level_type := current_map.level_type
	if action.extra_code[3] < 0:
		level_type = &"dungeon"
	elif action.extra_code[3] > 0:
		level_type = &"land"
	var map := _content.world.map_by_type_and_index(level_type, action.extra_code[0])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic trigger mutation references unavailable map %d." % action.extra_code[0])
	var record_indexes: Array[int] = []
	if action.extra_code[1] != 0:
		record_indexes.append(action.extra_code[1])
	if action.extra_code[3] != 0:
		for record_index: int in range(absi(action.extra_code[3]), absi(action.extra_code[4]) + 1):
			if not record_indexes.has(record_index):
				record_indexes.append(record_index)
	var changed: Array[String] = []
	for record_index: int in record_indexes:
		var trigger := _content.trigger_by_map_record(map.id, record_index)
		if trigger == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_trigger", "Classic trigger mutation references unavailable record %d on map '%s'." % [record_index, map.id])
		_game_state.world.set_trigger_chance(trigger.id, action.extra_code[2])
		changed.append(trigger.id)
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"trigger_chances_changed", {"triggerIds": changed, "chancePercent": action.extra_code[2]})])


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
		return ScenarioRuntimeOperationResult.completed(target_map.id, events, {"kind": "finish"})
	return ScenarioRuntimeOperationResult.completed(target_map.id, events)


func _shift_party(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 61 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 61 requires the party's current map.")
	var delta := Vector2i(action.extra_code[1], action.extra_code[2])
	var random_shift := action.extra_code[3] != 0
	if random_shift:
		if action.extra_code[1] < 1 or action.extra_code[2] < 1:
			return ScenarioRuntimeOperationResult.failed(&"invalid_shift_range", "Classic opcode 61 random shift ranges must be positive.")
		var x_sign := 1 if _rng.draw(100, &"classic.opcode61.x-sign") < 50 else -1
		var x_magnitude := _rng.draw_between(1, action.extra_code[1], &"classic.opcode61.x-magnitude")
		var y_sign := 1 if _rng.draw(100, &"classic.opcode61.y-sign") < 50 else -1
		var y_magnitude := _rng.draw_between(1, action.extra_code[2], &"classic.opcode61.y-magnitude")
		delta = Vector2i(x_sign * x_magnitude, y_sign * y_magnitude)
	var source_coordinate := _game_state.party.coordinate
	var target_coordinate := source_coordinate + delta
	if current_map.topology.cell_at(target_coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"shift_out_of_bounds", "Classic opcode 61 shifts the party outside the current map.")
	_game_state.party.coordinate = target_coordinate
	_game_state.world.mark_visited(current_map.id, target_coordinate)
	return ScenarioRuntimeOperationResult.completed(target_coordinate, [DomainEvent.new(&"party_shifted", {
		"mapId": current_map.id,
		"sourceX": source_coordinate.x,
		"sourceY": source_coordinate.y,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"deltaX": delta.x,
		"deltaY": delta.y,
		"random": random_shift,
		"source": "classic",
	})])


func _alter_game_time(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 63 requires a five-value Extra Code row.")
	var mode := action.extra_code[0]
	var target_minutes := _game_state.clock.total_minutes()
	match mode:
		1:
			var day := _game_state.clock.day() if action.extra_code[1] == -1 else action.extra_code[1]
			var hour := _game_state.clock.hour() if action.extra_code[2] == -1 else action.extra_code[2]
			var minute := _game_state.clock.minute() if action.extra_code[3] == -1 else action.extra_code[3]
			if day < 1 or hour < 0 or hour > 23 or minute < 0 or minute > 59:
				return ScenarioRuntimeOperationResult.failed(&"invalid_game_time", "Classic opcode 63 absolute time is outside the Realmz clock.")
			target_minutes = (day - 1) * RealmzClock.MINUTES_PER_DAY + hour * 60 + minute
		2:
			target_minutes += action.extra_code[1] * RealmzClock.MINUTES_PER_DAY + action.extra_code[2] * 60 + action.extra_code[3]
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_game_time_mode", "Classic opcode 63 requires set or offset mode.")
	if not _game_state.clock.set_total_minutes(target_minutes):
		return ScenarioRuntimeOperationResult.failed(&"invalid_game_time", "Classic opcode 63 cannot move before the start of the Realmz clock.")
	return ScenarioRuntimeOperationResult.completed(target_minutes, [DomainEvent.new(&"game_time_changed", {
		"mode": mode,
		"day": _game_state.clock.day(),
		"hour": _game_state.clock.hour(),
		"minute": _game_state.clock.minute(),
		"totalMinutes": target_minutes,
		"source": "classic",
	})])


func _branch_on_game_time(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 64 requires a five-value Extra Code row.")
	var day_limit := action.extra_code[0]
	var hour_limit := action.extra_code[1]
	if day_limit < -1 or hour_limit < -1 or hour_limit > 23:
		return ScenarioRuntimeOperationResult.failed(&"invalid_game_time_test", "Classic opcode 64 has an invalid day or hour limit.")
	var before_or_equal := (day_limit == -1 or _game_state.clock.day() <= day_limit) and (hour_limit == -1 or _game_state.clock.hour() <= hour_limit)
	var target_id := action.extra_code[3] if before_or_equal else action.extra_code[4]
	var branch := _branch_xap(target_id, action.gosub)
	branch.events.append(DomainEvent.new(&"game_time_branch_checked", {
		"day": _game_state.clock.day(),
		"hour": _game_state.clock.hour(),
		"dayLimit": day_limit,
		"hourLimit": hour_limit,
		"beforeOrEqual": before_or_equal,
		"targetId": target_id,
	}))
	return branch


func _adjust_quest_value(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 76 requires a five-value Extra Code row.")
	var quest_id := action.extra_code[0]
	if quest_id < 0 or quest_id >= 100:
		return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 76 references quest %d outside 0 through 99." % quest_id)
	var value := clampi(_game_state.quest_value(quest_id) + action.extra_code[1], -127, 127)
	_game_state.set_quest_value(quest_id, value)
	var event := DomainEvent.new(&"quest_value_changed", {"questId": quest_id, "value": value, "delta": action.extra_code[1], "source": "classic"})
	if action.extra_code[3] == 0 or value < action.extra_code[3]:
		return ScenarioRuntimeOperationResult.completed(value, [event])
	if action.extra_code[2] != 1:
		return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic opcode 76 auto-branch target type %d is unavailable." % action.extra_code[2])
	var branch := _branch_xap(action.extra_code[4], action.gosub)
	branch.events.append(event)
	return branch


func _branch_on_quest_value(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 77 requires a five-value Extra Code row.")
	var quest_id := action.extra_code[0]
	if quest_id < 0 or quest_id >= 100:
		return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 77 references quest %d outside 0 through 99." % quest_id)
	var matched := _game_state.quest_value(quest_id) >= action.extra_code[1]
	var target_id := action.extra_code[4] if matched else action.extra_code[3]
	var event := DomainEvent.new(&"quest_value_branch_checked", {"questId": quest_id, "value": _game_state.quest_value(quest_id), "minimum": action.extra_code[1], "matched": matched, "targetId": target_id})
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(matched, [event])
	var branch := _branch_target_mode(action.extra_code[2], target_id, action.gosub)
	branch.events.append(event)
	return branch


func _branch_on_ally(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 87 requires a five-value Extra Code row.")
	var monster := _content.monster_by_classic_id(absi(action.extra_code[0]))
	var present := false
	if monster != null:
		for ally: MonsterState in _game_state.party.allies():
			if ally.definition_id == monster.id:
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
			return ScenarioRuntimeOperationResult.completed(false, [event, DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-ally-check"})], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.failed(&"invalid_ally_branch", "Classic opcode 87 has an invalid absent-ally behavior.")


func _branch_on_misc(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 86 requires a five-value Extra Code row.")
	var test_kind := action.extra_code[0]
	var expected := action.extra_code[1]
	var selected_only := expected < 0 and test_kind in [0, 1, 2, 5, 6]
	var characters := _game_state.selected_characters() if selected_only else _game_state.party.characters()
	var matched := false
	match test_kind:
		0:
			for character: CharacterState in characters:
				var caste := _content.caste_by_id(character.caste_id)
				if caste != null and caste.classic_id == absi(expected):
					matched = true
					break
		1:
			for character: CharacterState in characters:
				var race := _content.race_by_id(character.race_id)
				if race != null and race.classic_id == absi(expected):
					matched = true
					break
		2:
			for character: CharacterState in characters:
				if character.gender == absi(expected):
					matched = true
					break
		3:
			matched = _game_state.party_in_boat
		4:
			matched = _game_state.party_camping
		5:
			for character: CharacterState in characters:
				var caste := _content.caste_by_id(character.caste_id)
				if caste != null and caste.caste_class == absi(expected):
					matched = true
					break
		6:
			if absi(expected) < 1 or absi(expected) > 32:
				return ScenarioRuntimeOperationResult.failed(&"invalid_race_descriptor", "Classic opcode 86 race descriptor is outside 1 through 32.")
			var descriptor_mask := 1 << (absi(expected) - 1)
			for character: CharacterState in characters:
				var race := _content.race_by_id(character.race_id)
				if race != null and (race.descriptor_flags & descriptor_mask) != 0:
					matched = true
					break
		7:
			var total_level := 0
			for character: CharacterState in _game_state.party.characters():
				total_level += character.level
			matched = total_level > expected
		8:
			var selected_level := 0
			for character: CharacterState in _game_state.selected_characters():
				selected_level += character.level
			matched = selected_level > expected
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_misc_branch", "Classic opcode 86 test kind is unavailable.")
	var target_id := action.extra_code[3] if matched else action.extra_code[4]
	var event := DomainEvent.new(&"misc_branch_checked", {"testKind": test_kind, "expected": expected, "matched": matched, "targetId": target_id})
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(matched, [event])
	var branch := _branch_target_mode(action.extra_code[2], target_id, action.gosub)
	branch.events.append(event)
	return branch


func _back_up_party() -> ScenarioRuntimeOperationResult:
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 101 requires the party's current map.")
	if current_map.level_type == &"dungeon":
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"party_backup_ignored", {"reason": "dungeon", "source": "classic"})])
	if _game_state.last_move_direction == Vector2i.ZERO:
		return ScenarioRuntimeOperationResult.failed(&"missing_move_direction", "Classic opcode 101 requires a prior party movement direction.")
	var source_coordinate := _game_state.party.coordinate
	var target_coordinate := source_coordinate - _game_state.last_move_direction
	if current_map.topology.cell_at(target_coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"backup_out_of_bounds", "Classic opcode 101 backs the party outside the current map.")
	_game_state.party.coordinate = target_coordinate
	_game_state.world.mark_visited(current_map.id, target_coordinate)
	return ScenarioRuntimeOperationResult.completed(target_coordinate, [DomainEvent.new(&"party_backed_up", {
		"mapId": current_map.id,
		"sourceX": source_coordinate.x,
		"sourceY": source_coordinate.y,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"directionX": _game_state.last_move_direction.x,
		"directionY": _game_state.last_move_direction.y,
		"source": "classic",
	})])


func _set_map_darkness(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 106 requires a five-value Extra Code row.")
	if action.extra_code[0] not in [1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_darkness", "Classic opcode 106 darkness value must be 1 or 2.")
	var map := _content.world.map_by_id(_game_state.party.map_id)
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 106 requires the party's current map.")
	var dark := action.extra_code[0] == 2
	var unchanged := _game_state.world.map_is_dark(map) == dark
	if unchanged and action.extra_code[1] != 0:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"map_darkness_unchanged", {"mapId": map.id, "dark": dark})], {"kind": "finish"})
	_game_state.world.set_map_darkness(map.id, dark)
	return ScenarioRuntimeOperationResult.completed(dark, [DomainEvent.new(&"map_darkness_changed", {"mapId": map.id, "dark": dark, "source": "classic"})])


func _test_or_set_party_mode(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 103 requires a five-value Extra Code row.")
	if action.extra_code[0] not in [0, 1, 2] or action.extra_code[1] not in [0, 1, 2] or action.extra_code[2] not in [0, 1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_mode", "Classic opcode 103 has an invalid boat or camping mode.")
	var should_finish := action.extra_code[0] == 1 and not _game_state.party_in_boat or action.extra_code[0] == 2 and _game_state.party_in_boat
	should_finish = should_finish or action.extra_code[1] == 1 and not _game_state.party_camping or action.extra_code[1] == 2 and _game_state.party_camping
	if action.extra_code[2] == 1:
		_game_state.party_in_boat = true
	elif action.extra_code[2] == 2:
		_game_state.party_in_boat = false
	var event := DomainEvent.new(&"party_mode_checked", {"inBoat": _game_state.party_in_boat, "camping": _game_state.party_camping, "finished": should_finish, "source": "classic"})
	return ScenarioRuntimeOperationResult.completed(not should_finish, [event], {"kind": "finish"} if should_finish else {})


func _mutate_timed_encounter(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 54 requires a five-value Extra Code row.")
	var encounter_id := action.extra_code[0]
	var current := _game_state.timed_encounter_override(encounter_id)
	if action.extra_code[1] > -1:
		current["percent"] = action.extra_code[1]
	if action.extra_code[2] > -1:
		current["increment"] = action.extra_code[2]
	if action.extra_code[3] != 0:
		current["day"] = _game_state.clock.day()
	if action.extra_code[4] > -1:
		current["day"] = int(current.get("day", 0)) + action.extra_code[4]
	_game_state.set_timed_encounter_override(encounter_id, current)
	return ScenarioRuntimeOperationResult.completed(current, [DomainEvent.new(&"timed_encounter_changed", {"encounterId": encounter_id, "state": current})])


func _request_shop(classic_shop_id: int, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	var shop := _content.shop_by_classic_id(absi(classic_shop_id))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic opcode 6 references unavailable shop %d." % classic_shop_id)
	return _request_shop_definition(shop, request_id, accept_ranges)


func _request_shop_definition(shop: ShopDefinition, request_id: String, accept_ranges: Array[int] = []) -> ScenarioRuntimeOperationResult:
	if _game_state.bank_available:
		_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_shop_request(shop, request_id, accept_ranges), {"kind": "classic-shop", "shopId": shop.id, "acceptRanges": accept_ranges.duplicate()}, [DomainEvent.new(&"shop_opened", {"shopId": shop.id, "acceptRanges": accept_ranges.duplicate(), "bankAvailable": _game_state.bank_available})])


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
	return InteractionRequest.new(request_id, &"shop_action", {"shopId": shop.id, "inflationPercent": _game_state.shop_inflation(shop), "partyGold": party_gold, "identifyPrice": 20, "stock": stock, "characters": characters, "acceptRanges": accept_ranges.duplicate(), "actions": ["buy", "sell", "identify", "leave"]})


func _shop_stock_view(item: ItemDefinition, stock_key: String, stock_index: int, quantity: int, shop: ShopDefinition) -> Dictionary:
	var price := _rules.economy.shop_buy_price(item, _game_state.shop_inflation(shop))
	return {"stockKey": stock_key, "index": stock_index, "itemId": item.id, "name": item.name, "quantity": quantity, "buyPrice": price, "canBuy": quantity > 0 and _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) >= price, "buyReason": "Out of stock." if quantity < 1 else "The party cannot afford this item." if _rules.economy.available(_game_state.party, WealthState.Kind.GOLD) < price else ""}


func _resume_shop(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != &"shop_action" or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop response requires an action string.")
	var shop := _content.shop_by_id(String(continuation.get("shopId", "")))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "The pending shop is unavailable.")
	var operation: String = response.payload["action"]
	if operation == "leave":
		if _game_state.bank_available:
			_rules.economy.pool_to_bank(_game_state.party)
		return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_closed", {"shopId": shop.id, "pooledWealthReturnedToBank": _game_state.bank_available})])
	var events: Array[DomainEvent] = []
	match operation:
		"buy":
			if not response.payload.get("characterId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop buy requires stock identity and characterId.")
			var stock_entry := _resolve_shop_stock(shop, response.payload)
			if stock_entry.is_empty() or int(stock_entry.get("quantity", 0)) < 1:
				return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "The selected shop item is out of stock.")
			var character := _game_state.party.character_by_id(response.payload["characterId"])
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
			if not response.payload.get("characterId") is String or not response.payload.get("instanceId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop sell requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(response.payload["characterId"])
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The shop sale character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == response.payload["instanceId"]:
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
			for value: Variant in continuation.get("acceptRanges", []):
				accept_ranges.append(int(value))
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
			if not response.payload.get("characterId") is String or not response.payload.get("instanceId") is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Shop identification requires characterId and instanceId.")
			var character := _game_state.party.character_by_id(response.payload["characterId"])
			if character == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The identification character is unavailable.")
			var instance: ItemInstance = null
			for candidate: ItemInstance in character.inventory():
				if candidate.id == response.payload["instanceId"]:
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
	for value: Variant in continuation.get("acceptRanges", []):
		ranges.append(int(value))
	return ScenarioRuntimeOperationResult.waiting(_shop_request(shop, request_id, ranges), continuation, events)


func _resolve_shop_stock(shop: ShopDefinition, payload: Dictionary) -> Dictionary:
	var stock_key := String(payload.get("stockKey", ""))
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
	if _whole_number(payload.get("stockIndex")):
		var index := int(payload["stockIndex"])
		var item_ids := shop.item_ids()
		if index >= 0 and index < item_ids.size():
			return {"kind": "base", "index": index, "item": _content.item_by_id(item_ids[index]), "quantity": _game_state.shop_quantity(shop, index)}
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


func _mutate_shop(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 51 requires a five-value Extra Code row.")
	var shop := _content.shop_by_classic_id(absi(action.extra_code[0]))
	if shop == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_shop", "Classic shop mutation references unavailable shop %d." % action.extra_code[0])
	var inflation := maxi(0, _game_state.shop_inflation(shop) + action.extra_code[1])
	_game_state.set_shop_inflation(shop, inflation)
	var stock_index := -1
	if action.extra_code[2] != 0:
		var item := _content.item_by_classic_id(absi(action.extra_code[2]))
		if item == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic shop mutation references unavailable item %d." % action.extra_code[2])
		stock_index = shop.item_ids().find(item.id)
		if stock_index < 0:
			return ScenarioRuntimeOperationResult.failed(&"shop_item_unavailable", "Classic shop mutation item is not stocked by the shop.")
		_game_state.set_shop_quantity(shop, stock_index, _game_state.shop_quantity(shop, stock_index) + action.extra_code[3])
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"shop_changed", {"shopId": shop.id, "inflationPercent": inflation, "stockIndex": stock_index, "quantity": _game_state.shop_quantity(shop, stock_index) if stock_index >= 0 else 0})])


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
	return InteractionRequest.new(request_id, InteractionRequest.TEMPLE, {
		"costPercent": cost_percent,
		"characters": characters,
		"services": _rules.temple.service_rows(cost_percent),
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankAvailable": _game_state.bank_available,
		"selectedCharacterId": selected_character_id,
		"actions": ["service", "pool", "share", "leave"],
	})


func _resume_temple(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.TEMPLE or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple response requires an action.")
	var operation: String = response.payload["action"]
	var cost_percent := int(continuation.get("costPercent", 100))
	var next_continuation := continuation.duplicate(true)
	if response.payload.has("selectedCharacterId"):
		if not response.payload["selectedCharacterId"] is String or _game_state.party.character_by_id(String(response.payload["selectedCharacterId"])) == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_character", "The selected temple character is unavailable.")
		next_continuation["selectedCharacterId"] = response.payload["selectedCharacterId"]
	match operation:
		"leave":
			if bool(continuation.get("bankAvailable", false)):
				_rules.economy.pool_to_bank(_game_state.party)
				return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"temple_closed", {"pooledWealthReturnedToBank": true})])
			if _has_pooled_wealth():
				var prompt := "Pooled wealth remains. Return to the temple to distribute it before leaving?"
				var request := InteractionRequest.yes_no(request_id, prompt, "Return", "Leave it behind")
				return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-temple-exit", "costPercent": cost_percent, "bankAvailable": false, "selectedCharacterId": String(next_continuation.get("selectedCharacterId", ""))})
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
			return ScenarioRuntimeOperationResult.waiting(_temple_request(cost_percent, request_id, String(next_continuation.get("selectedCharacterId", ""))), next_continuation, [
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
			return ScenarioRuntimeOperationResult.waiting(_temple_request(cost_percent, request_id, String(next_continuation.get("selectedCharacterId", ""))), next_continuation, [
				DomainEvent.new(&"wealth_shared", {"source": "classic-temple", "remaining": _game_state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-temple-share"}),
			])
		"service":
			return _apply_temple_service(next_continuation, response, request_id)
	return ScenarioRuntimeOperationResult.failed(&"unknown_temple_action", "Temple action '%s' is unavailable." % operation)


func _apply_temple_service(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if not response.payload.get("characterId") is String or not response.payload.get("serviceId") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple service requires characterId and serviceId.")
	var character := _game_state.party.character_by_id(response.payload["characterId"])
	var service_id := StringName(response.payload["serviceId"])
	if character == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_character", "Temple service target is unavailable.")
	if not TempleRules.SERVICE_IDS.has(service_id):
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	var cost := _rules.temple.service_cost(service_id, int(continuation.get("costPercent", 100)))
	var next_continuation := continuation.duplicate(true)
	next_continuation["selectedCharacterId"] = character.id
	var events: Array[DomainEvent] = [DomainEvent.new(&"sound_requested", {"soundId": 10129, "waitForCompletion": false, "source": "classic-temple-service"})]
	if cost > _game_state.party.pooled_wealth.gold + character.money.gold:
		events.append(DomainEvent.new(&"temple_service_rejected", {"serviceId": String(service_id), "characterId": character.id, "cost": cost, "reason": "insufficient_gold"}))
		return ScenarioRuntimeOperationResult.waiting(_temple_request(int(continuation.get("costPercent", 100)), request_id, character.id), next_continuation, events)
	if not _rules.economy.take_from_pool_and_character(_game_state.party, character, cost, WealthState.Kind.GOLD):
		return ScenarioRuntimeOperationResult.failed(&"temple_payment_failed", "Temple payment could not be committed after affordability validation.")
	var result := _rules.temple.apply_service(character, service_id, _rng, _content.item_definitions())
	if result == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_temple_service", "Temple service '%s' is unavailable." % service_id)
	events.append(DomainEvent.new(&"temple_service_completed", result.to_event_data(character.id, cost)))
	return ScenarioRuntimeOperationResult.waiting(_temple_request(int(continuation.get("costPercent", 100)), request_id, character.id), next_continuation, events)


func _resume_temple_exit(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.YES_NO or response.payload.get("accepted") is not bool:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Temple exit requires a yes/no response.")
	if response.payload["accepted"]:
		return ScenarioRuntimeOperationResult.waiting(
			_temple_request(int(continuation.get("costPercent", 100)), request_id, String(continuation.get("selectedCharacterId", ""))),
			{"kind": "classic-temple", "costPercent": int(continuation.get("costPercent", 100)), "bankAvailable": false, "selectedCharacterId": String(continuation.get("selectedCharacterId", ""))},
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


func _configure_banking() -> ScenarioRuntimeOperationResult:
	_game_state.bank_available = true
	return ScenarioRuntimeOperationResult.completed(true, [
		DomainEvent.new(&"bank_available"),
		DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-bank-offer"}),
	])


func _request_banking(request_id: String) -> ScenarioRuntimeOperationResult:
	_rules.economy.bank_to_pool(_game_state.party)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id), {"kind": "classic-banking"}, [
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
	return InteractionRequest.new(request_id, InteractionRequest.BANK, {
		"selectedCharacterId": selected_character_id,
		"pooledWealth": _game_state.party.pooled_wealth.to_data(),
		"bankedWealth": _game_state.party.banked_wealth.to_data(),
		"pool": _economy_probe_data(_rules.economy.pool_probe(_game_state.party)),
		"share": _economy_probe_data(_rules.economy.share_probe(_game_state.party)),
		"characters": characters,
		"actions": ["pool", "share", "to-pool", "to-character", "leave"],
	})


func _resume_banking(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.BANK or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank response requires an action.")
	var action: String = response.payload["action"]
	if action == "leave":
		return ScenarioRuntimeOperationResult.completed(true, [
			DomainEvent.new(&"bank_closed", {"pooledWealthReturnedToBank": false}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-bank-swap-done"}),
		])
	var selected_character_id := String(response.payload.get("characterId", response.payload.get("selectedCharacterId", "")))
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
			if not response.payload.get("characterId") is String or not response.payload.get("denomination") is String or not _whole_number(response.payload.get("amount")):
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Bank-backed Swap requires character, denomination, and amount.")
			var movement_error := _money_movement_context_error()
			if not movement_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"invalid_money_context", movement_error)
			var character := _game_state.party.character_by_id(response.payload["characterId"])
			var kind := _wealth_kind(response.payload["denomination"])
			var amount := int(response.payload["amount"])
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
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-bank", "characterId": character.id, "direction": action, "kind": response.payload["denomination"], "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-bank-swap"}))
		_:
			return ScenarioRuntimeOperationResult.failed(&"unknown_bank_action", "Bank action '%s' is unavailable." % action)
	return ScenarioRuntimeOperationResult.waiting(_bank_request(request_id, selected_character_id), continuation, events)


static func _economy_probe_data(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}


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
	var caller := {"kind": "classic", "opcode": action.opcode, "gosub": action.gosub, "mode": action.extra_code[4] if action.opcode == 2 and action.extra_code.size() > 4 else 0, "branchTarget": action.extra_code[4] if action.opcode == 107 and action.extra_code.size() > 4 else action.extra_code[2] if action.opcode == 56 and action.extra_code.size() > 2 else 0}
	var battle := _content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_battle", "Classic opcode %d references unavailable battle %d." % [action.opcode, battle_id])
	var operation := _start_battle_definition(battle, request_id, "classic", caller)
	if operation.state != ScenarioRuntimeOperationResult.State.FAILED:
		operation.events = prelude + operation.events
	return operation


static func _battle_caller(continuation: Dictionary) -> Dictionary:
	var caller: Variant = continuation.get("battleCaller", {})
	return caller.duplicate(true) if _battle_caller_is_valid(caller) else {}


static func _battle_caller_is_valid(caller: Variant) -> bool:
	if not caller is Dictionary:
		return false
	match String(caller.get("kind", "")):
		"safe":
			return caller.size() == 2 and caller.get("policy") == "continue"
		"classic":
			return caller.size() == 5 and _whole_number(caller.get("opcode")) and int(caller["opcode"]) in [2, 48, 56, 107] and caller.get("gosub") is bool and _whole_number(caller.get("mode")) and _whole_number(caller.get("branchTarget"))
	return false


static func party_defeat_handoff_is_valid(content: RealmzContent, state: GameState, handoff: Variant) -> bool:
	if content == null or state == null or state.combat == null or not handoff is Dictionary or handoff.size() != 4:
		return false
	if handoff.get("kind") != "party-defeat" or handoff.get("battleId") != state.combat.battle_id or handoff.get("sourceKind") not in ["classic-combat", "safe-combat"]:
		return false
	if not state.combat.completed or state.combat.outcome != &"defeat" or not _battle_caller_is_valid(handoff.get("caller")):
		return false
	var caller: Dictionary = handoff["caller"]
	if handoff["sourceKind"] == "safe-combat":
		return caller.get("kind") == "safe"
	if caller.get("kind") != "classic":
		return false
	var opcode: int = caller["opcode"]
	var target: int = caller["branchTarget"]
	if opcode == 107 or opcode == 56 and target >= 0:
		return content.scenario.program_by_id("xap:%d" % target) != null
	return true


func complete_party_defeat_handoff(handoff: Dictionary) -> ScenarioRuntimeOperationResult:
	if not party_defeat_handoff_is_valid(_content, _game_state, handoff):
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_defeat_handoff", "The suspended total-party defeat no longer matches its battle caller.")
	var caller: Dictionary = handoff["caller"]
	if caller.get("kind") == "classic" and caller.get("opcode") == 2 and caller.get("mode") == 10:
		return ScenarioRuntimeOperationResult.failed(&"classic_mode_10_defeat_unresolved", "Classic battle mode 10 revives and restarts its caller without running Party Death; that source-specific restart is not yet available.")
	if caller.get("kind") == "classic" and caller.get("opcode") == 56 and caller.get("branchTarget") == -1:
		return ScenarioRuntimeOperationResult.failed(&"classic_battle_loss_return_unresolved", "Classic opcode 56 uses a distinct experience-loss and party-backup return that is not yet available.")
	var combat := _game_state.combat
	var battle_id := combat.battle_id
	var directive: Dictionary = {}
	if caller.get("kind") == "classic":
		match int(caller["opcode"]):
			56:
				directive = {"kind": "branch-xap", "targetId": int(caller["branchTarget"]), "gosub": bool(caller["gosub"])}
			107:
				directive = {"kind": "branch-xap", "targetId": int(caller["branchTarget"]), "gosub": false}
	combat.outcome = &"retreated"
	_game_state.last_battle_outcome = &"retreated"
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"party_defeat_revived", {"battleId": battle_id, "source": "classic-party-death-hook", "callerOpcode": int(caller.get("opcode", 0))}),
		DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "retreated"}),
	]
	_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(battle_id, events, directive)


func _start_battle_definition(battle: BattleDefinition, request_id: String, source: String, caller: Dictionary) -> ScenarioRuntimeOperationResult:
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
	var continuation_kind := "safe-combat" if source == "scenario-action" else "classic-combat"
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(continuation_kind, caller, request_id, events, _game_state.combat.round_number)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(continuation_kind, caller, events, request_id)
	if result.completed:
		return _finish_battle_with_allies(continuation_kind, caller, request_id, events)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": continuation_kind, "battleId": battle.id, "battleCaller": caller.duplicate(true)}, events)


func _resume_battle(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != &"combat_action" or not response.payload.get("actorId") is String or not response.payload.get("action") is String or response.payload.get("targetId", "") is not String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat response requires actorId, action, and optional targetId strings.")
	if _game_state.combat == null or _game_state.combat.battle_id != continuation.get("battleId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle is unavailable.")
	var previous_round := _game_state.combat.round_number
	var caller := _battle_caller(continuation)
	if caller.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle lost its originating caller.")
	var result: CombatFlowResult
	if response.payload["action"] == "set_auto":
		if response.payload.get("enabled") is not bool or _game_state.party.character_by_id(response.payload["actorId"]) == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Persistent Auto requires a party character and an enabled boolean.")
		var auto_state_checkpoint := _game_state.to_data()
		var auto_rng_checkpoint := _rng.checkpoint()
		if not _game_state.set_combat_auto(response.payload["actorId"], response.payload["enabled"]):
			return ScenarioRuntimeOperationResult.failed(&"invalid_combat_auto_character", "Persistent Auto could not be changed for this character.")
		var toggle_sound := 147 if response.payload["enabled"] else 139
		var auto_events: Array[DomainEvent] = [
			DomainEvent.new(&"sound_requested", {"soundId": toggle_sound, "waitForCompletion": false, "source": "classic-combat-auto-toggle"}),
			DomainEvent.new(&"combat_auto_changed", {"characterId": response.payload["actorId"], "enabled": response.payload["enabled"], "source": "classic"}),
		]
		if not response.payload["enabled"] or _game_state.combat.active_actor_id() != response.payload["actorId"]:
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
	elif response.payload["action"] == "retreat":
		var retreat_probe: Variant = _rules.combat_flow.probe_character_retreat(_game_state.combat, _game_state.party.characters(), response.payload["actorId"])
		if not retreat_probe.allowed:
			return ScenarioRuntimeOperationResult.failed(retreat_probe.reason, retreat_probe.reason_text)
		return _wait_for_battle_retreat(continuation, response.payload["actorId"], &"explicit", Vector2i(-100_000, -100_000), request_id)
	elif response.payload["action"] == "retreat_edge":
		var edge_destination := _combat_destination(response.payload.get("destination"))
		var edge_probe: Variant = _rules.combat_flow.probe_edge_retreat(_game_state.combat, response.payload["actorId"], edge_destination)
		if not edge_probe.allowed:
			return ScenarioRuntimeOperationResult.failed(edge_probe.reason, edge_probe.reason_text)
		if not edge_probe.forced:
			return _wait_for_battle_retreat(continuation, response.payload["actorId"], &"edge", edge_destination, request_id)
		result = _rules.combat_flow.retreat_character(_game_state, _content, response.payload["actorId"], &"edge", edge_destination, _rng)
	elif response.payload["action"] == "move":
		var destination := _combat_destination(response.payload.get("destination"))
		if destination == Vector2i(-100_000, -100_000):
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat movement requires a two-integer destination.")
		var auto_switch_to_melee: Variant = response.payload.get("autoSwitchToMelee", false)
		if not auto_switch_to_melee is bool:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat movement's Auto Switch preference must be boolean.")
		result = _rules.combat_flow.move_character(_game_state, _content, response.payload["actorId"], destination, _rng, auto_switch_to_melee)
	elif response.payload["action"] == "cast_spell":
		if response.payload.get("spellId") is not String or response.payload["spellId"].is_empty() or response.payload.get("power") is not int:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat spell casting requires a spellId string and integer power.")
		var target_coordinate := _combat_destination(response.payload.get("targetCoordinate")) if response.payload.has("targetCoordinate") else CombatFlow.INVALID_COORDINATE
		var rotation: Variant = response.payload.get("rotation", 0)
		if not rotation is int:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat spell rotation must be an integer.")
		var target_ids: Array[String] = []
		var raw_target_ids: Variant = response.payload.get("targetIds", [])
		if not raw_target_ids is Array:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Repeated combat spell targets must be an ordered array.")
		for target_id: Variant in raw_target_ids:
			if not target_id is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Every repeated combat spell target must be a stable string ID.")
			target_ids.append(target_id)
		result = _rules.combat_flow.cast_spell(_game_state, _content, response.payload["actorId"], response.payload.get("targetId", ""), response.payload["spellId"], response.payload["power"], _rng, target_coordinate, int(rotation), target_ids)
	elif response.payload["action"] == "use_item":
		if response.payload.get("itemInstanceId") is not String or response.payload["itemInstanceId"].is_empty():
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat item use requires an itemInstanceId string.")
		result = _rules.combat_flow.use_spell_item(_game_state, _content, response.payload["actorId"], response.payload.get("targetId", ""), response.payload["itemInstanceId"], _rng)
	elif response.payload["action"] == "use_scroll":
		if response.payload.get("scrollSlot") is not int:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat scroll use requires an integer scrollSlot.")
		var scroll_target_coordinate := _combat_destination(response.payload.get("targetCoordinate")) if response.payload.has("targetCoordinate") else CombatFlow.INVALID_COORDINATE
		var scroll_rotation: Variant = response.payload.get("rotation", 0)
		if not scroll_rotation is int:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Combat scroll rotation must be an integer.")
		var scroll_target_ids: Array[String] = []
		var raw_target_ids: Variant = response.payload.get("targetIds", [])
		if not raw_target_ids is Array:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Repeated combat scroll targets must be an ordered array.")
		for target_id: Variant in raw_target_ids:
			if not target_id is String:
				return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Every repeated combat scroll target must be a stable string ID.")
			scroll_target_ids.append(target_id)
		result = _rules.combat_flow.use_combat_scroll(_game_state, _content, response.payload["actorId"], response.payload["scrollSlot"], response.payload.get("targetId", ""), _rng, scroll_target_coordinate, int(scroll_rotation), scroll_target_ids)
	else:
		result = _rules.combat_flow.submit_action(_game_state, _content, response.payload["actorId"], StringName(response.payload["action"]), response.payload.get("targetId", ""), _rng)
	if not result.ok:
		if response.payload["action"] == "move" and result.error_code == &"melee_weapon_mode_required":
			var warning_events: Array[DomainEvent] = [
				DomainEvent.new(&"sound_requested", {"soundId": 6000, "waitForCompletion": false, "source": "classic-auto-weapon-switch-warning"}),
				DomainEvent.new(&"combat_action_unavailable", {"actorId": response.payload["actorId"], "action": "move", "reason": String(result.error_code), "message": result.error_message, "source": "classic"}),
			]
			return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, warning_events)
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _wait_for_combat_age_updates(String(continuation.get("kind", "classic-combat")), caller, request_id, result.events, previous_round)
	if not _death_macro_request(result.events).is_empty():
		return _run_combat_death_macro(String(continuation.get("kind", "classic-combat")), caller, result.events, request_id)
	if result.completed:
		var completed_events: Array[DomainEvent] = []
		completed_events.assign(result.events)
		return _finish_battle_with_allies(String(continuation.get("kind", "classic-combat")), caller, request_id, completed_events)
	if _game_state.combat.round_number > previous_round and _game_state.combat.macro_id < 0:
		return _run_battle_macro(String(continuation.get("kind", "classic-combat")), caller, result.events, request_id)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), continuation, result.events)


func _wait_for_battle_retreat(continuation: Dictionary, actor_id: String, mode: StringName, destination: Vector2i, request_id: String) -> ScenarioRuntimeOperationResult:
	var source_kind := String(continuation.get("kind", "classic-combat"))
	var next_continuation := {"kind": "%s-retreat-confirmation" % source_kind, "sourceKind": source_kind, "battleId": _game_state.combat.battle_id, "battleCaller": _battle_caller(continuation), "actorId": actor_id, "mode": String(mode), "destination": [destination.x, destination.y]}
	var request := InteractionRequest.yes_no(request_id, "Will this character flee from battle?", "Embrace Cowardice", "Stay and Fight")
	return ScenarioRuntimeOperationResult.waiting(request, next_continuation)


func _resume_battle_retreat(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.YES_NO or response.payload.get("accepted") is not bool:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	if _game_state.combat == null or _game_state.combat.completed or _game_state.combat.battle_id != continuation.get("battleId") or _game_state.combat.active_actor_id() != continuation.get("actorId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The character awaiting Escape confirmation is unavailable.")
	var source_kind := String(continuation.get("sourceKind", "classic-combat"))
	var caller := _battle_caller(continuation)
	if caller.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending retreat lost its originating battle caller.")
	var mode := StringName(continuation.get("mode", ""))
	var destination := _combat_destination(continuation.get("destination"))
	var probe: Variant = _rules.combat_flow.probe_character_retreat(_game_state.combat, _game_state.party.characters(), continuation["actorId"]) if mode == &"explicit" else _rules.combat_flow.probe_edge_retreat(_game_state.combat, continuation["actorId"], destination) if mode == &"edge" else null
	if probe == null or not probe.allowed or probe.forced:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The saved Escape confirmation no longer represents a promptable Classic action.")
	if not response.payload["accepted"]:
		return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": source_kind, "battleId": continuation["battleId"], "battleCaller": caller}, [DomainEvent.new(&"combat_retreat_declined", {"actorId": continuation["actorId"], "mode": continuation["mode"], "source": "classic"})])
	var previous_round := _game_state.combat.round_number
	var result := _rules.combat_flow.retreat_character(_game_state, _content, continuation["actorId"], mode, destination, _rng)
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
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": source_kind, "battleId": continuation["battleId"], "battleCaller": caller}, result.events)


func _append_battle_after_message(battle: BattleDefinition, events: Array[DomainEvent]) -> void:
	if battle.message_after_id == 0:
		return
	var after := _content.message_by_id(absi(battle.message_after_id))
	if after != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": after.id, "text": after.text, "source": "classic-battle-definition"}))


func _finish_battle_with_allies(source_kind: String, caller: Dictionary, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle ally selection requires a completed battle.")
	if combat.outcome == &"defeat":
		if caller.get("kind") == "classic" and caller.get("opcode") == 2 and caller.get("mode") == 10:
			return ScenarioRuntimeOperationResult.failed(&"classic_mode_10_defeat_unresolved", "Classic battle mode 10 bypasses Party Death and restarts its encounter; that caller-specific path is unresolved.")
		return ScenarioRuntimeOperationResult.suspended({"kind": "party-defeat", "battleId": combat.battle_id, "sourceKind": source_kind, "caller": caller.duplicate(true)}, events)
	var payload := _rules.combat_flow.ally_selection_payload(_game_state, _content)
	if not payload.is_empty():
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, &"ally_selection", payload), {
			"kind": "%s-ally-selection" % source_kind,
			"sourceKind": source_kind,
			"battleId": combat.battle_id,
			"battleCaller": caller.duplicate(true),
		}, events)
	return _finish_battle_with_fumbles(source_kind, caller, request_id, events)


func _finish_battle_with_fumbles(source_kind: String, caller: Dictionary, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Post-battle fumbled-weapon recovery requires a completed battle.")
	var payload := _rules.combat_flow.fumble_recovery_payload(_game_state, _content)
	if not payload.is_empty():
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.new(request_id, InteractionRequest.TREASURE_DISTRIBUTION, payload), {
			"kind": "%s-fumble-recovery" % source_kind,
			"sourceKind": source_kind,
			"battleId": combat.battle_id,
			"battleCaller": caller.duplicate(true),
		}, events)
	var reward := begin_completed_battle_reward(request_id)
	reward.events = events + reward.events
	return reward


func _resume_ally_selection(continuation: Dictionary, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	if response.kind != &"ally_selection" or not response.payload.has("selectedIds"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Ally selection requires selectedIds.")
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != continuation.get("battleId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for ally selection.")
	if _rules.combat_flow.ally_selection_payload(_game_state, _content).is_empty():
		return _finish_battle_with_fumbles(String(continuation.get("sourceKind", "classic-combat")), _battle_caller(continuation), String(response.request_id), [])
	var selected := _rules.combat_flow.apply_ally_selection(_game_state, _content, response.payload["selectedIds"])
	if not selected.ok:
		return ScenarioRuntimeOperationResult.failed(selected.error_code, selected.error_message)
	var events: Array[DomainEvent] = []
	events.assign(selected.events)
	return _finish_battle_with_fumbles(String(continuation.get("sourceKind", "classic-combat")), _battle_caller(continuation), String(response.request_id), events)


func _resume_fumble_recovery(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	if _game_state.combat == null or not _game_state.combat.completed or _game_state.combat.battle_id != continuation.get("battleId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var recovered := _rules.combat_flow.apply_fumble_recovery(_game_state, _content, response.payload)
	if not recovered.ok:
		return ScenarioRuntimeOperationResult.failed(recovered.error_code, recovered.error_message)
	var events: Array[DomainEvent] = []
	events.assign(recovered.events)
	return _finish_battle_with_fumbles(String(continuation.get("sourceKind", "classic-combat")), _battle_caller(continuation), request_id, events)


func _run_battle_macro(source_kind: String, caller: Dictionary, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	if combat == null or combat.completed or combat.macro_id >= 0:
		return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": source_kind, "battleId": combat.battle_id, "battleCaller": caller.duplicate(true)}, preceding_events)
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
		return ScenarioRuntimeOperationResult.waiting(result.interaction, {
			"kind": "%s-macro" % source_kind,
			"sourceKind": source_kind,
			"battleId": combat.battle_id,
			"programId": program_id,
			"battleCaller": caller.duplicate(true),
			"macroVm": vm.snapshot().to_data(),
		}, events)
	return _continue_after_battle_macro(source_kind, caller, request_id, program_id, events)


func _resume_battle_macro(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.battle_id != continuation.get("battleId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending battle macro is unavailable.")
	var snapshot := ScenarioVmSnapshot.from_data(continuation.get("macroVm"))
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
		var next_continuation := continuation.duplicate(true)
		next_continuation["macroVm"] = vm.snapshot().to_data()
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_battle_macro(String(continuation.get("sourceKind", "classic-combat")), _battle_caller(continuation), request_id, String(continuation.get("programId", "")), result.events)


func _continue_after_battle_macro(source_kind: String, caller: Dictionary, request_id: String, program_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(DomainEvent.new(&"battle_macro_completed", {"battleId": _game_state.combat.battle_id, "programId": program_id, "round": _game_state.combat.round_number}))
	if _game_state.combat.completed:
		return _finish_battle_with_allies(source_kind, caller, request_id, committed)
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": source_kind, "battleId": _game_state.combat.battle_id, "battleCaller": caller.duplicate(true)}, committed)


func _run_combat_death_macro(source_kind: String, caller: Dictionary, preceding_events: Array[DomainEvent], request_id: String) -> ScenarioRuntimeOperationResult:
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
		return ScenarioRuntimeOperationResult.waiting(result.interaction, {
			"kind": "%s-death-macro" % source_kind,
			"sourceKind": source_kind,
			"battleId": combat.battle_id,
			"combatantId": combatant_id,
			"programId": program_id,
			"resetTraitorOnComplete": bool(request.get("resetTraitorOnComplete", true)),
			"battleCaller": caller.duplicate(true),
			"macroVm": vm.snapshot().to_data(),
		}, events)
	return _continue_after_combat_death_macro(source_kind, caller, request_id, combatant_id, program_id, events, bool(request.get("resetTraitorOnComplete", true)))


func _resume_combat_death_macro(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.battle_id != continuation.get("battleId"):
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The pending monster death macro is unavailable.")
	var snapshot := ScenarioVmSnapshot.from_data(continuation.get("macroVm"))
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
		var next_continuation := continuation.duplicate(true)
		next_continuation["macroVm"] = vm.snapshot().to_data()
		return ScenarioRuntimeOperationResult.waiting(result.interaction, next_continuation, result.events)
	return _continue_after_combat_death_macro(String(continuation.get("sourceKind", "classic-combat")), _battle_caller(continuation), request_id, String(continuation.get("combatantId", "")), String(continuation.get("programId", "")), result.events, bool(continuation.get("resetTraitorOnComplete", true)))


func _continue_after_combat_death_macro(source_kind: String, caller: Dictionary, request_id: String, combatant_id: String, program_id: String, events: Array[DomainEvent], reset_traitor_on_complete: bool = true) -> ScenarioRuntimeOperationResult:
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
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": source_kind, "battleId": combat.battle_id, "battleCaller": caller.duplicate(true)}, committed)


func _wait_for_combat_age_updates(source_kind: String, caller: Dictionary, request_id: String, events: Array[DomainEvent], round_before: int) -> ScenarioRuntimeOperationResult:
	var updates := CharacterAgingResult.update_payloads(events)
	if updates.is_empty() or _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_combat_age_update", "Monster aging did not provide a valid combat continuation.")
	var continuation := {
		"kind": "%s-age-updates" % source_kind,
		"sourceKind": source_kind,
		"battleId": _game_state.combat.battle_id,
		"updates": updates,
		"index": 1,
		"roundBefore": round_before,
		"battleCaller": caller.duplicate(true),
	}
	var committed: Array[DomainEvent] = []
	committed.assign(events)
	committed.append(CharacterAgingResult.sound_event(updates[0]))
	return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update(request_id, updates[0]), continuation, committed)


func _resume_combat_age_updates(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.AGE_UPDATE or not response.payload.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Classic combat age updates require an empty acknowledgement.")
	if _game_state.combat == null or _game_state.combat.battle_id != continuation.get("battleId") or _game_state.combat.pending_monster_attack == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The monster age-update battle is unavailable.")
	var updates: Variant = continuation.get("updates", [])
	var index := int(continuation.get("index", -1))
	if not updates is Array or updates.is_empty() or index < 1 or index > updates.size():
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_continuation", "The combat age-update queue is invalid.")
	var acknowledged: Dictionary = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.get("characterId", "")})]
	if index < updates.size():
		var next_payload: Dictionary = updates[index]
		var next_continuation := continuation.duplicate(true)
		next_continuation["index"] = index + 1
		events.append(CharacterAgingResult.sound_event(next_payload))
		return ScenarioRuntimeOperationResult.waiting(InteractionRequest.age_update(request_id, next_payload), next_continuation, events)
	var source_kind := String(continuation.get("sourceKind", "classic-combat"))
	var caller := _battle_caller(continuation)
	if caller.is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "The combat age update lost its originating battle caller.")
	var round_before := int(continuation.get("roundBefore", _game_state.combat.round_number))
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
	return ScenarioRuntimeOperationResult.waiting(_combat_request(request_id), {"kind": source_kind, "battleId": _game_state.combat.battle_id, "battleCaller": caller.duplicate(true)}, events)


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
	return InteractionRequest.new(request_id, &"combat_action", {"battleId": combat_view.battle_id, "round": combat_view.round_number, "actorId": combat_view.active_actor_id, "attackUnitsRemaining": combat_view.attack_units_remaining, "movementRemaining": combat_view.movement_remaining, "enemiesRemaining": enemies_remaining, "actions": actions, "weaponMode": String(combat_view.weapon_mode), "weaponSwitch": weapon_switch, "rangedAttack": ranged_attack, "retreat": retreat, "meleeAttackReason": combat_view.melee_attack_unavailable_reason, "targets": targets, "combatants": combatants, "movement": movement, "spellCasts": spell_casts, "spellCastReason": spell_cast_reason, "fastSpells": fast_spells, "itemCasts": item_casts, "itemCastReason": item_cast_reason, "scrollCasts": scroll_casts, "scrollCastReason": scroll_cast_reason, "autoTurn": {"enabled": combat_view.auto_turn.enabled, "reason": combat_view.auto_turn.reason}, "autoCharacterIds": combat_view.auto_character_ids.duplicate(), "delay": {"enabled": combat_view.delay.enabled, "reason": combat_view.delay.reason}, "bandage": {"enabled": combat_view.bandage.enabled, "reason": combat_view.bandage.reason, "targets": bandage_targets}, "turnUndead": {"enabled": combat_view.turn_undead.enabled, "reason": combat_view.turn_undead.reason, "targets": turn_targets}, "undo": {"enabled": combat_view.undo.enabled, "reason": combat_view.undo.reason}})


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
	var reward := ClassicRewardState.new(origin, source_id, maxi(0, total_experience), wealth)
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
	_game_state.party.pooled_wealth.gold += wealth.gold
	_game_state.party.pooled_wealth.gems += wealth.gems
	_game_state.party.pooled_wealth.jewelry += wealth.jewelry
	for character: CharacterState in recipients:
		character.experience += int(awards[character.id])
	var events: Array[DomainEvent] = [DomainEvent.new(&"reward_opened", {"origin": String(origin), "sourceId": source_id, "experiencePool": reward.experience_pool, "experienceShare": reward.experience_share, "experienceByCharacter": awards, "wealth": wealth.to_data(), "itemCount": items.size()})]
	if items.is_empty() and wealth.gold == 0 and wealth.gems == 0 and wealth.jewelry == 0 and total_experience == 0:
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
	return ScenarioRuntimeOperationResult.waiting(request, {"kind": "classic-reward", "state": reward.to_data()}, events)


func _reward_request(reward: ClassicRewardState, request_id: String) -> InteractionRequest:
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _level_result_request(reward, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _reward_spell_request(reward, request_id)
	if reward.completion_pending:
		var summary := "%d unclaimed item%s and %d gold, %d gems, %d jewelry will be left behind." % [reward.items().size(), "" if reward.items().size() == 1 else "s", _game_state.party.pooled_wealth.gold, _game_state.party.pooled_wealth.gems, _game_state.party.pooled_wealth.jewelry]
		return InteractionRequest.new(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {"mode": "completion-confirmation", "prompt": "Leave the remaining treasure behind?", "summary": summary})
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
	return InteractionRequest.new(request_id, InteractionRequest.TREASURE_DISTRIBUTION, {
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


func _resume_reward(continuation: Dictionary, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if continuation.size() != 2 or continuation.get("kind") != "classic-reward":
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The reward continuation is malformed.")
	var reward := ClassicRewardState.from_data(continuation.get("state"))
	if reward == null or not _reward_state_is_valid(reward):
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward_continuation", "The saved reward state is invalid.")
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return _resume_reward_level(reward, response, request_id)
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		return _resume_reward_spells(reward, response, request_id)
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or not response.payload.get("action") is String:
		return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "Treasure distribution requires a typed action.")
	var action: String = response.payload["action"]
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
			var mutation := _assign_reward_item(reward, response.payload)
			if not mutation.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(mutation["code"]), mutation["message"])
			events.append(DomainEvent.new(&"reward_item_assigned", {"instanceId": response.payload.get("instanceId"), "characterId": response.payload.get("characterId")}))
		"discard":
			var pending := reward.first_item()
			if pending == null or response.payload.get("instanceId") != pending.id or reward.remove_item(pending.id) == null:
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
			var transfer_error := _transfer_reward_wealth(response.payload)
			if not transfer_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(transfer_error["code"]), transfer_error["message"])
			events.append(DomainEvent.new(&"reward_wealth_transferred", response.payload))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if response.payload.get("direction") == "to-character" else 663, "waitForCompletion": false, "source": "classic-reward-swap"}))
		"detect", "identify":
			var detection_error := _apply_reward_detection(reward, action, response.payload)
			if not detection_error.is_empty():
				return ScenarioRuntimeOperationResult.failed(StringName(detection_error["code"]), detection_error["message"])
			events.append(DomainEvent.new(&"reward_magic_%s" % ("detected" if action == "detect" else "identified"), {"characterId": response.payload.get("characterId")}))
		"done":
			if not reward.items().is_empty() or _reward_has_pooled_wealth():
				reward.completion_pending = true
				return _wait_for_reward(reward, request_id)
			return _begin_reward_progression(reward, request_id)
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_interaction_response", "The treasure action is unavailable.")
	return _wait_for_reward(reward, request_id, events)


func _assign_reward_item(reward: ClassicRewardState, payload: Dictionary) -> Dictionary:
	if not payload.get("instanceId") is String or not payload.get("characterId") is String:
		return {"code": "invalid_interaction_response", "message": "Treasure assignment requires item and character IDs."}
	var pending := reward.first_item()
	var character := _game_state.party.character_by_id(payload["characterId"])
	var definition: ItemDefinition = null if pending == null else _content.item_by_id(pending.definition_id)
	if pending == null or pending.id != payload["instanceId"] or character == null or definition == null or not _rules.inventory.can_restore_item(character, pending, definition):
		return {"code": "reward_assignment_unavailable", "message": "The selected character cannot receive the pending item."}
	if not _rules.inventory.restore_item(character, pending, definition):
		return {"code": "reward_assignment_failed", "message": "The item assignment could not be committed."}
	if reward.identified:
		pending.identified = true
	if reward.remove_item(pending.id) == null:
		_rules.inventory.remove_item(character, pending.id, definition)
		return {"code": "reward_assignment_failed", "message": "The committed item could not be removed from the reward queue."}
	return {}


func _transfer_reward_wealth(payload: Dictionary) -> Dictionary:
	if not payload.get("characterId") is String or not payload.get("direction") is String or not payload.get("kind") is String or not payload.get("amount") is int:
		return {"code": "invalid_interaction_response", "message": "Treasure transfer requires character, direction, denomination, and amount."}
	var character := _game_state.party.character_by_id(payload["characterId"])
	var kind := _wealth_kind(payload["kind"])
	var amount: int = payload["amount"]
	if character == null or kind < 0 or amount != (5 if kind == WealthState.Kind.GOLD else 1):
		return {"code": "invalid_interaction_response", "message": "The requested Classic wealth increment is invalid."}
	var transferred := _rules.economy.transfer_pool_to_character(_game_state.party, character, kind as WealthState.Kind, amount) if payload["direction"] == "to-character" else _rules.economy.transfer_character_to_pool(_game_state.party, character, kind as WealthState.Kind, amount) if payload["direction"] == "to-pool" else false
	if transferred:
		_recalculate_party_movement()
	return {} if transferred else {"code": "reward_transfer_unavailable", "message": "The selected wealth transfer is no longer available."}


func _apply_reward_detection(reward: ClassicRewardState, action: String, payload: Dictionary) -> Dictionary:
	if not payload.get("characterId") is String:
		return {"code": "invalid_interaction_response", "message": "Magic detection requires a caster."}
	var special := 63 if action == "detect" else 48
	var cost := 5 if action == "detect" else 25
	var caster_id: String = payload["characterId"]
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
	return InteractionRequest.new(request_id, InteractionRequest.LEVEL_UP, {"mode": "result", "prompt": "Review the level gained.", "characterId": result["characterId"], "characterName": result["characterName"], "level": result["level"], "gains": {"stamina": result["stamina"], "spellPoints": result["spellPoints"], "toHit": result["toHit"], "magicResistance": result["magicResistance"]}})


func _resume_reward_level(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if response.kind != InteractionRequest.LEVEL_UP or response.payload.get("action") != "continue" or response.payload.get("characterId") != reward.pending_level_result.get("characterId"):
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
	return InteractionRequest.new(request_id, InteractionRequest.LEVEL_UP, {"mode": "spell-selection", "prompt": "Choose the spells this character knows.", "characterId": character.id, "characterName": character.name, "pointTotal": _rules.characters.spell_selection_total(character, caste), "spells": spells})


func _resume_reward_spells(reward: ClassicRewardState, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	var ids := reward.spell_character_ids()
	if response.kind != InteractionRequest.LEVEL_UP or response.payload.get("action") != "confirm-spells" or reward.spell_index < 0 or reward.spell_index >= ids.size() or response.payload.get("characterId") != ids[reward.spell_index] or not response.payload.get("spellIds") is Array:
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
	for value: Variant in response.payload["spellIds"]:
		if not value is String or selected.has(value) or not candidates.has(value):
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
	for character: CharacterState in targets:
		character.conditions.set_value(condition_index, duration)
	var ids: Array[String] = []
	for character: CharacterState in targets:
		ids.append(character.id)
	return ScenarioRuntimeOperationResult.completed(ids, [DomainEvent.new(&"condition_applied", {"characterIds": ids, "condition": condition_index, "duration": duration, "soundId": action.extra_code[3] if action.extra_code.size() > 3 else 0})])


func _remove_classic_ally(classic_monster_id: int) -> int:
	var definition := _content.monster_by_classic_id(classic_monster_id)
	return 0 if definition == null else _game_state.party.remove_allies_by_definition(definition.id)


func _add_classic_ally(classic_monster_id: int) -> ScenarioRuntimeOperationResult:
	var definition := _content.monster_by_classic_id(classic_monster_id)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 89 references unavailable monster %d." % classic_monster_id)
	var ally := _rules.monsters.build_monster(definition, _game_state.next_instance_id("party.ally"), 0, 0, _game_state.clock.day(), _rng)
	if ally == null or not _game_state.party.add_ally(ally):
		return ScenarioRuntimeOperationResult.failed(&"ally_add_failed", "The ally could not join the party.")
	return ScenarioRuntimeOperationResult.completed(ally.id, [DomainEvent.new(&"ally_added", {"allyId": ally.id, "monsterId": definition.id})])


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
	var definition := _content.monster_by_classic_id(absi(action.extra_code[1]))
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 124 references unavailable monster %d." % action.extra_code[1])
	var authored_count := action.extra_code[2]
	var count := _rng.draw(absi(authored_count), &"classic.combat.spawn-count") if authored_count < 0 else authored_count
	var spawned: Array[String] = []
	for _index: int in maxi(0, count):
		var monster := _rules.monsters.build_monster(definition, _game_state.next_instance_id("combat.spawn"), -1, 0, _game_state.clock.day(), _rng)
		if monster != null and _game_state.combat.add_monster(monster):
			_game_state.combat.append_turn_actor(monster.id)
			spawned.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(spawned, [DomainEvent.new(&"combat_monsters_spawned", {"monsterId": definition.id, "instanceIds": spawned, "soundId": action.extra_code[3] if action.extra_code.size() > 3 else 0})])


static func _whole_number(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, round(value))
