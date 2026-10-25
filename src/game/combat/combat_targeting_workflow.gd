## Commits manual spell sources before aiming and owns Castle's Abort action.
class_name CombatTargetingWorkflow
extends RefCounted

var _context: CombatContext
var _admission: CombatCastSourceAdmission


func _init(context: CombatContext) -> void:
	_context = context
	_admission = CombatCastSourceAdmission.new(context)


func respond(state: GameState, content: RealmzContent, body: InteractionResponse.CombatBody, rng: RealmzRng) -> CombatFlowResult:
	if not CombatCastResponsePolicy.allows(state, body): return blocked()
	if body.action not in [&"begin_spell", &"begin_scroll", &"begin_item", &"begin_projectile", &"adjust_cast", &"abort_cast"]: return null
	var selection := CombatCastSelection.from_body(body)
	if selection == null:
		return CombatFlowResult.rejected(&"invalid_cast_selection", "Combat targeting requires a valid source selection.")
	return command(state, content, body.action, selection, rng)


func command(state: GameState, content: RealmzContent, operation: StringName, selection: CombatCastSelection, _rng: RealmzRng) -> CombatFlowResult:
	if selection == null or not _active_character(state, selection.actor_id):
		return CombatFlowResult.rejected(&"invalid_cast_turn", "Only the active character may select combat targets.")
	var commitment := CombatCastResources.pending(state)
	if operation == &"abort_cast":
		if commitment == null: return blocked()
		if state.adventure_rules.free_targeting_cancellation:
			return _cancel_without_cost(state, content)
		CombatCastResources.abort(state)
		return CombatFlowResult.from_combat(state.combat, [])
	if operation == &"adjust_cast": return _adjust_power(state, content, selection)
	if commitment != null: return blocked()
	var expected := {&"begin_spell": &"cast_spell", &"begin_scroll": &"use_scroll", &"begin_item": &"use_item", &"begin_projectile": &"attack"}
	if not expected.has(operation) or not selection.is_valid() or selection.action != expected[operation]:
		return CombatFlowResult.rejected(&"invalid_cast_selection", "This combat targeting source is invalid.")
	var normalized := CombatCastSelection.from_data(selection.to_data())
	var probe := probe_source(state, content, normalized)
	if not probe.allowed: return probe.denial_result()
	var checkpoint := state.to_data()
	_context.actions().prepare_character_turn(state.combat, state.party.character_by_id(selection.actor_id))
	if state.adventure_rules.free_targeting_cancellation:
		state.combat.turns.clear_staged_random_item_power()
	if not CombatCastResources.reserve(state, content, normalized):
		if not state.restore_from_data(checkpoint): return CombatFlowResult.failed(&"cast_rollback_failed", "The failed combat reservation could not be restored.")
		return CombatFlowResult.failed(&"cast_reservation_failed", "The selected combat source could not be committed.")
	if not state.adventure_rules.free_targeting_cancellation:
		state.combat.turns.invalidate_undo()
	return CombatFlowResult.from_combat(state.combat, [])


## FD-COMBAT-022 is opt-in; Castle's default Abort arithmetic stays separate.
func _cancel_without_cost(state: GameState, content: RealmzContent) -> CombatFlowResult:
	if not commitment_is_valid(state, content):
		return CombatFlowResult.failed(&"cast_restoration_failed", "The reserved combat source no longer matches its pending action; targeting remains pending.")
	var checkpoint := state.to_data()
	if not CombatCastResources.release(state):
		if not state.restore_from_data(checkpoint):
			return CombatFlowResult.failed(&"cast_rollback_failed", "The failed cancellation could not restore its pending action.")
		return CombatFlowResult.failed(&"cast_restoration_failed", "The reserved combat source could not be restored; targeting remains pending.")
	state.combat.turns.clear_staged_random_item_power()
	return CombatFlowResult.from_combat(state.combat, [])


