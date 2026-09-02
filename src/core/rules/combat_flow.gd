class_name CombatFlow
extends RefCounted

const ContextType = preload("res://src/core/rules/combat_flow_context.gd")
const CombatRetreatProbeType = preload("res://src/core/rules/combat_retreat_probe.gd")
const CombatCommandProbeType = preload("res://src/core/rules/combat_command_probe.gd")
const LifecycleType = preload("res://src/core/rules/combat_flow_lifecycle.gd")
const ActionsType = preload("res://src/core/rules/combat_flow_actions.gd")
const ReactionsType = preload("res://src/core/rules/combat_flow_reactions.gd")
const MagicType = preload("res://src/core/rules/combat_flow_magic.gd")
const FieldsType = preload("res://src/core/rules/combat_flow_fields.gd")
const SummoningType = preload("res://src/core/rules/combat_flow_summoning.gd")
const PhaseType = preload("res://src/core/rules/combat_flow_phase.gd")
const AutomationType = preload("res://src/core/rules/combat_flow_automation.gd")

const MONSTER_ATTACK_COMPLETED := 0
const MONSTER_ATTACK_WAITING := 1
const MONSTER_ATTACK_DEATH_MACRO := 2
const MONSTER_ATTACK_FALLBACK := 3
const REACTION_COMPLETED := 0
const REACTION_WAITING := 1
const REACTION_DEATH_MACRO := 2
const REACTION_MOVER_DEFEATED := 3
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var _rules: ContextType
var _lifecycle: RefCounted
var _actions: RefCounted
var _reactions: RefCounted
var _magic: RefCounted
var _fields: RefCounted
var _summoning: RefCounted
var _phase: RefCounted
var _automation: RefCounted


func _init(rules: RealmzRules) -> void:
	_rules = ContextType.new(rules)
	_lifecycle = LifecycleType.new(self, _rules)
	_actions = ActionsType.new(self, _rules)
	_reactions = ReactionsType.new(self, _rules)
	_magic = MagicType.new(self, _rules)
	_fields = FieldsType.new(self, _rules)
	_summoning = SummoningType.new(self, _rules)
	_phase = PhaseType.new(self, _rules)
	_automation = AutomationType.new(self, _rules)


func is_processing_auto() -> bool:
	return _rules.processing_auto


func set_processing_auto(value: bool) -> void:
	_rules.processing_auto = value

func start_battle(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0, participant_character_ids: Array[String] = []) -> CombatFlowResult:
	return _lifecycle.start_battle(state, content, battle, rng, surprise, participant_character_ids)


func _battle_setup_failure(state: GameState, instance_checkpoint: int, rng: RealmzRng, checkpoint: Dictionary, code: StringName, message: String) -> CombatFlowResult:
	return _lifecycle._battle_setup_failure(state, instance_checkpoint, rng, checkpoint, code, message)


func submit_action(state: GameState, content: RealmzContent, actor_id: String, action: StringName, target_id: String, rng: RealmzRng, allow_friendly_contact: bool = false) -> CombatFlowResult:
	return _actions.submit_action(state, content, actor_id, action, target_id, rng, allow_friendly_contact)


func probe_delay(state: GameState, actor_id: String) -> CombatCommandProbeType:
	return _actions.probe_delay(state, actor_id)


func probe_undo(state: GameState, actor_id: String) -> CombatCommandProbeType:
	return _actions.probe_undo(state, actor_id)


func bandage_candidate_ids(state: GameState) -> Array[String]:
	return _actions.bandage_candidate_ids(state)


func probe_bandage(state: GameState, actor_id: String, target_id: String = "") -> CombatCommandProbeType:
	return _actions.probe_bandage(state, actor_id, target_id)


func turn_undead_target_ids(state: GameState, content: RealmzContent) -> Array[String]:
	return _actions.turn_undead_target_ids(state, content)


func probe_turn_undead(state: GameState, content: RealmzContent, actor_id: String) -> CombatCommandProbeType:
	return _actions.probe_turn_undead(state, content, actor_id)


