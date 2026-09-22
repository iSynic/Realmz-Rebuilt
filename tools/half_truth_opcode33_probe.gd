## Replays Half Truth's placed bond-payment branch through the public session.
extends SceneTree

const EXPECTED_PACKAGE_HASH := "a38948d427a2aeaa49eb9cececd90dd553ed7c0ff35fa141e540aabdb8fa1488"
const TRIGGER_ID := "Data DD:6:98"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() not in [2, 3, 4] or arguments[1] not in ["funded", "empty"] or (arguments.size() >= 3 and arguments[2] not in ["simple", "tavern"]) or (arguments.size() == 4 and (arguments[2] != "simple" or arguments[3] not in ["0", "1", "2"])):
		printerr("USAGE: --script res://tools/half_truth_opcode33_probe.gd -- <package.realmz2> <funded|empty> [simple [0|1|2]|tavern]")
		quit(2)
		return
	var funded := arguments[1] == "funded"
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		printerr("APPLICATION_ERROR ", application.error_code)
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package(arguments[0])
	if not package.is_ok() or package.content.package_hash != EXPECTED_PACKAGE_HASH:
		printerr("PACKAGE_ERROR ", package.error_code if not package.is_ok() else package.content.package_hash)
		quit(1)
		return
	var content: RealmzContent = package.content
	content.characters.install_application_catalog(application.content.characters)
	var session := GameSession.new()
	session.start(content, 853)
	var catalog := ClassicStarterCharacterCatalog.new()
	var records := catalog.load_records(CharacterVaultController.CLASSIC_STARTER_CATALOG_PATH, ApplicationLibraryIdentity.PACKAGE_HASH)
	var baseline := session.snapshot()
	if baseline == null or records.size() != 6:
		printerr("PARTY_BASELINE_UNAVAILABLE ", catalog.last_error)
		quit(1)
		return
	var rules := RealmzRules.new()
	for record: CharacterVaultRecord in records:
		var state := CharacterStateCodec.copy(record.state)
		if not funded:
			state.money.gold = 0
			state.money.gems = 0
			state.money.jewelry = 0
		state.carried_load = rules.inventory.calculated_load(state, content.items.definitions())
		baseline.game_state.party.add_character(state)
	baseline.game_state.party_setup_completed = true
	var prepared := session.restore(content, baseline)
	if prepared.state == SessionStep.State.FAILED:
		printerr("PREPARE_ERROR ", prepared.error_code)
		quit(1)
		return
	if arguments.size() >= 3 and arguments[2] == "tavern":
		_run_tavern_payment(session, content, funded)
		return
	if arguments.size() >= 3:
		_run_simple_payment(session, content, funded, int(arguments[3]) if arguments.size() == 4 else 0)
		return
	var warp := session.apply_debug_command(SessionDebugCommand.warp("land:6", Vector2i(7, 30)))
	if warp.state == SessionStep.State.FAILED:
		printerr("WARP_ERROR ", warp.error_code)
		quit(1)
		return
	var step := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var messages: Array[int] = []
	var events: Array[String] = []
	var paid := false
	var payment_seen := false
	var payer_restored := false
	for index in 30:
		print("STEP ", index, " state=", step.state, " error=", step.error_code)
		if step.state == SessionStep.State.FAILED:
			quit(1)
			return
		for event: DomainEvent in step.events:
			if event.kind == &"message_shown":
				messages.append(int(event.payload["messageId"]))
			if event.kind == &"trigger_fired" and event.payload.get("triggerId") == TRIGGER_ID:
				events.append("trigger_fired")
			if event.kind in [&"wealth_taken", &"trigger_disabled", &"action_point_kept", &"ally_added"]:
				events.append(String(event.kind))
			if event.kind == &"wealth_taken":
				payment_seen = true
				paid = bool(event.payload["paid"])
				if int(event.payload["amount"]) != 500:
					printerr("PAYMENT_AMOUNT_MISMATCH ", event.payload["amount"])
					quit(1)
					return
		var pending := session.view().pending_interaction
		if pending == null:
			break
		print("PENDING ", String(pending.kind))
		if pending.kind == InteractionRequest.ACKNOWLEDGE:
			step = session.respond(InteractionResponse.acknowledge(pending))
		elif pending.kind == InteractionRequest.YES_NO:
			if not payer_restored:
				var saved := session.snapshot()
				if saved == null:
					printerr("PAYER_SAVE_UNAVAILABLE")
					quit(1)
					return
				var resumed := GameSession.new()
				var restore := resumed.restore(content, saved)
				if restore.state == SessionStep.State.FAILED:
					printerr("PAYER_RESTORE_FAILED ", restore.error_code)
					quit(1)
					return
				session = resumed
				pending = session.view().pending_interaction
				payer_restored = true
			step = session.respond(InteractionResponse.yes_no(pending, true))
		else:
			printerr("UNEXPECTED_INTERACTION ", String(pending.kind))
			quit(1)
			return
	var final_save := session.snapshot()
	if final_save == null:
		printerr("FINAL_SAVE_UNAVAILABLE")
		quit(1)
		return
	var gold := final_save.game_state.party.characters().map(func(character: CharacterState) -> int: return character.money.gold)
	var disabled := final_save.game_state.world.triggers.trigger_is_disabled(TRIGGER_ID)
	var allies := final_save.game_state.party.allies().map(func(ally: MonsterState) -> String: return ally.definition_id)
	var pooled_gold := final_save.game_state.party.pooled_wealth.gold
	print("RESULT ", JSON.stringify({"funded": funded, "messages": messages, "events": events, "paymentSeen": payment_seen, "paid": paid, "gold": gold, "pooledGold": pooled_gold, "allies": allies, "disabled": disabled, "coordinate": [final_save.game_state.party.coordinate.x, final_save.game_state.party.coordinate.y], "rngDraws": final_save.rng_state.draw_count, "pending": String(session.view().pending_interaction.kind) if session.view().pending_interaction != null else ""}))
	var expected_messages := [412, 1765, 1766, 1768] if funded else [412, 1765, 1766, 1767]
	var expected_gold := [0, 0, 20, 0, 70, 170] if funded else [0, 0, 0, 0, 0, 0]
	if not payer_restored or not payment_seen or paid != funded or not events.has("trigger_fired") or messages != expected_messages or gold != expected_gold or pooled_gold != 0 or allies != (["classic.monster.186"] if funded else []) or disabled != funded or final_save.game_state.party.coordinate != (Vector2i(8, 30) if funded else Vector2i(7, 30)) or final_save.rng_state.draw_count != (12 if funded else 1):
		printerr("BOND_BRANCH_MISMATCH")
		quit(1)
		return
	var resumed := GameSession.new()
	var restored := resumed.restore(content, final_save)
	if restored.state == SessionStep.State.FAILED:
		printerr("POST_BOND_RESTORE_FAILED ", restored.error_code)
		quit(1)
		return
	var out: SessionStep
	if funded:
		out = resumed.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	else:
		out = restored
	var out_coordinate := resumed.snapshot().game_state.party.coordinate
	var back := resumed.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var reentry_messages := back.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"]))
	print("REENTRY ", JSON.stringify({"outState": out.state, "outCoordinate": [out_coordinate.x, out_coordinate.y], "backState": back.state, "backCoordinate": [resumed.snapshot().game_state.party.coordinate.x, resumed.snapshot().game_state.party.coordinate.y], "messages": reentry_messages, "pending": String(resumed.view().pending_interaction.kind) if resumed.view().pending_interaction != null else ""}))
	if out.state == SessionStep.State.FAILED or back.state == SessionStep.State.FAILED or reentry_messages != ([] if funded else [412]):
		printerr("BOND_REENTRY_MISMATCH")
		quit(1)
		return
	quit(0)


