## Coordinates Classic combat operations operations for the validated scenario runtime.

class_name ClassicCombatOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rules: RealmzRules
var _rng: RealmzRng
var _macros: ScenarioMacroLifecycle
var native_state: ScenarioClassicExecutionState
var native_invocation: ScenarioClassicInvocationRecord


func _init(content: RealmzContent, game_state: GameState, rules: RealmzRules, rng: RealmzRng, macros: ScenarioMacroLifecycle) -> void:
	_content = content
	_game_state = game_state
	_rules = rules
	_rng = rng
	_macros = macros


func opcode_ids() -> Array[int]:
	return [100, 119, 120, 121, 122, 123, 124, 125, 126, 127]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		100:
			return _finish_battle()
		119:
			return _revive_after_combat_macro(context)
		120:
			return _alter_combat_monsters(action)
		121:
			return _deanimate_lower_undead()
		122:
			return cause_fumble(action, context, request_id)
		123:
			return _cause_monsters_to_route(action, context)
		124:
			return _spawn_classic_monsters(action, context)
		125:
			return _destroy_related_monsters(action)
		126:
			return _branch_battle_round_macro(action)
		127:
			return _continue_if_monster_present(action)
	return super.execute(action, request_id, context)


func complete_macro_call(call: ScenarioMacroCall) -> ScenarioRuntimeOperationResult:
	if call.return_kind != ScenarioMacroCall.ReturnKind.DESTRUCTION:
		return ScenarioRuntimeOperationResult.failed(&"invalid_macro_return", "The macro has no destruction return owner.")
	var result := _macros.complete(call)
	if not result.ok: return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message, result.events)
	return _run_opcode_death_macros(call.remaining_combatant_ids, result.events)


func _destroy_related_monsters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 125 requires a five-value Extra Code row.")
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_related_monsters_destroyed", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	var limit := 100 if action.extra_code[1] == 0 else maxi(0, action.extra_code[1])
	var include_loyal := action.extra_code[4] != 0
	var destroyed: Array[String] = []
	var death_macros: Array[String] = []
	for monster: MonsterState in _game_state.combat.roster.monsters():
		if destroyed.size() >= limit:
			break
		var definition := _content.combat.monster_by_id(monster.definition_id)
		if monster.current_health <= 0 or definition == null or definition.classic_name_id != action.extra_code[0] or not monster.traitor and not include_loyal:
			continue
		monster.current_health = 0
		destroyed.append(monster.id)
		if definition.has_death_macro():
			death_macros.append(monster.id)
		elif _game_state.combat.battlefield != null:
			_game_state.combat.battlefield.actors.remove_monster(monster.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"combat_related_monsters_destroyed", {"count": destroyed.size(), "monsterIds": destroyed, "classicNameId": action.extra_code[0], "limit": limit, "includeLoyal": include_loyal, "source": "classic"})]
	return _run_opcode_death_macros(death_macros, events)


func _run_opcode_death_macros(combatant_ids: Array[String], preceding_events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	if combatant_ids.is_empty():
		var finalized := _rules.combat_flow.finalize_scenario_monster_destruction(_game_state, _content)
		if not finalized.ok:
			return ScenarioRuntimeOperationResult.failed(finalized.error_code, finalized.error_message)
		return ScenarioRuntimeOperationResult.completed(true, preceding_events + finalized.events)
	if _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Classic opcode 125 requires an active battle.")
	var remaining := combatant_ids.duplicate()
	var combatant_id: String = remaining.pop_front()
	var monster := _game_state.combat.roster.monster_by_id(combatant_id)
	var definition := _content.combat.monster_by_id(monster.definition_id) if monster != null else null
	if monster == null or definition == null or not definition.has_death_macro():
		return ScenarioRuntimeOperationResult.failed(&"invalid_death_macro_request", "Classic opcode 125 references unavailable monster death-macro content.")
	var call := ScenarioMacroCall.new()
	call.kind = ScenarioMacroCall.Kind.DEATH
	call.return_kind = ScenarioMacroCall.ReturnKind.DESTRUCTION
	call.battle_id = _game_state.combat.battle_id
	call.program_id = "xap:%d" % definition.death_macro
	call.combatant_id = monster.id
	call.classic_monster_id = definition.classic_id
	call.traitor = monster.traitor
	call.has_classic_monster_id = true
	call.has_traitor = true
	call.remaining_combatant_ids.assign(remaining)
	return _macros.begin(call, preceding_events)


func _finish_battle() -> ScenarioRuntimeOperationResult:
	var result := _rules.combat_flow.finish_classic_macro_victory(_game_state, _content)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message, result.events)
	return ScenarioRuntimeOperationResult.completed(true, result.events, ScenarioVmDirective.end_record(true))


