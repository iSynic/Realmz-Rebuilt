## Replays Half Truth's placed bond-payment branch through the public session.
extends SceneTree

const EXPECTED_PACKAGE_HASH := "a38948d427a2aeaa49eb9cececd90dd553ed7c0ff35fa141e540aabdb8fa1488"
const TRIGGER_ID := "Data DD:6:98"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2 or arguments[1] not in ["funded", "empty"]:
		printerr("USAGE: --script res://tools/half_truth_opcode33_probe.gd -- <package.realmz2> <funded|empty>")
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
			if event.kind in [&"wealth_taken", &"trigger_disabled", &"action_point_kept", &"ally_joined"]:
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
	print("RESULT ", JSON.stringify({"funded": funded, "messages": messages, "events": events, "paymentSeen": payment_seen, "paid": paid, "gold": gold, "disabled": disabled, "coordinate": [final_save.game_state.party.coordinate.x, final_save.game_state.party.coordinate.y], "rngDraws": final_save.rng_state.draw_count, "pending": String(session.view().pending_interaction.kind) if session.view().pending_interaction != null else ""}))
	var expected_messages := [412, 1765, 1766, 1768] if funded else [412, 1765, 1766, 1767]
	var expected_gold := [0, 0, 20, 0, 70, 170] if funded else [0, 0, 0, 0, 0, 0]
	if not payer_restored or not payment_seen or paid != funded or not events.has("trigger_fired") or messages != expected_messages or gold != expected_gold or disabled != funded or final_save.game_state.party.coordinate != (Vector2i(8, 30) if funded else Vector2i(7, 30)) or final_save.rng_state.draw_count != (12 if funded else 1):
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
