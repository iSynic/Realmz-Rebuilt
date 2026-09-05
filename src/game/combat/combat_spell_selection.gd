## Owns combat spell admission, target validation, and player-facing spell choices.
class_name CombatSpellSelection
extends RefCounted

const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var _context: CombatContext


func _init(context: CombatContext) -> void:
	_context = context


func probe_character_spell_choice(state: GameState, content: RealmzContent, caster_id: String, spell_id: String, power_level: int) -> CombatSpellCastProbe:
	var turn_probe := _probe_character_turn(state, content, caster_id)
	if not turn_probe.allowed:
		return turn_probe
	var combat := state.combat
	var caster := state.party.character_by_id(caster_id)
	var spell := content.magic.spell_by_id(spell_id)
	if caster == null or caster.current_health <= 0 or caster.traitor or spell == null or power_level < 1 or power_level > 7:
		return CombatSpellCastProbe.blocked(&"invalid_spell_target", "The spell, caster, or power is unavailable.")
	if not caster.known_spells().has(spell.id):
		return CombatSpellCastProbe.blocked(&"spell_not_known", "The caster does not know '%s'." % spell.id)
	var caster_probe := _probe_caster_casting(state, combat, caster)
	return caster_probe if not caster_probe.allowed else _probe_spell_rules(state, content, combat, caster, spell, power_level)


func _probe_character_turn(state: GameState, content: RealmzContent, caster_id: String) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_spell_turn", "Spell casting requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.turns.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_spell_turn", "The caster does not own an active combat turn.")
	if not combat.spell_runtime.pending_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	return CombatSpellCastProbe.permitted()


func _probe_caster_casting(state: GameState, combat: CombatState, caster: CharacterState) -> CombatSpellCastProbe:
	if state.character_spellcasting_blocked:
		return CombatSpellCastProbe.blocked(&"character_spellcasting_blocked", "Classic scenario state currently blocks character spellcasting.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if caster.conditions.is_active(condition):
			return CombatSpellCastProbe.blocked(&"spellcasting_condition_blocked", "The caster's current Classic condition prevents spellcasting.")
	if combat.actor_statuses.was_attacked(caster.id):
		return CombatSpellCastProbe.blocked(&"caster_attacked_this_round", "Castle prevents a character who has been attacked this combat round from casting.")
	var committed_casts := combat.turns.active_turn.spell_cast_count if combat.turns.active_turn != null else 0
	if caster.maximum_spell_attacks <= 0 or committed_casts >= caster.maximum_spell_attacks:
		return CombatSpellCastProbe.blocked(&"spell_attack_limit_reached", "The caster has reached the Classic per-activation spell limit.")
	return CombatSpellCastProbe.permitted()


func _probe_spell_rules(state: GameState, content: RealmzContent, combat: CombatState, caster: CharacterState, spell: SpellDefinition, power_level: int) -> CombatSpellCastProbe:
	if not spell.in_combat:
		return CombatSpellCastProbe.blocked(&"spell_not_available_in_combat", "The selected spell is not available in combat.")
	var repeated_target := spell.target_type == 0
	var area_target := spell.target_type in [3, 4]
	var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
	if ClassicSpellDispositionRules.combat_character_disposition(spell) != ClassicSpellDispositionRules.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_spell", ClassicSpellDispositionRules.unsupported_reason(spell, &"combat-character"))
	if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) and not combat.spell_runtime.can_queue_persistent_field():
		return CombatSpellCastProbe.blocked(&"persistent_field_queue_limit", "Castle's persistent battlefield-field queue is full.")
	if repeated_target and spell.size != 0 and not summon_spell:
		return CombatSpellCastProbe.blocked(&"repeated_open_space_spell_unresolved", "Classic target type 0 with nonzero size selects open-space footprints for summoning or special behavior, not ordinary actors.")
	if spell.cost < 0 and power_level != 1:
		return CombatSpellCastProbe.blocked(&"fixed_power_spell", "Castle fixes negative-cost spells at power one.")
	var spell_cost := absi(spell.cost * power_level)
	if caster.spell_points < spell_cost:
		return CombatSpellCastProbe.blocked(&"insufficient_spell_points", "The caster lacks the spell points for this power level.")
	var cast_level := spell.classic_tier()
	if cast_level < 0 or cast_level > 6:
		return CombatSpellCastProbe.blocked(&"invalid_classic_spell_tier", "The spell ID does not encode a valid Classic tier.")
	if area_target:
		var shape := _context.spell_areas.shape_for(spell, power_level)
		if _context.spell_areas.pattern(shape).is_empty():
			return CombatSpellCastProbe.blocked(&"invalid_spell_area_shape", "The spell references an unavailable Classic Data AD area mask.")
	return _context.summoning().probe_choice(state, content, caster.id, spell, power_level) if summon_spell else CombatSpellCastProbe.permitted()


