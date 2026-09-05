## Routes Classic reward entry points to battle and Treasure workflow owners.

class_name ClassicRewardOperations
extends RefCounted

var _content: RealmzContent
var _rng: RealmzRng
var _rules: RealmzRules
var _workflow: ClassicRewardWorkflow
var _battle_rewards: ClassicBattleRewardBuilder


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules) -> void:
	_content = content
	_rng = rng
	_rules = rules
	_workflow = ClassicRewardWorkflow.new(content, game_state, rng, rules)
	_battle_rewards = ClassicBattleRewardBuilder.new(content, game_state, rng, rules, _workflow)


func grant_random_items(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 65 requires a five-value Extra Code row.")
	var count := action.extra_code[0]
	if count < 0:
		count = _rng.draw(absi(count), &"classic.random-item-count")
	if count < 0 or count > 20 or action.extra_code[1] > action.extra_code[2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_random_item_range", "Classic opcode 65 has an invalid count or item range.")
	var item_ids: Array[String] = []
	for index: int in count:
		var classic_item_id := _rng.draw_between(action.extra_code[1], action.extra_code[2], StringName("classic.random-item.%d" % index))
		var definition := _content.items.item_by_classic_id(classic_item_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Classic opcode 65 generated unavailable item %d." % classic_item_id)
		item_ids.append(definition.id)
	return _workflow.begin_reward(&"scenario", "classic.random-items", 0, WealthState.new(), item_ids, request_id)


func begin_experience_reward(experience: int, request_id: String) -> ScenarioRuntimeOperationResult:
	var no_experience_items: Array[String] = []
	return _workflow.begin_reward(&"scenario", "classic.experience.%d" % experience, maxi(0, experience), WealthState.new(), no_experience_items, request_id)


func grant_treasure(classic_treasure_id: int, request_id: String) -> ScenarioRuntimeOperationResult:
	var treasure := _content.economy.treasure_by_classic_id(absi(classic_treasure_id))
	if treasure == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Classic opcode 10 references unavailable treasure %d." % classic_treasure_id)
	return grant_treasure_definition(treasure, request_id)


func grant_treasure_definition(treasure: TreasureDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var roll := _rules.economy.roll_treasure(treasure, _rng)
	return _workflow.begin_reward(&"scenario", treasure.id, roll.experience, roll.wealth, roll.item_ids, request_id)


func resume_reward(continuation: ScenarioRuntimeContinuation, response: InteractionResponse, request_id: String) -> ScenarioRuntimeOperationResult:
	return _workflow.resume_reward(continuation, response, request_id)


func begin_completed_battle_reward(request_id: String, caller: ScenarioBattleCaller = null) -> ScenarioRuntimeOperationResult:
	return _battle_rewards.begin_completed_battle_reward(request_id, caller)


func grant_item(character_id: String, item_id: String, identified: bool) -> ScenarioRuntimeOperationResult:
	return _workflow.grant_item(character_id, item_id, identified)
