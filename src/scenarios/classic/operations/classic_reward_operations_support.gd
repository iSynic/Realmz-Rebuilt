## Shares reward operation dependencies and transaction-safe utility policy.

class_name ClassicRewardOperationsSupport
extends RefCounted

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng
var _rules: RealmzRules


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_game_state = game_state
	_rng = rng
	_rules = rules
func _append_battle_after_message(battle: BattleDefinition, events: Array[DomainEvent]) -> void:
	if battle.message_after_id == 0:
		return
	var after := _content.scenario_records.message_by_id(absi(battle.message_after_id))
	if after != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": after.id, "text": after.text, "source": "classic-battle-definition"}))


func _rollback_failed_reward(operation: ScenarioRuntimeOperationResult, state_checkpoint: Dictionary, rng_checkpoint: Dictionary) -> ScenarioRuntimeOperationResult:
	if operation.state != ScenarioRuntimeOperationResult.State.FAILED:
		return operation
	operation.events.clear()
	if _game_state.to_data() == state_checkpoint and _rng.checkpoint() == rng_checkpoint:
		return operation
	var state_restored := _game_state.restore_from_data(state_checkpoint)
	var rng_restored := _rng.rollback(rng_checkpoint)
	if not state_restored or not rng_restored:
		return ScenarioRuntimeOperationResult.failed(&"reward_rollback_failed", "Reward processing failed and could not restore its deterministic transaction boundary.")
	# Restoring GameState replaces its owned object graph. Callers must return
	# immediately and resolve any subsequent state through _game_state again.
	return operation


static func _monster_reward_experience(monster: MonsterState, definition: MonsterDefinition) -> int:
	var base_values: Array[int] = [15, 30, 45, 65, 80, 100, 140, 200, 300, 450, 700, 1100, 1800, 2300, 2800, 3200, 3700, 4200, 4700, 5200, 5700]
	var increment_values: Array[int] = [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 50, 55, 60, 65, 70, 75]
	var index := clampi(monster.hit_dice, 0, 20)
	var base := base_values[index] if monster.hit_dice <= 20 else 6200
	var increment := increment_values[index] if monster.hit_dice <= 20 else 80
	return base + definition.experience + monster.maximum_health * increment
