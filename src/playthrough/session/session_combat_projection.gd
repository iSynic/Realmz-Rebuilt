## Reuses noncombat records across a single ordinary party combat step.
class_name SessionCombatProjection
extends RefCounted


static func can_reuse(previous: GameView, context: SessionWorkflowContext, pending: InteractionRequest, events: Array[DomainEvent]) -> bool:
	var combat := context.state.combat
	if previous == null or previous.combat_view == null or combat == null or events.is_empty(): return false
	if combat.battle_id != previous.combat_view.battle_id or combat.turns.round_number != previous.combat_view.round_number: return false
	if combat.turns.active_actor_id() != previous.combat_view.active_actor_id or combat.outcome != &"active": return false
	if context.state.party.character_by_id(combat.turns.active_actor_id()) == null: return false
	if (pending == null) != (previous.pending_interaction == null): return false
	if pending != null and (pending.kind != InteractionRequest.COMBAT or previous.pending_interaction.kind != InteractionRequest.COMBAT): return false
	var moves := 0
	for event: DomainEvent in events:
		if event.kind == &"combatant_moved":
			if event.payload.has("source") or bool(event.payload.get("automatic", true)) or String(event.payload.get("actorId", "")) != combat.turns.active_actor_id(): return false
			moves += 1
		elif event.kind != &"sound_requested" or String(event.payload.get("source", "")) != "classic-battle-movement":
			return false
	return moves == 1


static func project(previous: GameView, context: SessionWorkflowContext, pending: InteractionRequest, revision: int, combat: CombatView) -> GameView:
	var members: Array[CharacterView] = []
	for member: CharacterView in previous.party_members:
		if member.id != combat.active_actor_id:
			members.append(member)
			continue
		var character := context.state.party.character_by_id(member.id)
		var replacement := CharacterView.new(character, context.content, member)
		replacement.apply_equipment(context.rules.equipment.combat_equipment(character, context.content.items.definitions()))
		members.append(replacement)
	var result := GameView.new(revision, true, pending, previous.party_map_id, previous.party_coordinate, previous.realmz_day, previous.realmz_hour, previous.realmz_minute, previous.map_view, members, previous.party_fatigue, previous.pooled_gold, combat)
	_copy_shell(previous, result)
	var changed := {combat.active_actor_id: true}
	SessionActionViewProjector.populate_inventory_item_actions(context, result, changed)
	SessionActionViewProjector.populate_spell_actions(context, result, changed)
	SessionActionViewProjector.populate_action_availability(context, result)
	return result


static func _copy_shell(previous: GameView, result: GameView) -> void:
	result.party_allies = previous.party_allies
	result.bestiary_entries = previous.bestiary_entries
	result.character_spellcasting_blocked = previous.character_spellcasting_blocked
	result.campaign_id = previous.campaign_id
	result.rules_version = previous.rules_version
	result.party_setup_available = previous.party_setup_available
	result.character_draft = previous.character_draft
	result.character_draft_spell_options = previous.character_draft_spell_options
	result.character_draft_spell_points_total = previous.character_draft_spell_points_total
	result.character_draft_spell_points_remaining = previous.character_draft_spell_points_remaining
	result.race_options = previous.race_options
	result.caste_options = previous.caste_options
	result.portrait_options = previous.portrait_options
	result.combat_icon_options = previous.combat_icon_options
	result.campaign_summary = previous.campaign_summary
	result.party_setup = previous.party_setup
	result.party_summary = previous.party_summary
	result.journal_entries = previous.journal_entries
	result.acquired_player_maps = previous.acquired_player_maps
	result.player_map_menu_entries = previous.player_map_menu_entries
	result.location_notes = previous.location_notes
	result.current_location_note = previous.current_location_note
	result.services = previous.services
	result.money_workspace = previous.money_workspace
