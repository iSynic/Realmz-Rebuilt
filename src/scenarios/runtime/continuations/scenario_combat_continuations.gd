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


static func friendly_collision(source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller, actor_id: String, destination: Vector2i) -> ScenarioRuntimeContinuation:
	assert(source_kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT, ScenarioRuntimeContinuation.SAFE_COMBAT])
	var kind := ScenarioRuntimeContinuation.SAFE_COMBAT_FRIENDLY_COLLISION if source_kind == ScenarioRuntimeContinuation.SAFE_COMBAT else ScenarioRuntimeContinuation.CLASSIC_COMBAT_FRIENDLY_COLLISION
	var body := _body(source_kind, battle_id, caller)
	body.actor_id = actor_id
	body.mode = &"friendly"
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


static func terminal(kind: StringName, source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeContinuation:
	assert(kind in [ScenarioRuntimeContinuation.CLASSIC_COMBAT_ALLY, ScenarioRuntimeContinuation.SAFE_COMBAT_ALLY, ScenarioRuntimeContinuation.CLASSIC_COMBAT_FUMBLE, ScenarioRuntimeContinuation.SAFE_COMBAT_FUMBLE])
	return ScenarioRuntimeContinuation.new(kind, _body(source_kind, battle_id, caller))


static func _body(source_kind: StringName, battle_id: String, caller: ScenarioBattleCaller) -> ScenarioCombatContinuationBody:
	var body := ScenarioCombatContinuationBody.new()
	body.source_kind = source_kind
	body.battle_id = battle_id
	body.caller = caller.copy()
	return body