func cause_fumble(action: ClassicActionDefinition, context: ScenarioExecutionContext, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 122 requires message and sound fields.")
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"combat_fumble_skipped", {"reason": "no-active-battle", "source": "classic"})])
	var actor_id := _game_state.combat.turns.active_actor_id()
	if not CombatFlowActions.scripted_fumble_guard_reason(_game_state).is_empty():
		return _commit_scripted_fumble(actor_id, context)
	var events: Array[DomainEvent] = []
	if int(action.extra_code[1]) != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(int(action.extra_code[1])), "waitForCompletion": int(action.extra_code[1]) < 0, "source": "classic"}))
	if int(action.extra_code[0]) != 0:
		var message := _content.scenario_records.message_by_id(absi(int(action.extra_code[0])))
		if message != null:
			events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic", "classicClick": action.extra_code[0] > 0}))
			if action.extra_code[0] > 0:
				var request := InteractionRequest.from_payload(request_id, InteractionRequest.ACKNOWLEDGE, {"prompt": message.text, "messageId": message.id, "presentation": "classic-textbox", "journalEligible": ScenarioProgressState.journal_message_id_is_valid(message.id), "journalRecorded": _game_state.scenario_progress.journal_message_is_recorded(message.id)})
				return ScenarioRuntimeOperationResult.waiting(request, ScenarioInteractionContinuations.scripted_fumble(_game_state.combat.battle_id, actor_id, message.id, context), events)
	return _commit_scripted_fumble(actor_id, context, events)


func resume_scripted_fumble(continuation: ScenarioRuntimeContinuation, response: InteractionResponse) -> ScenarioRuntimeOperationResult:
	var body := continuation.body as ScenarioFumbleContinuationBody
	var ack := response.body as InteractionResponse.AcknowledgeBody
	if ack == null or response.kind != InteractionRequest.ACKNOWLEDGE:
		return ScenarioRuntimeOperationResult.rejected(&"invalid_interaction_response", "The scripted fumble message requires an acknowledgement.")
	if body == null or _game_state.combat == null or _game_state.combat.battle_id != body.battle_id or _game_state.combat.turns.active_actor_id() != body.actor_id or not CombatFlowActions.scripted_fumble_guard_reason(_game_state).is_empty():
		return ScenarioRuntimeOperationResult.failed(&"invalid_fumble_continuation", "The guarded scripted fumble cannot resume.")
	var events: Array[DomainEvent] = []
	if ack.take_note and not _game_state.scenario_progress.journal_message_is_recorded(body.message_id):
		if not _game_state.scenario_progress.record_journal_message(body.message_id):
			return ScenarioRuntimeOperationResult.rejected(&"journal_message_unrepresentable", "This message cannot be recorded in the journal.")
		events.append(DomainEvent.new(&"journal_entry_recorded", {"messageId": body.message_id}))
	return _commit_scripted_fumble(body.actor_id, body.context, events)


