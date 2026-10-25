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
var classic_enemy_count: int = 0
var classic_kill_count: int = 0
var classic_counters_available: bool = true
var _classic_actor_counts: Dictionary = {}
var battlefield: BattlefieldState
var pending_monster_attack: PendingMonsterAttack
var pending_reaction: CombatReactionState
var round_cursor: CombatRoundCursor

var roster: CombatRosterState
var turns: CombatTurnSequenceState
var actor_statuses: CombatActorStatusState
var dropped_items: CombatDroppedItemState
var spell_runtime: CombatSpellRuntimeState
var death_macros: CombatDeathMacroState
var pending_operations := CombatPendingOperations.new()


func _init(source_battle_id: String, initial_monsters: Array[MonsterState] = [], battle_macro_id: int = 0, initial_battlefield: BattlefieldState = null) -> void:
	battle_id = source_battle_id
	macro_id = battle_macro_id
	battlefield = initial_battlefield
	roster = CombatRosterState.new(initial_monsters)
	turns = CombatTurnSequenceState.new(roster)
	actor_statuses = CombatActorStatusState.new()
	spell_runtime = CombatSpellRuntimeState.new()
	spell_runtime.bind(turns)
	death_macros = CombatDeathMacroState.new()
	death_macros.bind(roster, turns)
	dropped_items = CombatDroppedItemState.new()
	reconcile_classic_counters()


func reconcile_classic_counters(party: PartyState = null) -> void:
	if not classic_counters_available:
		return
	for monster: MonsterState in roster.monsters():
		_record_classic_actor(monster.id, monster.classic_traitor, monster.current_health > 0, battlefield == null or battlefield.actors.has_actor(monster.id), false)
	if party != null:
		for character: CharacterState in party.characters():
			if not turns.turn_order().has(character.id) and not _classic_actor_counts.has(character.id): continue
			_record_classic_actor(character.id, character.classic_traitor, character.current_health > 0, battlefield == null or battlefield.actors.has_actor(character.id), true)


func _record_classic_actor(actor_id: String, side: int, alive: bool, positioned: bool, character: bool) -> void:
	var current: Array = [side, alive, positioned]
	if not _classic_actor_counts.has(actor_id):
		# Party slots start loyal; native setup counts authored hostile monsters.
		if side != 0: classic_enemy_count = RealmzArithmetic.new().signed_8(classic_enemy_count + 1)
	else:
		var previous: Array = _classic_actor_counts[actor_id]
		var old_side: int = previous[0]
		var old_alive: bool = previous[1]
		var old_positioned: bool = previous[2]
		var delta := (1 if side != 0 else 0) - (1 if old_side != 0 else 0)
		classic_enemy_count = RealmzArithmetic.new().signed_8(classic_enemy_count + delta)
		if side != 0 and (old_alive and not alive or old_positioned and not positioned and (alive or character)):
			classic_kill_count = RealmzArithmetic.new().signed_8(classic_kill_count + 1)
	_classic_actor_counts[actor_id] = current


func record_classic_traitor_write(monster: MonsterState, value: int) -> void:
	# newland 120 decrements even for an unchanged or newly hostile byte.
	monster.classic_traitor = value
	classic_enemy_count = RealmzArithmetic.new().signed_8(classic_enemy_count - 1)
	var previous: Array = _classic_actor_counts[monster.id]
	previous[0] = monster.classic_traitor


func clear_classic_death_macro_traitor(monster: MonsterState, party: PartyState) -> void:
	# killbody's post-macro clear and opcode 119 do not decrement numenemy.
	reconcile_classic_counters(party)
	monster.traitor = false
	_classic_actor_counts[monster.id] = [0, monster.current_health > 0, battlefield == null or battlefield.actors.has_actor(monster.id)]


func classic_counters_data() -> Dictionary:
	return {} if not classic_counters_available else {"enemyCount": classic_enemy_count, "killCount": classic_kill_count, "actors": _classic_actor_counts.duplicate(true)}


func restore_classic_counters(data: Variant) -> bool:
	classic_counters_available = false
	_classic_actor_counts.clear()
	if data == null:
		return true
	if not data is Dictionary:
		return false
	var fields: Dictionary = data
	if fields.size() != 3 or not fields.get("actors") is Dictionary:
		return false
	var enemies := _classic_byte(fields.get("enemyCount"))
	var kills := _classic_byte(fields.get("killCount"))
	if enemies < -128 or kills < -128: return false
	var counts: Dictionary = fields["actors"]
	for actor_id: Variant in counts:
		var value: Variant = counts[actor_id]
		if not actor_id is String or not value is Array:
			return false
		var identity: String = actor_id
		var entry: Array = value
		if identity.is_empty() or entry.size() != 3 or not entry[1] is bool or not entry[2] is bool:
			return false
		if roster.monster_by_id(identity) == null and not turns.turn_order().has(identity): return false
		var side := _classic_side(entry[0])
		if side < -32_768 or roster.monster_by_id(identity) != null and (side < -128 or side > 127): return false
		_classic_actor_counts[identity] = [side, entry[1], entry[2]]
	classic_enemy_count = enemies
	classic_kill_count = kills
	classic_counters_available = true
	return true


static func _classic_byte(value: Variant) -> int:
	if value is int:
		return value if value >= -128 and value <= 127 else -129
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and number >= -128 and number <= 127:
			return int(number)
	return -129


static func _classic_side(value: Variant) -> int:
	if value is int:
		return value if value >= -32_768 and value <= 32_767 else -32_769
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and number >= -32_768 and number <= 32_767:
			return int(number)
	return -32_769


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
