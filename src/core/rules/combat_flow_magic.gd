class_name CombatFlowMagic
extends RefCounted

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const CombatRetreatProbeType = preload("res://src/core/rules/combat_retreat_probe.gd")
const CombatCommandProbeType = preload("res://src/core/rules/combat_command_probe.gd")
const CombatScrollOptionViewType = preload("res://src/core/view/combat_scroll_option_view.gd")

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const MONSTER_ATTACK_FALLBACK := 3
const REACTION_COMPLETED := 0
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const MAX_MONSTERS: int = 100
const MAX_AUTO_OPERATIONS: int = 256
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)
const CHARACTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 10123, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": false},
]
const MONSTER_FUMBLE_SOUNDS: Array[Dictionary] = [
	{"soundId": 10121, "waitForCompletion": true},
	{"soundId": 655, "waitForCompletion": true},
]

var _flow_ref: WeakRef
var _rules: ContextType


func _init(flow: RefCounted, rules: ContextType) -> void:
	_flow_ref = weakref(flow)
	_rules = rules


func _flow() -> RefCounted:
	return _flow_ref.get_ref() if _flow_ref != null else null

func probe_character_item_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Item use requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_item_turn", "Only the active character may use an item in combat.")
	if not combat.pending_spell_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	var instance := _inventory_instance(caster, instance_id)
	var item: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else content.spell_by_classic_id(item.special_2)
	var use_probe := _rules.inventory.classic_spell_item_probe(caster, instance, item, spell, content.race_by_id(caster.race_id) if caster != null else null, content.caste_by_id(caster.caste_id) if caster != null else null, true)
	if not use_probe.allowed:
		return CombatSpellCastProbe.blocked(_item_use_reason_code(instance, item, spell), use_probe.reason)
	var power_level := absi(item.special_1)
	if power_level == 8:
		return CombatSpellCastProbe.blocked(&"random_item_power_requires_staging", "A random-power item requires a source-backed staged targeting continuation.")
	if ClassicSpellCapabilityCatalog.combat_item_disposition(spell) != ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_item_effect", ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"combat-item"))
	if spell.target_type in [9, 10, 12]:
		var group_target_count := 0
		for character: CharacterState in state.party.characters():
			if character.current_health > 0 and combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
				group_target_count += 1
		for monster: MonsterState in combat.monsters():
			if monster.current_health <= 0 or not combat.battlefield.has_actor(monster.id) or not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
				continue
			if content.monster_by_id(monster.definition_id) == null:
				return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "An item spell target has no immutable monster definition.")
			group_target_count += 1
		if group_target_count == 0:
			return CombatSpellCastProbe.blocked(&"invalid_item_target", "The item spell has no available group target.")
		return CombatSpellCastProbe.permitted()
	var effective_target_id := caster_id if spell.target_type == 5 else target_id
	if _spell_target_selection(state, content, effective_target_id) == null:
		return CombatSpellCastProbe.blocked(&"invalid_item_target", "The selected combatant is unavailable.")
	if not _spell_actor_target_is_valid(state, content, caster_id, effective_target_id, spell, power_level):
		return CombatSpellCastProbe.blocked(&"item_target_unavailable", "The target is outside the item's Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func use_spell_item(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, rng: RealmzRng) -> CombatFlowResult:
	var probe := probe_character_item_spell(state, content, caster_id, target_id, instance_id)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var caster := state.party.character_by_id(caster_id)
	var instance := _inventory_instance(caster, instance_id)
	var item := content.item_by_id(instance.definition_id)
	var spell := content.spell_by_classic_id(item.special_2)
	var power_level := absi(item.special_1)
	if not _rules.inventory.use_charge(caster, instance.id, item):
		return CombatFlowResult.failed(&"item_charge_commit_failed", "The validated item charge could not be committed.")
	_flow()._prepare_character_turn(state.combat, caster)
	state.combat.invalidate_undo()
	var cast_level := spell.classic_tier()
	var result: CombatFlowResult
	if spell.target_type == 6:
		var ray_selections := _ray_spell_selections(state, content, caster.id, target_id, spell)
		var ray := _rules.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng, false)
		if ray == null or not ray.cast:
			return CombatFlowResult.failed(&"item_spell_failed", "The item ray spell could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, ray, rng, INVALID_COORDINATE, 0, "classic-item", instance_id, false)
	elif spell.target_type in [9, 10, 12]:
		var character_targets: Array[CharacterState] = []
		var monster_targets: Array[MonsterState] = []
		var monster_definitions: Array[MonsterDefinition] = []
		for character: CharacterState in state.party.characters():
			if character.current_health > 0 and state.combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
				character_targets.append(character)
		for monster: MonsterState in state.combat.monsters():
			if monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id) or not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
				continue
			var definition := content.monster_by_id(monster.definition_id)
			if definition == null:
				return CombatFlowResult.failed(&"spell_target_unavailable", "An item spell target has no immutable monster definition.")
			monster_targets.append(monster)
			monster_definitions.append(definition)
		var group := _rules.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng, false, false)
		if group == null or not group.cast:
			return CombatFlowResult.failed(&"item_spell_failed", "The item spell could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, group, rng, INVALID_COORDINATE, 0, "classic-item", instance_id, false)
	else:
		var effective_target_id := caster_id if spell.target_type == 5 else target_id
		var selection := _spell_target_selection(state, content, effective_target_id)
		var targeted := _rules.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, false)
		if targeted == null or not targeted.cast:
			return CombatFlowResult.failed(&"item_spell_failed", "The item spell could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, targeted, rng, INVALID_COORDINATE, 0, "classic-item", instance_id, false)
	if not result.ok:
		return result
	var events: Array[DomainEvent] = [_item_used_event(caster_id, instance_id, item, spell, power_level, caster)]
	var native_sound_id := item.sound_id + 600
	if item.sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-item"}))
	events.append_array(result.events)
	result.events = events
	return result


func character_item_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatItemOptionView]:
	var result: Array[CombatItemOptionView] = []
	if state == null or state.combat == null or state.combat.active_actor_id() != caster_id:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	for instance: ItemInstance in caster.inventory():
		var item := content.item_by_id(instance.definition_id)
		var spell := content.spell_by_classic_id(item.special_2) if item != null else null
		if item == null or spell == null or absi(item.special_1) == 8:
			continue
		if spell.target_type in [9, 10, 12]:
			if probe_character_item_spell(state, content, caster_id, "", instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, absi(item.special_1), null, _group_spell_target_label(spell.target_type), &"automatic"))
			continue
		if spell.target_type == 5:
			if probe_character_item_spell(state, content, caster_id, caster_id, instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, absi(item.special_1), _spell_target_view(state, content, caster_id)))
			continue
		for target: CombatSpellTargetView in _character_actor_spell_candidates(state, content, caster, spell, absi(item.special_1)):
			if probe_character_item_spell(state, content, caster_id, target.id, instance.id).allowed:
				result.append(CombatItemOptionView.new(instance, item, spell, absi(item.special_1), target))
	return result