func _commit_scripted_fumble(actor_id: String, context: ScenarioExecutionContext, events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var result := _rules.combat_flow.cause_active_fumble(_game_state, _content, actor_id)
	if not result.ok:
		return ScenarioRuntimeOperationResult.failed(result.error_code, result.error_message, result.events)
	events.append_array(result.events)
	if result.fumble == CombatFlowResult.Fumble.CURSED_WEAPON:
		events.append(DomainEvent.new(&"classic_notification_requested", {"text": "This item appears to be cursed!", "soundId": 6000, "source": "classic-warning-7"}))
	if result.fumble in [CombatFlowResult.Fumble.UNARMED,CombatFlowResult.Fumble.CURSED_WEAPON]:
		# newland.c returns 0 here: stop this invocation, retaining its AP.
		if context != null and not context.trigger_id.is_empty():
			events.append(DomainEvent.new(&"action_point_kept", {"triggerId": context.trigger_id}))
		return ScenarioRuntimeOperationResult.completed(false, events, ScenarioVmDirective.native_return(0))
	return ScenarioRuntimeOperationResult.completed(result.fumble == CombatFlowResult.Fumble.COMMITTED, events)


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
		var result := ScenarioRuntimeOperationResult.completed(revived_party, [DomainEvent.new(&"party_revived", {"characterIds": revived_party, "source": "classic-death-macro"})], ScenarioVmDirective.native_return(-1))
		result.party_revived = true
		return result
	if _game_state.combat == null:
		return ScenarioRuntimeOperationResult.failed(&"revival_outside_combat", "Classic opcode 119 has no combatant to revive.")
	var monster := _macro_monster(context, false)
	if monster == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_combatant_context", "Classic opcode 119 requires its death-macro combatant identity.")
	_game_state.combat.reconcile_classic_counters(_game_state.party)
	monster.current_health = 1
	_game_state.combat.clear_classic_death_macro_traitor(monster, _game_state.party)
	return ScenarioRuntimeOperationResult.completed(monster.id, [DomainEvent.new(&"monster_revived", {"monsterId": monster.id, "source": "classic-death-macro"})])


func _alter_combat_monsters(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_monsters_altered", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 120 requires a five-value Extra Code row.")
	var target_kind := action.extra_code[0]
	if target_kind not in [1, 2]:
		return ScenarioRuntimeOperationResult.completed(0)
	_game_state.combat.reconcile_classic_counters(_game_state.party)
	var remaining := action.extra_code[2]
	var candidates := _game_state.combat.roster.monsters()
	var altered: Array[String] = []
	for monster: MonsterState in candidates:
		if remaining == 0:
			break
		var candidate_definition := _content.combat.monster_by_id(monster.definition_id)
		if candidate_definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 120 requires every live monster definition.")
		if candidate_definition.classic_name_id != action.extra_code[1] or (candidate_definition.can_summon == -1) != (target_kind == 1):
			continue
		if action.extra_code[3] != -1:
			monster.icon_id = action.extra_code[3]
			altered.append(monster.id)
			remaining = RealmzArithmetic.new().signed_16(remaining - 1)
		elif action.extra_code[4] != -1 or monster.classic_traitor != action.extra_code[4]:
			if not _game_state.combat.classic_counters_available:
				return ScenarioRuntimeOperationResult.failed(&"missing_classic_battle_counters", "This older battle has no retained native enemy-counter history.")
			_game_state.combat.record_classic_traitor_write(monster, action.extra_code[4])
			altered.append(monster.id)
			remaining = RealmzArithmetic.new().signed_16(remaining - 1)
	return ScenarioRuntimeOperationResult.completed(altered.size(), [DomainEvent.new(&"combat_monsters_altered", {"count": altered.size(), "monsterIds": altered, "classicNameId": action.extra_code[1], "targetKind": target_kind, "source": "classic"})])


func _deanimate_lower_undead() -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0)
	var affected: Array[String] = []
	for monster: MonsterState in _game_state.combat.roster.monsters():
		var definition := _content.combat.monster_by_id(monster.definition_id)
		if definition != null and definition.type_flag(1) and not definition.type_flag(5) and monster.current_health > 0:
			monster.current_health = 0
			affected.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(affected, [DomainEvent.new(&"lower_undead_deanimated", {"monsterIds": affected})])