func _turn_undead(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	return _actions._turn_undead(state, content, actor, rng)


func _is_fresh_character_activation(combat: CombatState, actor: CharacterState) -> bool:
	return _actions._is_fresh_character_activation(combat, actor)


func _mark_character_bleeding(state: GameState, character: CharacterState, defeated: bool) -> void:
	_actions._mark_character_bleeding(state, character, defeated)


func _advance_turn(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	_lifecycle._advance_turn(state, content, rng, events)


func _resolve_persistent_field_collisions(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng, events: Array[DomainEvent], retain_turn_collisions: bool = true, begin_death_macros: bool = true) -> int:
	return _fields.resolve_actor_collisions(state, content, actor_id, rng, events, retain_turn_collisions, begin_death_macros)


func _begin_persistent_field_death_macros(combat: CombatState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	return _fields.begin_pending_death_macros(combat, content, events)


func _process_bleeding_round(state: GameState, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	_lifecycle._process_bleeding_round(state, rng, events)


func run_auto_turn(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	return _automation.run_auto_turn(state, content, actor_id, rng)


func run_auto_activation_chain(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	return _automation.run_auto_activation_chain(state, content, actor_id, rng)


func run_persistent_auto_characters(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	return _automation.run_persistent_auto_characters(state, content, rng)


func _auto_projectile_or_move(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	return _automation._auto_projectile_or_move(state, content, actor, rng)


func _auto_move_toward_target(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng) -> CombatFlowResult:
	return _automation._auto_move_toward_target(state, content, actor, rng)


func _events_include(events: Array[DomainEvent], kind: StringName) -> bool:
	return _automation._events_include(events, kind)


func probe_character_retreat(combat: CombatState, characters: Array[CharacterState], actor_id: String):
	return _reactions.probe_character_retreat(combat, characters, actor_id)


func character_projectile_profile(character: CharacterState, content: RealmzContent, equipment: CharacterCombatEquipment = null) -> ProjectileAttackProfile:
	return _reactions.character_projectile_profile(character, content, equipment)


func projectile_target_is_valid(combat: CombatState, content: RealmzContent, actor_id: String, target_id: String, maximum_range: int, require_line_of_sight: bool = true) -> bool:
	return _reactions.projectile_target_is_valid(combat, content, actor_id, target_id, maximum_range, require_line_of_sight)


func probe_edge_retreat(combat: CombatState, actor_id: String, destination: Vector2i):
	return _reactions.probe_edge_retreat(combat, actor_id, destination)


func retreat_character(state: GameState, content: RealmzContent, actor_id: String, mode: StringName, destination: Vector2i, rng: RealmzRng) -> CombatFlowResult:
	return _reactions.retreat_character(state, content, actor_id, mode, destination, rng)


func move_character(state: GameState, content: RealmzContent, actor_id: String, destination: Vector2i, rng: RealmzRng, auto_switch_to_melee: bool = false, friendly_collision_action: StringName = &"") -> CombatFlowResult:
	return _reactions.move_character(state, content, actor_id, destination, rng, auto_switch_to_melee, friendly_collision_action)


func friendly_collision_target_id(state: GameState, actor_id: String, destination: Vector2i) -> String:
	return _reactions.friendly_collision_target_id(state, actor_id, destination)


func _classic_projectile_uses_point_blank_auto_switch(actor: CharacterState, content: RealmzContent) -> bool:
	return _reactions._classic_projectile_uses_point_blank_auto_switch(actor, content)


func _continue_pending_reaction(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _reactions._continue_pending_reaction(state, content, rng, events)


func _commit_reaction_move(state: GameState, content: RealmzContent, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _reactions._commit_reaction_move(state, content, reaction, rng, events)


func _resolve_reaction_attack(state: GameState, content: RealmzContent, attacker_id: String, reaction: CombatReactionState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _reactions._resolve_reaction_attack(state, content, attacker_id, reaction, rng, events)


func _resolve_character_reaction(state: GameState, content: RealmzContent, attacker: CharacterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _reactions._resolve_character_reaction(state, content, attacker, target_id, action, behind, rng, events)


func _resolve_monster_reaction(state: GameState, content: RealmzContent, attacker: MonsterState, target_id: String, action: StringName, behind: bool, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _reactions._resolve_monster_reaction(state, content, attacker, target_id, action, behind, rng, events)


func _append_reaction_identity(event: DomainEvent, action: StringName, behind: bool) -> void:
	_reactions._append_reaction_identity(event, action, behind)


func _guarding_hostiles(state: GameState, mover_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	return _reactions._guarding_hostiles(state, mover_id, anchor_override)


func _withdrawal_hostiles(state: GameState, reaction: CombatReactionState) -> Array[String]:
	return _reactions._withdrawal_hostiles(state, reaction)


func _guarding_actor_ids(state: GameState, actor_ids: Array[String]) -> Array[String]:
	return _reactions._guarding_actor_ids(state, actor_ids)


func _combatant_is_alive(state: GameState, actor_id: String) -> bool:
	return _reactions._combatant_is_alive(state, actor_id)


func _combatant_is_helpless(state: GameState, actor_id: String) -> bool:
	return _reactions._combatant_is_helpless(state, actor_id)


func _combatant_is_invisible(state: GameState, actor_id: String) -> bool:
	return _reactions._combatant_is_invisible(state, actor_id)


func cause_active_fumble(state: GameState, content: RealmzContent, actor_id: String) -> CombatFlowResult:
	return _actions.cause_active_fumble(state, content, actor_id)


func probe_character_item_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	return _magic.probe_character_item_spell(state, content, caster_id, target_id, instance_id, target_coordinate, rotation, target_ids, target_coordinates)


func use_spell_item(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	return _magic.use_spell_item(state, content, caster_id, target_id, instance_id, rng, target_coordinate, rotation, target_ids, target_coordinates)


func character_item_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatItemOptionView]:
	var result: Array[CombatItemOptionView] = _magic.character_item_spell_options(state, content, caster_id)
	if state == null or content == null or state.combat == null or state.combat.completed or state.combat.active_actor_id() != caster_id:
		return result
	var caster := state.party.character_by_id(caster_id)
	if caster == null:
		return result
	var staged_instance_id := state.combat.staged_random_item_instance_id()
	for instance: ItemInstance in caster.inventory():
		var item := content.item_by_id(instance.definition_id)
		if item == null or item.special_1 != -23 or not staged_instance_id.is_empty() and staged_instance_id != instance.id:
			continue
		var probe := _rules.inventory.classic_door_item_probe(caster, instance, item, content.race_by_id(caster.race_id), content.caste_by_id(caster.caste_id), true, content.scenario.program_by_id("xap:%d" % item.special_5) != null)
		if probe.allowed:
			result.append(CombatItemOptionView.new(instance, item, null, 0, null, "Scenario action", &"automatic"))
	return result


func character_item_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	if not character_item_spell_options(state, content, caster_id).is_empty():
		return ""
	return _magic.character_item_spell_unavailable_reason(state, content, caster_id)


func _inventory_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	return _magic._inventory_instance(character, instance_id)


func _item_use_reason_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	return _magic._item_use_reason_code(instance, item, spell)


func _item_used_event(caster_id: String, instance_id: String, item: ItemDefinition, spell: SpellDefinition, power_level: int, caster: CharacterState) -> DomainEvent:
	return _magic._item_used_event(caster_id, instance_id, item, spell, power_level, caster)


func cast_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, rng: RealmzRng, target_coordinate: Vector2i = Vector2i(-100_000, -100_000), rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	return _magic.cast_spell(state, content, caster_id, target_id, spell_id, power_level, rng, target_coordinate, rotation, target_ids, target_coordinates)


func probe_character_scroll_cast(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String = "", target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	return _magic.probe_character_scroll_cast(state, content, caster_id, scroll_slot, target_id, target_coordinate, rotation, target_ids, target_coordinates)


func use_combat_scroll(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	return _magic.use_combat_scroll(state, content, caster_id, scroll_slot, target_id, rng, target_coordinate, rotation, target_ids, target_coordinates)


func _combat_spell_group_targets(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, selected_ids: Dictionary = {}, area_target: bool = false) -> Dictionary:
	return _magic._combat_spell_group_targets(state, content, caster, spell, selected_ids, area_target)


func _rollback_combat_scroll(state: GameState, rng: RealmzRng, state_checkpoint: Dictionary, rng_checkpoint: Dictionary, error_code: StringName, error_message: String) -> CombatFlowResult:
	return _magic._rollback_combat_scroll(state, rng, state_checkpoint, rng_checkpoint, error_code, error_message)


func _cast_character_group_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> CombatFlowResult:
	return _magic._cast_character_group_spell(state, content, caster, spell, power_level, cast_level, rng)


func _cast_character_area_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, center: Vector2i, rotation: int) -> CombatFlowResult:
	return _magic._cast_character_area_spell(state, content, caster, spell, power_level, cast_level, rng, center, rotation)


func _commit_character_multi_spell(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, group: GroupSpellResolution, rng: RealmzRng, center: Vector2i = Vector2i(-100_000, -100_000), shape: int = 0, event_source: String = "classic", item_instance_id: String = "", count_spell_cast: bool = true, persistent_fields: Array = []) -> CombatFlowResult:
	return _magic._commit_character_multi_spell(state, content, caster, spell, power_level, cast_level, group, rng, center, shape, event_source, item_instance_id, count_spell_cast, persistent_fields)


func _append_spell_sound(events: Array[DomainEvent], authored_sound_id: int, source: String) -> void:
	_magic._append_spell_sound(events, authored_sound_id, source)


func _append_spell_cast_event(events: Array[DomainEvent], actor_id: String, spell: SpellDefinition, resolutions: GroupSpellResolution, center: Vector2i, shape: int, source: String) -> void:
	_magic._append_spell_cast_event(events, actor_id, spell, resolutions, center, shape, source)


func _append_spell_projectile_event(events: Array[DomainEvent], actor_id: String, target_id: String, spell: SpellDefinition, source: String) -> void:
	_magic._append_spell_projectile_event(events, actor_id, target_id, spell, source)


func _append_spell_presentation(payload: Dictionary, spell: SpellDefinition, sequence_index: int, sequence_count: int, target_defeated: bool) -> void:
	_magic._append_spell_presentation(payload, spell, sequence_index, sequence_count, target_defeated)


func _queue_persistent_field(combat: CombatState, caster_id: String, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, center: Vector2i, rotation: int, shape: int) -> RefCounted:
	return _fields.queue_persistent_field(combat, caster_id, spell, power_level, cast_level, rng, center, rotation, shape)


func _queue_single_actor_field(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> RefCounted:
	return _fields.queue_single_actor_field(state, caster_id, target_id, spell, power_level, cast_level, rng)


func _repeated_field_callback(state: GameState, spell: SpellDefinition, caster_id: String, selected_target_ids: Array[String], power_level: int, cast_level: int, rng: RealmzRng, created_fields: Array[RefCounted]) -> Callable:
	return _fields.repeated_field_callback(state, spell, caster_id, selected_target_ids, power_level, cast_level, rng, created_fields)


func _append_persistent_field_events(events: Array[DomainEvent], fields: Array, source: String) -> void:
	_fields.append_created_events(events, fields, source)


func probe_character_spell_cast(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatSpellCastProbe:
	return _magic.probe_character_spell_cast(state, content, caster_id, target_id, spell_id, power_level, target_coordinate, rotation, target_ids, target_coordinates)


func probe_character_spell_choice(state: GameState, content: RealmzContent, caster_id: String, spell_id: String, power_level: int) -> CombatSpellCastProbe:
	return _magic.probe_character_spell_choice(state, content, caster_id, spell_id, power_level)


func character_spell_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	return _magic.character_spell_options(state, content, caster_id)


func character_scroll_options(state: GameState, content: RealmzContent, caster_id: String) -> Array[CombatSpellOptionView]:
	return _magic.character_scroll_options(state, content, caster_id)


func character_scroll_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	return _magic.character_scroll_unavailable_reason(state, content, caster_id)


func _legal_area_spell_target_coordinates(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, shape: int) -> Array[Vector2i]:
	return _magic._legal_area_spell_target_coordinates(state, content, caster_id, spell, power_level, shape)


func _is_summon_spell(spell: SpellDefinition) -> bool:
	return SummoningType.is_summon_spell(spell)


func _probe_summon_choice(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int) -> CombatSpellCastProbe:
	return _summoning.probe_choice(state, content, caster_id, spell, power_level)


func _probe_summon_coordinates(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, target_coordinates: Array[Vector2i]) -> CombatSpellCastProbe:
	return _summoning.probe_coordinates(state, content, caster_id, spell, power_level, target_coordinates)


func _cast_character_summon(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, rng: RealmzRng, target_coordinates: Array[Vector2i], event_source: String = "classic", spend_spell_points: bool = true, count_spell_cast: bool = true) -> CombatFlowResult:
	return _summoning.cast_character_summon(state, content, caster, spell, power_level, rng, target_coordinates, event_source, spend_spell_points, count_spell_cast)


func _cast_monster_summon(state: GameState, content: RealmzContent, caster: MonsterState, spell: SpellDefinition, power_level: int, rng: RealmzRng, target_coordinates: Array[Vector2i]) -> CombatFlowResult:
	return _summoning.cast_monster_summon(state, content, caster, spell, power_level, rng, target_coordinates)


func _automatic_summon_coordinate(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int) -> Vector2i:
	return _summoning.automatic_coordinate(state, content, caster, spell, power_level)


func _automatic_monster_summon_coordinate(state: GameState, content: RealmzContent, caster: MonsterState, spell: SpellDefinition, power_level: int) -> Vector2i:
	return _summoning.automatic_monster_coordinate(state, content, caster, spell, power_level)


func _cast_character_phase(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, destination: Vector2i, spend_spell_points: bool = true, event_source: String = "classic", count_spell_cast: bool = true) -> CombatFlowResult:
	return _phase.cast_character_phase(state, content, caster, spell, power_level, cast_level, rng, destination, spend_spell_points, event_source, count_spell_cast)


func _phase_checkpoint_available(combat: CombatState, caster_id: String) -> bool:
	return _phase.checkpoint_available(combat, caster_id)


func _probe_phase_destination(state: GameState, content: RealmzContent, caster_id: String, spell: SpellDefinition, power_level: int, destination: Vector2i) -> CombatSpellCastProbe:
	return _phase.probe_destination(state, content, caster_id, spell, power_level, destination)


func _character_actor_spell_candidates(state: GameState, content: RealmzContent, caster: CharacterState, spell: SpellDefinition, power_level: int) -> Array[CombatSpellTargetView]:
	return _magic._character_actor_spell_candidates(state, content, caster, spell, power_level)


func _spell_target_view(state: GameState, content: RealmzContent, target_id: String) -> CombatSpellTargetView:
	return _magic._spell_target_view(state, content, target_id)


func _spell_actor_target_is_valid(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition, power_level: int) -> bool:
	return _magic._spell_actor_target_is_valid(state, content, caster_id, target_id, spell, power_level)


func _spell_target_selection(state: GameState, content: RealmzContent, target_id: String) -> SpellTargetSelection:
	return _magic._spell_target_selection(state, content, target_id)


func ray_spell_actor_ids(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell: SpellDefinition) -> Array[String]:
	return _magic.ray_spell_actor_ids(state, content, caster_id, target_id, spell)


func _group_spell_target_label(target_type: int) -> String:
	return _magic._group_spell_target_label(target_type)


func _group_target_matches(target_type: int, target_traitor: bool, caster_traitor: bool) -> bool:
	return _magic._group_target_matches(target_type, target_traitor, caster_traitor)


func character_spell_unavailable_reason(state: GameState, content: RealmzContent, caster_id: String) -> String:
	return _magic.character_spell_unavailable_reason(state, content, caster_id)


func continue_after_monster_death_macro(state: GameState, content: RealmzContent, rng: RealmzRng, completed_combatant_id: String = "") -> CombatFlowResult:
	return _lifecycle.continue_after_monster_death_macro(state, content, rng, completed_combatant_id)


func finalize_scenario_monster_destruction(state: GameState, content: RealmzContent) -> CombatFlowResult:
	return _lifecycle.finalize_scenario_monster_destruction(state, content)


func continue_after_age_update(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	return _lifecycle.continue_after_age_update(state, content, rng)


func ally_selection_payload(state: GameState, content: RealmzContent) -> Dictionary:
	return _lifecycle.ally_selection_payload(state, content)


func apply_ally_selection(state: GameState, content: RealmzContent, selected_value: Variant) -> CombatFlowResult:
	return _lifecycle.apply_ally_selection(state, content, selected_value)


func fumble_recovery_payload(state: GameState, content: RealmzContent) -> Dictionary:
	return _lifecycle.fumble_recovery_payload(state, content)


func apply_fumble_recovery(state: GameState, content: RealmzContent, action: StringName, instance_id: String, character_id: String = "") -> CombatFlowResult:
	return _lifecycle.apply_fumble_recovery(state, content, action, instance_id, character_id)


func _fire_character_projectile(state: GameState, content: RealmzContent, actor: CharacterState, equipment: CharacterCombatEquipment, target_id: String, rng: RealmzRng) -> CombatFlowResult:
	return _actions._fire_character_projectile(state, content, actor, equipment, target_id, rng)


func _projectile_spell_unavailable_reason(spell: SpellDefinition) -> String:
	return _actions._projectile_spell_unavailable_reason(spell)


func _prepare_character_turn(combat: CombatState, character: CharacterState) -> void:
	_actions._prepare_character_turn(combat, character)


func _consume_character_attack(character: CharacterState) -> void:
	_actions._consume_character_attack(character)


func _character_can_continue(character: CharacterState) -> bool:
	return _actions._character_can_continue(character)


func _process_monster_turns(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	_automation._process_monster_turns(state, content, rng, events)


func _process_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _automation._process_monster_cast(state, content, monster, definition, active_turn, rng, events)


func _monster_can_retry_cast(state: GameState, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState) -> bool:
	return _automation._monster_can_retry_cast(state, monster, definition, active_turn)


func _monster_spell_unavailable_reason(spell: SpellDefinition) -> String:
	return _automation._monster_spell_unavailable_reason(spell)


func _is_source_backed_combat_healing_spell(spell: SpellDefinition) -> bool:
	return _automation._is_source_backed_combat_healing_spell(spell)


func _process_monster_advance(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _automation._process_monster_advance(state, content, monster, definition, active_turn, rng, events)


func _process_monster_projectile(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _automation._process_monster_projectile(state, content, monster, definition, active_turn, rng, events)


func _process_monster_retreat(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _automation._process_monster_retreat(state, content, monster, definition, active_turn, rng, events)


func _retreating_monster_reached_edge(state: GameState, content: RealmzContent, monster_id: String, destination: Vector2i, events: Array[DomainEvent]) -> bool:
	return _automation._retreating_monster_reached_edge(state, content, monster_id, destination, events)


func _resolve_monster_attack_row(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _automation._resolve_monster_attack_row(state, content, monster, definition, attack_index, active_turn, rng, events)


func _select_adjacent_monster_target(state: GameState, monster: MonsterState, rng: RealmzRng) -> String:
	return _automation._select_adjacent_monster_target(state, monster, rng)


func _monster_projectile_target_ids(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, maximum_range: int) -> Array[String]:
	return _automation._monster_projectile_target_ids(state, monster, terrain_set, maximum_range)


func _prepare_monster_melee_weapon(monster: MonsterState, definition: MonsterDefinition, content: RealmzContent) -> void:
	_automation._prepare_monster_melee_weapon(monster, definition, content)


func _select_visible_monster_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition, rng: RealmzRng) -> String:
	return _automation._select_visible_monster_target(state, monster, terrain_set, rng)


func _scan_visible_monster_target(state: GameState, monster: MonsterState, terrain_set: BattleTerrainSetDefinition) -> String:
	return _automation._scan_visible_monster_target(state, monster, terrain_set)


func _monster_target_id_for_slot(state: GameState, monster: MonsterState, slot: int) -> String:
	return _automation._monster_target_id_for_slot(state, monster, slot)


func _has_available_monster_target(state: GameState, monster: MonsterState) -> bool:
	return _automation._has_available_monster_target(state, monster)


func _monster_target_is_available(state: GameState, monster: MonsterState, target_id: String) -> bool:
	return _automation._monster_target_is_available(state, monster, target_id)


func _monster_movement_allowance(monster: MonsterState, definition: MonsterDefinition) -> int:
	return _automation._monster_movement_allowance(monster, definition)


func _monster_attack_limit(definition: MonsterDefinition) -> int:
	return _automation._monster_attack_limit(definition)


func _process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	return _automation._process_charmed_character_turn(state, content, actor, rng, events)


func _hostile_adjacent_ids(state: GameState, actor_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	return _automation._hostile_adjacent_ids(state, actor_id, anchor_override)


func _hostile_contact_target_id(state: GameState, actor_id: String, destination_or_target: Variant) -> String:
	return _automation._hostile_contact_target_id(state, actor_id, destination_or_target)


func _remove_defeated_position(combat: CombatState, actor_id: String, defeated: bool) -> void:
	_automation._remove_defeated_position(combat, actor_id, defeated)


func _remove_all_defeated_positions(state: GameState) -> void:
	_automation._remove_all_defeated_positions(state)


func _battle_terrain_set(content: RealmzContent, battlefield: BattlefieldState) -> BattleTerrainSetDefinition:
	return _automation._battle_terrain_set(content, battlefield)


func _movement_failure_message(result: BattlefieldStepResult) -> String:
	return _automation._movement_failure_message(result)


func _character_attack_event(actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution, armed: bool) -> DomainEvent:
	return _actions._character_attack_event(actor_id, target_id, target_kind, resolution, armed)


func _append_physical_result_effect(event: DomainEvent, hit: bool, armed: bool) -> void:
	_actions._append_physical_result_effect(event, hit, armed)


func _commit_character_fumble(state: GameState, character: CharacterState, equipment: CharacterCombatEquipment, events: Array[DomainEvent]) -> bool:
	return _actions._commit_character_fumble(state, character, equipment, events)


func _commit_monster_fumble(monster: MonsterState, events: Array[DomainEvent]) -> void:
	_actions._commit_monster_fumble(monster, events)


func _append_fumble_feedback(events: Array[DomainEvent], actor_id: String, item: ItemInstance, player_weapon: bool, monster_weapon_id: String = "") -> void:
	_actions._append_fumble_feedback(events, actor_id, item, player_weapon, monster_weapon_id)


func _append_monster_special_events(events: Array[DomainEvent], actor_id: String, target_id: String, target_kind: StringName, resolution: AttackResolution) -> void:
	_actions._append_monster_special_events(events, actor_id, target_id, target_kind, resolution)


func _append_monster_physical_feedback(events: Array[DomainEvent], sound_id: int) -> void:
	_actions._append_monster_physical_feedback(events, sound_id)


func _append_character_attack_audio(events: Array[DomainEvent], attacker: CharacterState, equipment: CharacterCombatEquipment, resolution: AttackResolution, target_kind: StringName) -> void:
	_actions._append_character_attack_audio(events, attacker, equipment, resolution, target_kind)


func _append_monster_attack_audio(events: Array[DomainEvent], attacker: MonsterState, definition: MonsterDefinition, attack_index: int, weapon: ItemDefinition, resolution: AttackResolution, rng: RealmzRng) -> void:
	_actions._append_monster_attack_audio(events, attacker, definition, attack_index, weapon, resolution, rng)


func _weapon_requirement_sound(reason: StringName) -> int:
	return _actions._weapon_requirement_sound(reason)


func _append_attack_sound(events: Array[DomainEvent], native_sound_id: int) -> void:
	_actions._append_attack_sound(events, native_sound_id)


func _request_monster_death_macro(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent]) -> bool:
	return _actions._request_monster_death_macro(monster, definition, events)


func _queue_spell_death_macro(combat: CombatState, monster: MonsterState, definition: MonsterDefinition) -> bool:
	return _actions._queue_spell_death_macro(combat, monster, definition)


func _request_next_spell_death_macro(combat: CombatState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	return _actions._request_next_spell_death_macro(combat, content, events)


func _append_monster_death_macro_request(monster: MonsterState, definition: MonsterDefinition, events: Array[DomainEvent], queued_by_spell: bool) -> void:
	_actions._append_monster_death_macro_request(monster, definition, events, queued_by_spell)


func _finish_if_resolved(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	return _lifecycle._finish_if_resolved(state, content, events)


func finish_debug_victory(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	return _lifecycle._finish_if_resolved(state, content, events)


func finish_classic_macro_victory(state: GameState, content: RealmzContent) -> CombatFlowResult:
	return _lifecycle.finish_classic_macro_victory(state, content)


func _complete_battle(state: GameState, _content: RealmzContent, outcome: StringName, events: Array[DomainEvent]) -> void:
	_lifecycle._complete_battle(state, _content, outcome, events)


func _has_loyal_battlefield_character(state: GameState) -> bool:
	return _lifecycle._has_loyal_battlefield_character(state)


func _has_living_retreated_character(state: GameState) -> bool:
	return _lifecycle._has_living_retreated_character(state)


func _restore_party_allegiance(state: GameState, events: Array[DomainEvent]) -> void:
	_lifecycle._restore_party_allegiance(state, events)
