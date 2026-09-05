## Builds terminal battle rewards, recovered fumbles, and battle reward handoff.

class_name ClassicBattleRewardBuilder
extends ClassicRewardOperationsSupport

class BattleRewardPlan:
	extends RefCounted

	var bonus_treasure_id := 0
	var experience_only := false
	var pending_item_count := 0
	var defeated_monsters: Array[Dictionary] = []
	var reward_monsters: Array[Dictionary] = []
	var recovered_fumbles: Array[ItemInstance] = []
	var error: ScenarioRuntimeOperationResult


class BattleRewardRoll:
	extends RefCounted

	var item_ids: Array[String] = []
	var item_magic_detected: Array[bool] = []
	var wealth := WealthState.new()
	var experience := 0
	var events: Array[DomainEvent] = []


var _workflow: ClassicRewardWorkflow


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules, workflow: ClassicRewardWorkflow) -> void:
	super(content, game_state, rng, rules)
	_workflow = workflow

func begin_completed_battle_reward(request_id: String, caller: ScenarioBattleCaller = null) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	var early_result := _early_battle_reward_result(combat, caller)
	if early_result != null:
		return early_result
	var plan := _prepare_battle_reward(combat, caller)
	if plan.error != null:
		return plan.error
	# Validate the whole source-owned reward before consuming RNG or claiming its
	# one-shot battle continuation. A malformed package therefore remains retryable.
	var state_checkpoint := _game_state.to_data()
	var rng_checkpoint := _rng.checkpoint()
	combat.rewards_started = true
	var rolled := _roll_battle_reward(combat, plan)
	var operation := _workflow.begin_reward(&"battle", combat.battle_id, rolled.experience, rolled.wealth, rolled.item_ids, request_id, ClassicRewardState.ORDINARY_BATTLE_STAGE, absi(plan.bonus_treasure_id), plan.recovered_fumbles, rolled.item_magic_detected)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _rollback_failed_reward(operation, state_checkpoint, rng_checkpoint)
	combat.dropped_items.clear()
	operation.events = rolled.events + operation.events
	return operation


func _prepare_battle_reward(combat: CombatState, caller: ScenarioBattleCaller) -> BattleRewardPlan:
	var plan := BattleRewardPlan.new()
	plan.bonus_treasure_id = caller.mode if combat.outcome == &"victory" and caller != null and caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 48 else 0
	if plan.bonus_treasure_id != 0 and _content.economy.treasure_by_classic_id(absi(plan.bonus_treasure_id)) == null:
		plan.error = ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Classic opcode 48 references unavailable bonus treasure %d." % plan.bonus_treasure_id)
		return plan
	plan.experience_only = combat.outcome == &"victory" and (combat.classic_post_battle_sentinel == 8 or caller != null and caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 5)
	var recovered_value: Variant = _recovered_fumble_items(combat)
	if recovered_value is ScenarioRuntimeOperationResult:
		plan.error = recovered_value
		return plan
	plan.recovered_fumbles = recovered_value
	plan.pending_item_count = plan.recovered_fumbles.size()
	if plan.pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
		plan.error = ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
		return plan
	if combat.outcome == &"victory":
		plan.error = _collect_battle_reward_monsters(combat, plan)
	return plan


