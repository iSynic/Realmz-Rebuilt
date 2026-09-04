## Aggregates the durable state owned by one battle and its focused collaborators.

class_name CombatState
extends RefCounted

var battle_id: String
var macro_id: int = 0
var completed: bool = false
var outcome: StringName = &"active"
var rewards_started: bool = false
var rewards_completed: bool = false
var classic_post_battle_sentinel: int = 0
var battlefield: BattlefieldState
var pending_monster_attack: PendingMonsterAttack
var pending_reaction: CombatReactionState

var roster: CombatRosterState
var turns: CombatTurnSequenceState
var actor_statuses: CombatActorStatusState
var dropped_items: CombatDroppedItemState
var spell_runtime: CombatSpellRuntimeState


func _init(source_battle_id: String, initial_monsters: Array[MonsterState] = [], battle_macro_id: int = 0, initial_battlefield: BattlefieldState = null) -> void:
	battle_id = source_battle_id
	macro_id = battle_macro_id
	battlefield = initial_battlefield
	roster = CombatRosterState.new(initial_monsters)
	turns = CombatTurnSequenceState.new(roster)
	actor_statuses = CombatActorStatusState.new()
	spell_runtime = CombatSpellRuntimeState.new()
	spell_runtime.bind(roster, turns)
	dropped_items = CombatDroppedItemState.new()


func set_turn_order(order: Array[String]) -> void:
	turns.set_turn_order(order)
	actor_statuses.replace_actor_registry(order, roster)
	spell_runtime.clear_field_collisions()


func append_turn_actor(actor_id: String) -> void:
	turns.append_turn_actor(actor_id)
	actor_statuses.replace_actor_registry(turns.turn_order(), roster)


func advance_turn() -> bool:
	var round_advanced := turns.advance_turn()
	spell_runtime.clear_field_collisions()
	if round_advanced:
		actor_statuses.clear_attacked()
	return round_advanced


func delay_active_actor() -> bool:
	var round_advanced := turns.delay_active_actor()
	spell_runtime.clear_field_collisions()
	if round_advanced:
		actor_statuses.clear_attacked()
	return round_advanced


func to_data() -> Dictionary:
	return CombatStateCodec.encode(self)


static func from_data(data: Variant) -> CombatState:
	return CombatStateCodec.decode(data)