func _run_tavern_payment(session: GameSession, content: RealmzContent, funded: bool) -> void:
	var warp := session.apply_debug_command(SessionDebugCommand.warp("land:1", Vector2i(9, 8)))
	if warp.state == SessionStep.State.FAILED:
		printerr("TAVERN_WARP_ERROR ", warp.error_code)
		quit(1)
		return
	var step := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var messages: Array[int] = []
	var payments: Array[Dictionary] = []
	var fired := false
	var choice_restored := false
	var cancelled := false
	for index in 12:
		print("TAVERN_STEP ", index, " state=", step.state, " error=", step.error_code)
		if step.state == SessionStep.State.FAILED:
			quit(1)
			return
		for event: DomainEvent in step.events:
			if event.kind == &"trigger_fired" and event.payload.get("triggerId") == "Data DD:1:6":
				fired = true
			if event.kind == &"message_shown":
				messages.append(int(event.payload["messageId"]))
			if event.kind == &"wealth_taken":
				payments.append(event.payload)
		var pending := session.view().pending_interaction
		if pending == null:
			break
		print("TAVERN_PENDING ", String(pending.kind))
		if pending.kind == InteractionRequest.ACKNOWLEDGE:
			step = session.respond(InteractionResponse.acknowledge(pending))
		elif pending.kind == InteractionRequest.ENCOUNTER_CHOICE:
			if not choice_restored:
				var saved := session.snapshot()
				if saved == null:
					printerr("TAVERN_CHOICE_SAVE_UNAVAILABLE")
					quit(1)
					return
				var resumed := GameSession.new()
				var restore := resumed.restore(content, saved)
				if restore.state == SessionStep.State.FAILED:
					printerr("TAVERN_CHOICE_RESTORE_FAILED ", restore.error_code)
					quit(1)
					return
				session = resumed
				pending = session.view().pending_interaction
				choice_restored = true
				step = session.respond(InteractionResponse.from_data(pending.request_id, pending.kind, {"index": 0}))
			else:
				cancelled = true
				step = session.respond(InteractionResponse.from_data(pending.request_id, pending.kind, {"index": -1, "cancelled": true}))
		else:
			printerr("TAVERN_UNEXPECTED_INTERACTION ", String(pending.kind))
			quit(1)
			return
	var saved_final := session.snapshot()
	if saved_final == null:
		printerr("TAVERN_FINAL_SAVE_UNAVAILABLE")
		quit(1)
		return
	var gold := saved_final.game_state.party.characters().map(func(character: CharacterState) -> int: return character.money.gold)
	print("TAVERN_RESULT ", JSON.stringify({"funded": funded, "triggerFired": fired, "messages": messages, "payments": payments, "gold": gold, "pooledGold": saved_final.game_state.party.pooled_wealth.gold, "disabled": saved_final.game_state.world.triggers.trigger_is_disabled("Data DD:1:6"), "coordinate": [saved_final.game_state.party.coordinate.x, saved_final.game_state.party.coordinate.y], "rngDraws": saved_final.rng_state.draw_count, "choiceRestored": choice_restored, "cancelled": cancelled}))
	var expected_gold := [9, 99, 150, 0, 200, 300] if funded else [0, 0, 0, 0, 0, 0]
	if step.state != SessionStep.State.COMPLETED or session.view().pending_interaction != null or not fired or not choice_restored or cancelled != funded or messages != ([122] if funded else [194]) or payments.size() != 1 or int(payments[0].get("amount", -1)) != 2 or bool(payments[0].get("paid", not funded)) != funded or gold != expected_gold or saved_final.game_state.party.pooled_wealth.gold != 0 or not saved_final.game_state.party.allies().is_empty() or saved_final.game_state.world.triggers.trigger_is_disabled("Data DD:1:6") or saved_final.game_state.party.coordinate != Vector2i(9, 8) or saved_final.rng_state.draw_count != 2:
		printerr("TAVERN_BRANCH_MISMATCH")
		quit(1)
		return
	var resumed_final := GameSession.new()
	var restored_final := resumed_final.restore(content, saved_final)
	if restored_final.state == SessionStep.State.FAILED:
		printerr("TAVERN_POST_RESTORE_FAILED ", restored_final.error_code)
		quit(1)
		return
	var reentry := resumed_final.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var reentered := reentry.events.any(func(event: DomainEvent) -> bool: return event.kind == &"trigger_fired" and event.payload.get("triggerId") == "Data DD:1:6")
	print("TAVERN_REENTRY ", JSON.stringify({"state": reentry.state, "reentered": reentered, "pending": String(resumed_final.view().pending_interaction.kind) if resumed_final.view().pending_interaction != null else ""}))
	if reentry.state == SessionStep.State.FAILED or not reentered or resumed_final.view().pending_interaction == null or resumed_final.view().pending_interaction.kind != InteractionRequest.ENCOUNTER_CHOICE:
		printerr("TAVERN_REENTRY_MISMATCH")
		quit(1)
		return
	quit(0)


