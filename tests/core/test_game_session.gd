extends RealmzTestCase


func run() -> void:
	_test_player_intent_contract()
	_test_interaction_value_decoder_contracts()

	var session := GameSession.new()
	var before_start := session.submit_intent(ExplorationIntents.search())
	assert_equal(before_start.state, SessionStep.State.FAILED, "an unstarted session rejects intents")
	assert_equal(before_start.error_code, &"session_not_started", "the rejection is explicit")

	var invalid_start := session.start(null, 42); assert_equal(invalid_start.state, SessionStep.State.FAILED, "start requires validated typed content")
	assert_equal(invalid_start.error_code, &"invalid_content", "invalid content never partially starts a session")

	var snapshot := session.snapshot(); assert_equal(snapshot, null, "an unstarted session has no save boundary")

	var character := CharacterState.new("fast.spell.character", "Quickcaster", 12, 12)
	assert_equal(character.fast_spells().size(), 10, "every character owns Castle's ten Fast Spell slots")
	assert_true(character.fast_spells().all(func(binding: FastSpellBindingState) -> bool: return binding.is_empty()), "new characters default every Fast Spell slot to undefined")
	assert_true(character.bind_fast_spell(9, "classic.spell.quick", 4), "slot ten accepts a typed stable spell identity and power")
	character.set_save_value(0, 32_767, false); character.set_special_value(0, 40_000, false); character.set_ability_value(0, -40_000, false)
	var round_trip := CharacterStateCodec.decode(JSON.parse_string(JSON.stringify(CharacterStateCodec.encode(character))))
	assert_equal(round_trip.fast_spell_at(9).to_data(), {"spellId": "classic.spell.quick", "power": 4}, "Fast Spell bindings round-trip inside character-owned state")
	assert_equal([round_trip.save_value(0), round_trip.special_value(0), round_trip.ability_value(0)], [32_767, 40_000, -40_000], "strict restoration preserves historical signed character arrays without applying gameplay clamps")
	var corrupt := CharacterStateCodec.encode(character)
	corrupt["fastSpells"][0] = {"spellId": "", "power": 2}
	assert_equal(CharacterStateCodec.decode(corrupt), null, "malformed empty Fast Spell bindings fail strict character restoration")
	var debug_package := load_test_package("res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"); var debug_content := debug_package.content; var debug_race := debug_content.characters.race_definitions()[0]; var debug_caste := debug_race.eligible_caste_ids[0]; var debug_session := GameSession.new(); debug_session.start(debug_content, 17); debug_session.submit_intent(PartyIntents.create([CharacterCreationSpec.new("Debugger", debug_race.id, debug_caste, 1)])); var rng_before_debug := debug_session.snapshot().rng_state.to_data(); assert_equal(debug_session.apply_debug_command(SessionDebugCommand.warp("dungeon:0", Vector2i.ZERO)).state, SessionStep.State.COMPLETED, "a public debug warp commits only to a validated topology cell"); assert_equal([debug_session.view().party_map_id, debug_session.view().party_coordinate, debug_session.snapshot().rng_state.to_data()], ["dungeon:0", Vector2i.ZERO, rng_before_debug], "debug warp changes no gameplay RNG and exposes the committed destination through the detached view"); var noclip_step := debug_session.apply_debug_command(SessionDebugCommand.noclip_step(Vector2i.RIGHT)); var noclip_view := debug_session.view(noclip_step.events); assert_equal([noclip_step.state, noclip_view.party_coordinate, noclip_view.map_view.presentation_delta != null, debug_session.snapshot().rng_state.to_data()], [SessionStep.State.COMPLETED, Vector2i.RIGHT, true, rng_before_debug], "adjacent no-clip bypasses topology through the incremental presentation path without RNG"); assert_equal(debug_session.apply_debug_command(SessionDebugCommand.restore_party()).state, SessionStep.State.COMPLETED, "party restoration is a public committed debug command")
	var encounter_session := GameSession.new(); encounter_session.start(debug_content, 19); encounter_session.submit_intent(PartyIntents.create([CharacterCreationSpec.new("Encounter Debugger", debug_race.id, debug_caste, 1)])); var encounter_step := encounter_session.apply_debug_command(SessionDebugCommand.start_encounter(&"simple", 0)); assert_equal([encounter_step.state, encounter_step.interaction.kind, encounter_session.snapshot()], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.ENCOUNTER_CHOICE, null], "a debug encounter uses the ordinary typed interaction but cannot enter a save"); var battle_session := GameSession.new(); battle_session.start(debug_content, 23); battle_session.submit_intent(PartyIntents.create([CharacterCreationSpec.new("Battle Debugger", debug_race.id, debug_caste, 1), CharacterCreationSpec.new("Swap Ally", debug_race.id, debug_caste, 1)])); assert_equal(battle_session.apply_debug_command(SessionDebugCommand.start_battle(0)).state, SessionStep.State.COMPLETED, "a debug battle uses ordinary deterministic battle construction"); var tactical := battle_session.view(); var swap_options := tactical.combat_view.movement_options.filter(func(option: CombatMoveOptionView) -> bool: return option.enabled and option.movement_cost == 5); assert_false(swap_options.is_empty(), "the detached public combat view enables an adjacent allied footprint as Castle's five-movement swap"); var swap_step := battle_session.submit_intent(CombatIntents.move(tactical.combat_view.active_actor_id, swap_options[0].destination)); assert_equal([swap_step.state, swap_step.interaction.kind, swap_step.interaction.body.yes_label, swap_step.interaction.body.no_label], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO, "Swap Positions", "Attack Friend"], "manual movement opens Castle's typed friendly-collision choice"); var swap_boundary := battle_session.snapshot(); assert_not_null(swap_boundary, "the friendly-collision choice is a saveable committed boundary"); var resumed_swap := GameSession.new(); assert_equal(resumed_swap.restore(debug_content, swap_boundary).state, SessionStep.State.COMPLETED, "the friendly-collision choice restores without rerunning movement"); assert_true(resumed_swap.respond(InteractionResponse.yes_no(resumed_swap.view().pending_interaction, true)).events.any(func(event: DomainEvent) -> bool: return event.kind == &"combatants_swapped"), "accepting Swap Positions resumes the restored combat transaction exactly once"); battle_session = resumed_swap; var victory := battle_session.apply_debug_command(SessionDebugCommand.win_battle()); assert_true(victory.state != SessionStep.State.FAILED and victory.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_completed" and event.payload.get("outcome") == "victory"), "debug victory enters the ordinary terminal battle and reward flow")

	var malformed_requests: Array = [
		[InteractionRequest.ACKNOWLEDGE, {"prompt": "Read this.", "journalEligible": true}],
		[InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No", "yesId": 1}],
		[InteractionRequest.INDEXED_CHOICE, {"prompt": "Choose.", "options": [{"label": 7}]}],
		[InteractionRequest.CHARACTER_SELECTION, {"count": 1, "eligible": [{"id": "hero"}]}],
		[InteractionRequest.ALLY_SELECTION, {"prompt": "Choose.", "maximum": 1, "selectedIds": [], "requiredIds": [], "candidates": [{"id": "ally", "name": "Ally", "classicMonsterId": 1}]}],
		[InteractionRequest.SESSION_LIFECYCLE, {"operation": "quit-application", "prompt": "Quit?", "inCombat": false, "options": [{"action": "cancel", "label": 3}]}],
	]
	for malformed: Array in malformed_requests:
		assert_equal(InteractionRequest.from_payload("malformed.contract", malformed[0], malformed[1]), null, "typed interaction request variants reject partial or malformed nested records")


func _test_interaction_value_decoder_contracts() -> void:
	var availability := {"enabled": true, "reason": ""}
	var wealth := {"gold": 3, "gems": 2, "jewelry": 1}
	var fact := {"label": "Damage", "value": "1-4"}
	var inventory_item := {"instanceId": "item.instance", "itemId": "classic.item.1", "name": "Dagger", "identified": true, "equipped": false, "charges": 0, "sellPrice": 4, "canSell": true, "sellReason": "", "canIdentify": false, "identifyReason": "Known", "iconResourceType": "cicn", "iconId": -185}
	var transfer := {"denomination": "gold", "amount": 3, "toPool": availability, "toCharacter": availability}
	var combat_target := {"id": "combat.monster.1", "name": "Goblin"}
	var combatant := {"id": "combat.monster.1", "kind": "monster", "name": "Goblin", "currentHealth": 4, "maximumHealth": 4, "spellPoints": 0, "maximumSpellPoints": 0, "armor": 2, "magicResistance": 0, "attacks": "1", "movement": 4, "maximumMovement": 4, "traitor": false, "helpless": false, "conditions": []}
	var movement := {"direction": [1, 0], "destination": [3, 4], "cost": 1, "enabled": true, "reasonCode": "", "reason": "", "retreat": false, "forcedRetreat": false, "attackTargetId": "", "attackTargetName": ""}
	var cast_common := {"spellId": "classic.spell.1", "spellName": "Spark", "power": 1, "targetId": "", "targetName": "All enemies", "targetCurrentHealth": -1, "targetMaximumHealth": -1, "targetMode": "automatic"}
	var reward_item := {"instanceId": "reward.item", "definitionId": "classic.item.1", "name": "Dagger", "charges": 0, "identified": true, "description": "", "facts": [fact], "iconResourceType": "cicn", "iconId": -185}
	var ordinary_reward_character := {"id": "party.character.1", "name": "Hero", "enabled": true, "reason": "", "wealth": wealth, "canTakeGold": true, "canTakeGems": true, "canTakeJewelry": true, "goldReason": "", "gemsReason": "", "jewelryReason": "", "itemCount": 0, "maximumMovement": 10, "load": 0, "maximumLoad": 100}
	var thief_action := {"index": 0, "label": "Pick Lock", "value": 50, "enabled": true, "reason": ""}
	var valid_values: Array = [
		InteractionCommonValueDecoder.availability(availability), InteractionCommonValueDecoder.wealth(wealth), InteractionCommonValueDecoder.condition({"index": 1, "name": "Poisoned", "value": 2}), InteractionCommonValueDecoder.item_detail_fact(fact),
		InteractionServiceValueDecoder.inventory_item(inventory_item), InteractionServiceValueDecoder.shop_stock({"stockKey": "base:1", "index": 1, "itemId": "classic.item.1", "name": "Dagger", "quantity": 1, "buyPrice": 8, "canBuy": true, "buyReason": "", "iconResourceType": "cicn", "iconId": -185}), InteractionServiceValueDecoder.temple_service({"id": "heal", "label": "Heal", "description": "Restore health.", "cost": 10}),
		InteractionServiceValueDecoder.service_character({"id": "party.character.1", "name": "Hero", "inventory": [inventory_item]}, &"shop"), InteractionServiceValueDecoder.service_character({"id": "party.character.1", "name": "Hero", "currentHealth": 4, "maximumHealth": 10, "personalGold": 5, "availableGold": 8, "load": 0, "maximumLoad": 100, "portraitId": "portrait.1", "conditions": []}, &"temple"), InteractionServiceValueDecoder.service_character({"id": "party.character.1", "name": "Hero", "wealth": wealth, "load": 0, "maximumLoad": 100, "transfers": [transfer]}, &"bank"),
		InteractionCombatValueDecoder.combat_target(combat_target), InteractionCombatValueDecoder.combatant(combatant), InteractionCombatValueDecoder.movement_option(movement), InteractionCombatValueDecoder.fast_spell({"slot": 0, "spellId": "classic.spell.1", "spellName": "Spark", "power": 1, "enabled": true, "reason": ""}), InteractionCombatValueDecoder.cast_option(cast_common.merged({"cost": 2}), &"spell"), InteractionCombatValueDecoder.cast_option(cast_common.merged({"itemInstanceId": "item.instance", "itemId": "classic.item.1", "itemName": "Wand", "charges": 3}), &"item"), InteractionCombatValueDecoder.cast_option(cast_common.merged({"scrollSlot": 2}), &"scroll"),
		InteractionRewardValueDecoder.reward_item(reward_item), InteractionRewardValueDecoder.reward_character({"id": "party.character.1", "name": "Hero", "currentHealth": 4, "maximumHealth": 10, "enabled": true, "reason": ""}, &"fumbled-item-recovery"), InteractionRewardValueDecoder.reward_character(ordinary_reward_character, &"ordinary"), InteractionRewardValueDecoder.reward_method({"visible": true, "casters": [{"id": "party.character.1", "name": "Hero", "spellPoints": 10, "cost": 5}], "reason": ""}), InteractionRewardValueDecoder.level_gains({"stamina": 1, "spellPoints": 2, "toHit": 3, "magicResistance": 4}), InteractionRewardValueDecoder.spell_choice({"id": "classic.spell.1", "name": "Spark", "classicId": 1, "cost": 1, "selected": false}),
		InteractionSelectionValueDecoder.encounter_action({"id": "choice.0", "kind": "choice", "label": "Continue", "slot": 0}), InteractionSelectionValueDecoder.named_character({"id": "party.character.1", "name": "Hero", "portraitId": "portrait.1"}), InteractionSelectionValueDecoder.thief_action(thief_action), InteractionSelectionValueDecoder.thief_character({"id": "party.character.1", "name": "Hero", "portraitId": "portrait.1", "actions": [thief_action]}), InteractionSelectionValueDecoder.encounter_catalog_entry({"classicItemId": 1, "name": "Dagger", "characterId": "party.character.1", "instanceId": "item.instance", "iconResourceType": "cicn", "iconId": 1, "charges": 0, "equipped": false}, &"item"), InteractionSelectionValueDecoder.encounter_catalog_entry({"classicSpellId": 1, "name": "Spark", "characterId": "party.character.1"}, &"spell"), InteractionSelectionValueDecoder.choice_option({"id": "choice.0", "label": "Continue"}), InteractionSelectionValueDecoder.selection_candidate({"id": "party.character.1", "name": "Hero"}), InteractionSelectionValueDecoder.selection_candidate({"id": "combat.ally.1", "name": "Ally", "classicMonsterId": 1, "required": false, "canSummon": 1}), InteractionSelectionValueDecoder.spell_target_context({"actorId": "party.character.1", "actorName": "Hero", "spellId": "classic.spell.1", "spellName": "Spark", "description": "", "iconResourceType": "cicn", "iconId": 1, "power": 1, "spellPointCost": 2, "targetType": 1, "targetSize": 1, "targetCount": 1, "sourceKind": "field-spell"}), InteractionSelectionValueDecoder.lifecycle_option({"action": "cancel", "label": "Cancel"}),
	]
	assert_equal(valid_values.size(), 34, "the nested request-value denominator covers every feature decoder and alternate service/cast mode")
	assert_true(valid_values.all(func(value: Variant) -> bool: return value != null and (not (value is InteractionRequestValue.InventoryItem or value is InteractionRequestValue.ShopStock or value is InteractionRequestValue.RewardItem) or [value.to_data().get("iconResourceType"), value.to_data().get("iconId")] == ["cicn", -185])), "every nested request value decodes and item records preserve exact signed resource keys through encoding")
	assert_true([InteractionCommonValueDecoder.availability({"enabled": true, "reason": "", "unknown": 1}), InteractionServiceValueDecoder.service_character({"id": "hero", "name": "Hero"}, &"unknown"), InteractionRewardValueDecoder.reward_character(ordinary_reward_character, &"unknown"), InteractionSelectionValueDecoder.encounter_action({"id": "x", "kind": "unknown", "label": "Unknown"}), InteractionServiceValueDecoder.inventory_item(inventory_item.merged({"iconId": 0}, true)), InteractionRewardValueDecoder.reward_item(reward_item.merged({"iconId": -185.5}, true)), InteractionRewardValueDecoder.reward_item(reward_item.merged({"iconResourceType": ""}, true))].all(func(value: Variant) -> bool: return value == null), "nested values reject unknown fields, modes, discriminators, and zero, fractional, or untyped item resource keys")
	var legacy_unknown_cast := InteractionCombatValueDecoder.cast_option(cast_common, &"unknown")
	assert_true(legacy_unknown_cast != null and legacy_unknown_cast.source_kind == &"unknown", "the current combat-value wire preserves its historical acceptance of an unknown cast source discriminator")


func _test_player_intent_contract() -> void:
	var spec := CharacterCreationSpec.new("Intent Hero", "race.intent", "caste.intent", 2)
	var character := CharacterState.new("character.intent", "Intent Hero", 10, 10)
	var move_intent := ExplorationIntents.move(Vector2i.RIGHT)
	var overhead_intent := ExplorationIntents.overhead_dungeon_move(Vector2i.UP)
	var item_target_intent := InventoryIntents.use_on_target("item.instance", character.id, "monster.1", ["monster.1"], Vector2i(4, 5), 2, [Vector2i(4, 5)])
	var area_spell_intent := MagicIntents.cast_at("spell.area", character.id, Vector2i(8, 9), 5, 3)
	var vault_intent := PartyIntents.import_vault_character(character.id, "a".repeat(64), character, "campaign.intent", "b".repeat(64))
	var item_action_intent := InventoryIntents.equip("item.instance", character.id, 2)
	var intents: Array[PlayerIntent] = [
		move_intent,
		overhead_intent,
		ExplorationIntents.dungeon_turn(-1),
		ExplorationIntents.search(),
		ExplorationIntents.toggle_search(),
		ExplorationIntents.use_torch(),
		ExplorationIntents.contextual_encounter(),
		ExplorationIntents.camp(),
		ExplorationIntents.rest(),
		ExplorationIntents.heal(),
		InventoryIntents.use("item.instance", character.id),
		item_target_intent,
		MagicIntents.cast("spell.1", character.id, "monster.1", 3),
		MagicIntents.identify_carried_items("spell.identify", character.id, character.id),
		MagicIntents.make_scroll("spell.scroll", character.id, 4),
		MagicIntents.use_scroll(character.id, 2, [character.id]),
		MagicIntents.use_scroll_on_target(character.id, 2, "monster.1", ["monster.1"], Vector2i(6, 7), 1),
		MagicIntents.use_scroll_at_coordinates(character.id, 2, [Vector2i(6, 7)]),
		area_spell_intent,
		MagicIntents.cast_at_targets("spell.group", character.id, ["monster.1", "monster.2"], 2),
		MagicIntents.cast_at_coordinates("spell.ray", character.id, [Vector2i(8, 9)], 2),
		MagicIntents.set_fast_spell(character.id, 3, "spell.fast", 4),
		CombatIntents.choose_action(&"guard", character.id),
		PartyIntents.create([spec]),
		PartyIntents.begin_adventure(),
		PartyIntents.configure_setup(2, 1),
		vault_intent,
		PartyIntents.generate_character_draft(spec),
		PartyIntents.cancel_character_draft(),
		PartyIntents.set_character_draft_spells(["spell.1"]),
		PartyIntents.finalize_character(),
		PartyIntents.remove_member(character.id),
		PartyIntents.reorder([character.id]),
		PartyIntents.change_appearance(character.id, &"portrait", "portrait.1"),
		item_action_intent,
		InventoryIntents.unequip("item.instance", character.id),
		InventoryIntents.drop("item.instance", character.id),
		InventoryIntents.split("item.instance", character.id, 2),
		InventoryIntents.join("item.instance", character.id),
		InventoryIntents.trade("item.instance", character.id, "character.other"),
		EconomyIntents.money(&"to-pool", character.id, "gold", 5),
		EconomyIntents.service("service.temple", &"buy", character.id, 6),
		CombatIntents.move(character.id, Vector2i(10, 11), true),
		CombatIntents.set_auto(character.id, true),
		ExplorationIntents.set_location_note("The western gate."),
	]
	assert_true(intents.all(func(intent: PlayerIntent) -> bool: return intent.is_valid()), "every public player-intent factory produces a payload accepted by the central kind registry")
	var kinds: Array[int] = []
	for intent: PlayerIntent in intents:
		if not kinds.has(intent.kind):
			kinds.append(intent.kind)
	kinds.sort()
	assert_equal(kinds, range(PlayerIntent.Kind.size()), "public player-intent factories retain every stable kind identity")
	var move := move_intent.payload as ExplorationIntentPayloads.Move
	var overhead := overhead_intent.payload as ExplorationIntentPayloads.Move
	var item_target := item_target_intent.payload as InventoryIntentPayloads.Target
	var spell := area_spell_intent.payload as SpellIntentPayload
	var vault := vault_intent.payload as PartyIntentPayloads.VaultImport
	var item_action := item_action_intent.payload as InventoryIntentPayloads.Action
	assert_equal([move.direction, move.aligns_dungeon_heading, overhead.direction, overhead.aligns_dungeon_heading], [Vector2i.RIGHT, false, Vector2i.UP, true], "movement intent payloads preserve direction and the overhead heading-alignment distinction")
	assert_equal([item_target.item_id, item_target.actor_id, item_target.target_id, item_target.target_ids, item_target.coordinate, item_target.rotation, item_target.target_coordinates], ["item.instance", character.id, "monster.1", ["monster.1"], Vector2i(4, 5), 2, [Vector2i(4, 5)]], "targeted item intent payloads preserve every actor, target, coordinate, and rotation value")
	assert_equal([spell.operation, spell.spell_id, spell.caster_id, spell.power, spell.coordinate, spell.rotation], [&"cast", "spell.area", character.id, 5, Vector2i(8, 9), 3], "spell intent payloads preserve their operation, source identities, power, placement, and rotation")
	assert_equal([vault.character_id, vault.revision_hash, vault.character_state, vault.source_campaign_id, vault.source_package_hash], [character.id, "a".repeat(64), character, "campaign.intent", "b".repeat(64)], "Character Files import payloads preserve revision and source-package provenance")
	assert_equal([item_action.item_id, item_action.actor_id, item_action.quantity, item_action.destination_character_id], ["item.instance", character.id, 2, ""], "inventory action payloads preserve identity and normalize their quantity")
	assert_false(PlayerIntent.new(PlayerIntent.Kind.DUNGEON_TURN, ExplorationIntentPayloads.DungeonTurn.new(0)).is_valid(), "the intent registry rejects an invalid dungeon-turn delta")
	assert_false(PlayerIntent.new(PlayerIntent.Kind.MOVE, EmptyIntentPayload.new()).is_valid(), "the intent registry rejects a payload from the wrong feature family")