func character_item_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null or state.combat.active_actor_id() != caster_id:
		return "Only the active character may use an item."
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.inventory().is_empty():
		return "The active character carries no items."
	for instance: ItemInstance in caster.inventory():
		var item := content.item_by_id(instance.definition_id)
		var spell := content.spell_by_classic_id(item.special_2) if item != null else null
		if item != null and spell != null:
			var probe := probe_character_item_spell(state, content, caster_id, caster_id if spell.target_type == 5 else "", instance.id)
			if not probe.allowed:
				return probe.reason_text
	return "No carried item has a supported Classic combat use."


static func _inventory_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func _item_use_reason_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	if instance == null or item == null:
		return &"unknown_item_instance"
	if instance.charges == 0:
		return &"item_has_no_charges"
	if item.special_2 <= 1100:
		return &"item_has_no_spell_effect"
	if spell == null:
		return &"unknown_item_spell"
	return &"item_cannot_be_used"


static func _item_used_event(caster_id: String, instance_id: String, item: ItemDefinition, spell: SpellDefinition, power_level: int, caster: CharacterState) -> DomainEvent:
	var remaining := -1
	var dropped := true
	for instance: ItemInstance in caster.inventory():
		if instance.id == instance_id:
			remaining = instance.charges
			dropped = false
			break
	return DomainEvent.new(&"item_used", {"characterId": caster_id, "instanceId": instance_id, "itemId": item.id, "spellId": spell.id, "power": power_level, "chargesRemaining": remaining, "droppedOnEmpty": dropped, "source": "classic"})


func cast_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, rng: RealmzRng, target_coordinate: Vector2i = Vector2i(-100_000, -100_000), rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	var probe := probe_character_spell_cast(state, content, caster_id, target_id, spell_id, power_level, target_coordinate, rotation, target_ids, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var combat := state.combat
	var caster := state.party.character_by_id(caster_id)
	var spell := content.spell_by_id(spell_id)
	var cast_level := spell.classic_tier()
	if _flow()._is_summon_spell(spell):
		return _flow()._cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates)
	if spell.target_type in [3, 4]:
		if target_coordinate == INVALID_COORDINATE:
			return CombatFlowResult.failed(&"area_target_required", "A fixed or power area spell requires a battlefield coordinate.")
		_flow()._prepare_character_turn(combat, caster)
		combat.invalidate_undo()
		return _cast_character_area_spell(state, content, caster, spell, power_level, cast_level, rng, target_coordinate, rotation)
	_flow()._prepare_character_turn(combat, caster)
	combat.invalidate_undo()
	if spell.target_type in [9, 10, 12]:
		return _cast_character_group_spell(state, content, caster, spell, power_level, cast_level, rng)
	if spell.target_type == 0:
		var selections: Array[SpellTargetSelection] = []
		for selected_id: String in target_ids:
			var repeated_selection := _spell_target_selection(state, content, selected_id)
			if repeated_selection == null:
				return CombatFlowResult.failed(&"spell_target_unavailable", "A selected repeated-spell target is unavailable.")
			selections.append(repeated_selection)
		var repeated := _rules.magic.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng)
		if repeated == null or not repeated.cast:
			return CombatFlowResult.failed(&"spell_cast_failed", "The repeated-target spell could not be cast with the available spell points.")
		return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, repeated, rng)
	if spell.target_type == 6:
		var ray_selections := _ray_spell_selections(state, content, caster.id, target_id, spell)
		var ray := _rules.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng)
		if ray == null or not ray.cast:
			return CombatFlowResult.failed(&"spell_cast_failed", "The ray spell could not be cast with the available spell points.")
		return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, ray, rng)
	var selection := _spell_target_selection(state, content, target_id)
	if selection == null:
		return CombatFlowResult.failed(&"spell_target_unavailable", "The selected combatant is unavailable.")
	var targeted := _rules.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng)
	if targeted == null or not targeted.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The spell could not be cast with the available spell points.")
	return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, targeted, rng)


func _ray_spell_selections(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition) -> Array[SpellTargetSelection]:
	var result: Array[SpellTargetSelection] = []
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
	if terrain_set == null or not state.combat.battlefield.has_actor(target_id):
		return result
	var stop_at_blocker := spell.range_min + spell.range_max > 0
	for actor_id: String in _rules.battlefield.ray_actor_ids(state.combat.battlefield, terrain_set, caster_id, state.combat.battlefield.actor_position(target_id), stop_at_blocker):
		var selection := _spell_target_selection(state, content, actor_id)
		if selection != null:
			result.append(selection)
	return result