func _cause_monsters_to_route(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.completed(0, [DomainEvent.new(&"combat_route_applied", {"count": 0, "reason": "no-active-battle", "source": "classic"})])
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 123 requires a five-value Extra Code row.")
	var source_traitor := 1
	var source_monster := _macro_monster(context)
	if source_monster != null:
		source_traitor = source_monster.classic_traitor
	if native_invocation != null and native_invocation.queued_source != null:
		if not native_invocation.queued_source.available: return ScenarioRuntimeOperationResult.failed(&"unavailable_macro_source", "The historical queued macro did not retain its source allegiance.")
		source_traitor = native_invocation.queued_source.classic_traitor
	var definition_ids: Dictionary = {}
	for classic_id: int in action.extra_code:
		if classic_id == 0:
			continue
		if _content.classic_records != null:
			# combatsetup.c records the physical Data MD row in monsternameid.
			definition_ids[classic_id] = true
			continue
		var definition := _content.combat.monster_by_classic_id_for_set(absi(classic_id), _game_state.monster_set)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 123 references unavailable monster %d." % classic_id)
		definition_ids[definition.classic_id] = true
	if _content.classic_records != null and not definition_ids.is_empty():
		for monster: MonsterState in _game_state.combat.roster.monsters():
			if monster.classic_route_id == MonsterState.UNKNOWN_CLASSIC_ROUTE_ID:
				return ScenarioRuntimeOperationResult.failed(&"missing_monster_route_identity", "Classic opcode 123 requires the actor's recorded native routing identity.")
	var routed: Array[String] = []
	for monster: MonsterState in _game_state.combat.roster.monsters():
		var routed_definition := _content.combat.monster_by_id(monster.definition_id)
		var route_id := monster.classic_route_id if _content.classic_records != null else routed_definition.classic_id if routed_definition != null else MonsterState.UNKNOWN_CLASSIC_ROUTE_ID
		if monster.current_health > 0 and monster.classic_traitor == source_traitor and definition_ids.has(route_id):
			monster.conditions.set_value(ConditionRules.RUNS_AWAY, -1)
			monster.surrender_percent = 50
			routed.append(monster.id)
	return ScenarioRuntimeOperationResult.completed(routed.size(), [DomainEvent.new(&"combat_route_applied", {"count": routed.size(), "monsterIds": routed, "traitorSide": source_traitor, "source": "classic"})])


func _spawn_classic_monsters(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		if _content.package_schema_version >= 7:
			return ClassicCompatibility.skip(&"spawn-outside-battle", "Data EDCD", action.operand_id)
		return ScenarioRuntimeOperationResult.failed(&"no_active_battle", "Classic opcode 124 requires an active battle.")
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 124 requires a five-value Extra Code row.")
	if _content.package_schema_version >= 7 and _game_state.combat.roster.monsters().size() >= CombatFlowSummoning.MAX_MONSTERS:
		return ClassicCompatibility.skip(&"spawn-capacity-reached", "Data EDCD", action.operand_id)
	var native_id := action.extra_code[1] if _content.package_schema_version >= 7 else absi(action.extra_code[1])
	var definition := _content.combat.monster_by_classic_id_for_set(native_id, _game_state.monster_set)
	if definition == null:
		var native_path := "Data MD" + (str(_game_state.monster_set) if _game_state.monster_set != 0 else "")
		if ClassicCompatibility.source_unavailable(_content, native_path, native_id):
			return ClassicCompatibility.skip(&"unavailable-spawn-monster", native_path, native_id)
		return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Classic opcode 124 references unavailable monster %d." % action.extra_code[1])
	var consumption := MonsterConsumptionProbe.inspect(_content, definition)
	if consumption.outcome == MonsterConsumptionProbe.Outcome.PACKAGE_DEFECT:
		return ScenarioRuntimeOperationResult.failed(&"missing_monster_dependency", consumption.reason)
	if consumption.outcome == MonsterConsumptionProbe.Outcome.AUTHORED_UNSAFE:
		return ClassicCompatibility.skip(&"unsafe-spawn-record", "Data MD", native_id)
	var table_error := MonsterRules.random_weapon_table_error(definition)
	if not table_error.is_empty(): return ScenarioRuntimeOperationResult.failed(&"invalid_random_weapon_table", "Classic opcode 124: %s" % table_error)
	var battlefield := _game_state.combat.battlefield
	var map := _content.world.map_by_id(battlefield.map_id) if battlefield != null else null
	var terrain_set := _content.world.battle_terrain_set_for_map(map, _game_state.world) if map != null else null
	if battlefield == null or terrain_set == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_battlefield", "Classic opcode 124 cannot place its monster without the active battlefield terrain.")
	var source_coordinate := _classic_spawn_source_coordinate(context)
	if not BattlefieldGrid.contains(source_coordinate):
		return ScenarioRuntimeOperationResult.failed(&"missing_spawn_source", "Classic opcode 124 cannot resolve the combatant position used to place its monster.")
	var authored_count := action.extra_code[2]
	var count := _rng.draw(absi(authored_count), &"classic.combat.spawn-count") if authored_count < 0 else authored_count
	if _content.package_schema_version >= 7:
		# Castle checks nummon < maxmon before rolling a random spawn count and per insertion.
		count = mini(count, maxi(0, CombatFlowSummoning.MAX_MONSTERS - _game_state.combat.roster.monsters().size()))
	var spawned: Array[String] = []
	var coordinates: Array[Vector2i] = []
	var traitor_override := _classic_spawn_traitor_override(action, context)
	var builder := BattlefieldBuilder.new()
	for _index: int in maxi(0, count):
		var monster := _build_classic_spawn(definition, traitor_override, native_id)
		if monster == null:
			continue
		var desired_local := source_coordinate - battlefield.party_anchor
		var coordinate := builder.find_monster_position(battlefield, terrain_set, desired_local, definition.size)
		if coordinate.x < 0 or not battlefield.actors.place_monster(monster.id, coordinate, definition.size):
			continue
		if not _game_state.combat.roster.add_monster(monster):
			battlefield.actors.remove_monster(monster.id)
			continue
		_game_state.combat.append_turn_actor(monster.id)
		spawned.append(monster.id)
		coordinates.append(coordinate)
	var events: Array[DomainEvent] = []
	if action.extra_code[3] != 0 and not spawned.is_empty():
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(action.extra_code[3]), "waitForCompletion": action.extra_code[3] < 0, "source": "classic"}))
	events.append(DomainEvent.new(&"combat_monsters_spawned", {"monsterId": definition.id, "instanceIds": spawned, "coordinates": coordinates, "requestedCount": maxi(0, count), "soundId": action.extra_code[3], "source": "classic"}))
	return ScenarioRuntimeOperationResult.completed(spawned, events)


