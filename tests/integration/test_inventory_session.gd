extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func selected_case_arguments() -> Array:
	var loaded := load_test_package(FIXTURE_PATH)
	return [_inventory_content(loaded.content)] if loaded.is_ok() else []


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var content := _inventory_content(loaded.content)
	_test_field_spell_item_use(content)
	_test_door_item_xap(content)
	_test_inventory_identification(content)
	_test_split_join(content)
	var session := GameSession.new()
	assert_equal(session.start(content, 41).state, SessionStep.State.COMPLETED, "inventory session starts")
	var source := _character("inventory.source", "Alis", content)
	var destination := _character("inventory.destination", "Borin", content)
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(source.id, "1".repeat(64), source, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "source character enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(destination.id, "2".repeat(64), destination, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "trade recipient enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "inventory fixture begins the adventure")
	var carried_source := session._state.party.character_by_id(source.id)
	var item := content.item_by_id("classic.item.inventory-sword")
	var instance := RealmzRules.new().inventory.add_item(carried_source, item, "inventory.instance.sword", true)
	assert_not_null(instance, "source-backed carried item enters the source character inventory")
	var item_view := session.view().party_members[0].items[0]
	assert_true(item_view.actions.equip.enabled, "detached item actions expose a legal Classic equip")
	assert_true(item_view.actions.trade.enabled, "detached item actions expose a legal recipient")
	assert_equal([item_view.actions.trade_targets[0].character_id, item_view.actions.trade_targets[0].current_load, item_view.actions.trade_targets[0].resulting_load, item_view.actions.trade_targets[0].maximum_load], [destination.id, destination.carried_load, destination.carried_load + item.instance_weight(instance.charges), destination.maximum_load], "the detached trade target carries stable identity and source-projected current, resulting, and maximum load")

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
	var rejected_use := session.submit_intent(PlayerIntent.use_item(instance.id, destination.id))
	assert_equal(rejected_use.error_code, &"item_has_no_spell_effect", "ordinary equipment does not masquerade as a charged spell item")
	assert_equal(carried_destination.inventory()[0].charges, before_use_charges, "rejected ordinary item use preserves charges")

	var drop_wait := session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.DROP_ITEM, instance.id, destination.id))
	assert_equal(drop_wait.state, SessionStep.State.WAITING_FOR_INTERACTION, "Drop opens a typed irreversible-action confirmation")
	assert_equal(drop_wait.interaction.kind, InteractionRequest.YES_NO, "Drop uses the ordinary serializable yes/no interaction")
	assert_false(session._scenario_vm.is_active(), "a session-owned Drop does not create a VM continuation")
	assert_equal(session._scenario_vm.pending_request(), null, "a session-owned Drop does not create a VM request")
	var pending_snapshot := session.snapshot()
	assert_not_null(pending_snapshot, "Drop confirmation is a saveable committed boundary")
	if pending_snapshot == null:
		return
	var restored_envelope := SaveEnvelope.from_data(save_data(pending_snapshot))
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


