extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var loaded := PackageRepository.new().load_package(FIXTURE_PATH)
	assert_true(loaded.is_ok(), "inventory workflow starts from the validated package fixture")
	if not loaded.is_ok():
		return
	var content := _inventory_content(loaded.content)
	var session := GameSession.new()
	assert_equal(session.start(content, 41).state, SessionStep.State.COMPLETED, "inventory session starts")
	var source := _character("inventory.source", "Alis", content)
	var destination := _character("inventory.destination", "Borin", content)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(source.id, "1".repeat(64), source.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "source character enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(destination.id, "2".repeat(64), destination.to_data(), "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "trade recipient enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "inventory fixture begins the adventure")
	var carried_source := session._state.party.character_by_id(source.id)
	var item := content.item_by_id("classic.item.inventory-sword")
	var instance := RealmzRules.new().inventory.add_item(carried_source, item, "inventory.instance.sword", true)
	assert_not_null(instance, "source-backed carried item enters the source character inventory")
	var item_view := session.view().party_members[0].items[0]
	assert_true(item_view.actions.equip.enabled, "detached item actions expose a legal Classic equip")
	assert_true(item_view.actions.trade.enabled, "detached item actions expose a legal recipient")
	assert_equal(item_view.actions.trade_targets[0].character_id, destination.id, "the detached trade target uses stable character identity")

	var equipped := session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, instance.id, source.id))
	assert_equal(equipped.state, SessionStep.State.COMPLETED, "typed Equip commits synchronously")
	assert_true(carried_source.inventory()[0].equipped, "Equip changes only session-owned item state")
	assert_equal(equipped.events[0].kind, &"item_equipped", "Equip publishes a presentation event")
	var equipped_trade := session.submit_intent(PlayerIntent.trade_item(instance.id, source.id, destination.id))
	assert_equal(equipped_trade.state, SessionStep.State.COMPLETED, "Classic trade accepts an equipped ordinary item")
	var carried_destination := session._state.party.character_by_id(destination.id)
	assert_false(carried_destination.inventory()[0].equipped, "the transferred record becomes unequipped on its recipient")
	assert_equal(session.submit_intent(PlayerIntent.trade_item(instance.id, destination.id, source.id)).state, SessionStep.State.COMPLETED, "the exact item can be traded back")
	assert_equal(session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, instance.id, source.id)).state, SessionStep.State.COMPLETED, "the returned item can be equipped again")
	var unequipped := session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.UNEQUIP_ITEM, instance.id, source.id))
	assert_equal(unequipped.state, SessionStep.State.COMPLETED, "typed Unequip commits synchronously")
	var traded := session.submit_intent(PlayerIntent.trade_item(instance.id, source.id, destination.id))
	assert_equal(traded.state, SessionStep.State.COMPLETED, "typed trade moves one exact item instance")
	assert_equal(carried_source.inventory().size(), 0, "trade removes the source item")
	assert_equal(carried_destination.inventory()[0].id, instance.id, "trade preserves stable instance identity")
	assert_equal(carried_source.carried_load, 0, "trade removes the exact item load from the source")
	assert_equal(carried_destination.carried_load, item.instance_weight(instance.charges), "trade adds the exact item load to the destination")

	var before_use_charges := carried_destination.inventory()[0].charges
	var rejected_use := session.submit_intent(PlayerIntent.use_item(instance.id))
	assert_equal(rejected_use.error_code, &"item_effect_unimplemented", "an unimplemented item effect fails instead of spending a charge")
	assert_equal(carried_destination.inventory()[0].charges, before_use_charges, "failed item use preserves charges")

	var drop_wait := session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, instance.id, destination.id))
	assert_equal(drop_wait.state, SessionStep.State.WAITING_FOR_INTERACTION, "Drop opens a typed irreversible-action confirmation")
	assert_equal(drop_wait.interaction.kind, InteractionRequest.YES_NO, "Drop uses the ordinary serializable yes/no interaction")
	assert_false(session._scenario_vm.is_active(), "a session-owned Drop does not create a VM continuation")
	assert_equal(session._scenario_vm.pending_request(), null, "a session-owned Drop does not create a VM request")
	var pending_snapshot := session.snapshot()
	assert_not_null(pending_snapshot, "Drop confirmation is a saveable committed boundary")
	if pending_snapshot == null:
		return
	var restored_envelope := SaveEnvelope.from_data(pending_snapshot.to_data())
	assert_not_null(restored_envelope, "Drop confirmation save data validates before restore")
	if restored_envelope == null:
		return
	var restored := GameSession.new()
	assert_equal(restored.restore(content, restored_envelope).state, SessionStep.State.COMPLETED, "pending Drop confirmation restores transactionally")
	assert_equal(restored.view().pending_interaction.to_data(), drop_wait.interaction.to_data(), "restored Drop retains its exact request and labels")
	var declined := restored.respond(InteractionResponse.yes_no(restored.view().pending_interaction, false))
	assert_equal(declined.state, SessionStep.State.COMPLETED, "declining Drop resumes at a committed boundary")
	assert_equal(restored._state.party.character_by_id(destination.id).inventory().size(), 1, "declining Drop preserves the item")
	var second_wait := restored.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, instance.id, destination.id))
	var accepted := restored.respond(InteractionResponse.yes_no(second_wait.interaction, true))
	assert_equal(accepted.state, SessionStep.State.COMPLETED, "accepting Drop commits the irreversible action")
	assert_equal(restored._state.party.character_by_id(destination.id).inventory().size(), 0, "accepted Drop removes the exact item")
	assert_equal(accepted.events[0].kind, &"item_dropped", "accepted Drop publishes its committed result")

	var cursed := content.item_by_id("classic.item.inventory-curse")
	var cursed_instance := RealmzRules.new().inventory.add_item(restored._state.party.character_by_id(source.id), cursed, "inventory.instance.curse", false)
	var cursed_equip := restored.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, cursed_instance.id, source.id))
	assert_equal(cursed_equip.state, SessionStep.State.COMPLETED, "a source-backed cursed item can be equipped")
	assert_true(cursed_instance.identified, "equipping a curse reveals it as Castle wear.c does")
	var cursed_remove := restored.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.UNEQUIP_ITEM, cursed_instance.id, source.id))
	assert_equal(cursed_remove.error_code, &"item_cannot_unequip", "a cursed item cannot be removed through ordinary Unequip")
	var cursed_trade := restored.submit_intent(PlayerIntent.trade_item(cursed_instance.id, source.id, destination.id))
	assert_equal(cursed_trade.error_code, &"item_cannot_trade", "FD-INVENTORY-001 prevents Castle's trade path from bypassing an equipped curse")
	_test_equipment_probes(content)