func _build_classic_spawn(definition: MonsterDefinition, traitor_override: int, native_id: int) -> MonsterState:
	var monster := _rules.monsters.build_monster(definition, _game_state.next_instance_id("combat.spawn"), traitor_override, _game_state.difficulty, _game_state.clock.day(), _rng)
	if monster != null:
		if traitor_override != MonsterState.UNKNOWN_CLASSIC_ROUTE_ID:
			monster.classic_traitor = traitor_override
		if _content.package_schema_version >= 7:
			monster.classic_route_id = native_id
	return monster


func _classic_spawn_source_coordinate(context: ScenarioExecutionContext) -> Vector2i:
	var battlefield := _game_state.combat.battlefield
	if native_invocation != null and native_invocation.queued_source != null:
		var captured := native_invocation.queued_source
		return captured.position if captured.available and captured.has_position else Vector2i(-1,-1)
	var source := _macro_monster(context)
	if source != null and battlefield.actors.has_actor(source.id):
		return battlefield.actors.actor_position(source.id)
	return Vector2i(-1, -1)


func _classic_spawn_traitor_override(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> int:
	if action.extra_code[4] != 0:
		return action.extra_code[4]
	if native_invocation != null and native_invocation.queued_source != null: return native_invocation.queued_source.classic_traitor
	if native_state != null and native_state.battle_macro_active: return MonsterState.UNKNOWN_CLASSIC_ROUTE_ID
	var source := _macro_monster(context)
	if source != null: return source.classic_traitor
	return MonsterState.UNKNOWN_CLASSIC_ROUTE_ID


func _macro_monster(context: ScenarioExecutionContext, use_queue: bool = true) -> MonsterState:
	var monsters := _game_state.combat.roster.monsters()
	if native_invocation != null and native_invocation.queued_source != null and not native_invocation.queued_source.available: return null
	if native_state != null and not (use_queue and native_invocation != null and native_invocation.queued_source != null):
		return monsters[native_state.macro_monster_index] if native_state.macro_monster_index >= 0 and native_state.macro_monster_index < monsters.size() else null
	if context != null and not context.combatant_id.is_empty(): return _game_state.combat.roster.monster_by_id(context.combatant_id)
	return monsters[0] if not monsters.is_empty() else null


func _branch_battle_round_macro(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"battle_macro_outside_combat", "Classic opcode 126 requires an active battle macro.")
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 126 requires a five-value Extra Code row.")
	var combat := _game_state.combat
	if combat.macro_id > 0:
		return ScenarioRuntimeOperationResult.completed(false, [], ScenarioVmDirective.native_return(0))
	var mode := action.extra_code[0]
	var matched := false
	match mode:
		0:
			matched = combat.turns.round_number - 1 == action.extra_code[1]
		1:
			matched = _rng.draw(100, &"classic.battle-round-macro-percent") <= action.extra_code[1]
		_:
			# Castle tests only modes zero and one; other modes branch unconditionally.
			matched = true
	if not matched:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"battle_macro_tested", {"matched": false, "mode": mode, "round": combat.turns.round_number, "source": "classic"})], ScenarioVmDirective.native_return(0))
	if action.extra_code[2] != 1:
		combat.macro_id = 0
	var target_id := action.extra_code[3]
	if action.extra_code[2] == 2:
		target_id = _rng.draw_between_classic(action.extra_code[3], action.extra_code[4], &"classic.battle-round-macro-target") if _content.package_schema_version >= 7 else _rng.draw_between(action.extra_code[3], action.extra_code[4], &"classic.battle-round-macro-target")
	if target_id <= 0 and _content.package_schema_version < 7:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_macro_target", "Classic opcode 126 references an invalid Extra Action Point target.")
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"battle_macro_tested", {"matched": true, "mode": mode, "round": combat.turns.round_number, "targetId": target_id, "repeating": action.extra_code[2] == 1, "source": "classic"})], ScenarioVmDirective.branch_xap(target_id, false))


func _continue_if_monster_present(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if _game_state.combat == null or _game_state.combat.completed:
		if _content.package_schema_version >= 7:
			return ScenarioRuntimeOperationResult.completed(false, [], ScenarioVmDirective.native_return(0))
		return ScenarioRuntimeOperationResult.failed(&"monster_test_outside_combat", "Classic opcode 127 requires an active battle macro.")
	var present := false
	for monster: MonsterState in _game_state.combat.roster.monsters():
		var present_definition := _content.combat.monster_by_id(monster.definition_id)
		var native_name := present_definition.classic_name_id if present_definition != null and _content.classic_records != null else present_definition.classic_id if present_definition != null else -1
		if present_definition != null and native_name == action.operand_id and monster.current_health > 0:
			present = true
			break
	var directive: ScenarioVmDirective = null if present else ScenarioVmDirective.native_return(0)
	return ScenarioRuntimeOperationResult.completed(present, [DomainEvent.new(&"battle_monster_presence_checked", {"classicMonsterId": action.operand_id, "present": present, "source": "classic"})], directive)