func probe_source(state: GameState, content: RealmzContent, selection: CombatCastSelection) -> CombatSpellCastProbe:
	match selection.action:
		&"cast_spell":
			var probe: CombatSpellCastProbe = _context.magic_flow().selection().probe_character_spell_choice(state, content, selection.actor_id, selection.spell_id, selection.power)
			return probe if not probe.allowed else _manual_target_probe(content.magic.spell_by_id(selection.spell_id))
		&"use_scroll":
			var probe := _admission.probe_scroll(state, content, selection.actor_id, selection.scroll_slot)
			if not probe.allowed: return probe
			var scroll := state.party.character_by_id(selection.actor_id).scroll_at(selection.scroll_slot)
			if scroll.spell_id != selection.spell_id or scroll.power != selection.power:
				return CombatSpellCastProbe.blocked(&"scroll_selection_changed", "The selected scroll has changed.")
			return _manual_target_probe(content.magic.spell_by_id(scroll.spell_id))
		&"use_item":
			var probe := _admission.probe_item(state, content, selection.actor_id, selection.item_instance_id)
			if not probe.allowed: return probe
			return _normalize_item(state, content, selection)
		&"attack":
			if state.combat.actor_statuses.character_weapon_mode(selection.actor_id) != &"missile":
				return CombatSpellCastProbe.blocked(&"missile_mode_required", "Select Fire Weapon before aiming a missile.")
			var caster := state.party.character_by_id(selection.actor_id)
			var profile: ProjectileAttackProfile = _context.reactions().character_projectile_profile(caster, content, null, state)
			if not profile.available: return CombatSpellCastProbe.blocked(profile.error_code, profile.error_message)
			var reason: String = _context.actions().projectile_spell_unavailable_reason(profile.spell)
			if not reason.is_empty(): return CombatSpellCastProbe.blocked(&"projectile_item_targeting_required", reason)
			selection.item_instance_id = profile.item_instance_id
			selection.spell_id = profile.spell.id
			selection.power = profile.power_level
			return CombatSpellCastProbe.permitted()
	return CombatSpellCastProbe.blocked(&"invalid_cast_selection", "This combat source is unavailable.")


func _normalize_item(state: GameState, content: RealmzContent, selection: CombatCastSelection) -> CombatSpellCastProbe:
	var caster := state.party.character_by_id(selection.actor_id)
	var instance: ItemInstance = _context.magic_flow().inventory_instance(caster, selection.item_instance_id)
	var item := content.items.item_by_id(instance.definition_id)
	var spell := content.magic.spell_by_classic_id(item.special_2)
	var power := state.combat.turns.staged_random_item_power(caster.id, instance.id) if absi(item.special_1) == 8 else absi(item.special_1)
	if power < 1 or power > 7:
		return CombatSpellCastProbe.blocked(&"random_item_power_not_staged", "Roll this item's power before choosing targets.")
	if not selection.spell_id.is_empty() and selection.spell_id != spell.id:
		return CombatSpellCastProbe.blocked(&"item_selection_changed", "The selected item spell has changed.")
	selection.spell_id = spell.id
	selection.power = power
	return _manual_target_probe(spell)


func _manual_target_probe(spell: SpellDefinition) -> CombatSpellCastProbe:
	if spell.target_type in [5, 7, 9, 10, 12] and not ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell):
		return CombatSpellCastProbe.blocked(&"automatic_cast_has_no_targeting", "This spell resolves immediately without choosing battlefield targets.")
	return CombatSpellCastProbe.permitted()


func _adjust_power(state: GameState, content: RealmzContent, selection: CombatCastSelection) -> CombatFlowResult:
	var commitment := CombatCastResources.pending(state)
	if commitment == null or commitment.selection.action != &"cast_spell" or not commitment.selection.same_source(selection): return blocked()
	var preview := CombatCastResources.preview(state)
	if preview == null: return CombatFlowResult.failed(&"invalid_cast_commitment", "The pending cast could not be reconstructed.")
	var probe := probe_source(preview, content, selection)
	if not probe.allowed: return probe.denial_result()
	var cost := absi(content.magic.spell_by_id(selection.spell_id).cost * selection.power)
	state.party.character_by_id(selection.actor_id).spell_points += commitment.spell_points_paid - cost
	commitment.spell_points_paid = cost
	commitment.selection.power = selection.power
	return CombatFlowResult.from_combat(state.combat, [])