func probe_character_scroll_cast(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String = "", target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_turn", "Scroll use requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_turn", "Only the active character may use a scroll in combat.")
	if not combat.pending_spell_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.current_health <= 0 or caster.conditions.is_active(ConditionRules.ANIMATED):
		return CombatSpellCastProbe.blocked(&"scroll_user_unavailable", "The active character cannot use a scroll.")
	if not _has_equipped_scroll_case(caster, content):
		return CombatSpellCastProbe.blocked(&"scroll_case_not_equipped", "Equip a scroll case before using its spells.")
	var scroll := caster.scroll_at(scroll_slot)
	var spell := content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
	if scroll_slot < 0 or scroll_slot >= 5 or scroll == null or scroll.is_empty() or spell == null or scroll.power < 1 or scroll.power > 7:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_slot", "This scroll slot is empty or invalid.")
	if not spell.in_combat:
		return CombatSpellCastProbe.blocked(&"scroll_not_available_in_combat", "This scroll cannot be used in combat.")
	var repeated_target := spell.target_type == 0
	var summon_spell: bool = _flow()._is_summon_spell(spell)
	var group_target := spell.target_type in [9, 10, 12]
	var area_target := spell.target_type in [3, 4]
	var self_target := spell.target_type == 5
	var actor_target: bool = not repeated_target and not group_target and not area_target and not summon_spell
	var effective_target_id := caster_id if self_target else target_id
	if actor_target and _spell_target_selection(state, content, effective_target_id) == null:
		return CombatSpellCastProbe.blocked(&"invalid_scroll_target", "The selected combatant is unavailable.")
	if ClassicSpellCapabilityCatalog.combat_scroll_disposition(spell) != ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_scroll", ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"combat-scroll"))
	if repeated_target and spell.size != 0 and not summon_spell:
		return CombatSpellCastProbe.blocked(&"repeated_open_space_spell_unresolved", "Classic target type 0 with nonzero size selects open-space footprints for summoning or special behavior, not ordinary actors.")
	if area_target and rotation != 0:
		return CombatSpellCastProbe.blocked(&"invalid_area_rotation", "This non-rotating Classic area spell requires rotation zero.")
	var cast_level := spell.classic_tier()
	if cast_level < 0 or cast_level > 6:
		return CombatSpellCastProbe.blocked(&"invalid_classic_spell_tier", "The scroll spell ID does not encode a valid Classic tier.")
	if summon_spell:
		return _flow()._probe_summon_choice(state, content, caster_id, spell, scroll.power) if target_coordinates.is_empty() else _flow()._probe_summon_coordinates(state, content, caster_id, spell, scroll.power, target_coordinates)
	if repeated_target:
		if target_ids.size() > scroll.power:
			return CombatSpellCastProbe.blocked(&"too_many_scroll_targets", "A repeated scroll may select at most one distinct actor per power level.")
		var seen: Dictionary = {}
		for selected_id: String in target_ids:
			if selected_id.is_empty() or seen.has(selected_id):
				return CombatSpellCastProbe.blocked(&"invalid_repeated_scroll_targets", "Repeated scroll targets must be nonempty and distinct.")
			seen[selected_id] = true
			if _spell_target_selection(state, content, selected_id) == null:
				return CombatSpellCastProbe.blocked(&"invalid_scroll_target", "A selected repeated-scroll actor is unavailable.")
			if not _spell_actor_target_is_valid(state, content, caster.id, selected_id, spell, scroll.power):
				return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "A selected repeated-scroll actor is outside the Classic spell range or line of sight.")
		if target_ids.is_empty() and _character_actor_spell_candidates(state, content, caster, spell, scroll.power).is_empty():
			return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "No actor is available within this repeated scroll's Classic range and line of sight.")
	elif area_target:
		var shape := _rules.spell_areas.shape_for(spell, scroll.power, rotation)
		if _rules.spell_areas.pattern(shape).is_empty():
			return CombatSpellCastProbe.blocked(&"invalid_scroll_area_shape", "The scroll references an unavailable Classic Data AD area mask.")
		if target_coordinate != INVALID_COORDINATE:
			if not _rules.spell_areas.pattern_fits(target_coordinate, shape):
				return CombatSpellCastProbe.blocked(&"scroll_area_outside_battlefield", "The complete Classic area mask must remain inside the validated battlefield.")
			var map := content.world.map_by_id(combat.battlefield.map_id)
			var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
			var maximum_range := absi(spell.range_min + spell.range_max * scroll.power)
			if terrain_set == null or not _rules.battlefield.coordinate_target_is_valid(combat.battlefield, terrain_set, caster.id, target_coordinate, maximum_range, spell.range_min + spell.range_max > 0):
				return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "The area center is outside the Classic spell range or line of sight.")
	elif group_target:
		var group_count := 0
		for character: CharacterState in state.party.characters():
			if character.current_health > 0 and combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
				group_count += 1
		for monster: MonsterState in combat.monsters():
			if monster.current_health > 0 and combat.battlefield.has_actor(monster.id) and _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
				group_count += 1
		if group_count == 0:
			return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "The scroll has no available group target.")
	elif not _spell_actor_target_is_valid(state, content, caster.id, effective_target_id, spell, scroll.power):
		return CombatSpellCastProbe.blocked(&"scroll_target_unavailable", "The target is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func use_combat_scroll(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	var probe := probe_character_scroll_cast(state, content, caster_id, scroll_slot, target_id, target_coordinate, rotation, target_ids, target_coordinates)
	if not probe.allowed:
		return CombatFlowResult.failed(probe.reason, probe.reason_text)
	var state_checkpoint := state.to_data()
	var rng_checkpoint := rng.checkpoint()
	var caster := state.party.character_by_id(caster_id)
	var scroll := caster.scroll_at(scroll_slot)
	var spell := content.spell_by_id(scroll.spell_id)
	var power_level := scroll.power
	var cast_level := spell.classic_tier()
	var result: CombatFlowResult
	if _flow()._is_summon_spell(spell):
		if target_coordinates.is_empty():
			return CombatFlowResult.failed(&"summon_target_required", "Choose at least one open battlefield space for the summon scroll.")
		result = _flow()._cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates, "classic-scroll", false, false)
	else:
		_flow()._prepare_character_turn(state.combat, caster)
		state.combat.invalidate_undo()
	if not _flow()._is_summon_spell(spell) and spell.target_type in [3, 4]:
		var shape := _rules.spell_areas.shape_for(spell, power_level, rotation)
		var selected_ids: Dictionary = {}
		for offset: Vector2i in _rules.spell_areas.pattern(shape):
			var actor_id := state.combat.battlefield.actor_at(target_coordinate + offset)
			if not actor_id.is_empty():
				selected_ids[actor_id] = true
		var area_targets := _combat_spell_group_targets(state, content, caster, spell, selected_ids, true)
		if not bool(area_targets.get("ok", false)):
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", String(area_targets.get("error", "A scroll target is unavailable.")))
		var area_characters: Array[CharacterState] = area_targets.get("characters", [])
		var area_monsters: Array[MonsterState] = area_targets.get("monsters", [])
		var area_definitions: Array[MonsterDefinition] = area_targets.get("definitions", [])
		var area := _rules.magic.resolve_character_group_spell(caster, area_characters, area_monsters, area_definitions, spell, power_level, cast_level, rng, true, false)
		if area == null or not area.cast:
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The area scroll could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, area, rng, target_coordinate, shape, "classic-scroll", "", false)
	elif not _flow()._is_summon_spell(spell) and spell.target_type in [9, 10, 12]:
		var group_targets := _combat_spell_group_targets(state, content, caster, spell)
		if not bool(group_targets.get("ok", false)):
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", String(group_targets.get("error", "A scroll target is unavailable.")))
		var group_characters: Array[CharacterState] = group_targets.get("characters", [])
		var group_monsters: Array[MonsterState] = group_targets.get("monsters", [])
		var group_definitions: Array[MonsterDefinition] = group_targets.get("definitions", [])
		var group := _rules.magic.resolve_character_group_spell(caster, group_characters, group_monsters, group_definitions, spell, power_level, cast_level, rng, false, false)
		if group == null or not group.cast:
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The group scroll could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, group, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	elif not _flow()._is_summon_spell(spell) and spell.target_type == 0:
		var selections: Array[SpellTargetSelection] = []
		for selected_id: String in target_ids:
			var selection := _spell_target_selection(state, content, selected_id)
			if selection == null:
				return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_target_unavailable", "A repeated-scroll target became unavailable.")
			selections.append(selection)
		var repeated := _rules.magic.resolve_character_repeated_spell(caster, selections, spell, power_level, cast_level, rng, false)
		if repeated == null or not repeated.cast:
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The repeated scroll could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, repeated, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	elif not _flow()._is_summon_spell(spell) and spell.target_type == 6:
		var ray_selections := _ray_spell_selections(state, content, caster.id, target_id, spell)
		var ray := _rules.magic.resolve_character_ray_spell(caster, ray_selections, spell, power_level, cast_level, rng, false)
		if ray == null or not ray.cast:
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The ray scroll could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, ray, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	elif not _flow()._is_summon_spell(spell):
		var effective_target_id := caster_id if spell.target_type == 5 else target_id
		var selection := _spell_target_selection(state, content, effective_target_id)
		var targeted := _rules.magic.resolve_character_targeted_spell(caster, selection, spell, power_level, cast_level, rng, false)
		if targeted == null or not targeted.cast:
			return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_spell_failed", "The targeted scroll could not be resolved.")
		result = _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, targeted, rng, INVALID_COORDINATE, 0, "classic-scroll", "", false)
	if not result.ok:
		return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, result.error_code, result.error_message)
	var committed_caster := state.party.character_by_id(caster_id)
	if committed_caster == null or not committed_caster.clear_scroll(scroll_slot):
		return _rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, &"scroll_commit_failed", "The resolved scroll could not be removed from its case.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_used", {"characterId": caster_id, "slot": scroll_slot, "spellId": spell.id, "power": power_level, "source": "classic-combat"})]
	events.append_array(result.events)
	result.events = events
	return result