func _test_equipment_probes(content: RealmzContent) -> void:
	var rules := RealmzRules.new()
	var character := _character("inventory.probes", "Probe", content)
	character.maximum_load = 2_000
	var party: Array[CharacterState] = [character]
	var race := content.race_by_id(character.race_id)
	var caste := content.caste_by_id(character.caste_id)
	var category_mask := 1 << 5
	var missile_mask := 1 << 12
	var greatsword := ItemDefinition.new("classic.item.probe-greatsword", 20, "Greatsword")
	greatsword.item_type = 2
	greatsword.hands = 2
	greatsword.item_category_mask_low = category_mask
	var shield := ItemDefinition.new("classic.item.probe-shield", 21, "Shield")
	shield.item_type = 3
	shield.hands = 1
	shield.item_category_mask_low = category_mask
	var quiver := ItemDefinition.new("classic.item.probe-quiver", 22, "Quiver")
	quiver.item_type = 10
	quiver.item_category_mask_low = missile_mask
	var bow := ItemDefinition.new("classic.item.probe-bow", 23, "Bow")
	bow.item_type = 15
	bow.hands = 2
	bow.item_category_mask_low = missile_mask
	var unsupported := ItemDefinition.new("classic.item.probe-speed", 24, "Boots of Speed")
	unsupported.item_type = 14
	unsupported.item_category_mask_low = category_mask
	unsupported.movement_bonus = 2
	var definitions: Array[ItemDefinition] = [greatsword, shield, quiver, bow, unsupported]
	var greatsword_instance := rules.inventory.add_item(character, greatsword, "probe.greatsword", true)
	var shield_instance := rules.inventory.add_item(character, shield, "probe.shield", true)
	var quiver_instance := rules.inventory.add_item(character, quiver, "probe.quiver", true)
	var bow_instance := rules.inventory.add_item(character, bow, "probe.bow", true)
	var unsupported_instance := rules.inventory.add_item(character, unsupported, "probe.speed", true)
	assert_true(rules.inventory.equip_classic(character, greatsword_instance, greatsword, race, caste, party, definitions).allowed, "Classic equipment probe accepts a legal two-handed weapon")
	assert_false(rules.inventory.classic_equip_probe(character, shield_instance, shield, race, caste, party, definitions).allowed, "Classic equipment probe rejects a shield when both hands are occupied")
	assert_true(rules.inventory.unequip_classic(character, greatsword_instance, greatsword, definitions).allowed, "the two-handed weapon can be removed")
	assert_false(rules.inventory.classic_equip_probe(character, bow_instance, bow, race, caste, party, definitions).allowed, "a normal bow requires an equipped quiver")
	assert_true(rules.inventory.equip_classic(character, quiver_instance, quiver, race, caste, party, definitions).allowed, "the Classic quiver slot can be equipped")
	assert_true(rules.inventory.equip_classic(character, bow_instance, bow, race, caste, party, definitions).allowed, "the bow becomes legal after its quiver is equipped")
	assert_false(rules.inventory.classic_unequip_probe(character, quiver_instance, quiver, definitions).allowed, "the quiver cannot be removed while a missile weapon is equipped")
	assert_false(rules.inventory.classic_equip_probe(character, unsupported_instance, unsupported, race, caste, party, definitions).allowed, "unimplemented passive item effects stay explicitly unavailable")
	character.money = WealthState.new(7, 2, 1)
	var expected_load := 7 + 2 + 15
	for carried: ItemInstance in character.inventory():
		expected_load += (definitions.filter(func(definition: ItemDefinition) -> bool: return definition.id == carried.definition_id)[0] as ItemDefinition).instance_weight(carried.charges)
	assert_equal(rules.inventory.calculated_load(character, definitions), expected_load, "Castle carried load is derived from gold, gems, jewelry, and each item's charge-aware weight")
	var unknown := ItemInstance.new("probe.unknown", "classic.item.missing")
	var invalid_items := character.inventory()
	invalid_items.append(unknown)
	character.set_inventory(invalid_items)
	assert_equal(rules.inventory.calculated_load(character, definitions), -1, "load validation rejects an item without immutable package content")