func probe_character_spell_cast(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	var choice_probe := probe_character_spell_choice(state, content, caster_id, spell_id, power_level)
	if not choice_probe.allowed: return choice_probe
	var combat := state.combat
	var caster := state.party.character_by_id(caster_id)
	var spell := content.magic.spell_by_id(spell_id)
	var repeated_target := spell.target_type == 0
	var summon_spell: bool = CombatFlowSummoning.is_summon_spell(spell)
	var phase_spell := ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell)
	var group_target := spell.target_type in [9, 10, 12]
	var area_target := spell.target_type in [3, 4]
	if area_target and invalid_area_rotation(spell, rotation):
		return CombatSpellCastProbe.blocked(&"invalid_area_rotation", "This Classic area spell does not support the selected orientation.")
	if summon_spell: return _context.summoning().probe_coordinates(state, content, caster_id, spell, power_level, target_coordinates)
	if phase_spell: return _context.phase().probe_destination(state, content, caster_id, spell, power_level, target_coordinate)
	if repeated_target:
		if target_ids.size() > power_level:
			return CombatSpellCastProbe.blocked(&"too_many_spell_targets", "A repeated-target spell may select at most one distinct actor per power level.")
		var seen: Dictionary = {}
		for selected_id: String in target_ids:
			if selected_id.is_empty() or seen.has(selected_id):
				return CombatSpellCastProbe.blocked(&"invalid_repeated_spell_targets", "Repeated spell targets must be nonempty and distinct.")
			seen[selected_id] = true
			if spell_target_selection(state, content, selected_id) == null:
				return CombatSpellCastProbe.blocked(&"invalid_spell_target", "A selected repeated-spell actor is unavailable.")
			if not spell_actor_target_is_valid(state, content, caster.id, selected_id, spell, power_level):
				return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "A selected repeated-spell actor is outside the Classic spell range or line of sight.")
		if target_ids.is_empty() and character_actor_spell_candidates(state, content, caster, spell, power_level).is_empty():
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "No actor is available within this repeated spell's Classic range and line of sight.")
	elif area_target:
		var shape := _context.spell_areas.shape_for(spell, power_level, rotation)
		if target_coordinate == INVALID_COORDINATE:
			return CombatSpellCastProbe.blocked(&"invalid_spell_target", "Choose a battlefield center for this area spell.")
		if not _context.spell_areas.pattern_fits(target_coordinate, shape):
			return CombatSpellCastProbe.blocked(&"spell_area_outside_battlefield", "The complete Classic area mask must remain inside the validated battlefield.")
		var map := content.world.map_by_id(combat.battlefield.map_id)
		var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
		var maximum_range := absi(spell.range_min + spell.range_max * power_level)
		if terrain_set == null or not _context.battlefield.coordinate_target_is_valid(combat.battlefield, terrain_set, caster.id, target_coordinate, maximum_range, spell.range_min + spell.range_max > 0):
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The area center is outside the Classic spell range or line of sight.")
	elif not group_target:
		var effective_target_id := caster_id if spell.target_type in [5, 7] else target_id
		if spell_target_selection(state, content, effective_target_id) == null:
			return CombatSpellCastProbe.blocked(&"invalid_spell_target", "The spell target is unavailable.")
		if not spell_actor_target_is_valid(state, content, caster.id, effective_target_id, spell, power_level):
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The target is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func character_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	var result: Array[CombatSpellOptionView] = []
	var turn_probe := _probe_character_turn(state, content, caster_id)
	if not turn_probe.allowed: return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.current_health <= 0 or caster.traitor: return result
	var combat := state.combat
	if not _probe_caster_casting(state, combat, caster).allowed: return result
	for spell_id: String in caster.known_spells():
		var spell := content.magic.spell_by_id(spell_id)
		if spell == null: continue
		for power_level: int in range(1, 8):
			if not _probe_spell_rules(state, content, combat, caster, spell, power_level).allowed: continue
			if spell.target_type == 0:
				if CombatFlowSummoning.is_summon_spell(spell): result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose up to %d open spaces" % power_level, &"coordinate_sequence", 0, state.combat.battlefield.actors.actor_position(caster_id), [], power_level))
				else: result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose up to %d actors" % power_level, &"sequence", 0, INVALID_COORDINATE, [], power_level))
				continue
			if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell):
				result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose battlefield destination", &"area", 0, state.combat.battlefield.actors.actor_position(caster_id), [Vector2i.ZERO]))
				continue
			if spell.target_type in [9, 10, 12]:
				result.append(CombatSpellOptionView.new(spell, power_level, null, group_spell_target_label(spell.target_type), &"automatic"))
				continue
			if spell.target_type in [3, 4]:
				var shape := _context.spell_areas.shape_for(spell, power_level)
				var offsets := _context.spell_areas.pattern(shape)
				result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose battlefield point", &"area", shape, state.combat.battlefield.actors.actor_position(caster_id), offsets, 1, [], [], _context.spell_areas.rotation_patterns(spell, power_level)))
				continue
			if spell.target_type in [5, 7]:
				result.append(CombatSpellOptionView.new(spell, power_level, spell_target_view(state, content, caster_id), "Party" if spell.target_type == 7 else "Self", &"automatic"))
				continue
			result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose combatant"))
	return result


