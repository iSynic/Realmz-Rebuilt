class_name ClassicCombatOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules
var _rng: RealmzRng


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules, rng: RealmzRng) -> void:
	_content = content
	_game_state = game_state
	_rules = rules
	_rng = rng


func opcode_ids() -> Array[int]:
	return [119, 120, 121, 122, 123, 124, 126, 127]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		119:
			return _revive_after_combat_macro(context)
		120:
			return _alter_combat_monsters(action)
		121:
			return _deanimate_lower_undead()
		122:
			return cause_fumble(action, context)
		123:
			return _cause_monsters_to_route(action, context)
		124:
			return _spawn_classic_monsters(action)
		126:
			return _branch_battle_round_macro(action)
		127:
			return _continue_if_monster_present(action)
	return super.execute(action, request_id, context)


func cause_fumble(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 122 requires message and sound fields.")
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"combat_fumble_skipped", {"reason": "no-active-battle", "source": "classic"})])
	var actor_id := context.combatant_id if not context.combatant_id.is_empty() else _game_state.combat.active_actor_id()
	var result := _rules.combat_flow.cause_active_fumble(_game_state, _content, actor_id)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message)
	if result.events.any(func(event: DomainEvent) -> bool: return event.kind == &"combat_fumble_skipped" and event.payload.get("reason") in ["no-physical-action", "not-party-actor"]):
		return ScenarioRuntimeOperationResult.completed(false, result.events)
	var events: Array[DomainEvent] = []
	if int(action.extra_code[1]) != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(int(action.extra_code[1])), "waitForCompletion": int(action.extra_code[1]) < 0, "source": "classic"}))
	if int(action.extra_code[0]) != 0:
		var message := _content.message_by_id(absi(int(action.extra_code[0])))
		if message != null:
			events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic"}))
	events.append_array(result.events)
	var changed := false
	for event: DomainEvent in result.events:
		if event.kind == &"combatant_fumbled":
			changed = true
			break
	return ScenarioRuntimeOperationResult.completed(changed, events)


func _revive_after_combat_macro(context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
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
	var combatant_id := context.combatant_id
	var monster := _game_state.combat.monster_by_id(combatant_id)
	if monster == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_combatant_context", "Classic opcode 119 requires its death-macro combatant identity.")
	monster.current_health = 1
	monster.traitor = false
	return ScenarioRuntimeOperationResult.completed(monster.id, [DomainEvent.new(&"monster_revived", {"monsterId": monster.id, "source": "classic-death-macro"})])


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


func _cause_monsters_to_route(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_route_applied", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 123 requires a five-value Extra Code row.")
	var source_traitor := true
	var source_id := context.combatant_id
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
