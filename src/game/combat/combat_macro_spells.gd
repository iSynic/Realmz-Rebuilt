## Resolves source-anchored scenario spells without spending or advancing an activation.
class_name CombatMacroSpells
extends RefCounted

const SOURCE := "classic-monster-macro"
var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func cast(state: GameState, content: RealmzContent, source_id: String, authored_spell: SpellDefinition, power: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or not combat.battlefield.actors.has_actor(source_id) or power < 1:
		return CombatFlowResult.failed(&"invalid_macro_spell_source", "A monster macro spell requires its retained battlefield source.")
	var spell := authored_spell.with_scenario_adjustments(extra_save_adjust, force_affect)
	if not _supports_spell(spell):
		if spell != null and spell.target_type == 1:
			return CombatFlowResult.failed(&"unsupported_macro_single_target", "Single-target monster macros require separate adjudication due to Classic coordinate-target aliasing.")
		if spell != null and spell.target_type == 6:
			return CombatFlowResult.failed(&"unsupported_macro_ray", "Ray monster macros require separate adjudication due to Classic ray traversal bypass.")
		return CombatFlowResult.failed(&"unsupported_macro_spell", "Monster macros require an area, side-group, or repeated-target combat spell.")
	var center := combat.battlefield.actors.actor_position(source_id)
	var shape := _context.spell_areas.shape_for(spell, power) if spell.target_type in [3, 4] else 0
	if spell.target_type in [3, 4] and _context.spell_areas.pattern(shape).is_empty():
		return CombatFlowResult.failed(&"invalid_spell_area_shape", "The monster macro references an unavailable Classic area mask.")
	var persistent_field: RefCounted = null
	if spell.queue_icon != 0:
		persistent_field = _context.fields().queue_persistent_field(combat, source_id, spell, power, spell.classic_tier(), rng, center, 0, shape)
		if persistent_field == null:
			return CombatFlowResult.failed(&"persistent_field_queue_failed", "The monster macro field could not be queued.")
	var selections := _targets(state, content, source_id, spell, center, shape, power, rng)
	var group := _resolve(state, content, selections, spell, power, rng, source_id)
	if group == null or not group.cast:
		return CombatFlowResult.failed(&"invalid_macro_spell_effect", "The monster macro spell could not resolve its battlefield targets.")
	var events: Array[DomainEvent] = []
	_context.fields().append_created_events(events, [persistent_field] if persistent_field != null else [], SOURCE)
	CombatSpellEventBuilder.append_sound(events, spell.sound_start, "classic-monster-macro-start")
	CombatSpellEventBuilder.append_cast(events, source_id, spell, group, center, shape, SOURCE)
	for index: int in group.resolutions.size():
		_append_result(state, content, source_id, spell, power, group, index, center, shape, events)
	return CombatFlowResult.succeeded(events)


static func _supports_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.target_type in [0, 3, 4, 9, 10, 12] and (spell.queue_icon == 0 or spell.target_type in [3, 4])


func _targets(state: GameState, content: RealmzContent, source_id: String, spell: SpellDefinition, center: Vector2i, shape: int, power: int, rng: RealmzRng) -> Array[SpellTargetSelection]:
	if spell.target_type == 0:
		return _repeated_targets(state, content, source_id, spell, power)
	var selected: Dictionary = {}
	for offset: Vector2i in _context.spell_areas.pattern(shape):
		var actor_id := state.combat.battlefield.actors.actor_at(center + offset)
		var character := state.party.character_by_id(actor_id)
		var monster := state.combat.roster.monster_by_id(actor_id)
		if character != null and character.current_health > 0:
			_select_area_actor(state, spell, actor_id, character.conditions, selected, rng)
		elif monster != null and monster.current_health > 0:
			if not _select_area_actor(state, spell, actor_id, monster.conditions, selected, rng) and monster.magic_resistance > 100:
				selected.erase(actor_id)
	var result: Array[SpellTargetSelection] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id) and _selected(character.id, character.traitor, spell.target_type, selected):
			result.append(SpellTargetSelection.for_character(character))
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health <= 0 or monster.magic_resistance > 100 or not state.combat.battlefield.actors.has_actor(monster.id) or not _selected(monster.id, monster.traitor, spell.target_type, selected):
			continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition != null:
			result.append(SpellTargetSelection.for_monster(monster, definition))
	return result


func _repeated_targets(state: GameState, content: RealmzContent, source_id: String, spell: SpellDefinition, power: int) -> Array[SpellTargetSelection]:
	var max_targets := spell.fixed_target_count if spell.fixed_target_count > 0 else power
	var source_monster := state.combat.roster.monster_by_id(source_id)
	var source_traitor := source_monster.traitor if source_monster != null else false
	var friendly_only := spell.cannot == 4
	var result: Array[SpellTargetSelection] = []
	for character: CharacterState in state.party.characters():
		if result.size() >= max_targets:
			break
		if character.current_health <= 0 or not state.combat.battlefield.actors.has_actor(character.id) or character.id == source_id:
			continue
		var is_friendly := character.traitor == source_traitor
		if (friendly_only and not is_friendly) or (not friendly_only and is_friendly):
			continue
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, source_id, character.id, spell, power):
			continue
		result.append(SpellTargetSelection.for_character(character))
	for candidate_monster: MonsterState in state.combat.roster.monsters():
		if result.size() >= max_targets:
			break
		if candidate_monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(candidate_monster.id) or candidate_monster.id == source_id:
			continue
		if candidate_monster.magic_resistance > 100:
			continue
		var is_friendly := candidate_monster.traitor == source_traitor
		if (friendly_only and not is_friendly) or (not friendly_only and is_friendly):
			continue
		if not _context.magic_flow().selection().spell_actor_target_is_valid(state, content, source_id, candidate_monster.id, spell, power):
			continue
		var definition := content.combat.monster_by_id(candidate_monster.definition_id)
		if definition != null:
			result.append(SpellTargetSelection.for_monster(candidate_monster, definition))
	return result