func _collect_battle_reward_monsters(combat: CombatState, plan: BattleRewardPlan) -> ScenarioRuntimeOperationResult:
	for monster: MonsterState in combat.roster.monsters():
		if monster.summoned:
			continue
		var definition := _content.combat.monster_by_id(monster.definition_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Battle reward references unavailable monster content.")
		var parchment_eligible := definition.can_summon != -1 and definition.type_flag(0) and not definition.type_flag(7)
		var rations_eligible := definition.can_summon != -1 and not definition.type_flag(7) and not definition.type_flag(1)
		var incidental_error := _validate_incidental_items(plan, parchment_eligible, rations_eligible)
		if incidental_error != null:
			return incidental_error
		plan.reward_monsters.append({"monster": monster, "definition": definition, "parchmentEligible": parchment_eligible, "rationsEligible": rations_eligible})
		if not monster.traitor or monster.current_health >= 1:
			continue
		var loot := monster.loot_item_ids()
		var loot_magic_detected := monster.loot_magic_detected()
		if loot.is_empty():
			loot = definition.item_ids()
			loot_magic_detected.resize(loot.size())
			loot_magic_detected.fill(false)
			if not loot.is_empty() and definition.random_weapon_table > 0:
				loot[0] = monster.weapon_id
		if not plan.experience_only:
			var loot_error := _validate_monster_loot(plan, loot)
			if loot_error != null:
				return loot_error
		plan.defeated_monsters.append({"monster": monster, "definition": definition, "loot": loot, "lootMagicDetected": loot_magic_detected})
	return null


func _validate_incidental_items(plan: BattleRewardPlan, parchment_eligible: bool, rations_eligible: bool) -> ScenarioRuntimeOperationResult:
	for incidental_classic_id: int in [806 if parchment_eligible else 0, 877 if rations_eligible else 0]:
		if incidental_classic_id == 0:
			continue
		if _content.items.item_by_classic_id(incidental_classic_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle reward can generate unavailable Classic item %d." % incidental_classic_id)
		plan.pending_item_count += 1
		if plan.pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
			return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
	return null


func _validate_monster_loot(plan: BattleRewardPlan, loot: Array[String]) -> ScenarioRuntimeOperationResult:
	for item_id: String in loot:
		if item_id.is_empty():
			continue
		if _content.items.item_by_id(item_id) == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle reward references unavailable item '%s'." % item_id)
		plan.pending_item_count += 1
		if plan.pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
			return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
	return null


func _roll_battle_reward(combat: CombatState, plan: BattleRewardPlan) -> BattleRewardRoll:
	var result := BattleRewardRoll.new()
	if combat.outcome != &"victory":
		return result
	for row: Dictionary in plan.defeated_monsters:
		var monster: MonsterState = row["monster"]
		var definition: MonsterDefinition = row["definition"]
		_roll_monster_money(result, monster, definition, plan.experience_only)
		result.experience += _monster_reward_experience(monster, definition)
		if not plan.experience_only:
			_append_monster_loot(result, row)
	for row: Dictionary in plan.reward_monsters:
		_append_incidental_loot(result, row)
	result.events.append(DomainEvent.new(&"battle_reward_constructed", {"battleId": combat.battle_id, "experience": result.experience, "experienceOnly": plan.experience_only, "wealth": result.wealth.to_data(), "itemCount": plan.recovered_fumbles.size() + result.item_ids.size()}))
	return result


func _roll_monster_money(result: BattleRewardRoll, monster: MonsterState, definition: MonsterDefinition, experience_only: bool) -> void:
	var money := definition.money_values()
	for kind: WealthState.Kind in [WealthState.Kind.GOLD, WealthState.Kind.GEMS, WealthState.Kind.JEWELRY]:
		var maximum := maxi(0, money[kind] if kind < money.size() else 0)
		# Castle calls randrange for zero maxima too; that draw still advances RNG.
		var amount := _rng.draw_between(0, maximum, StringName("battle.reward.%s.money.%d" % [monster.id, kind]))
		if not experience_only:
			result.wealth.add(kind, amount)


static func _append_monster_loot(result: BattleRewardRoll, row: Dictionary) -> void:
	var loot: Array[String] = row["loot"]
	var loot_magic_detected: Array[bool] = row["lootMagicDetected"]
	for index: int in loot.size():
		var item_id: String = loot[index]
		if not item_id.is_empty():
			result.item_ids.append(item_id)
			result.item_magic_detected.append(loot_magic_detected[index])


func _append_incidental_loot(result: BattleRewardRoll, row: Dictionary) -> void:
	var monster: MonsterState = row["monster"]
	if row["parchmentEligible"] and _rng.draw_classic(100, StringName("battle.reward.%s.parchment" % monster.id)) < 10:
		result.item_ids.append(_content.items.item_by_classic_id(806).id)
		result.item_magic_detected.append(false)
	if row["rationsEligible"] and _rng.draw_classic(100, StringName("battle.reward.%s.rations" % monster.id)) < 10:
		result.item_ids.append(_content.items.item_by_classic_id(877).id)
		result.item_magic_detected.append(false)


func _early_battle_reward_result(combat: CombatState, caller: ScenarioBattleCaller) -> ScenarioRuntimeOperationResult:
	if combat == null or not combat.completed:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Battle rewards require a completed battle.")
	if combat.rewards_completed:
		return ScenarioRuntimeOperationResult.completed(String(combat.outcome))
	if combat.rewards_started:
		return ScenarioRuntimeOperationResult.failed(&"battle_reward_already_started", "The completed battle already has an active reward continuation.")
	if caller != null and caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 10:
		return _complete_mode_ten_battle(combat)
	return null


func _recovered_fumble_items(combat: CombatState) -> Variant:
	var result: Array[ItemInstance] = []
	for fumbled: ItemInstance in combat.dropped_items.items():
		var definition := _content.items.item_by_id(fumbled.definition_id)
		if definition == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle recovery references unavailable item '%s'." % fumbled.definition_id)
		var recovered := ItemInstance.from_data(fumbled.to_data())
		if recovered == null:
			return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "A fumbled battle item cannot enter the reward queue.")
		recovered.equipped = false
		recovered.identified = true
		result.append(recovered)
	return result


func _complete_mode_ten_battle(combat: CombatState) -> ScenarioRuntimeOperationResult:
	if combat.outcome not in [&"victory", &"defeat"]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_battle_continuation", "Classic battle mode 10 requires victory or total defeat.")
	combat.rewards_started = true
	combat.rewards_completed = true
	var battle_id := combat.battle_id
	var events: Array[DomainEvent] = []
	var directive: ScenarioVmDirective
	if combat.outcome == &"defeat":
		for character: CharacterState in _game_state.party.characters():
			character.current_health = 1
			character.conditions.set_value(ConditionRules.ANIMATED, 0)
		events.append(DomainEvent.new(&"party_defeat_revived", {"battleId": battle_id, "source": "classic-mode-10"}))
		events.append(DomainEvent.new(&"classic_battle_restart_requested", {"battleId": battle_id, "callerOpcode": 2}))
		directive = ScenarioVmDirective.restart_current_program()
	elif combat.outcome == &"victory":
		_game_state.party.pooled_wealth = WealthState.new()
		var restored := _game_state.party.restore_equipment()
		if restored:
			for character: CharacterState in _game_state.party.characters():
				character.carried_load = _rules.inventory.calculated_load(character, _content.items.definitions())
		events.append(DomainEvent.new(&"equipment_restored", {"changed": restored, "source": "classic-mode-10"}))
		events.append(DomainEvent.new(&"reward_completed", {"origin": "battle", "sourceId": battle_id, "experienceByCharacter": {}}))
		var battle := _content.combat.battle_by_id(battle_id)
		if battle != null:
			_append_battle_after_message(battle, events)
		events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "victory"}))
	_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(battle_id, events, directive)