func confirm(state: GameState, content: RealmzContent, body: InteractionResponse.CombatBody, rng: RealmzRng) -> CombatFlowResult:
	var commitment := CombatCastResources.pending(state)
	if commitment == null or not _matches(commitment.selection, body): return blocked()
	var checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	if not CombatCastResources.release(state):
		if not state.restore_from_data(checkpoint) or not rng.rollback(rng_checkpoint): return CombatFlowResult.failed(&"cast_rollback_failed", "The failed combat confirmation could not be restored.")
		return CombatFlowResult.failed(&"invalid_cast_commitment", "The pending combat source could not be reconstructed.")
	var result := _resolve(state, content, body, rng)
	if not result.ok and (not state.restore_from_data(checkpoint) or not rng.rollback(rng_checkpoint)):
		return CombatFlowResult.failed(&"cast_rollback_failed", "The pending combat cast could not be restored after a failed confirmation.")
	return result


func commitment_is_valid(state: GameState, content: RealmzContent) -> bool:
	var commitment := CombatCastResources.pending(state)
	if commitment == null: return true
	if not commitment.is_valid() or not _active_character(state, commitment.selection.actor_id): return false
	var preview := CombatCastResources.preview(state)
	if preview == null or GameState.from_data(preview.to_data()) == null: return false
	var selection := CombatCastSelection.from_data(commitment.selection.to_data())
	if not probe_source(preview, content, selection).allowed or selection.to_data() != commitment.selection.to_data(): return false
	if not CombatCastResources.reserve(preview, content, selection): return false
	return preview.to_data() == state.to_data()


func _matches(selection: CombatCastSelection, body: InteractionResponse.CombatBody) -> bool:
	if body.actor_id != selection.actor_id or body.action != selection.action: return false
	match body.action:
		&"cast_spell": return body.spell_id == selection.spell_id and body.power == selection.power
		&"use_scroll": return body.scroll_slot == selection.scroll_slot
		&"use_item": return body.item_instance_id == selection.item_instance_id
		&"attack": return true
	return false


func _resolve(state: GameState, content: RealmzContent, body: InteractionResponse.CombatBody, rng: RealmzRng) -> CombatFlowResult:
	var coordinate := body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE
	match body.action:
		&"cast_spell": return _context.magic_flow().cast_spell(state, content, body.actor_id, body.target_id, body.spell_id, body.power, rng, coordinate, body.rotation, body.target_ids, body.target_coordinates)
		&"use_scroll": return _context.magic_flow().use_combat_scroll(state, content, body.actor_id, body.scroll_slot, body.target_id, rng, coordinate, body.rotation, body.target_ids, body.target_coordinates)
		&"use_item": return _context.magic_flow().use_spell_item(state, content, body.actor_id, body.target_id, body.item_instance_id, rng, coordinate, body.rotation, body.target_ids, body.target_coordinates)
		&"attack": return _context.actions().submit_action(state, content, body.actor_id, &"attack", body.target_id, rng)
	return blocked()


func _active_character(state: GameState, actor_id: String) -> bool:
	if state == null or state.combat == null or state.combat.completed: return false
	var combat := state.combat
	var caster := state.party.character_by_id(actor_id)
	return combat.turns.active_actor_id() == actor_id and caster != null and caster.current_health > 0 and not caster.traitor and combat.battlefield != null and combat.battlefield.actors.has_actor(actor_id) and combat.pending_reaction == null and combat.pending_monster_attack == null and combat.death_macros.pending_id().is_empty()


static func blocked() -> CombatFlowResult:
	return CombatFlowResult.rejected(&"combat_targeting_pending", "Finish or abort the current combat targeting action first.")
