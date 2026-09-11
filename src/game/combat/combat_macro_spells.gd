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
	if not _supports_condition_spell(spell):
		return CombatFlowResult.failed(&"unsupported_macro_spell", "Monster macros currently support non-damaging area and side-group condition spells.")
	var center := combat.battlefield.actors.actor_position(source_id)
	var shape := _context.spell_areas.shape_for(spell, power) if spell.target_type in [3, 4] else 0
	if spell.target_type in [3, 4] and _context.spell_areas.pattern(shape).is_empty():
		return CombatFlowResult.failed(&"invalid_spell_area_shape", "The monster macro references an unavailable Classic area mask.")
	var selections := _targets(state, content, spell, center, shape, rng)
	var group := _resolve(state, content, selections, spell, power, rng)
	if group == null or not group.cast:
		return CombatFlowResult.failed(&"invalid_macro_spell_effect", "The monster macro spell could not resolve its battlefield targets.")
	var events: Array[DomainEvent] = []
	CombatSpellEventBuilder.append_cast(events, source_id, spell, group, center, shape, SOURCE)
	for index: int in group.resolutions.size():
		_append_result(source_id, spell, power, group, index, center, shape, events)
	return CombatFlowResult.succeeded(events)


static func _supports_condition_spell(spell: SpellDefinition) -> bool:
	return spell.target_type in [3, 4, 9, 10, 12] and spell.queue_icon == 0 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and absi(spell.special) not in [27, 28] and ClassicSpellConditionRules.is_combat_condition_effect_spell(spell)


func _targets(state: GameState, content: RealmzContent, spell: SpellDefinition, center: Vector2i, shape: int, rng: RealmzRng) -> Array[SpellTargetSelection]:
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


func _resolve(state: GameState, content: RealmzContent, selections: Array[SpellTargetSelection], spell: SpellDefinition, power: int, rng: RealmzRng) -> GroupSpellResolution:
	# Castle retains q[up] as the resistance caster while data supplies the macro center.
	var actor_id := state.combat.turns.active_actor_id()
	var character := state.party.character_by_id(actor_id)
	var polymorph := MonsterPolymorphContext.new(content, state.monster_set, state.difficulty, state.clock.day())
	if character != null:
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
	var definition := content.combat.monster_by_id(monster.definition_id) if monster != null else null
	return _context.magic.resolve_monster_group_spell(monster, definition, selections, spell, power, spell.classic_tier(), rng, true, false, polymorph)


static func _append_result(source_id: String, spell: SpellDefinition, power: int, group: GroupSpellResolution, index: int, center: Vector2i, shape: int, events: Array[DomainEvent]) -> void:
	var resolution := group.resolutions[index]
	var target_id := group.target_ids[index]
	var target_kind := group.target_kinds[index]
	CombatSpellEventBuilder.append_sound(events, spell.sound_end, SOURCE)
	var payload := {"actorId": source_id, "targetId": target_id, "selectedTargetId": group.selected_target_ids[index], "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": power, "classicTier": spell.classic_tier(), "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": SOURCE, "areaCenter": [center.x, center.y], "areaShape": shape}
	if resolution.applied_condition >= 0:
		payload["appliedCondition"] = resolution.applied_condition
	CombatSpellEventBuilder.append_resolution_effect(payload, spell, index, group.resolutions.size(), resolution.target_defeated)
	events.append(DomainEvent.new(&"combat_spell_resolved", payload))
