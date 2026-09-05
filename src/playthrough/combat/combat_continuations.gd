## Creates combat-owned session continuations.

class_name CombatContinuations
extends RefCounted


static func retreat_confirmation(body: CombatContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"combat-retreat-confirmation", body)


static func friendly_collision(body: CombatContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"combat-friendly-collision", body)


static func death_macro(body: CombatContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"combat-death-macro", body)


static func ally_selection(body: CombatContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"combat-ally-selection", body)


static func fumble_recovery(body: CombatContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"combat-fumble-recovery", body)


static func reward(battle_id: String, runtime_continuation: ScenarioRuntimeContinuation) -> SessionContinuation:
	var body := CombatRewardContinuationBody.new()
	body.battle_id = battle_id
	body.runtime_continuation = runtime_continuation.copy() if runtime_continuation != null else null
	return SessionContinuation.new(&"combat-reward", body)
