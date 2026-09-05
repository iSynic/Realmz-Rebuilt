## Creates combat-owned scenario runtime continuations.

class_name ScenarioCombatContinuations
extends RefCounted


static func battle(kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT])
	var body := _body(kind, battle_id, caller)
	return ScenarioRuntimeContinuation.new(kind, body)


static func retreat(kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, actor_id: String, mode: StringName, destination: Vector2i) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_RETREAT, ScenarioRuntimeContinuation.SAFE_COMBAT_RETREAT])
	var body := _body(source_kind, battle_id, caller)
	body.actor_id = actor_id
	body.mode = mode
	body.destination = destination
	return ScenarioRuntimeContinuation.new(kind, body)


static func age_updates(kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, updates: Array[AgeUpdateRequestBody], index: int, round_before: int) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_AGE, ScenarioRuntimeContinuation.SAFE_COMBAT_AGE])
	var body := _body(source_kind, battle_id, caller)
	for update: AgeUpdateRequestBody in updates:
		body.updates.append(ScenarioAgeContinuations.copy_update(update))
	body.index = index
	body.round_before = round_before
	return ScenarioRuntimeContinuation.new(kind, body)


static func macro(kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, program_id: String, macro_vm: ScenarioVmSnapshot, combatant_id: String = "", reset_traitor_on_complete: bool = true) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_MACRO, ScenarioRuntimeContinuation.CLASSIC_COMBAT_DEATH_MACRO, ScenarioRuntimeContinuation.SAFE_COMBAT_DEATH_MACRO])
	var body := _body(source_kind, battle_id, caller)
	body.program_id = program_id
	body.macro_vm = ScenarioVmSnapshot.from_data(macro_vm.to_data())
	body.combatant_id = combatant_id
	body.reset_traitor_on_complete = reset_traitor_on_complete
	return ScenarioRuntimeContinuation.new(kind, body)


static func opcode_death_macro(battle_id: String, combatant_id: String, program_id: String, remaining_combatant_ids: Array[String], macro_vm: ScenarioVmSnapshot) -> ScenarioRuntimeContinuation:
	var body := ScenarioOpcodeDeathContinuationBody.new()
	body.battle_id = battle_id
	body.combatant_id = combatant_id
	body.program_id = program_id
	body.remaining_combatant_ids.assign(remaining_combatant_ids)
	body.macro_vm = macro_vm
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_OPCODE_DEATH_MACRO, body)


static func terminal(kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE])
	return ScenarioRuntimeContinuation.new(kind, _body(source_kind, battle_id, caller))


static func _body(source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioCombatContinuationBody:
	var body := ScenarioCombatContinuationBody.new()
	body.source_kind = source_kind
	body.battle_id = battle_id
	body.caller = caller.copy()
	return body