func _combat_spell_group_targets(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, selected_ids: Dictionary = {}, area_target: bool = false) -> Dictionary:
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if character.current_health <= 0 or not state.combat.battlefield.has_actor(character.id):
			continue
		if area_target:
			if not selected_ids.has(character.id):
				continue
			if character.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
				return {"ok": false, "error": "This area intersects a spell-reflecting character; Classic reflection targeting remains unresolved."}
		elif not _group_target_matches(spell.target_type, character.traitor, caster.traitor):
			continue
		character_targets.append(character)
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id):
			continue
		if area_target:
			if not selected_ids.has(monster.id):
				continue
			if monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
				return {"ok": false, "error": "This area intersects a spell-reflecting monster; Classic reflection targeting remains unresolved."}
			if monster.magic_resistance > 100:
				continue
		elif not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			return {"ok": false, "error": "A scroll target has no immutable monster definition."}
		monster_targets.append(monster)
		monster_definitions.append(definition)
	return {"ok": true, "characters": character_targets, "monsters": monster_targets, "definitions": monster_definitions}


func _rollback_combat_scroll(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	if not state.restore_from_data(state_checkpoint) or not rng.rollback(rng_checkpoint):
		return CombatFlowResult.failed(&"combat_scroll_rollback_failed", "Combat scroll resolution failed and its transaction could not be restored.")
	return CombatFlowResult.failed(error_code, error_message)


func _cast_character_group_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> CombatFlowResult:
	var combat := state.combat
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and combat.battlefield.has_actor(character.id) and _group_target_matches(spell.target_type, character.traitor, caster.traitor):
			character_targets.append(character)
	for monster: MonsterState in combat.monsters():
		if monster.current_health <= 0 or not combat.battlefield.has_actor(monster.id):
			continue
		if not _group_target_matches(spell.target_type, monster.traitor, caster.traitor):
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			return CombatFlowResult.failed(&"spell_target_unavailable", "A group spell target has no immutable monster definition.")
		monster_targets.append(monster)
		monster_definitions.append(definition)
	var group := _rules.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng)
	if group == null or not group.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The group spell could not be cast with the available spell points.")
	return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, group, rng)