func _test_split_join(content: RealmzContent) -> void:
	var stack := content.item_by_id("classic.item.inventory-stack")
	var owner := _character("inventory.stack-owner", "Cora", content)
	owner.maximum_load = 100_000
	owner.set_inventory([ItemInstance.new("inventory.instance.stack", stack.id, 5, false, true)])
	owner.carried_load = stack.instance_weight(5)
	var session := GameSession.new()
	assert_equal(session.start(content, 97).state, SessionStep.State.COMPLETED, "stack inventory session starts")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(owner.id, "5".repeat(64), owner, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "stack owner enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "stack inventory fixture begins")
	assert_true(session.view().party_members[0].items[0].actions.split.enabled, "a finite per-charge stack exposes Split")
	assert_false(session.view().party_members[0].items[0].actions.join.enabled, "a lone stack does not expose a meaningless Join")
	assert_equal(session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.EQUIP_ITEM, "inventory.instance.stack", owner.id)).state, SessionStep.State.COMPLETED, "the source stack can be equipped before splitting")
	var split := session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.SPLIT_ITEM, "inventory.instance.stack", owner.id))
	assert_equal(split.state, SessionStep.State.COMPLETED, "typed Split commits synchronously")
	var split_owner := session.snapshot().game_state.party.character_by_id(owner.id)
	assert_equal([split_owner.inventory().size(), split_owner.inventory()[0].charges, split_owner.inventory()[1].charges], [2, 3, 2], "Split keeps the ceiling on the source and creates a floor half")
	assert_equal([split_owner.inventory()[0].id, split_owner.inventory()[0].equipped, split_owner.inventory()[1].equipped, split_owner.inventory()[1].identified], ["inventory.instance.stack", true, false, true], "Split retains source identity and equipment while copying identification to an unequipped sibling")
	assert_equal(split_owner.carried_load, stack.instance_weight(3) + stack.instance_weight(2), "Split immediately derives the two-record load instead of retaining Castle's stale display value")
	assert_true(split.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 678), "Split requests Castle's integrated sound")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "a split stack and its deterministic identity restore transactionally")
	var sibling_id := restored.view().party_members[0].items[1].instance_id
	assert_true(restored.view().party_members[0].items[1].actions.join.enabled, "matching stacks expose Join on either exact instance")
	var joined := restored.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, sibling_id, owner.id))
	assert_equal(joined.state, SessionStep.State.COMPLETED, "typed Join commits synchronously")
	var joined_owner := restored.snapshot().game_state.party.character_by_id(owner.id)
	assert_equal([joined_owner.inventory().size(), joined_owner.inventory()[0].id, joined_owner.inventory()[0].charges], [1, sibling_id, 5], "Join keeps the selected stable instance and absorbs every matching stack")
	assert_true(joined_owner.inventory()[0].equipped and joined_owner.inventory()[0].identified, "Join preserves Castle's OR-style equipped and identified state")
	assert_equal(joined_owner.carried_load, stack.instance_weight(5), "Join immediately removes duplicate-record base weight")
	assert_true(joined.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 663), "Join requests Castle's integrated sound")

	var overflow_owner := _character("inventory.overflow-owner", "Dara", content)
	overflow_owner.maximum_load = 100_000
	overflow_owner.set_inventory([ItemInstance.new("inventory.instance.large-a", stack.id, 20_000, false, true), ItemInstance.new("inventory.instance.large-b", stack.id, 20_000, false, true)])
	overflow_owner.carried_load = stack.instance_weight(20_000) * 2
	var overflow_session := GameSession.new()
	assert_equal(overflow_session.start(content, 101).state, SessionStep.State.COMPLETED, "overflow inventory session starts")
	assert_equal(overflow_session.submit_intent(PlayerIntent.import_vault_character(overflow_owner.id, "6".repeat(64), overflow_owner, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "large finite stacks enter the bounded fixture")
	assert_equal(overflow_session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "overflow inventory fixture begins")
	assert_false(overflow_session.view().party_members[0].items[0].actions.join.enabled, "a Join that would overflow Classic's signed charge field is unavailable")
	var rejected := overflow_session.submit_intent(PlayerIntent.item_action(PlayerIntent.Kind.JOIN_ITEM, "inventory.instance.large-a", overflow_owner.id))
	assert_equal(rejected.error_code, &"item_cannot_join", "overflowing Join fails explicitly")
	assert_equal(overflow_session.snapshot().game_state.party.character_by_id(overflow_owner.id).inventory().map(func(item: ItemInstance) -> int: return item.charges), [20_000, 20_000], "rejected overflow preserves both exact stacks")


func _test_inventory_identification(content: RealmzContent) -> void:
	var target := _character("inventory.identify-target", "Galen", content)
	var caster := _character("inventory.identify-caster", "Iria", content)
	var spell := content.spell_by_id("classic.spell.inventory-identify")
	caster.spellcaster_type = 1
	caster.spell_points = 30
	caster.maximum_spell_points = 30
	caster.set_known_spells([spell.id])
	target.set_inventory([
		ItemInstance.new("inventory.identify.unknown", "classic.item.inventory-sword", 2, false, false),
		ItemInstance.new("inventory.identify.known", "classic.item.inventory-stack", 5, false, true),
	])
	target.carried_load = content.item_by_id("classic.item.inventory-sword").instance_weight(2) + content.item_by_id("classic.item.inventory-stack").instance_weight(5)
	var session := GameSession.new()
	assert_equal(session.start(content, 109).state, SessionStep.State.COMPLETED, "inventory identification session starts")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(target.id, "7".repeat(64), target, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "identification target enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(caster.id, "8".repeat(64), caster, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "Identify caster enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "identification fixture begins")
	var action := session.view().party_members[0].items[0].actions
	assert_true(action.identify.enabled, "an inventory with items exposes Castle's Cast Identify action")
	assert_equal([action.identify_caster_id, action.identify_spell_id], [caster.id, spell.id], "the detached action selects the first eligible party caster and exact Identify spell")
	var identified := session.submit_intent(PlayerIntent.identify_carried_items(action.identify_spell_id, action.identify_caster_id, target.id))
	assert_equal(identified.state, SessionStep.State.COMPLETED, "Cast Identify commits synchronously from the inventory workspace")
	var snapshot := session.snapshot()
	assert_equal(snapshot.game_state.party.character_by_id(caster.id).spell_points, 5, "Cast Identify spends Castle's fixed twenty-five spell points rather than the spell record cost")
	assert_true(snapshot.game_state.party.character_by_id(target.id).inventory().all(func(item: ItemInstance) -> bool: return item.identified), "Cast Identify reveals every item carried by the selected character")
	assert_equal(identified.events.map(func(event: DomainEvent) -> StringName: return event.kind), [&"inventory_identified", &"sound_requested"], "identification publishes one result before integrated sound 683")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, save_round_trip(snapshot)).state, SessionStep.State.COMPLETED, "identified inventory and spent spell points restore transactionally")
	assert_false(restored.view().party_members[0].items[0].actions.identify.enabled, "the action disables when no party caster retains twenty-five spell points")


