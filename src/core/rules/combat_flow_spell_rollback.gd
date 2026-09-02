class_name CombatFlowSpellRollback
extends RefCounted


static func scroll(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"combat_scroll_rollback_failed", "Combat scroll resolution failed and its transaction could not be restored.")
	return CombatFlowResult.failed(error_code, error_message)


static func item(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"combat_item_rollback_failed", "Combat item resolution failed and its transaction could not be restored.")
	return CombatFlowResult.failed(error_code, error_message)


static func character_area(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"character_area_spell_rollback_failed", "Area spell resolution failed and its transaction could not be restored.")
	return CombatFlowResult.failed(error_code, error_message)


static func character_targeted(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	if state_checkpoint.is_empty() or rng_checkpoint.is_empty() or not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"character_targeted_spell_rollback_failed", "A self-centered spell failed and its transaction could not be restored.")
	return CombatFlowResult.failed(error_code, error_message)
