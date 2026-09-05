## Implements deterministic combat flow phase rules without presentation dependencies.

class_name CombatFlowPhase
extends RefCounted

const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func cast_character_phase(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, destination: Vector2i, spend_spell_points: bool = true, event_source: String = "classic", count_spell_cast: bool = true) -> CombatFlowResult:
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var result := _resolve_character_phase(state, content, caster, spell, power_level, cast_level, rng, destination, spend_spell_points, event_source, count_spell_cast)
	if result.ok:
		return result
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"character_phase_spell_rollback_failed", "Phase resolution failed and its transaction could not be restored.")
	return result


func checkpoint_available(combat: CombatState, caster_id: String) -> bool:
	var undo := combat.turns.undo_state if combat != null else null
	return undo != null and undo.available and undo.actor_id == caster_id and undo.round_number == combat.turns.round_number and undo.turn_index == combat.turns.turn_index


func probe_destination(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, destination: Vector2i) -> CombatSpellCastProbe:
	var combat := state.combat
	if destination == INVALID_COORDINATE:
		return CombatSpellCastProbe.blocked(&"invalid_spell_target", "Choose a battlefield destination for Phase.")
	if not checkpoint_available(combat, caster_id) and combat.turns.active_turn != null:
		return CombatSpellCastProbe.blocked(&"phase_checkpoint_unavailable", "Phase is available only while this activation can still be undone.")
	var map := content.world.map_by_id(combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	if terrain_set == null or not _context.battlefield.coordinate_target_is_valid(combat.battlefield, terrain_set, caster_id, destination, maximum_range, spell.range_min + spell.range_max > 0):
		return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The Phase destination is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func _resolve_character_phase(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, destination: Vector2i, spend_spell_points: bool, event_source: String, count_spell_cast: bool) -> CombatFlowResult:
	var combat := state.combat
	_context.actions().prepare_character_turn(combat, caster)
	if not checkpoint_available(combat, caster.id):
		return CombatFlowResult.failed(&"phase_checkpoint_unavailable", "Phase is available only while this activation can still be undone.")
	var phase := _context.magic.resolve_character_group_spell(caster, [], [], [], spell, power_level, cast_level, rng, true, spend_spell_points)
	if phase == null or not phase.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "Phase could not be cast with the available spell points.")
	if count_spell_cast:
		combat.turns.active_turn.spell_cast_count += 1
		caster.lifetime_record.record_spell_cast()
	caster.attacks_remaining = _context.arithmetic.signed_16(caster.attacks_remaining - 2)
	caster.movement = maxi(0, caster.movement - 12)
	combat.turns.invalidate_undo()
	var origin := combat.battlefield.actors.actor_position(caster.id)
	var collision_actor_id := combat.battlefield.actors.actor_at(destination, caster.id)
	var phased_into_solid := _destination_is_solid(state, content, combat, destination)
	var defeated := not collision_actor_id.is_empty() or phased_into_solid
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"sound_requested", {"soundId": 699, "waitForCompletion": false, "source": "classic-combat-phase-start"}),
		DomainEvent.new(&"combat_spell_cast", {"actorId": caster.id, "targetId": "", "spellId": spell.id, "spellName": spell.name, "classicEffectResourceId": 11_992 + spell.look_start * 8, "targetCoordinate": [destination.x, destination.y], "source": event_source}),
	]
	if defeated:
		caster.current_health = -10
		_context.actions().mark_character_bleeding(state, caster, true)
		_context.automation().remove_defeated_position(combat, caster.id, true)
	else:
		if not combat.battlefield.actors.move_actor(caster.id, destination):
			return CombatFlowResult.failed(&"phase_destination_unavailable", "The Phase destination could not receive the caster.")
		events.append(DomainEvent.new(&"combatant_moved", {"actorId": caster.id, "from": [origin.x, origin.y], "to": [destination.x, destination.y], "cost": 12, "movementRemaining": caster.movement, "automatic": false, "source": "classic-combat-phase"}))
		if spell.size == 0:
			caster.attacks_remaining = 0
		combat.actor_statuses.mark_attacked(caster.id)
	events.append(DomainEvent.new(&"sound_requested", {"soundId": 658, "waitForCompletion": false, "source": "classic-combat-phase-arrival"}))
	if defeated:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 631, "waitForCompletion": false, "source": "classic-combat-phase-death"}))
	events.append(DomainEvent.new(&"combat_spell_resolved", {"actorId": caster.id, "targetId": caster.id, "spellId": spell.id, "targetType": spell.target_type, "power": power_level, "classicTier": cast_level, "targetCoordinate": [destination.x, destination.y], "phased": true, "collisionActorId": collision_actor_id, "solidCollision": phased_into_solid, "defeated": defeated, "source": event_source}))
	var advances_turn: bool = not _context.actions().character_can_continue(caster)
	if advances_turn and not defeated:
		_context.rounds().advance_turn(state, content, rng, events)
	if _context.rounds().finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	if defeated and combat.turns.active_actor_id() == caster.id:
		_context.rounds().advance_turn(state, content, rng, events)
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


static func _destination_is_solid(state: GameState, content: RealmzContent, combat: CombatState, destination: Vector2i) -> bool:
	var map := content.world.map_by_id(combat.battlefield.map_id) if content != null and combat != null and combat.battlefield != null else null
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null and state != null else null
	var terrain := terrain_set.tile_by_id(combat.battlefield.terrain.tile_at(destination)) if terrain_set != null else null
	return terrain == null or terrain.solid != 0