func _test_field_spell_item_use(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 73).state, SessionStep.State.COMPLETED, "field item-use session starts")
	var user := _character("inventory.item-user", "Ena", content)
	var target := _character("inventory.item-target", "Fenn", content)
	user.current_health = 4
	target.current_health = 5
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(user.id, "3".repeat(64), user, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "item user enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.import_vault_character(target.id, "4".repeat(64), target, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "item target enters party setup")
	assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "field item-use fixture begins")
	var carried_user := session._state.party.character_by_id(user.id)
	var carried_target := session._state.party.character_by_id(target.id)
	var wand := content.item_by_id("classic.item.inventory-healing-wand")
	var wand_instance := RealmzRules.new().inventory.add_item(carried_user, wand, "inventory.instance.healing-wand", true)
	assert_not_null(wand_instance, "charged field spell item enters inventory")
	wand_instance.identified = false
	assert_true(session.view().party_members[0].items[0].actions.use.enabled, "detached inventory actions expose a source-backed field item use")
	var load_before := carried_user.carried_load
	var requested := session.submit_intent(PlayerIntent.use_item(wand_instance.id, carried_user.id))
	assert_equal([requested.state, requested.interaction.kind, requested.interaction.body.to_data().get("count")], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.CHARACTER_SELECTION, 1], "party-target item use yields one typed character selection")
	assert_true(String(requested.interaction.body.to_data().get("prompt", "")).contains(wand.unidentified_name) and not String(requested.interaction.body.to_data().get("prompt", "")).contains(wand.name), "field item targeting does not reveal an unidentified item's true name")
	assert_equal(wand_instance.charges, 2, "opening target selection does not spend a charge before a valid target commits")
	var corrupt_power_data := save_data(session.snapshot())
	corrupt_power_data["sessionContinuation"]["data"]["power"] = 7
	var corrupt_power_envelope := SaveEnvelope.from_data(corrupt_power_data)
	assert_not_null(corrupt_power_envelope, "the wire envelope accepts a structurally valid continuation before content validation")
	var corrupt_power_restore := GameSession.new()
	assert_equal(corrupt_power_restore.restore(content, corrupt_power_envelope).error_code, &"invalid_session_continuation", "restore rejects a fixed-power item continuation whose staged power was tampered")
	var envelope := save_round_trip(session.snapshot())
	var restored := GameSession.new()
	assert_equal(restored.restore(content, envelope).state, SessionStep.State.COMPLETED, "pending item target selection restores transactionally")
	var pending := restored.view().pending_interaction
	var rejected := restored.respond(InteractionResponse.from_data(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": ["missing.character"]}))
	assert_equal(rejected.error_code, &"invalid_item_use_target", "a stale or invented item target is rejected explicitly")
	assert_equal(restored._state.party.character_by_id(carried_user.id).inventory()[0].charges, 2, "corrupt item target response spends no charge")
	var completed := restored.respond(InteractionResponse.from_data(pending.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [carried_target.id]}))
	assert_equal(completed.state, SessionStep.State.COMPLETED, "valid item target commits the effect")
	assert_equal(restored._state.party.character_by_id(carried_target.id).current_health, 8, "fixed-power healing item applies its source spell to the selected party member")
	assert_equal(restored._state.party.character_by_id(carried_user.id).inventory()[0].charges, 1, "committed field item use spends exactly one positive charge")
	assert_equal(restored._state.party.character_by_id(carried_user.id).carried_load, load_before - wand.weight_per_charge, "spent charge removes its authored per-charge load")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested" and event.payload.get("soundId") == 649), "field item use requests Castle item sound plus 600")
	assert_true(completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"item_spell_resolved" and event.payload.get("targetId") == carried_target.id), "field item use publishes its exact committed target")
	wand.special_1 = 8
	restored._rng = ScriptedRng.new([32_767, 0, 0, 32_767])
	var invalid_random_target := restored.submit_intent(PlayerIntent.use_item_on_target(wand_instance.id, carried_user.id, "missing.character"))
	assert_equal(invalid_random_target.error_code, &"invalid_item_use_target", "an invented direct target rejects a random-power item before commit")
	assert_equal([restored._rng.snapshot().draw_count, restored._state.party.character_by_id(carried_user.id).inventory()[0].charges], [0, 1], "rejected direct random-power targeting rolls back its staged draw and preserves the charge")
	var random_requested := restored.submit_intent(PlayerIntent.use_item(wand_instance.id, carried_user.id))
	assert_equal([random_requested.state, restored._session_continuation.targeting().power, restored._rng.trace()[0].get("tag")], [SessionStep.State.WAITING_FOR_INTERACTION, 7, "item.use.power.inventory.instance.healing-wand"], "random-power field item rolls Castle Rand(7) once before staging its target")
	assert_equal(restored._state.party.character_by_id(carried_user.id).inventory()[0].charges, 1, "random power selection still cannot consume the charge before a target commits")
	var random_completed := restored.respond(InteractionResponse.from_data(random_requested.interaction.request_id, InteractionRequest.CHARACTER_SELECTION, {"characterIds": [carried_target.id]}))
	assert_equal(random_completed.state, SessionStep.State.COMPLETED, "the staged random power survives through the target response")
	assert_true(random_completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"item_used" and event.payload.get("power") == 7), "the committed item event retains its one rolled power")
	wand.special_1 = 1
	restored._rng = RealmzRng.new(73)

	var self_item := content.item_by_id("classic.item.inventory-self-tonic")
	var self_instance := RealmzRules.new().inventory.add_item(restored._state.party.character_by_id(carried_user.id), self_item, "inventory.instance.self-tonic", true)
	var self_completed := restored.submit_intent(PlayerIntent.use_item(self_instance.id, carried_user.id))
	assert_equal(self_completed.state, SessionStep.State.COMPLETED, "target-type-five item applies immediately to its user")
	assert_equal(restored._state.party.character_by_id(carried_user.id).current_health, 7, "self-target item heals only its user")
	assert_equal(self_instance.charges, -1, "an authored infinite-charge item remains infinite after use")
	var torch := content.item_by_id("classic.item.inventory-torch")
	var torch_instance := RealmzRules.new().inventory.add_item(restored._state.party.character_by_id(carried_user.id), torch, "inventory.instance.torch", true)
	var torch_load_before := restored._state.party.character_by_id(carried_user.id).carried_load
	assert_true(restored.view().party_members[0].items.any(func(item: ItemView) -> bool: return item.instance_id == torch_instance.id and item.actions.use.enabled), "detached inventory actions expose Castle's targetless Torch item effect")
	assert_true(restored.view().availability(&"use_torch").enabled, "the exploration command surface exposes Torch when Classic item 805 is carried and usable")
	var torch_completed := restored.submit_intent(PlayerIntent.use_torch())
	assert_equal(torch_completed.state, SessionStep.State.COMPLETED, "the Torch shortcut resolves Classic item 805 through the ordinary targetless item workflow")
	assert_equal(restored._state.party.conditions.value(ConditionRules.PARTY_TORCH_LIT), 119, "Torch applies Shine power four as Castle's 30-times-power minus one party condition")
	assert_equal([torch_instance.charges, restored._state.party.character_by_id(carried_user.id).carried_load], [5, torch_load_before - torch.weight_per_charge], "Torch spends exactly one charge and its authored per-charge load")
	assert_equal(torch_completed.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"sound_requested").map(func(event: DomainEvent) -> int: return int(event.payload.get("soundId", 0))), [606, 601], "Torch orders its integrated item sound before Shine's resolution sound")
	assert_true(torch_completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"party_condition_changed" and event.payload.get("condition") == ConditionRules.PARTY_TORCH_LIT), "Torch publishes the committed party-state change")
	self_instance.charges = 0
	var empty := restored.submit_intent(PlayerIntent.use_item(self_instance.id, carried_user.id))
	assert_equal(empty.error_code, &"item_has_no_charges", "a depleted item fails before effect or randomness")


