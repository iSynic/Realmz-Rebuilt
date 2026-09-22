## Replays Prelude AP 9 at the public session boundary with pinned starter wealth.
extends SceneTree

const EXPECTED_PACKAGE_HASH := "7f18df4eecc935dd7c1481b0c2419cfc224e8e03950b2263e121c5236073c95c"
const BUNDLED_PACKAGE_PATH := "res://src/storage/packages/bundled_campaigns/scenario-prelude-to-pestilence.realmz2"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var paid := false
	var package_path := BUNDLED_PACKAGE_PATH
	var expected_hash := EXPECTED_PACKAGE_HASH
	var custom_path := false
	var custom_hash := false
	var invalid_arguments := false
	for argument in arguments:
		if argument == "--paid" and not paid:
			paid = true
		elif argument.begins_with("--package-path=") and not custom_path:
			package_path = argument.substr("--package-path=".length())
			custom_path = true
		elif argument.begins_with("--package-hash=") and not custom_hash:
			expected_hash = argument.substr("--package-hash=".length())
			custom_hash = true
		else:
			invalid_arguments = true
	if invalid_arguments or custom_path != custom_hash or package_path.is_empty() or expected_hash.length() != 64:
		printerr("USAGE: --script res://tools/prelude_payment_probe.gd [-- --paid] [--package-path=<archive> --package-hash=<sha256>]")
		quit(2)
		return
	var zero_gold := not paid
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		printerr("APPLICATION_ERROR ", application.error_code, " ", application.error_message)
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package(package_path)
	if not package.is_ok():
		printerr("PACKAGE_ERROR ", package.error_code, " ", package.error_message)
		quit(1)
		return
	var content: RealmzContent = package.content
	if content.package_hash != expected_hash:
		printerr("PACKAGE_IDENTITY_CHANGED ", content.package_hash)
		quit(1)
		return
	content.characters.install_application_catalog(application.content.characters)
	var session := GameSession.new()
	var started := session.start(content, 853)
	if started.state == SessionStep.State.FAILED:
		printerr("START_ERROR ", started.error_code)
		quit(1)
		return
	var catalog := ClassicStarterCharacterCatalog.new()
	var records := catalog.load_records(CharacterVaultController.CLASSIC_STARTER_CATALOG_PATH, ApplicationLibraryIdentity.PACKAGE_HASH)
	var snapshot := session.snapshot()
	if records.size() != 6 or snapshot == null:
		printerr("STARTER_BASELINE_UNAVAILABLE ", catalog.last_error)
		quit(1)
		return
	var rules := RealmzRules.new()
	for record: CharacterVaultRecord in records:
		var state := CharacterStateCodec.copy(record.state)
		if zero_gold:
			state.money.gold = 0
			state.money.gems = 0
			state.money.jewelry = 0
		state.carried_load = rules.inventory.calculated_load(state, content.items.definitions())
		if not snapshot.game_state.party.add_character(state):
			printerr("PARTY_ERROR ", record.state.name)
			quit(1)
			return
	snapshot.game_state.party_setup_completed = true
	snapshot.game_state.scenario_progress.set_quest_value(0, -1)
	var restored := session.restore(content, snapshot)
	if restored.state == SessionStep.State.FAILED:
		printerr("RESTORE_ERROR ", restored.error_code, " ", restored.error_message)
		quit(1)
		return
	var warp := session.apply_debug_command(SessionDebugCommand.warp("land:0", Vector2i(22, 12)))
	if warp.state == SessionStep.State.FAILED:
		printerr("WARP_ERROR ", warp.error_code, " ", warp.error_message)
		quit(1)
		return
	print("BASELINE ", JSON.stringify({"package": content.package_hash, "party": snapshot.game_state.party.characters().map(func(character: CharacterState) -> Dictionary: return {"name": character.name, "gold": character.money.gold})}))
	var step := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var message_ids: Array[int] = []
	var no_funds := false
	var payment_amount := -1
	var no_funds_notices := 0
	var replaced := false
	var kept := false
	for index: int in 30:
		print("STEP ", index, " state=", step.state, " messages=", step.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"])))
		if step.state == SessionStep.State.FAILED:
			quit(1)
			return
		for event: DomainEvent in step.events:
			if event.kind == &"message_shown":
				message_ids.append(int(event.payload["messageId"]))
			if event.kind == &"wealth_taken":
				payment_amount = int(event.payload["amount"])
				no_funds = not event.payload["paid"]
			if event.kind == &"classic_notification_requested" and event.payload.get("text") == "The party does not have enough gold.":
				no_funds_notices += 1
			if event.kind == &"scenario_program_replaced" and event.payload["targetProgramId"] == "xap:31":
				replaced = true
			if event.kind == &"action_point_kept":
				kept = true
		var request := session.view().pending_interaction
		if request == null:
			break
		print("PENDING ", String(request.kind))
		if request.kind == InteractionRequest.ACKNOWLEDGE:
			step = session.respond(InteractionResponse.acknowledge(request))
		elif request.kind == InteractionRequest.YES_NO:
			step = session.respond(InteractionResponse.yes_no(request, true))
		elif request.kind == InteractionRequest.INDEXED_CHOICE or request.kind == InteractionRequest.ENCOUNTER_CHOICE:
			step = session.respond(InteractionResponse.from_data(request.request_id, request.kind, {"index": 0}))
		elif request.kind == InteractionRequest.CHARACTER_SELECTION:
			var pending_save := session.snapshot()
			if pending_save == null:
				printerr("PENDING_SAVE_UNAVAILABLE")
				quit(1)
				return
			var resumed := GameSession.new()
			var resume_step := resumed.restore(content, pending_save)
			if resume_step.state == SessionStep.State.FAILED or resumed.view().pending_interaction == null:
				printerr("PENDING_RESTORE_FAILED ", resume_step.error_code)
				quit(1)
				return
			session = resumed
			request = session.view().pending_interaction
			step = session.respond(InteractionResponse.from_data(request.request_id, request.kind, {"characterIds": [snapshot.game_state.party.characters()[0].id]}))
		else:
			break
	var final_save := session.snapshot()
	var gold := final_save.game_state.party.characters().map(func(character: CharacterState) -> int: return character.money.gold)
	print("FINAL ", JSON.stringify({"location": {"x": session.view().party_coordinate.x, "y": session.view().party_coordinate.y}, "gold": gold, "messages": message_ids, "noFunds": no_funds, "noFundsNotices": no_funds_notices, "paymentAmount": payment_amount, "replaced": replaced, "kept": kept}))
	var override_id := final_save.game_state.scenario_progress.encounters.program_id("trigger:Data DD:0:9")
	var expected_messages := [65, 66, 67, 69, 100, 101, 102, 368, 369] if zero_gold else [65, 66, 67, 69, 100, 101, 102, 103]
	var expected_gold := [0, 0, 0, 0, 0, 0] if zero_gold else [9, 99, 149, 0, 199, 299]
	if message_ids != expected_messages or no_funds != zero_gold or no_funds_notices != (1 if zero_gold else 0) or payment_amount != 5 or not replaced or not kept or gold != expected_gold or override_id != "xap:31":
		printerr("ROUTE_MISMATCH")
		quit(1)
		return
	var out := session.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	var back := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var reentry := session.view().pending_interaction
	print("REENTRY ", JSON.stringify({"outState": out.state, "backState": back.state, "messages": back.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"])), "pendingKind": String(reentry.kind) if reentry != null else "", "override": override_id}))
	if out.state == SessionStep.State.FAILED or back.state == SessionStep.State.FAILED or reentry == null or reentry.kind != InteractionRequest.YES_NO or override_id != "xap:31":
		printerr("REENTRY_MISMATCH")
		quit(1)
		return
	var declined := session.respond(InteractionResponse.yes_no(reentry, false))
	print("DECLINE ", JSON.stringify({"state": declined.state, "location": {"x": session.view().party_coordinate.x, "y": session.view().party_coordinate.y}, "messages": declined.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"]))}))
	if declined.state == SessionStep.State.FAILED or session.view().party_coordinate != Vector2i(22, 12):
		printerr("DECLINE_MISMATCH")
		quit(1)
		return
	quit(0)