func _cast_character_area_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, center: Vector2i, rotation: int) -> CombatFlowResult:
	var combat := state.combat
	var shape := _rules.spell_areas.shape_for(spell, power_level, rotation)
	var selected_ids: Dictionary = {}
	for offset: Vector2i in _rules.spell_areas.pattern(shape):
		var actor_id := combat.battlefield.actor_at(center + offset)
		if not actor_id.is_empty():
			selected_ids[actor_id] = true
	var character_targets: Array[CharacterState] = []
	var monster_targets: Array[MonsterState] = []
	var monster_definitions: Array[MonsterDefinition] = []
	for character: CharacterState in state.party.characters():
		if not selected_ids.has(character.id) or character.current_health <= 0 or not combat.battlefield.has_actor(character.id):
			continue
		if character.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
			return CombatFlowResult.failed(&"area_spell_reflection_unresolved", "This area intersects a spell-reflecting character; Classic reflection targeting remains unresolved.")
		character_targets.append(character)
	for monster: MonsterState in combat.monsters():
		if not selected_ids.has(monster.id) or monster.current_health <= 0 or not combat.battlefield.has_actor(monster.id):
			continue
		if monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS):
			return CombatFlowResult.failed(&"area_spell_reflection_unresolved", "This area intersects a spell-reflecting monster; Classic reflection targeting remains unresolved.")
		# spelltargets.c removes over-100 magic resistance before resolvespell.
		if monster.magic_resistance > 100:
			continue
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			return CombatFlowResult.failed(&"spell_target_unavailable", "An area spell target has no immutable monster definition.")
		monster_targets.append(monster)
		monster_definitions.append(definition)
	_flow()._prepare_character_turn(combat, caster)
	var area := _rules.magic.resolve_character_group_spell(caster, character_targets, monster_targets, monster_definitions, spell, power_level, cast_level, rng, true)
	if area == null or not area.cast:
		return CombatFlowResult.failed(&"spell_cast_failed", "The area spell could not be cast with the available spell points.")
	return _commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, area, rng, center, shape)


func _commit_character_multi_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, group: GroupSpellResolution, rng: RealmzRng, center: Vector2i = Vector2i(-100_000, -100_000), shape: int = 0, event_source: String = "classic", item_instance_id: String = "", count_spell_cast: bool = true) -> CombatFlowResult:
	var combat := state.combat
	if count_spell_cast:
		combat.active_turn.spell_cast_count += 1
	caster.attacks_remaining = _rules.arithmetic.signed_16(caster.attacks_remaining - 2)
	caster.movement = maxi(0, caster.movement - 12)
	var events: Array[DomainEvent] = []
	_append_spell_sound(events, spell.sound_start, "classic-combat-spell-start")
	_append_spell_cast_event(events, caster.id, spell, group, center, shape, event_source)
	for index: int in group.resolutions.size():
		var resolution := group.resolutions[index]
		var resolved_target_id := group.target_ids[index]
		var selected_target_id := group.selected_target_ids[index]
		var target_kind := group.target_kinds[index]
		var reflected := group.reflected_targets[index]
		if resolution.damage > 0 or (resolution.damage < 0 and target_kind == &"monster"):
			combat.mark_attacked(resolved_target_id)
		_append_spell_projectile_event(events, caster.id, resolved_target_id, spell, event_source)
		_append_spell_sound(events, spell.sound_end, "classic-combat-spell-result")
		var payload := {"actorId": caster.id, "targetId": resolved_target_id, "selectedTargetId": selected_target_id, "targetKind": String(target_kind), "spellId": spell.id, "targetType": spell.target_type, "power": power_level, "classicTier": cast_level, "reflected": reflected, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "source": event_source}
		if resolution.cleared_condition >= 0:
			payload["clearedCondition"] = resolution.cleared_condition
		_append_spell_presentation(payload, spell, index, group.resolutions.size(), resolution.target_defeated)
		if not item_instance_id.is_empty():
			payload["itemInstanceId"] = item_instance_id
		if shape > 0:
			payload["areaCenter"] = [center.x, center.y]
			payload["areaShape"] = shape
		events.append(DomainEvent.new(&"combat_spell_resolved", payload))
		if not resolution.target_defeated:
			continue
		if target_kind == &"character":
			_flow()._remove_defeated_position(combat, resolved_target_id, true)
		else:
			var defeated_monster := combat.monster_by_id(resolved_target_id)
			var defeated_definition := content.monster_by_id(defeated_monster.definition_id) if defeated_monster != null else null
			var queued = _flow()._queue_spell_death_macro(combat, defeated_monster, defeated_definition)
			_flow()._remove_defeated_position(combat, resolved_target_id, not queued)
	var advances_turn = not _flow()._character_can_continue(caster)
	if not combat.pending_spell_death_macro_id().is_empty():
		if not combat.begin_spell_death_macro_sequence(caster.id, advances_turn) or not _flow()._request_next_spell_death_macro(combat, content, events):
			return CombatFlowResult.failed(&"invalid_spell_death_macro_queue", "The multi-target spell death-macro queue could not retain its caster and source order.")
		return CombatFlowResult.succeeded(events)
	if advances_turn:
		_flow()._advance_turn(state, rng, events)
	if _flow()._finish_if_resolved(state, content, events):
		return CombatFlowResult.succeeded(events, true)
	_flow()._process_monster_turns(state, content, rng, events)
	return CombatFlowResult.succeeded(events, state.combat.completed)


static func _append_spell_sound(events: Array[DomainEvent], authored_sound_id: int, source: String) -> void:
	var native_sound_id := authored_sound_id + 600
	if native_sound_id == 0:
		return
	events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": source}))