func character_scroll_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	var result: Array[CombatSpellOptionView] = []
	if state == null or content == null or state.combat == null or state.combat.turns.active_actor_id() != caster_id: return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null: return result
	for scroll_slot: int in caster.scroll_case().size():
		var scroll := caster.scroll_at(scroll_slot)
		var spell := content.magic.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
		if spell == null: continue
		if spell.target_type == 0:
			if _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed:
				if CombatFlowSummoning.is_summon_spell(spell): result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, null, "Choose up to %d open spaces" % scroll.power, &"coordinate_sequence", 0, state.combat.battlefield.actors.actor_position(caster_id), [], scroll.power))
				else: result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, null, "Choose up to %d actors" % scroll.power, &"sequence", 0, INVALID_COORDINATE, [], scroll.power, character_actor_spell_candidates(state, content, caster, spell, scroll.power)))
			continue
		if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell):
			if _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed: result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, null, "Choose battlefield destination", &"area", 0, state.combat.battlefield.actors.actor_position(caster_id), [Vector2i.ZERO]))
			continue
		if spell.target_type in [9, 10, 12]:
			if _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed: result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, null, group_spell_target_label(spell.target_type), &"automatic"))
			continue
		if spell.target_type in [3, 4]:
			if _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed:
				var shape := _context.spell_areas.shape_for(spell, scroll.power)
				var offsets := _context.spell_areas.pattern(shape)
				var legal_coordinates := legal_area_spell_target_coordinates(state, content, caster_id, spell, scroll.power, shape)
				result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, null, "Choose battlefield point", &"area", shape, state.combat.battlefield.actors.actor_position(caster_id), offsets, 1, [], legal_coordinates, _context.spell_areas.rotation_patterns(spell, scroll.power)))
			continue
		if spell.target_type in [5, 7]:
			if _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot, caster_id).allowed: result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, spell_target_view(state, content, caster_id), "Party" if spell.target_type == 7 else "Self", &"automatic"))
			continue
		for target: CombatSpellTargetView in character_actor_spell_candidates(state, content, caster, spell, scroll.power):
			if _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot, target.id).allowed: result.append(CombatScrollOptionView.new(scroll_slot, spell, scroll.power, target))
	return result


func character_scroll_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null or state.combat.turns.active_actor_id() != caster_id: return "Only the active character may use a scroll."
	var caster := state.party.character_by_id(caster_id)
	if caster == null: return "The active character is unavailable."
	if not _context.equipment.has_equipped_scroll_case(caster, content): return "Equip a scroll case before using its spells."
	for scroll_slot: int in caster.scroll_case().size():
		var scroll := caster.scroll_at(scroll_slot)
		if scroll == null or scroll.is_empty(): continue
		var spell := content.magic.spell_by_id(scroll.spell_id)
		if spell == null: return "A stored scroll references an unavailable spell."
		var target_id := caster_id if spell.target_type in [5, 7] else ""
		var probe: CombatSpellCastProbe = _context.magic_flow().probe_character_scroll_cast(state, content, caster_id, scroll_slot, target_id)
		if not probe.allowed: return probe.reason_text
	return "The equipped scroll case contains no combat-ready spells."


