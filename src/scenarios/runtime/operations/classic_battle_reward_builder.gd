## Builds terminal battle rewards, recovered fumbles, and battle reward handoff.

class_name ClassicBattleRewardBuilder
extends ClassicRewardOperationsSupport

var _workflow: ClassicRewardWorkflow


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng, rules: RealmzRules, workflow: ClassicRewardWorkflow) -> void:
	super(content, game_state, rng, rules)
	_workflow = workflow

func begin_completed_battle_reward(request_id: String, caller: ScenarioBattleCaller = null) -> ScenarioRuntimeOperationResult:
	var combat := _game_state.combat
	var early_result := _early_battle_reward_result(combat, caller)
	if early_result != null:
		return early_result
	var bonus_treasure_id := caller.mode if combat.outcome == &"victory" and caller != null and caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 48 else 0
	if bonus_treasure_id != 0 and _content.treasure_by_classic_id(absi(bonus_treasure_id)) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_treasure", "Classic opcode 48 references unavailable bonus treasure %d." % bonus_treasure_id)
	var experience_only := combat.outcome == &"victory" and (combat.classic_post_battle_sentinel == 8 or caller != null and caller.kind == ScenarioBattleCaller.CLASSIC and caller.opcode == 2 and caller.mode == 5)
	var defeated_monsters: Array[Dictionary] = []
	var reward_monsters: Array[Dictionary] = []
	var recovered_value: Variant = _recovered_fumble_items(combat)
	if recovered_value is ScenarioRuntimeOperationResult:
		return recovered_value
	var recovered_fumbles: Array[ItemInstance] = recovered_value
	var pending_item_count := recovered_fumbles.size()
	if pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
		return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
	if combat.outcome == &"victory":
		for monster: MonsterState in combat.monsters():
			if monster.summoned:
				continue
			var definition := _content.monster_by_id(monster.definition_id)
			if definition == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_monster", "Battle reward references unavailable monster content.")
			var parchment_eligible := definition.can_summon != -1 and definition.type_flag(0) and not definition.type_flag(7)
			var rations_eligible := definition.can_summon != -1 and not definition.type_flag(7) and not definition.type_flag(1)
			for incidental_classic_id: int in [806 if parchment_eligible else 0, 877 if rations_eligible else 0]:
				if incidental_classic_id == 0:
					continue
				if _content.item_by_classic_id(incidental_classic_id) == null:
					return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle reward can generate unavailable Classic item %d." % incidental_classic_id)
				pending_item_count += 1
				if pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
					return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
			reward_monsters.append({"monster": monster, "definition": definition, "parchmentEligible": parchment_eligible, "rationsEligible": rations_eligible})
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
			if not experience_only:
				for item_id: String in loot:
					if item_id.is_empty():
						continue
					if _content.item_by_id(item_id) == null:
						return ScenarioRuntimeOperationResult.failed(&"unknown_item", "Battle reward references unavailable item '%s'." % item_id)
					pending_item_count += 1
					if pending_item_count > ClassicRewardState.MAX_PENDING_ITEMS:
						return ScenarioRuntimeOperationResult.failed(&"invalid_reward", "The battle reward exceeds the supported Classic reward bounds.")
			defeated_monsters.append({"monster": monster, "definition": definition, "loot": loot, "lootMagicDetected": loot_magic_detected})
	# Validate the whole source-owned reward before consuming RNG or claiming its
	# one-shot battle continuation. A malformed package therefore remains retryable.
	var state_checkpoint := _game_state.to_data()
	var rng_checkpoint := _rng.checkpoint()
	combat.rewards_started = true
	var item_ids: Array[String] = []
	var item_magic_detected: Array[bool] = []
	var wealth := WealthState.new()
	var experience := 0
	var events: Array[DomainEvent] = []
	if combat.outcome == &"victory":
		for row: Dictionary in defeated_monsters:
			var monster: MonsterState = row["monster"]
			var definition: MonsterDefinition = row["definition"]
			var money := definition.money_values()
			for kind: WealthState.Kind in [WealthState.Kind.GOLD, WealthState.Kind.GEMS, WealthState.Kind.JEWELRY]:
				var maximum := maxi(0, money[kind] if kind < money.size() else 0)
				# Castle calls randrange for all three denominations even when the
				# authored maximum is zero. The zero-result draw still advances the
				# gameplay stream and therefore affects later scenario randomness.
				var amount := _rng.draw_between(0, maximum, StringName("battle.reward.%s.money.%d" % [monster.id, kind]))
				if not experience_only:
					wealth.add(kind, amount)
			experience += _monster_reward_experience(monster, definition)
			if not experience_only:
				var loot: Array[String] = row["loot"]
				var loot_magic_detected: Array[bool] = row["lootMagicDetected"]
				for index: int in loot.size():
					var item_id: String = loot[index]
					if not item_id.is_empty():
						item_ids.append(item_id)
						item_magic_detected.append(loot_magic_detected[index])
		for row: Dictionary in reward_monsters:
			var monster: MonsterState = row["monster"]
			if row["parchmentEligible"] and _rng.draw_classic(100, StringName("battle.reward.%s.parchment" % monster.id)) < 10:
				item_ids.append(_content.item_by_classic_id(806).id)
				item_magic_detected.append(false)
			if row["rationsEligible"] and _rng.draw_classic(100, StringName("battle.reward.%s.rations" % monster.id)) < 10:
				item_ids.append(_content.item_by_classic_id(877).id)
				item_magic_detected.append(false)
		events.append(DomainEvent.new(&"battle_reward_constructed", {"battleId": combat.battle_id, "experience": experience, "experienceOnly": experience_only, "wealth": wealth.to_data(), "itemCount": recovered_fumbles.size() + item_ids.size()}))
	var operation := _workflow.begin_reward(&"battle", combat.battle_id, experience, wealth, item_ids, request_id, ClassicRewardState.ORDINARY_BATTLE_STAGE, absi(bonus_treasure_id), recovered_fumbles, item_magic_detected)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _rollback_failed_reward(operation, state_checkpoint, rng_checkpoint)
	combat.clear_fumbled_items()
	operation.events = events + operation.events
	return operation


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
	for fumbled: ItemInstance in combat.fumbled_items():
		var definition := _content.item_by_id(fumbled.definition_id)
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
				character.carried_load = _rules.inventory.calculated_load(character, _content.item_definitions())
		events.append(DomainEvent.new(&"equipment_restored", {"changed": restored, "source": "classic-mode-10"}))
		events.append(DomainEvent.new(&"reward_completed", {"origin": "battle", "sourceId": battle_id, "experienceByCharacter": {}}))
		var battle := _content.battle_by_id(battle_id)
		if battle != null:
			_append_battle_after_message(battle, events)
		events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": "victory"}))
	_game_state.combat = null
	return ScenarioRuntimeOperationResult.completed(battle_id, events, directive)