static func _append_spell_cast_event(events: Array[DomainEvent], actor_id: String, spell: SpellDefinition, resolutions: GroupSpellResolution, center: Vector2i, shape: int, source: String) -> void:
	var target_id := resolutions.target_ids[0] if not resolutions.target_ids.is_empty() else ""
	var payload := {"actorId": actor_id, "targetId": target_id, "spellId": spell.id, "classicEffectResourceId": 11_992 + spell.look_start * 8, "source": source}
	if shape > 0:
		payload["areaCenter"] = [center.x, center.y]
		payload["areaShape"] = shape
	events.append(DomainEvent.new(&"combat_spell_cast", payload))


static func _append_spell_projectile_event(events: Array[DomainEvent], actor_id: String, target_id: String, spell: SpellDefinition, source: String) -> void:
	if not spell.target_type in [0, 1, 2, 5, 6, 7, 8, 11]:
		return
	events.append(DomainEvent.new(&"combat_spell_projectile", {"actorId": actor_id, "targetId": target_id, "spellId": spell.id, "classicBattleTileId": 200 + spell.look_start, "source": source}))


static func _append_spell_presentation(payload: Dictionary, spell: SpellDefinition, sequence_index: int, sequence_count: int, target_defeated: bool) -> void:
	payload["castSequenceIndex"] = sequence_index
	payload["castSequenceCount"] = sequence_count
	# resolvespell.c bypasses the ordinary eight-frame resolution effect when the
	# target dies, and group-body flashes (9/10) use a separate path.
	if target_defeated or spell.target_type in [9, 10]:
		return
	var first_resource_id := 12_032 if spell.look_end == 0 else 11_992 + spell.look_end * 8
	var effect_ids: Array[int] = []
	for frame_offset: int in 8:
		effect_ids.append(first_resource_id + frame_offset)
	payload["classicResolutionEffectResourceIds"] = effect_ids


func probe_character_spell_choice(state: GameState, content: RealmzContent, caster_id: String, spell_id: String, power_level: int) -> CombatSpellCastProbe:
	if state == null or content == null:
		return CombatSpellCastProbe.blocked(&"invalid_spell_turn", "Spell casting requires an active game session.")
	var combat := state.combat
	if combat == null or combat.completed or combat.battlefield == null or combat.active_actor_id() != caster_id:
		return CombatSpellCastProbe.blocked(&"invalid_spell_turn", "The caster does not own an active combat turn.")
	if not combat.pending_spell_death_macro_id().is_empty():
		return CombatSpellCastProbe.blocked(&"spell_death_macro_pending", "A spell-triggered monster death macro must complete before another combat action.")
	var caster := state.party.character_by_id(caster_id)
	var spell := content.spell_by_id(spell_id)
	if caster == null or caster.current_health <= 0 or caster.traitor or spell == null or power_level < 1 or power_level > 7:
		return CombatSpellCastProbe.blocked(&"invalid_spell_target", "The spell, caster, or power is unavailable.")
	var repeated_target := spell.target_type == 0
	var area_target := spell.target_type in [3, 4]
	if not caster.known_spells().has(spell.id):
		return CombatSpellCastProbe.blocked(&"spell_not_known", "The caster does not know '%s'." % spell.id)
	if state.character_spellcasting_blocked:
		return CombatSpellCastProbe.blocked(&"character_spellcasting_blocked", "Classic scenario state currently blocks character spellcasting.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if caster.conditions.is_active(condition):
			return CombatSpellCastProbe.blocked(&"spellcasting_condition_blocked", "The caster's current Classic condition prevents spellcasting.")
	if combat.was_attacked(caster.id):
		return CombatSpellCastProbe.blocked(&"caster_attacked_this_round", "Castle prevents a character who has been attacked this combat round from casting.")
	var committed_casts := combat.active_turn.spell_cast_count if combat.active_turn != null else 0
	if caster.maximum_spell_attacks <= 0 or committed_casts >= caster.maximum_spell_attacks:
		return CombatSpellCastProbe.blocked(&"spell_attack_limit_reached", "The caster has reached the Classic per-activation spell limit.")
	if not spell.in_combat:
		return CombatSpellCastProbe.blocked(&"spell_not_available_in_combat", "The selected spell is not available in combat.")
	var summon_spell: bool = _flow()._is_summon_spell(spell)
	if ClassicSpellCapabilityCatalog.combat_character_disposition(spell) != ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE:
		return CombatSpellCastProbe.blocked(&"unsupported_combat_spell", ClassicSpellCapabilityCatalog.unsupported_reason(spell, &"combat-character"))
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
		var shape := _rules.spell_areas.shape_for(spell, power_level)
		if _rules.spell_areas.pattern(shape).is_empty():
			return CombatSpellCastProbe.blocked(&"invalid_spell_area_shape", "The spell references an unavailable Classic Data AD area mask.")
	return _flow()._probe_summon_choice(state, content, caster_id, spell, power_level) if summon_spell else CombatSpellCastProbe.permitted()


func probe_character_spell_cast(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	var choice_probe := probe_character_spell_choice(state, content, caster_id, spell_id, power_level)
	if not choice_probe.allowed:
		return choice_probe
	var combat := state.combat
	var caster := state.party.character_by_id(caster_id)
	var spell := content.spell_by_id(spell_id)
	var repeated_target := spell.target_type == 0
	var summon_spell: bool = _flow()._is_summon_spell(spell)
	var group_target := spell.target_type in [9, 10, 12]
	var area_target := spell.target_type in [3, 4]
	if area_target and rotation != 0:
		return CombatSpellCastProbe.blocked(&"invalid_area_rotation", "This non-rotating Classic area spell requires rotation zero.")
	if summon_spell:
		return _flow()._probe_summon_coordinates(state, content, caster_id, spell, power_level, target_coordinates)
	if repeated_target:
		if target_ids.size() > power_level:
			return CombatSpellCastProbe.blocked(&"too_many_spell_targets", "A repeated-target spell may select at most one distinct actor per power level.")
		var seen: Dictionary = {}
		for selected_id: String in target_ids:
			if selected_id.is_empty() or seen.has(selected_id):
				return CombatSpellCastProbe.blocked(&"invalid_repeated_spell_targets", "Repeated spell targets must be nonempty and distinct.")
			seen[selected_id] = true
			var selection := _spell_target_selection(state, content, selected_id)
			if selection == null:
				return CombatSpellCastProbe.blocked(&"invalid_spell_target", "A selected repeated-spell actor is unavailable.")
			if not _spell_actor_target_is_valid(state, content, caster.id, selected_id, spell, power_level):
				return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "A selected repeated-spell actor is outside the Classic spell range or line of sight.")
		if target_ids.is_empty() and _character_actor_spell_candidates(state, content, caster, spell, power_level).is_empty():
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "No actor is available within this repeated spell's Classic range and line of sight.")
	elif area_target:
		var shape := _rules.spell_areas.shape_for(spell, power_level, rotation)
		if target_coordinate == INVALID_COORDINATE:
			return CombatSpellCastProbe.blocked(&"invalid_spell_target", "Choose a battlefield center for this area spell.")
		if not _rules.spell_areas.pattern_fits(target_coordinate, shape):
			return CombatSpellCastProbe.blocked(&"spell_area_outside_battlefield", "The complete Classic area mask must remain inside the validated battlefield.")
		var map := content.world.map_by_id(combat.battlefield.map_id)
		var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
		var maximum_range := absi(spell.range_min + spell.range_max * power_level)
		if terrain_set == null or not _rules.battlefield.coordinate_target_is_valid(combat.battlefield, terrain_set, caster.id, target_coordinate, maximum_range, spell.range_min + spell.range_max > 0):
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The area center is outside the Classic spell range or line of sight.")
	elif not group_target:
		if _spell_target_selection(state, content, target_id) == null:
			return CombatSpellCastProbe.blocked(&"invalid_spell_target", "The spell target is unavailable.")
		if not _spell_actor_target_is_valid(state, content, caster.id, target_id, spell, power_level):
			return CombatSpellCastProbe.blocked(&"spell_target_unavailable", "The target is outside the Classic spell range or line of sight.")
	return CombatSpellCastProbe.permitted()


