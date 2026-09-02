class_name CombatFlowFields
extends RefCounted

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const PersistentCombatFieldType = preload("res://src/core/state/persistent_combat_field.gd")

const COLLISION_COMPLETED := 0
const COLLISION_DEFEATED := 1
const COLLISION_DEATH_MACRO := 2
const COLLISION_INVALID := 3
const CLEARED_TARGET_QUEUE_SHAPE := 127

var _flow_ref: WeakRef
var _rules: ContextType


func _init(flow: RefCounted, rules: ContextType) -> void:
	_flow_ref = weakref(flow)
	_rules = rules


func _flow() -> RefCounted:
	return _flow_ref.get_ref() if _flow_ref != null else null


func queue_persistent_field(combat: CombatState, caster_id: String, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, center: Vector2i, rotation: int, shape: int) -> RefCounted:
	if combat == null or caster_id.is_empty() or not ClassicSpellCapabilityCatalog.is_combat_persistent_field_spell(spell) or not combat.can_queue_persistent_field():
		return null
	var duration := _rules.magic.roll_persistent_field_duration(spell, power_level, rng, StringName("combat.field.%s.duration" % spell.id))
	if duration <= 0:
		return null
	return combat.queue_persistent_field(spell.id, caster_id, center, rotation if spell.can_rotate else 0, shape, spell.queue_icon, power_level, cast_level, duration)


