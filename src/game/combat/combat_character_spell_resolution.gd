## Resolves and commits character-cast multi-target combat magic.
class_name CombatCharacterSpellResolution
extends RefCounted

const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var _context: CombatContext
var _selection: CombatSpellSelection


func _init(context: CombatContext, selection: CombatSpellSelection) -> void:
	_context = context
	_selection = selection


func ray_selections(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition) -> Array[SpellTargetSelection]:
	var result: Array[SpellTargetSelection] = []
	for actor_id: String in ray_actor_ids(state, content, caster_id, target_id, spell):
		var selection := _selection.spell_target_selection(state, content, actor_id)
		if selection != null:
			result.append(selection)
	return result


func ray_actor_ids(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition) -> Array[String]:
	var result: Array[String] = []
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null or not state.combat.battlefield.actors.has_actor(target_id):
		return result
	var stop_at_blocker := spell.range_min + spell.range_max > 0
	return _context.battlefield.ray_actor_ids(state.combat.battlefield, terrain_set, caster_id, state.combat.battlefield.actors.actor_position(target_id), stop_at_blocker)


func group_targets(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, selected_ids: Dictionary = {}, area_target: bool = false, missing_definition_message: String = "A scroll target has no immutable monster definition.") -> Dictionary:
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if character.current_health <= 0 or not state.combat.battlefield.actors.has_actor(character.id):
			continue
		if area_target:
			if not selected_ids.has(character.id):
				continue
			if character.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
				return {"ok": false, "errorCode": &"area_spell_reflection_unresolved", "error": "This area intersects a spell-reflecting character; Classic reflection targeting remains unresolved."}
		elif not _selection.group_target_matches(spell.target_type, character.traitor, caster.traitor):
			continue
		character_targets.append(character)
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(monster.id):
			continue
		if area_target:
			if not selected_ids.has(monster.id):
				continue
			if monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
				return {"ok": false, "errorCode": &"area_spell_reflection_unresolved", "error": "This area intersects a spell-reflecting monster; Classic reflection targeting remains unresolved."}
			if monster.magic_resistance > 100:
				continue
		elif not _selection.group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition == null:
			return {"ok": false, "errorCode": &"spell_target_unavailable", "error": missing_definition_message}
		monster_targets.append(monster)
		monster_definitions.append(definition)
	return {"ok": true, "characters": character_targets, "monsters": monster_targets, "definitions": monster_definitions}


