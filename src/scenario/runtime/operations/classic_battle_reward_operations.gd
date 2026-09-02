class_name ClassicBattleRewardOperations
extends ClassicOpcodeHandler

const BattleLifecycleType = preload("res://src/scenario/runtime/operations/classic_battle_lifecycle_operations.gd")
const RewardOperationsType = preload("res://src/scenario/runtime/operations/classic_reward_operations.gd")

var _battle: RefCounted
var _rewards: RefCounted


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_rewards = RewardOperationsType.new(content, game_state, rng, rules)
	_battle = BattleLifecycleType.new(content, game_state, rng, rules, _rewards)


func bind_runtime_api(runtime_api: RealmzRuntimeApi) -> void:
	_battle.bind_runtime_api(runtime_api)


func opcode_ids() -> Array[int]:
	return [2, 10, 11, 48, 56, 65, 107]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		2, 48, 56, 107:
			return _battle.start_classic_battle(action, request_id)
		10:
			return _rewards.grant_treasure(action.operand_id, request_id)
		11:
			return _rewards.begin_experience_reward(action.operand_id, request_id)
		65:
			return _rewards.grant_random_items(action, request_id)
	return super.execute(action, request_id, context)


func resume(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	if continuation.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD:
		return _rewards.resume_reward(continuation, response, request_id)
	return _battle.resume_battle(continuation, response, request_id)


static func party_defeat_handoff_is_valid(content: RealmzContent, state: GameState, handoff: ScenarioRuntimeHandoff) -> bool:
	return BattleLifecycleType.party_defeat_handoff_is_valid(content, state, handoff)


func complete_party_defeat_handoff(handoff: ScenarioRuntimeHandoff) -> ScenarioRuntimeOperationResult:
	return _battle.complete_party_defeat_handoff(handoff)


func start_battle_definition(battle: BattleDefinition, request_id: String, source: String, caller: ScenarioBattleCaller) -> ScenarioRuntimeOperationResult:
	return _battle.start_battle_definition(battle, request_id, source, caller)


func grant_treasure_definition(treasure: TreasureDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	return _rewards.grant_treasure_definition(treasure, request_id)


func begin_completed_battle_reward(request_id: String, caller: ScenarioBattleCaller = null) -> ScenarioRuntimeOperationResult:
	return _rewards.begin_completed_battle_reward(request_id, caller)


func active_combat_request(request_id: String) -> InteractionRequest:
	return _battle.active_combat_request(request_id)


func complete_debug_victory(continuation: ScenarioRuntimeContinuation, request_id: String, events: Array[DomainEvent]) -> ScenarioRuntimeOperationResult:
	return _battle.complete_debug_victory(continuation, request_id, events)


func grant_item(character_id: String, item_id: String, identified: bool) -> ScenarioRuntimeOperationResult:
	return _rewards.grant_item(character_id, item_id, identified)