func _test_door_item_xap(content: RealmzContent) -> void:
	var session := GameSession.new(); assert_equal(session.start(content, 79).state, SessionStep.State.COMPLETED, "door-item session starts")
	var user := _character("inventory.door-user", "Ena", content); assert_equal(session.submit_intent(PlayerIntent.import_vault_character(user.id, "9".repeat(64), user, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "door-item user enters party setup"); assert_equal(session.submit_intent(PlayerIntent.begin_adventure()).state, SessionStep.State.COMPLETED, "door-item fixture begins")
	var carried := session._state.party.character_by_id(user.id); var door := content.item_by_id("classic.item.inventory-door"); var instance := RealmzRules.new().inventory.add_item(carried, door, "inventory.instance.door", true); assert_true(session.view().party_members[0].items[0].actions.use.enabled, "type-23 item exposes its authored field XAP")
	var waiting := session.submit_intent(PlayerIntent.use_item(instance.id, carried.id)); assert_equal([waiting.state, waiting.interaction.kind, instance.charges, session._session_continuation.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.ACKNOWLEDGE, 1, &"item-xap"], "field door item spends one charge and waits inside its typed XAP owner")
	var restored := GameSession.new(); assert_equal(restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "pending door-item XAP restores transactionally"); var completed := restored.respond(InteractionResponse.acknowledge(restored.view().pending_interaction)); assert_true(completed.state == SessionStep.State.COMPLETED and completed.events.any(func(event: DomainEvent) -> bool: return event.kind == &"item_xap_completed"), "restored field door XAP completes exactly once")
	carried = restored._state.party.character_by_id(user.id); instance = carried.inventory()[0]; door.special_1 = -23; var tiles: Array[int] = []; tiles.resize(BattlefieldState.CELL_COUNT); tiles.fill(0); var field := BattlefieldState.new(content.start_map_id, tiles); field.place_character(carried.id, Vector2i(45, 45)); restored._state.combat = CombatState.new("inventory.door-battle", [], 0, field); restored._state.combat.set_turn_order([carried.id])
	var option := restored._rules.combat_flow.character_item_spell_options(restored._state, content, carried.id)[0]; assert_equal([option.item_instance_id, option.spell_id, option.target_mode], [instance.id, "", &"automatic"], "negative Special 1 door item is an automatic combat item action without a fabricated spell")
	waiting = restored.submit_intent(PlayerIntent.use_item(instance.id, carried.id)); assert_equal([waiting.state, waiting.interaction.kind, carried.inventory().size(), restored._state.combat.battle_id], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.ACKNOWLEDGE, 0, "inventory.door-battle"], "combat door item drops on its final charge while retaining the active battle"); completed = restored.respond(InteractionResponse.acknowledge(waiting.interaction)); assert_equal([completed.state, restored._state.combat.battle_id, restored._session_continuation.is_empty()], [SessionStep.State.COMPLETED, "inventory.door-battle", true], "combat door XAP returns to the same battle without a second dispatch")


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
	var sword := ItemDefinition.new("classic.item.inventory-sword", 10, "Longsword", "Sword", "A balanced one-handed sword."); sword.item_type = 2; sword.hands = 1; sword.weight = 12; sword.initial_charges = 2; sword.item_category_mask_low = 1 << 5; sword.damage_bonus = 2
	var cursed := ItemDefinition.new("classic.item.inventory-curse", 11, "Cursed Longsword", "Sword", "A blade that refuses to leave its bearer."); cursed.item_type = 2; cursed.hands = 1; cursed.weight = 10; cursed.item_category_mask_low = 1 << 5; cursed.cursed_item_id = cursed.id
	var healing_spell := SpellDefinition.new("classic.spell.inventory-heal", 1101, "Mending")
	healing_spell.damage_min = 3
	healing_spell.damage_max = 3
	healing_spell.special = 57
	healing_spell.cannot = 4
	healing_spell.target_type = 1
	healing_spell.in_camp = true
	var self_spell := SpellDefinition.new("classic.spell.inventory-self-heal", 1102, "Restore Self")
	self_spell.damage_min = 3
	self_spell.damage_max = 3
	self_spell.special = 57
	self_spell.cannot = 4
	self_spell.target_type = 5
	self_spell.in_camp = true
	var light_spell := SpellDefinition.new("classic.spell.inventory-light", 1110, "Shine")
	light_spell.special = 50
	light_spell.target_type = 7
	light_spell.in_camp = true
	light_spell.sound_start = 1
	var identify_spell := SpellDefinition.new("classic.spell.inventory-identify", 1103, "Identify Objects")
	identify_spell.special = 48
	identify_spell.cost = 99
	identify_spell.in_camp = false
	var healing_wand := ItemDefinition.new("classic.item.inventory-healing-wand", 12, "Wand of Mending")
	healing_wand.item_type = 21
	healing_wand.weight = 4
	healing_wand.initial_charges = 2
	healing_wand.weight_per_charge = 1
	healing_wand.item_category_mask_low = 1 << 5
	healing_wand.special_1 = 1
	healing_wand.special_2 = healing_spell.classic_id
	healing_wand.sound_id = 49
	var self_tonic := ItemDefinition.new("classic.item.inventory-self-tonic", 13, "Everfull Tonic")
	self_tonic.item_type = 21
	self_tonic.weight = 1
	self_tonic.initial_charges = -1
	self_tonic.item_category_mask_low = 1 << 5
	self_tonic.special_1 = 1
	self_tonic.special_2 = self_spell.classic_id
	var torch := ItemDefinition.new("classic.item.inventory-torch", 805, "Torch")
	torch.item_type = 21
	torch.weight = 4
	torch.initial_charges = 6
	torch.weight_per_charge = 12
	torch.item_category_mask_low = 1 << 5
	torch.special_1 = -4
	torch.special_2 = light_spell.classic_id
	torch.sound_id = 6
	var stack := ItemDefinition.new("classic.item.inventory-stack", 14, "Weighted Darts")
	stack.item_type = 2
	stack.hands = 1
	stack.weight = 2
	stack.initial_charges = 5
	stack.weight_per_charge = 1
	stack.item_category_mask_low = 1 << 5
	var door := ItemDefinition.new("classic.item.inventory-door", 662, "Crown of Safe Return"); door.item_type = 23; door.initial_charges = 2; door.drop_on_empty = true; door.item_category_mask_low = 1 << 5; door.special_5 = 69
	var door_program := ScenarioProgramDefinition.new("xap:69", &"extra-action-point", "69", [ClassicActionDefinition.new(0, 62, 62, 901, false, [])])
	var races: Array[RaceDefinition] = [race]; var castes: Array[CasteDefinition] = [caste]
	var items: Array[ItemDefinition] = [sword, cursed, healing_wand, self_tonic, torch, stack, door]
	var spells: Array[SpellDefinition] = [healing_spell, self_spell, light_spell, identify_spell]
	return RealmzContent.new("inventory-workflow", source.package_hash, "inventory-workflow-content", source.rules_version, source.start_map_id, source.start_coordinate, source.world, ScenarioDefinition.new([door_program], []), [MessageDefinition.new(901, "The crown answers.")], [], [], races, castes, items, spells)


func _character(character_id: String, display_name: String, content: RealmzContent) -> CharacterState:
	var result := CharacterState.new(character_id, display_name, 12, 12)
	result.race_id = content.race_definitions()[0].id
	result.caste_id = content.caste_definitions()[0].id
	result.maximum_load = 100
	return result