static func _select_area_actor(state: GameState, spell: SpellDefinition, actor_id: String, conditions: ConditionSet, selected: Dictionary, rng: RealmzRng) -> bool:
	var reflected := spell.spell_class != 9 and conditions.is_active(ConditionRules.REFLECTING_SPELLS) and rng.draw(100, &"combat.macro-spell.reflect") < 34
	selected[state.combat.turns.active_actor_id() if reflected else actor_id] = true
	return reflected


static func _selected(actor_id: String, traitor: bool, target_type: int, area_ids: Dictionary) -> bool:
	match target_type:
		9: return not traitor
		10: return traitor
		12: return true
	return area_ids.has(actor_id)


func _resolve(state: GameState, content: RealmzContent, selections: Array[SpellTargetSelection], spell: SpellDefinition, power: int, rng: RealmzRng, source_id: String) -> GroupSpellResolution:
	# Castle retains q[up] as the resistance caster while data supplies the macro center.
	var actor_id := state.combat.turns.active_actor_id()
	var character := state.party.character_by_id(actor_id)
	var polymorph := MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day())
	if character != null:
		if spell.target_type == 0:
			return _context.magic.resolve_character_repeated_spell(character, selections, spell, power, spell.classic_tier(), rng, false, Callable(), content.items.definitions(), true)
		var characters: Array[CharacterState] = []
		var monsters: Array[MonsterState] = []
		var definitions: Array[MonsterDefinition] = []
		for selection: SpellTargetSelection in selections:
			if selection.kind == &"character":
				characters.append(selection.character)
			else:
				monsters.append(selection.monster)
				definitions.append(selection.monster_definition)
		return _context.magic.resolve_character_group_spell(character, characters, monsters, definitions, spell, power, spell.classic_tier(), rng, true, false, polymorph)
	var monster := state.combat.roster.monster_by_id(actor_id)
	if monster == null and not source_id.is_empty():
		monster = state.combat.roster.monster_by_id(source_id)
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null else null
	if spell.target_type == 0:
		return _context.magic.resolve_monster_repeated_spell(monster, definition, selections, spell, power, spell.classic_tier(), rng, Callable(), false, true)
	return _context.magic.resolve_monster_group_spell(monster, definition, selections, spell, power, spell.classic_tier(), rng, true, false, polymorph)


func _append_result(state: GameState, content: RealmzContent, source_id: String, spell: SpellDefinition, power: int, group: GroupSpellResolution, index: int, center: Vector2i, shape: int, events: Array[DomainEvent]) -> void:
	var resolution := group.resolutions[index]
	var target_id := group.target_ids[index]
	var target_kind := group.target_kinds[index]
	if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
		state.combat.actor_statuses.mark_attacked(target_id)
	CombatSpellEventBuilder.append_projectile(events, source_id, target_id, spell, SOURCE)
	if resolution.special_result == &"turned":
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 630, "waitForCompletion": false, "source": "classic-combat-destroy-turn-undead"}))
	CombatSpellEventBuilder.append_sound(events, spell.sound_end, SOURCE)
	var payload := {"actorId": source_id, "targetId": target_id, "selectedTargetId": group.selected_target_ids[index], "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": power, "classicTier": spell.classic_tier(), "reflected": group.reflected_targets[index], "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": SOURCE, "areaCenter": [center.x, center.y], "areaShape": shape, "clearedConditionCount": resolution.cleared_condition_count, "detectedMagicItemCount": resolution.detected_magic_item_count}
	if resolution.cleared_condition >= 0:
		payload["clearedCondition"] = resolution.cleared_condition
	if not resolution.unequipped_item_ids.is_empty():
		payload["unequippedItemIds"] = resolution.unequipped_item_ids.duplicate()
	if resolution.applied_condition >= 0:
		payload["appliedCondition"] = resolution.applied_condition
	if resolution.spell_point_delta != 0 or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell):
		payload["spellPointDelta"] = resolution.spell_point_delta
	if resolution.allegiance_changed:
		payload["traitorBefore"] = resolution.target_traitor_before
		payload["traitorAfter"] = resolution.target_traitor_after
	if not resolution.transformed_definition_after.is_empty():
		payload["transformedDefinitionBefore"] = resolution.transformed_definition_before
		payload["transformedDefinitionAfter"] = resolution.transformed_definition_after
	if not resolution.special_result.is_empty():
		payload["specialResult"] = String(resolution.special_result)
		payload["specialRoll"] = resolution.special_roll
		payload["specialThreshold"] = resolution.special_threshold
	CombatSpellEventBuilder.append_resolution_effect(payload, spell, index, group.resolutions.size(), resolution.target_defeated)
	events.append(DomainEvent.new(&"combat_spell_resolved", payload))
	if not resolution.target_defeated:
		return
	if target_kind == &"character":
		_context.actions().mark_character_bleeding(state, state.party.character_by_id(target_id), true)
		_context.automation().remove_defeated_position(state.combat, target_id, true)
		return
	var defeated := state.combat.roster.monster_by_id(target_id)
	var definition := content.combat.monster_by_id(defeated.definition_id) if defeated != null else null
	var queued: bool = _context.actions().events().queue_spell_death_macro(state.combat, defeated, definition)
	_context.automation().remove_defeated_position(state.combat, target_id, not queued)