func cast_group(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> CombatFlowResult:
	var targets := group_targets(state, content, caster, spell, {}, false, "A group spell target has no immutable monster definition.")
	if not bool(targets.get("ok", false)):
		return CombatFlowResult.failed(targets.get("errorCode", &"spell_target_unavailable"), String(targets.get("error", "A group spell target is unavailable.")))
	var group := _context.magic.resolve_character_group_spell(caster, targets.get("characters", []), targets.get("monsters", []), targets.get("definitions", []), spell, power_level, cast_level, rng, false, true, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if group == null or not group.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The group spell could not be cast with the available spell points.")
	return commit(state, content, caster, spell, power_level, cast_level, group, rng)


func cast_area(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, center: Vector2i, rotation: int) -> CombatFlowResult:
	var combat := state.combat
	var shape := _context.spell_areas.shape_for(spell, power_level, rotation)
	var persistent_field: RefCounted = _context.fields().queue_persistent_field(combat, caster.id, spell, power_level, cast_level, rng, center, rotation, shape)
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _context.spell_areas.pattern(shape):
		var actor_id := combat.battlefield.actors.actor_at(center + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var targets := group_targets(state, content, caster, spell, selected_ids, true, "An area spell target has no immutable monster definition.")
	if not bool(targets.get("ok", false)):
		return CombatFlowResult.failed(targets.get("errorCode", &"spell_target_unavailable"), String(targets.get("error", "An area spell target is unavailable.")))
	_context.actions().prepare_character_turn(combat, caster)
	var area := _context.magic.resolve_character_group_spell(caster, targets.get("characters", []), targets.get("monsters", []), targets.get("definitions", []), spell, power_level, cast_level, rng, true, true, MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day()))
	if area == null or not area.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The area spell could not be cast with the available spell points.")
	return commit(state, content, caster, spell, power_level, cast_level, area, rng, center, shape, "classic", "", true, [persistent_field])


func commit(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, group: GroupSpellResolution, rng: RealmzRng, center: Vector2i = INVALID_COORDINATE, shape: int = 0, event_source: String = "classic", item_instance_id: String = "", count_spell_cast: bool = true, persistent_fields: Array = []) -> CombatFlowResult:
	var combat := state.combat
	if count_spell_cast:
		combat.turns.active_turn.spell_cast_count += 1
		caster.lifetime_record.record_spell_cast()
	caster.attacks_remaining = _context.arithmetic.signed_16(caster.attacks_remaining - 2)
	caster.movement = maxi(0, caster.movement - 12)
	var events: Array[DomainEvent] = []
	_context.fields().append_created_events(events, persistent_fields, event_source)
	CombatSpellEventBuilder.append_sound(events, spell.sound_start, "classic-combat-spell-start")
	CombatSpellEventBuilder.append_cast(events, caster.id, spell, group, center, shape, event_source)
	if spell.target_type == 7:
		var party_condition := absi(spell.special)
		state.party.conditions.set_value(party_condition, maxi(state.party.conditions.value(party_condition), group.duration))
		events.append(DomainEvent.new(&"combat_spell_resolved", {"actorId": caster.id, "targetKind": "party", "spellId": spell.id, "targetType": spell.target_type, "power": power_level, "classicTier": cast_level, "duration": group.duration, "partyCondition": party_condition, "partyConditionValue": state.party.conditions.value(party_condition), "source": event_source}))
	for index: int in group.resolutions.size():
		_append_resolution(state, content, caster, spell, power_level, cast_level, group, index, center, shape, event_source, item_instance_id, events)
	var advances_turn = not _context.actions().character_can_continue(caster)
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		if not combat.spell_runtime.begin_death_macro_sequence(caster.id, advances_turn) or not _context.actions().events().request_next_spell_death_macro(combat, content, events):
			return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The multi-target spell death-macro queue could not retain its caster and source order.")
		return CombatFlowResult.succeeded(events)
	if advances_turn:
		_context.rounds().advance_turn(state, content, rng, events)
	if _context.rounds().finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_context.automation().process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


func _append_resolution(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, group: GroupSpellResolution, index: int, center: Vector2i, shape: int, event_source: String, item_instance_id: String, events: Array[DomainEvent]) -> void:
	var resolution := group.resolutions[index]
	var resolved_target_id := group.target_ids[index]
	var selected_target_id := group.selected_target_ids[index]
	var target_kind := group.target_kinds[index]
	var reflected := group.reflected_targets[index]
	if target_kind == &"monster":
		var missile_spell := absi(spell.spell_class) == 9
		caster.lifetime_record.add_spell_damage(resolution.damage, missile_spell and not resolution.resisted, missile_spell and resolution.resisted, resolution.target_defeated)
	if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
		state.combat.actor_statuses.mark_attacked(resolved_target_id)
	CombatSpellEventBuilder.append_projectile(events, caster.id, resolved_target_id, spell, event_source)
	if resolution.special_result == &"turned":
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 630, "waitForCompletion": false, "source": "classic-combat-destroy-turn-undead"}))
	CombatSpellEventBuilder.append_sound(events, spell.sound_end, "classic-combat-spell-result")
	var payload := _resolution_payload(caster, spell, power_level, cast_level, resolution, resolved_target_id, selected_target_id, target_kind, reflected, event_source)
	CombatSpellEventBuilder.append_resolution_effect(payload, spell, index, group.resolutions.size(), resolution.target_defeated)
	if not item_instance_id.is_empty():
		payload["itemInstanceId"] = item_instance_id
	if shape > 0:
		payload["areaCenter"] = [center.x, center.y]
		payload["areaShape"] = shape
	events.append(DomainEvent.new(&"combat_spell_resolved", payload))
	if resolution.target_defeated:
		_remove_defeated_target(state, content, resolved_target_id, target_kind)


static func _resolution_payload(caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, resolution: SpellResolution, resolved_target_id: String, selected_target_id: String, target_kind: StringName, reflected: bool, event_source: String) -> Dictionary:
	var payload := {"actorId": caster.id, "targetId": resolved_target_id, "selectedTargetId": selected_target_id, "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": power_level, "classicTier": cast_level, "reflected": reflected, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": event_source, "clearedConditionCount": resolution.cleared_condition_count, "detectedMagicItemCount": resolution.detected_magic_item_count}
	if resolution.spell_point_delta != 0 or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell):
		payload["spellPointDelta"] = resolution.spell_point_delta
	if resolution.cleared_condition >= 0:
		payload["clearedCondition"] = resolution.cleared_condition
	if not resolution.unequipped_item_ids.is_empty():
		payload["unequippedItemIds"] = resolution.unequipped_item_ids.duplicate()
	if resolution.applied_condition >= 0:
		payload["appliedCondition"] = resolution.applied_condition
	if not resolution.transformed_definition_after.is_empty():
		payload["transformedDefinitionBefore"] = resolution.transformed_definition_before
		payload["transformedDefinitionAfter"] = resolution.transformed_definition_after
	if not resolution.special_result.is_empty():
		payload["specialResult"] = String(resolution.special_result)
		payload["specialRoll"] = resolution.special_roll
		payload["specialThreshold"] = resolution.special_threshold
	if resolution.allegiance_changed:
		payload["traitorBefore"] = resolution.target_traitor_before
		payload["traitorAfter"] = resolution.target_traitor_after
	return payload


func _remove_defeated_target(state: GameState, content: RealmzContent, target_id: String, target_kind: StringName) -> void:
	if target_kind == &"character":
		_context.actions().mark_character_bleeding(state, state.party.character_by_id(target_id), true)
		_context.automation().remove_defeated_position(state.combat, target_id, true)
		return
	var defeated_monster := state.combat.roster.monster_by_id(target_id)
	var defeated_definition := content.combat.monster_by_id(defeated_monster.definition_id) if defeated_monster != null else null
	var queued = _context.actions().events().queue_spell_death_macro(state.combat, defeated_monster, defeated_definition)
	_context.automation().remove_defeated_position(state.combat, target_id, not queued)
