## Provides the narrow command surface for deterministic combat transactions.

class_name CombatFlow
extends RefCounted

const CombatBattleSetup = preload("res://src/game/combat/combat_battle_setup.gd")
const INVALID_COORDINATE := Vector2i(-100_000, -100_000)

var rounds: CombatFlowLifecycle
var actions: CombatFlowActions
var reactions: CombatFlowReactions
var magic: CombatFlowMagic
var fields: CombatFlowFields
var summoning: CombatFlowSummoning
var phase: CombatFlowPhase
var automation: CombatFlowAutomation
var battle_setup: CombatBattleSetup
var _context: CombatContext


func _init(rules: RealmzRules) -> void:
	_context = CombatContext.new(rules)
	rounds = CombatFlowLifecycle.new(_context)
	actions = CombatFlowActions.new(_context)
	reactions = CombatFlowReactions.new(_context)
	magic = CombatFlowMagic.new(_context)
	fields = CombatFlowFields.new(_context)
	summoning = CombatFlowSummoning.new(_context)
	phase = CombatFlowPhase.new(_context)
	automation = CombatFlowAutomation.new(_context)
	battle_setup = CombatBattleSetup.new(_context)
	_context.bind_collaborators(rounds, actions, reactions, magic, fields, summoning, phase, automation)


func start_battle(state: GameState, content: RealmzContent, battle: BattleDefinition, rng: RealmzRng, surprise: int = 0, participant_character_ids: Array[String] = []) -> CombatFlowResult:
	return battle_setup.start(state, content, battle, rng, surprise, participant_character_ids)


func submit_action(state: GameState, content: RealmzContent, actor_id: String, action: StringName, target_id: String, rng: RealmzRng, allow_friendly_contact: bool = false) -> CombatFlowResult:
	return actions.submit_action(state, content, actor_id, action, target_id, rng, allow_friendly_contact)


func run_auto_activation_chain(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	return automation.run_auto_activation_chain(state, content, actor_id, rng)


func run_persistent_auto_characters(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	return automation.run_persistent_auto_characters(state, content, rng)


func retreat_character(state: GameState, content: RealmzContent, actor_id: String, mode: StringName, destination: Vector2i, rng: RealmzRng) -> CombatFlowResult:
	return reactions.retreat_character(state, content, actor_id, mode, destination, rng)


func move_character(state: GameState, content: RealmzContent, actor_id: String, destination: Vector2i, rng: RealmzRng, auto_switch_to_melee: bool = false, friendly_collision_action: StringName = &"") -> CombatFlowResult:
	return reactions.move_character(state, content, actor_id, destination, rng, auto_switch_to_melee, friendly_collision_action)


func cause_active_fumble(state: GameState, content: RealmzContent, actor_id: String) -> CombatFlowResult:
	return actions.cause_active_fumble(state, content, actor_id)


func use_spell_item(state: GameState, content: RealmzContent, caster_id: String, target_id: String, instance_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	return magic.use_spell_item(state, content, caster_id, target_id, instance_id, rng, target_coordinate, rotation, target_ids, target_coordinates)


func cast_spell(state: GameState, content: RealmzContent, caster_id: String, target_id: String, spell_id: String, power_level: int, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	return magic.cast_spell(state, content, caster_id, target_id, spell_id, power_level, rng, target_coordinate, rotation, target_ids, target_coordinates)


func use_combat_scroll(state: GameState, content: RealmzContent, caster_id: String, scroll_slot: int, target_id: String, rng: RealmzRng, target_coordinate: Vector2i = INVALID_COORDINATE, rotation: int = 0, target_ids: Array[String] = [], target_coordinates: Array[Vector2i] = []) -> CombatFlowResult:
	return magic.use_combat_scroll(state, content, caster_id, scroll_slot, target_id, rng, target_coordinate, rotation, target_ids, target_coordinates)


func continue_after_monster_death_macro(state: GameState, content: RealmzContent, rng: RealmzRng, completed_combatant_id: String = "") -> CombatFlowResult:
	return rounds.continue_after_monster_death_macro(state, content, rng, completed_combatant_id)


func finalize_scenario_monster_destruction(state: GameState, content: RealmzContent) -> CombatFlowResult:
	return rounds.finalize_scenario_monster_destruction(state, content)


func continue_after_age_update(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	return rounds.continue_after_age_update(state, content, rng)


func apply_ally_selection(state: GameState, content: RealmzContent, selected_value: Variant) -> CombatFlowResult:
	return rounds.apply_ally_selection(state, content, selected_value)


func apply_fumble_recovery(state: GameState, content: RealmzContent, action: StringName, instance_id: String, character_id: String = "") -> CombatFlowResult:
	return rounds.apply_fumble_recovery(state, content, action, instance_id, character_id)


func finish_debug_victory(state: GameState, content: RealmzContent, events: Array[DomainEvent]) -> bool:
	return rounds.finish_if_resolved(state, content, events)


func finish_classic_macro_victory(state: GameState, content: RealmzContent) -> CombatFlowResult:
	return rounds.finish_classic_macro_victory(state, content)