func queue_single_actor_field(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> RefCounted:
	if state == null or state.combat == null or not ClassicSpellCapabilityCatalog.is_combat_single_actor_field_spell(spell) or not state.combat.can_queue_persistent_field():
		return null
	var duration := _rules.magic.roll_persistent_field_duration(spell, power_level, rng, StringName("combat.actor-field.%s.duration" % spell.id))
	return state.combat.queue_persistent_field(spell.id, caster_id, _classic_target_selector(state, target_id), 0, 1, spell.queue_icon, power_level, cast_level, duration)


func repeated_field_callback(state: GameState, spell: SpellDefinition, caster_id: String, selected_target_ids: Array[String], power_level: int, cast_level: int, rng: RealmzRng, created_fields: Array[RefCounted]) -> Callable:
	if state == null or state.combat == null or not ClassicSpellCapabilityCatalog.is_combat_repeated_field_spell(spell) or selected_target_ids.is_empty():
		return Callable()
	var first_center := _classic_target_selector(state, selected_target_ids[0])
	return func(index: int) -> void:
		if not state.combat.can_queue_persistent_field():
			return
		var duration := _rules.magic.roll_persistent_field_duration(spell, power_level, rng, StringName("combat.repeated-field.%s.%d.duration" % [spell.id, index]))
		var center := first_center if index == 0 else Vector2i.ZERO
		var shape := 1 if index == 0 else CLEARED_TARGET_QUEUE_SHAPE
		var field := state.combat.queue_persistent_field(spell.id, caster_id, center, 0, shape, spell.queue_icon, power_level, cast_level, duration)
		if field != null:
			created_fields.append(field)


static func append_created_events(events: Array[DomainEvent], fields: Array, source: String) -> void:
	for field: Variant in fields:
		if field != null:
			events.append(DomainEvent.new(&"combat_persistent_field_created", {"slot": field.slot, "spellId": field.spell_id, "casterId": field.caster_id, "center": [field.center.x, field.center.y], "rotation": field.rotation, "shape": field.shape, "queueIcon": field.queue_icon, "power": field.power_level, "classicTier": field.cast_level, "duration": field.remaining_duration, "phaseTurnIndex": field.phase_turn_index, "source": source}))


static func _classic_target_selector(state: GameState, target_id: String) -> Vector2i:
	var characters := state.party.characters()
	for index: int in characters.size():
		if characters[index].id == target_id:
			return Vector2i(index, 1)
	var monsters := state.combat.monsters()
	for index: int in monsters.size():
		if monsters[index].id == target_id:
			return Vector2i(index + 10, 2)
	return Vector2i.ZERO


func resolve_actor_collisions(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng, events: Array[DomainEvent], retain_turn_collisions: bool = true, begin_death_macros: bool = true) -> int:
	if state == null or content == null or rng == null or state.combat == null or state.combat.battlefield == null or actor_id.is_empty():
		return COLLISION_INVALID
	var combat := state.combat
	var character := state.party.character_by_id(actor_id)
	var monster := combat.monster_by_id(actor_id)
	if character == null and monster == null:
		return COLLISION_INVALID
	if not combat.battlefield.has_actor(actor_id):
		return COLLISION_COMPLETED
	var footprint := combat.battlefield.actor_footprint(actor_id)
	for field: PersistentCombatFieldType in combat.persistent_fields():
		if retain_turn_collisions and combat.has_persistent_field_collision(field.slot):
			continue
		var spell := content.spell_by_id(field.spell_id)
		var character_caster := state.party.character_by_id(field.caster_id)
		var monster_caster := combat.monster_by_id(field.caster_id)
		if spell == null or character_caster == null and monster_caster == null:
			return COLLISION_INVALID
		if not _field_intersects_footprint(field, footprint):
			continue
		var character_targets: Array[CharacterState] = []
		var monster_targets: Array[MonsterState] = []
		var monster_definitions: Array[MonsterDefinition] = []
		var selections: Array[SpellTargetSelection] = []
		if character != null:
			character_targets.append(character)
			selections.append(SpellTargetSelection.for_character(character))
		else:
			var definition := content.monster_by_id(monster.definition_id)
			if definition == null:
				return COLLISION_INVALID
			monster_targets.append(monster)
			monster_definitions.append(definition)
			selections.append(SpellTargetSelection.for_monster(monster, definition))
		var group: GroupSpellResolution
		if character_caster != null:
			group = _rules.magic.resolve_character_group_spell(character_caster, character_targets, monster_targets, monster_definitions, spell, field.power_level, field.cast_level, rng, false, false)
		else:
			var caster_definition := content.monster_by_id(monster_caster.definition_id)
			if caster_definition == null:
				return COLLISION_INVALID
			group = _rules.magic.resolve_monster_group_spell(monster_caster, caster_definition, selections, spell, field.power_level, field.cast_level, rng, false, false)
		if group == null or not group.cast or group.resolutions.size() != 1:
			return COLLISION_INVALID
		var resolution: SpellResolution = group.resolutions[0]
		if retain_turn_collisions and _collision_consumes_field(spell, group, resolution):
			combat.mark_persistent_field_collision(field.slot)
		if resolution.damage > 0 or resolution.damage < 0 and monster != null:
			combat.mark_attacked(actor_id)
		var payload := {"actorId": field.caster_id, "targetId": actor_id, "targetKind": "character" if character != null else "monster", "spellId": spell.id, "targetType": spell.target_type, "power": field.power_level, "classicTier": field.cast_level, "reflected": false, "resisted": resolution.resisted, "saved": resolution.saved, "damage": resolution.damage, "healing": maxi(0, -resolution.damage), "duration": resolution.duration, "defeated": resolution.target_defeated, "fieldSlot": field.slot, "areaCenter": [field.center.x, field.center.y], "areaShape": field.shape, "source": "classic-persistent-field", "detectedMagicItemCount": resolution.detected_magic_item_count}
		if resolution.applied_condition >= 0:
			payload["appliedCondition"] = resolution.applied_condition
		events.append(DomainEvent.new(&"combat_spell_resolved", payload))
	var defeated := character != null and character.current_health <= 0 or monster != null and monster.current_health <= 0
	if not defeated:
		return COLLISION_COMPLETED
	if character != null:
		_flow()._remove_defeated_position(combat, actor_id, true)
	else:
		var definition := content.monster_by_id(monster.definition_id)
		var queued: bool = _flow()._queue_spell_death_macro(combat, monster, definition)
		_flow()._remove_defeated_position(combat, actor_id, not queued)
	if begin_death_macros and not combat.pending_spell_death_macro_id().is_empty():
		return COLLISION_DEATH_MACRO if begin_pending_death_macros(combat, content, events) else COLLISION_INVALID
	return COLLISION_DEFEATED


func begin_pending_death_macros(combat: CombatState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	if combat == null or content == null or combat.pending_spell_death_macro_id().is_empty():
		return false
	if not combat.spell_macro_actor_id().is_empty():
		return true
	return combat.begin_spell_death_macro_sequence(combat.active_actor_id(), false) and _flow()._request_next_spell_death_macro(combat, content, events)


func _field_intersects_footprint(field: PersistentCombatFieldType, footprint: Array[Vector2i]) -> bool:
	var covered: Dictionary = {}
	for offset: Vector2i in _rules.spell_areas.pattern(field.shape):
		covered[field.center + offset] = true
	return footprint.any(func(coordinate: Vector2i) -> bool: return covered.has(coordinate))


static func _collision_consumes_field(spell: SpellDefinition, group: GroupSpellResolution, resolution: SpellResolution) -> bool:
	var damage_type := absi(spell.damage_type)
	return damage_type > 0 and damage_type < 8 and not resolution.resisted and not (resolution.saved and group.base_damage == 0)