func _inventory_content(source: RealmzContent) -> RealmzContent:
	var empty_ints: Array[int] = []
	var empty_ranges: Array[Vector2i] = []
	var age_changes: Array[PackedInt32Array] = []
	for _index: int in 5:
		age_changes.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
	var category_mask := (1 << 5) | (1 << 12)
	var race := RaceDefinition.new("classic.race.inventory", 1, "Human", empty_ints, empty_ints, empty_ints, empty_ints, empty_ints, empty_ranges, age_changes, 0, false, 10, 0, 0, 0, 1, 1, false, 0, category_mask, 0)
	var caste := CasteDefinition.new("classic.caste.inventory", 1, "Fighter", empty_ints, empty_ints, empty_ints, empty_ints, Vector2i(8, 8), Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, [], [], [], 1, 1, 0, 1, 0, 0, 0, 1, 0, true, false, 0, category_mask, 0)
	var sword := ItemDefinition.new("classic.item.inventory-sword", 10, "Longsword", "Sword", "A balanced one-handed sword.")
	sword.item_type = 2
	sword.hands = 1
	sword.weight = 12
	sword.initial_charges = 2
	sword.item_category_mask_low = 1 << 5
	sword.damage_bonus = 2
	var cursed := ItemDefinition.new("classic.item.inventory-curse", 11, "Cursed Longsword", "Sword", "A blade that refuses to leave its bearer.")
	cursed.item_type = 2
	cursed.hands = 1
	cursed.weight = 10
	cursed.item_category_mask_low = 1 << 5
	cursed.cursed_item_id = cursed.id
	var races: Array[RaceDefinition] = [race]
	var castes: Array[CasteDefinition] = [caste]
	var items: Array[ItemDefinition] = [sword, cursed]
	return RealmzContent.new("inventory-workflow", source.package_hash, "inventory-workflow-content", source.rules_version, source.start_map_id, source.start_coordinate, source.world, ScenarioDefinition.new([], []), [], [], [], races, castes, items)


func _character(character_id: String, display_name: String, content: RealmzContent) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, 12, 12)
	result.race_id = content.race_definitions()[0].id
	result.caste_id = content.caste_definitions()[0].id
	result.maximum_load = 100
	return result
