## Coordinates deterministic party Auto and monster-phase collaborators.

class_name CombatFlowAutomation
extends RefCounted

var _party: CombatPartyAutomation
var _monsters: CombatMonsterAutomation


func _init(context: CombatContext) -> void:
	_party = CombatPartyAutomation.new(context)
	_monsters = CombatMonsterAutomation.new(context)


func monster_actions() -> CombatMonsterActions:
	return _monsters.monster_actions()


func run_auto_turn(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	return _party.run_auto_turn(state, content, actor_id, rng)


func run_auto_activation_chain(state: GameState, content: RealmzContent, actor_id: String, rng: RealmzRng) -> CombatFlowResult:
	return _party.run_auto_activation_chain(state, content, actor_id, rng)


func run_persistent_auto_characters(state: GameState, content: RealmzContent, rng: RealmzRng) -> CombatFlowResult:
	return _party.run_persistent_auto_characters(state, content, rng)


func auto_move_toward_target(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, visited_anchors: Array[Vector2i] = []) -> CombatFlowResult:
	return _party.auto_move_toward_target(state, content, actor, rng, visited_anchors)


func process_monster_turns(state: GameState, content: RealmzContent, rng: RealmzRng, events: Array[DomainEvent]) -> void:
	_monsters.process_monster_turns(state, content, rng, events)


func process_monster_cast(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _monsters.process_monster_cast(state, content, monster, definition, active_turn, rng, events)


static func monster_can_retry_cast(state: GameState, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState) -> bool:
	return CombatMonsterAutomation.monster_can_retry_cast(state, monster, definition, active_turn)


static func monster_spell_unavailable_reason(spell: SpellDefinition) -> String:
	return CombatMonsterAutomation.monster_spell_unavailable_reason(spell)


static func is_source_backed_combat_healing_spell(spell: SpellDefinition) -> bool:
	return CombatMonsterAutomation.is_source_backed_combat_healing_spell(spell)


func process_monster_advance(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _monsters.process_monster_advance(state, content, monster, definition, active_turn, rng, events)


func process_monster_projectile(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _monsters.process_monster_projectile(state, content, monster, definition, active_turn, rng, events)


func process_monster_retreat(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _monsters.process_monster_retreat(state, content, monster, definition, active_turn, rng, events)


func retreating_monster_reached_edge(state: GameState, content: RealmzContent, monster_id: String, destination: Vector2i, events: Array[DomainEvent]) -> bool:
	return _monsters.retreating_monster_reached_edge(state, content, monster_id, destination, events)


func resolve_monster_attack_row(state: GameState, content: RealmzContent, monster: MonsterState, definition: MonsterDefinition, attack_index: int, active_turn: CombatTurnState, rng: RealmzRng, events: Array[DomainEvent]) -> int:
	return _monsters.resolve_monster_attack_row(state, content, monster, definition, attack_index, active_turn, rng, events)


func process_charmed_character_turn(state: GameState, content: RealmzContent, actor: CharacterState, rng: RealmzRng, events: Array[DomainEvent]) -> bool:
	return _monsters.process_charmed_character_turn(state, content, actor, rng, events)


func hostile_adjacent_ids(state: GameState, actor_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	return _monsters.hostile_adjacent_ids(state, actor_id, anchor_override)


func hostile_contact_target_id(state: GameState, actor_id: String, destination_or_target: Variant) -> String:
	return _monsters.hostile_contact_target_id(state, actor_id, destination_or_target)


static func remove_defeated_position(combat: CombatState, actor_id: String, defeated: bool) -> void:
	CombatMonsterAutomation.remove_defeated_position(combat, actor_id, defeated)


static func remove_all_defeated_positions(state: GameState) -> void:
	CombatMonsterAutomation.remove_all_defeated_positions(state)