func character_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	var result: Array[CombatSpellOptionView] = []
	if state == null or state.combat == null:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	for spell_id: String in caster.known_spells():
		var spell := content.spell_by_id(spell_id)
		if spell == null:
			continue
		for power_level: int in range(1, 8):
			if not probe_character_spell_choice(state, content, caster_id, spell.id, power_level).allowed:
				continue
			if spell.target_type == 0:
				if _flow()._is_summon_spell(spell):
					result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose up to %d open spaces" % power_level, &"coordinate_sequence", 0, state.combat.battlefield.actor_position(caster_id), [], power_level))
				else:
					result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose up to %d actors" % power_level, &"sequence", 0, INVALID_COORDINATE, [], power_level))
				continue
			if spell.target_type in [9, 10, 12]:
				result.append(CombatSpellOptionView.new(spell, power_level, null, _group_spell_target_label(spell.target_type), &"automatic"))
				continue
			if spell.target_type in [3, 4]:
				var shape := _rules.spell_areas.shape_for(spell, power_level)
				var offsets := _rules.spell_areas.pattern(shape)
				result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose battlefield point", &"area", shape, state.combat.battlefield.actor_position(caster_id), offsets))
				continue
			result.append(CombatSpellOptionView.new(spell, power_level, null, "Choose combatant"))
	return result


func character_scroll_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	var result: Array[CombatSpellOptionView] = []
	if state == null or content == null or state.combat == null or state.combat.active_actor_id() != caster_id:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	for scroll_slot: int in caster.scroll_case().size():
		var scroll := caster.scroll_at(scroll_slot)
		var spell := content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
		if spell == null:
			continue
		if spell.target_type == 0:
			if probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed:
				if _flow()._is_summon_spell(spell):
					result.append(CombatScrollOptionViewType.new(scroll_slot, spell, scroll.power, null, "Choose up to %d open spaces" % scroll.power, &"coordinate_sequence", 0, state.combat.battlefield.actor_position(caster_id), [], scroll.power))
				else:
					var candidates := _character_actor_spell_candidates(state, content, caster, spell, scroll.power)
					result.append(CombatScrollOptionViewType.new(scroll_slot, spell, scroll.power, null, "Choose up to %d actors" % scroll.power, &"sequence", 0, INVALID_COORDINATE, [], scroll.power, candidates))
			continue
		if spell.target_type in [9, 10, 12]:
			if probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed:
				result.append(CombatScrollOptionViewType.new(scroll_slot, spell, scroll.power, null, _group_spell_target_label(spell.target_type), &"automatic"))
			continue
		if spell.target_type in [3, 4]:
			if probe_character_scroll_cast(state, content, caster_id, scroll_slot).allowed:
				var shape := _rules.spell_areas.shape_for(spell, scroll.power)
				var offsets := _rules.spell_areas.pattern(shape)
				var legal_coordinates := _legal_area_spell_target_coordinates(state, content, caster_id, spell, scroll.power, shape)
				result.append(CombatScrollOptionViewType.new(scroll_slot, spell, scroll.power, null, "Choose battlefield point", &"area", shape, state.combat.battlefield.actor_position(caster_id), offsets, 1, [], legal_coordinates))
			continue
		if spell.target_type == 5:
			if probe_character_scroll_cast(state, content, caster_id, scroll_slot, caster_id).allowed:
				result.append(CombatScrollOptionViewType.new(scroll_slot, spell, scroll.power, _spell_target_view(state, content, caster_id)))
			continue
		for target: CombatSpellTargetView in _character_actor_spell_candidates(state, content, caster, spell, scroll.power):
			if probe_character_scroll_cast(state, content, caster_id, scroll_slot, target.id).allowed:
				result.append(CombatScrollOptionViewType.new(scroll_slot, spell, scroll.power, target))
	return result