static func invalid_area_rotation(spell: SpellDefinition, rotation: int) -> bool:
	return rotation < 0 or rotation > (3 if spell != null and spell.can_rotate else 0)


func legal_area_spell_target_coordinates(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, shape: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if state == null or state.combat == null or state.combat.battlefield == null or content == null or spell == null: return result
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null: return result
	var origin := state.combat.battlefield.actors.actor_position(caster_id)
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	var minimum := Vector2i(maxi(0, origin.x - maximum_range - 1), maxi(0, origin.y - maximum_range - 1))
	var maximum := Vector2i(mini(BattlefieldGrid.SIZE - 1, origin.x + maximum_range + 1), mini(BattlefieldGrid.SIZE - 1, origin.y + maximum_range + 1))
	var require_line_of_sight := spell.range_min + spell.range_max > 0
	for y: int in range(minimum.y, maximum.y + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			var coordinate := Vector2i(x, y)
			if _context.spell_areas.pattern_fits(coordinate, shape) and _context.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, coordinate, maximum_range, require_line_of_sight): result.append(coordinate)
	return result


func character_actor_spell_candidates(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int) -> Array[CombatSpellTargetView]:
	var result: Array[CombatSpellTargetView] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id) and spell_actor_target_is_valid(state, content, caster.id, character.id, spell, power_level): result.append(CombatSpellTargetView.new(character.id, &"character", character.name, character.current_health, character.maximum_health))
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health > 0 and state.combat.battlefield.actors.has_actor(monster.id) and spell_actor_target_is_valid(state, content, caster.id, monster.id, spell, power_level): result.append(CombatSpellTargetView.new(monster.id, &"monster", monster.name, monster.current_health, monster.maximum_health))
	return result


static func spell_target_view(state: GameState, content: RealmzContent, target_id: String) -> CombatSpellTargetView:
	var character := state.party.character_by_id(target_id)
	if character != null: return CombatSpellTargetView.new(character.id, &"character", character.name, character.current_health, character.maximum_health)
	var monster := state.combat.roster.monster_by_id(target_id) if state.combat != null else null
	if monster != null and content.combat.monster_by_id(monster.definition_id) != null: return CombatSpellTargetView.new(monster.id, &"monster", monster.name, monster.current_health, monster.maximum_health)
	return null


func spell_actor_target_is_valid(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition, power_level: int) -> bool:
	if ClassicSpellSpecialEffectRules.is_combat_remove_curse_spell(spell) and state.party.character_by_id(target_id) == null: return false
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	if caster_id == target_id:
		var map := content.world.map_by_id(state.combat.battlefield.map_id)
		var terrain_set := content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
		return terrain_set != null and _context.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, state.combat.battlefield.actors.actor_position(caster_id), maximum_range, spell.range_min + spell.range_max > 0)
	return _context.reactions().projectile_target_is_valid(state.combat, content, caster_id, target_id, maximum_range, spell.range_min + spell.range_max > 0)


static func spell_target_selection(state: GameState, content: RealmzContent, target_id: String) -> SpellTargetSelection:
	var character := state.party.character_by_id(target_id)
	if character != null and character.current_health > 0 and state.combat.battlefield.actors.has_actor(character.id): return SpellTargetSelection.for_character(character)
	var monster := state.combat.roster.monster_by_id(target_id)
	if monster == null or monster.current_health <= 0 or not state.combat.battlefield.actors.has_actor(monster.id): return null
	var definition := content.combat.monster_by_id(monster.definition_id)
	return SpellTargetSelection.for_monster(monster, definition) if definition != null else null


static func group_spell_target_label(target_type: int) -> String:
	return {9: "All Friendly", 10: "All Enemies", 12: "Everybody"}.get(target_type, "Automatic Targets")


static func group_target_matches(target_type: int, target_traitor: bool, caster_traitor: bool) -> bool:
	if target_type == 12: return true
	if target_type == 9: return target_traitor == caster_traitor
	return target_traitor != caster_traitor


func character_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null: return ""
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.maximum_spell_attacks <= 0 or caster.known_spells().is_empty(): return ""
	var first_reason := ""
	for spell_id: String in caster.known_spells():
		for power_level: int in range(1, 8):
			var probe := probe_character_spell_choice(state, content, caster_id, spell_id, power_level)
			if probe.allowed: return ""
			if first_reason.is_empty() and not probe.reason_text.is_empty(): first_reason = probe.reason_text
	return first_reason