func _run_simple_payment(session: GameSession, content: RealmzContent, funded: bool, choice_index: int) -> void:
	var warp := session.apply_debug_command(SessionDebugCommand.warp("land:4", Vector2i(16, 26)))
	if warp.state == SessionStep.State.FAILED:
		printerr("SIMPLE_WARP_ERROR ", warp.error_code)
		quit(1)
		return
	var step := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var messages: Array[int] = []
	var events: Array[String] = []
	var choice_restored := false
	var paid := false
	var payment_count := 0
	var paid_count := 0
	for index in 25:
		print("SIMPLE_STEP ", index, " state=", step.state, " error=", step.error_code)
		if step.state == SessionStep.State.FAILED:
			quit(1)
			return
		for event: DomainEvent in step.events:
			if event.kind == &"message_shown":
				messages.append(int(event.payload["messageId"]))
			if event.kind == &"trigger_fired" and event.payload.get("triggerId") == "Data DD:4:73":
				events.append("trigger_fired")
			if event.kind in [&"wealth_taken", &"action_point_kept", &"trigger_disabled"]:
				events.append(String(event.kind))
			if event.kind == &"wealth_taken":
				payment_count += 1
				paid = bool(event.payload["paid"])
				if paid:
					paid_count += 1
				if int(event.payload["amount"]) != [7, 15, 24][choice_index]:
					printerr("SIMPLE_PAYMENT_AMOUNT_MISMATCH")
					quit(1)
					return
		var pending := session.view().pending_interaction
		if pending == null:
			break
		print("SIMPLE_PENDING ", String(pending.kind))
		if pending.kind == InteractionRequest.ACKNOWLEDGE:
			step = session.respond(InteractionResponse.acknowledge(pending))
		elif pending.kind == InteractionRequest.ENCOUNTER_CHOICE:
			if not choice_restored:
				var saved := session.snapshot()
				if saved == null:
					printerr("SIMPLE_CHOICE_SAVE_UNAVAILABLE")
					quit(1)
					return
				var resumed := GameSession.new()
				var restore := resumed.restore(content, saved)
				if restore.state == SessionStep.State.FAILED:
					printerr("SIMPLE_CHOICE_RESTORE_FAILED ", restore.error_code)
					quit(1)
					return
				session = resumed
				pending = session.view().pending_interaction
				choice_restored = true
			step = session.respond(InteractionResponse.from_data(pending.request_id, pending.kind, {"index": choice_index}))
		else:
			printerr("SIMPLE_UNEXPECTED_INTERACTION ", String(pending.kind))
			quit(1)
			return
	var final_save := session.snapshot()
	if final_save == null:
		printerr("SIMPLE_FINAL_SAVE_UNAVAILABLE")
		quit(1)
		return
	var gold := final_save.game_state.party.characters().map(func(character: CharacterState) -> int: return character.money.gold)
	var disabled := final_save.game_state.world.triggers.trigger_is_disabled("Data DD:4:73")
	var pooled_gold := final_save.game_state.party.pooled_wealth.gold
	print("SIMPLE_RESULT ", JSON.stringify({"funded": funded, "choiceIndex": choice_index, "messages": messages, "events": events, "paid": paid, "paymentCount": payment_count, "paidCount": paid_count, "gold": gold, "pooledGold": pooled_gold, "disabled": disabled, "coordinate": [final_save.game_state.party.coordinate.x, final_save.game_state.party.coordinate.y], "rngDraws": final_save.rng_state.draw_count}))
	var expected_messages := [1779 + choice_index, 1779 + choice_index, 1779 + choice_index, 1779 + choice_index] if funded else [194]
	var funded_gold := [
		[2, 92, 146, 0, 196, 296],
		[0, 87, 137, 0, 188, 288],
		[0, 78, 128, 0, 178, 280],
	]
	var expected_gold: Array = funded_gold[choice_index] if funded else [0, 0, 0, 0, 0, 0]
	if not choice_restored or payment_count != (4 if funded else 1) or paid_count != (4 if funded else 0) or paid != funded or not events.has("trigger_fired") or messages != expected_messages or gold != expected_gold or pooled_gold != 0 or final_save.game_state.party.allies().size() != 0 or disabled != funded or final_save.game_state.party.coordinate != (Vector2i(17, 26) if funded else Vector2i(16, 26)) or final_save.rng_state.draw_count != 1:
		printerr("SIMPLE_BRANCH_MISMATCH")
		quit(1)
		return
	var resumed := GameSession.new()
	var restored := resumed.restore(content, final_save)
	if restored.state == SessionStep.State.FAILED:
		printerr("SIMPLE_POST_RESTORE_FAILED ", restored.error_code)
		quit(1)
		return
	var out: SessionStep
	if funded:
		out = resumed.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	else:
		out = restored
	var back := resumed.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var reentered := back.events.any(func(event: DomainEvent) -> bool: return event.kind == &"trigger_fired" and event.payload.get("triggerId") == "Data DD:4:73")
	print("SIMPLE_REENTRY ", JSON.stringify({"outState": out.state, "backState": back.state, "reentered": reentered, "pending": String(resumed.view().pending_interaction.kind) if resumed.view().pending_interaction != null else ""}))
	if out.state == SessionStep.State.FAILED or back.state == SessionStep.State.FAILED or reentered != (not funded) or (not funded and (resumed.view().pending_interaction == null or resumed.view().pending_interaction.kind != InteractionRequest.ENCOUNTER_CHOICE)):
		printerr("SIMPLE_REENTRY_MISMATCH")
		quit(1)
		return
	quit(0)