func character_scroll_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null or state.combat.active_actor_id() != caster_id:
		return "Only the active character may use a scroll."
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return "The active character is unavailable."
	if not _has_equipped_scroll_case(caster, content):
		return "Equip a scroll case before using its spells."
	for scroll_slot: int in caster.scroll_case().size():
		var scroll := caster.scroll_at(scroll_slot)
		if scroll == null or scroll.is_empty():
			continue
		var spell := content.spell_by_id(scroll.spell_id)
		if spell == null:
			return "A stored scroll references an unavailable spell."
		var target_id := caster_id if spell.target_type == 5 else ""
		var probe := probe_character_scroll_cast(state, content, caster_id, scroll_slot, target_id)
		if not probe.allowed:
			return probe.reason_text
	return "The equipped scroll case contains no combat-ready spells."


static func _has_equipped_scroll_case(character: CharacterState, content: RealmzContent) -> bool:
	if character == null or content == null:
		return false
	for instance: ItemInstance in character.inventory():
		var definition := content.item_by_id(instance.definition_id)
		if instance.equipped and definition != null and absi(definition.item_type) == 13:
			return true
	return false


func _legal_area_spell_target_coordinates(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, shape: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if state == null or state.combat == null or state.combat.battlefield == null or content == null or spell == null:
		return result
	var map := content.world.map_by_id(state.combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
	if terrain_set == null:
		return result
	var origin := state.combat.battlefield.actor_position(caster_id)
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	var minimum := Vector2i(maxi(0, origin.x - maximum_range - 1), maxi(0, origin.y - maximum_range - 1))
	var maximum := Vector2i(mini(BattlefieldState.SIZE - 1, origin.x + maximum_range + 1), mini(BattlefieldState.SIZE - 1, origin.y + maximum_range + 1))
	var require_line_of_sight := spell.range_min + spell.range_max > 0
	for y: int in range(minimum.y, maximum.y + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			var coordinate := Vector2i(x, y)
			if _rules.spell_areas.pattern_fits(coordinate, shape) and _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, coordinate, maximum_range, require_line_of_sight):
				result.append(coordinate)
	return result


func _character_actor_spell_candidates(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int) -> Array[CombatSpellTargetView]:
	var result: Array[CombatSpellTargetView] = []
	for character: CharacterState in state.party.characters():
		if character.current_health <= 0 or not state.combat.battlefield.has_actor(character.id):
			continue
		if _spell_actor_target_is_valid(state, content, caster.id, character.id, spell, power_level):
			result.append(CombatSpellTargetView.new(character.id, &"character", character.name, character.current_health, character.maximum_health))
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id):
			continue
		if _spell_actor_target_is_valid(state, content, caster.id, monster.id, spell, power_level):
			result.append(CombatSpellTargetView.new(monster.id, &"monster", monster.name, monster.current_health, monster.maximum_health))
	return result


static func _spell_target_view(state: GameState, content: RealmzContent, target_id: String) -> CombatSpellTargetView:
	var character := state.party.character_by_id(target_id)
	if character != null:
		return CombatSpellTargetView.new(character.id, &"character", character.name, character.current_health, character.maximum_health)
	var monster := state.combat.monster_by_id(target_id) if state.combat != null else null
	if monster != null and content.monster_by_id(monster.definition_id) != null:
		return CombatSpellTargetView.new(monster.id, &"monster", monster.name, monster.current_health, monster.maximum_health)
	return null


func _spell_actor_target_is_valid(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition, power_level: int) -> bool:
	var maximum_range := absi(spell.range_min + spell.range_max * power_level)
	if caster_id == target_id:
		var map := content.world.map_by_id(state.combat.battlefield.map_id)
		var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
		return terrain_set != null and _rules.battlefield.coordinate_target_is_valid(state.combat.battlefield, terrain_set, caster_id, state.combat.battlefield.actor_position(caster_id), maximum_range, spell.range_min + spell.range_max > 0)
	return _flow().projectile_target_is_valid(state.combat, content, caster_id, target_id, maximum_range, spell.range_min + spell.range_max > 0)


static func _spell_target_selection(state: GameState, content: RealmzContent, target_id: String) -> SpellTargetSelection:
	var character := state.party.character_by_id(target_id)
	if character != null and character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
		return SpellTargetSelection.for_character(character)
	var monster := state.combat.monster_by_id(target_id)
	if monster == null or monster.current_health <= 0 or not state.combat.battlefield.has_actor(monster.id):
		return null
	var definition := content.monster_by_id(monster.definition_id)
	return SpellTargetSelection.for_monster(monster, definition) if definition != null else null


static func _group_spell_target_label(target_type: int) -> String:
	return {9: "All Friendly", 10: "All Enemies", 12: "Everybody"}.get(target_type, "Automatic Targets")


static func _group_target_matches(target_type: int, target_traitor: bool, caster_traitor: bool) -> bool:
	if target_type == 12:
		return true
	if target_type == 9:
		return target_traitor == caster_traitor
	return target_traitor != caster_traitor


func character_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if state == null or state.combat == null:
		return ""
	var caster := state.party.character_by_id(caster_id)
	if caster == null or caster.maximum_spell_attacks <= 0 or caster.known_spells().is_empty():
		return ""
	var first_reason := ""
	for spell_id: String in caster.known_spells():
		for power_level: int in range(1, 8):
			var probe := probe_character_spell_choice(state, content, caster_id, spell_id, power_level)
			if probe.allowed:
				return ""
			if first_reason.is_empty() and not probe.reason_text.is_empty():
				first_reason = probe.reason_text
	return first_reason
