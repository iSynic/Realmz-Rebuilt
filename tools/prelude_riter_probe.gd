## Replays Prelude's Mayor-to-Riter Battle 75 return through the public session.
extends SceneTree

const EXPECTED_PACKAGE_HASH := "7f18df4eecc935dd7c1481b0c2419cfc224e8e03950b2263e121c5236073c95c"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var invalid_arguments := arguments.size() > 2
	for argument in arguments:
		invalid_arguments = invalid_arguments or argument not in ["--funded", "--ordinary"]
	if invalid_arguments:
		printerr("USAGE: --script res://tools/prelude_riter_probe.gd [-- --funded] [--ordinary]")
		quit(2)
		return
	var funded := arguments.has("--funded")
	var ordinary := arguments.has("--ordinary")
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	if not application.is_ok():
		printerr("APPLICATION_ERROR ", application.error_code)
		quit(1)
		return
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package("res://src/storage/packages/bundled_campaigns/scenario-prelude-to-pestilence.realmz2")
	if not package.is_ok():
		printerr("PACKAGE_ERROR ", package.error_code)
		quit(1)
		return
	var content: RealmzContent = package.content
	if content.package_hash != EXPECTED_PACKAGE_HASH:
		printerr("PACKAGE_IDENTITY_CHANGED ", content.package_hash)
		quit(1)
		return
	content.characters.install_application_catalog(application.content.characters)
	var session := GameSession.new()
	session.start(content, 853)
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
		if not funded:
			state.money.gold = 0
			state.money.gems = 0
			state.money.jewelry = 0
		state.carried_load = rules.inventory.calculated_load(state, content.items.definitions())
		snapshot.game_state.party.add_character(state)
	snapshot.game_state.party_setup_completed = true
	snapshot.game_state.scenario_progress.set_quest_value(0, -1)
	var prepared := session.restore(content, snapshot)
	if prepared.state == SessionStep.State.FAILED:
		printerr("PREPARE_ERROR ", prepared.error_code)
		quit(1)
		return
	var warp := session.apply_debug_command(SessionDebugCommand.warp("land:0", Vector2i(13, 7)))
	if warp.state == SessionStep.State.FAILED:
		printerr("WARP_ERROR ", warp.error_code)
		quit(1)
		return
	var step := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var mayor_messages: Array[int] = []
	for index: int in 30:
		print("MAYOR_STEP ", index, " state=", step.state, " messages=", step.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"])))
		if step.state == SessionStep.State.FAILED:
			printerr("MAYOR_ERROR ", step.error_code)
			quit(1)
			return
		for event: DomainEvent in step.events:
			if event.kind == &"message_shown":
				mayor_messages.append(int(event.payload["messageId"]))
		var pending := session.view().pending_interaction
		if pending == null or step.state == SessionStep.State.FAILED:
			break
		print("MAYOR_PENDING ", String(pending.kind))
		if pending.kind == InteractionRequest.ACKNOWLEDGE:
			step = session.respond(InteractionResponse.acknowledge(pending))
		elif pending.kind == InteractionRequest.YES_NO:
			step = session.respond(InteractionResponse.yes_no(pending, true))
		else:
			break
	print("MAYOR_FINAL ", JSON.stringify({"override": session.snapshot().game_state.scenario_progress.encounters.program_id("trigger:Data DD:0:6"), "pending": String(session.view().pending_interaction.kind) if session.view().pending_interaction != null else ""}))
	if session.view().pending_interaction != null or mayor_messages != [3, 4, 5, 6] or session.snapshot().game_state.scenario_progress.encounters.program_id("trigger:Data DD:0:6") != "xap:12":
		printerr("MAYOR_ROUTE_MISMATCH")
		quit(1)
		return
	warp = session.apply_debug_command(SessionDebugCommand.warp("land:0", Vector2i(16, 18)))
	if warp.state == SessionStep.State.FAILED:
		printerr("RITER_WARP_ERROR ", warp.error_code)
		quit(1)
		return
	step = session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var riter_yes_no_count := 0
	var riter_messages: Array[int] = []
	for index: int in 35:
		print("RITER_STEP ", index, " state=", step.state, " messages=", step.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"])))
		if step.state == SessionStep.State.FAILED:
			printerr("RITER_ERROR ", step.error_code)
			quit(1)
			return
		for event: DomainEvent in step.events:
			if event.kind == &"message_shown":
				riter_messages.append(int(event.payload["messageId"]))
		if session.view().combat_view != null:
			print("BATTLE ", session.view().combat_view.battle_id)
			break
		var pending := session.view().pending_interaction
		if pending == null or step.state == SessionStep.State.FAILED:
			break
		print("RITER_PENDING ", String(pending.kind))
		if pending.kind == InteractionRequest.ACKNOWLEDGE:
			step = session.respond(InteractionResponse.acknowledge(pending))
		elif pending.kind == InteractionRequest.YES_NO:
			riter_yes_no_count += 1
			if riter_yes_no_count == 2:
				var pre_battle_save := session.snapshot()
				if pre_battle_save == null:
					printerr("PRE_BATTLE_SAVE_UNAVAILABLE")
					quit(1)
					return
				var resumed_before_battle := GameSession.new()
				var restored_before_battle := resumed_before_battle.restore(content, pre_battle_save)
				if restored_before_battle.state == SessionStep.State.FAILED or resumed_before_battle.view().pending_interaction == null:
					printerr("PRE_BATTLE_RESTORE_FAILED ", restored_before_battle.error_code)
					quit(1)
					return
				session = resumed_before_battle
				pending = session.view().pending_interaction
			step = session.respond(InteractionResponse.yes_no(pending, riter_yes_no_count > 1))
		elif pending.kind == InteractionRequest.ENCOUNTER_CHOICE:
			step = session.respond(InteractionResponse.from_data(pending.request_id, pending.kind, {"index": 1}))
		else:
			break
	if riter_messages != [56, 57, 58, 219, 221, 246] or session.view().combat_view == null or session.view().combat_view.battle_id != "classic.battle.75":
		printerr("WRONG_BATTLE")
		quit(1)
		return
	var victory: SessionStep
	if ordinary:
		var ordinary_victory := false
		var ordinary_battle_completed := false
		for turn in 250:
			var combat_request := session.view().pending_interaction
			if combat_request == null or combat_request.kind != InteractionRequest.COMBAT:
				if combat_request != null and combat_request.kind == InteractionRequest.TREASURE_DISTRIBUTION and session.view().combat_view != null and session.view().combat_view.outcome == &"victory" and ordinary_battle_completed:
					ordinary_victory = true
					print("ORDINARY_COMBAT_COMPLETED ", turn)
					break
				printerr("ORDINARY_COMBAT_REQUEST_MISSING ", turn, " pending=", String(combat_request.kind) if combat_request != null else "none", " outcome=", String(session.view().combat_view.outcome) if session.view().combat_view != null else "none")
				quit(1)
				return
			var body := combat_request.body as CombatRequestBody
			victory = session.respond(InteractionResponse.from_data(combat_request.request_id, combat_request.kind, {"actorId": body.actor_id, "action": "auto", "targetId": ""}))
			if victory.state == SessionStep.State.FAILED:
				printerr("ORDINARY_COMBAT_FAILED ", turn, " ", victory.error_code)
				quit(1)
				return
			ordinary_battle_completed = ordinary_battle_completed or victory.events.any(func(event: DomainEvent) -> bool: return event.kind == &"battle_completed" and event.payload.get("outcome") == "victory")
			if turn % 20 == 0:
				print("ORDINARY_COMBAT_PROGRESS ", turn, " round=", body.round_number, " enemies=", body.enemies_remaining)
		if not ordinary_victory:
			printerr("ORDINARY_COMBAT_LIMIT")
			quit(1)
			return
	else:
		victory = session.apply_debug_command(SessionDebugCommand.win_battle())
	var treasure_shared := false
	var victory_messages: Array[int] = []
	var payment_amount := -1
	var paid := false
	var treasure_gold := -1
	var treasure_gems := -1
	var treasure_items := -1
	var no_funds_notices := 0
	var continuation_events: Array[String] = []
	for index: int in 35:
		print("VICTORY_STEP ", index, " state=", victory.state, " error=", victory.error_code, " events=", JSON.stringify(victory.events.map(func(event: DomainEvent) -> Dictionary: return {"kind": String(event.kind), "messageId": event.payload.get("messageId"), "amount": event.payload.get("amount"), "paid": event.payload.get("paid"), "gold": event.payload.get("gold")})))
		if victory.state == SessionStep.State.FAILED:
			quit(1)
			return
		for event: DomainEvent in victory.events:
			if event.kind in [&"battle_returned", &"message_shown", &"wealth_taken", &"action_point_kept", &"trigger_disabled"]:
				continuation_events.append(String(event.kind))
			if event.kind == &"message_shown":
				victory_messages.append(int(event.payload["messageId"]))
			if event.kind == &"wealth_taken":
				payment_amount = int(event.payload["amount"])
				paid = bool(event.payload["paid"])
			if event.kind == &"classic_notification_requested" and event.payload.get("text") == "The party does not have enough gold.":
				no_funds_notices += 1
		var pending := session.view().pending_interaction
		if pending == null or victory.state == SessionStep.State.FAILED:
			break
		print("VICTORY_PENDING ", JSON.stringify({"kind": String(pending.kind), "wealth": pending.body.to_data().get("wealth"), "messageId": pending.body.to_data().get("messageId")}))
		if pending.kind == InteractionRequest.TREASURE_DISTRIBUTION and not treasure_shared:
			var wealth: Dictionary = pending.body.to_data().get("wealth", {})
			treasure_gold = int(wealth.get("gold", -1))
			treasure_gems = int(wealth.get("gems", -1))
			treasure_items = (pending.body.to_data().get("items", []) as Array).size()
		if pending.kind == InteractionRequest.TREASURE_DISTRIBUTION and pending.body.to_data().get("wealth") == null:
			print("VICTORY_PENDING_DETAIL ", JSON.stringify(pending.to_data()))
		if pending.kind == InteractionRequest.ACKNOWLEDGE:
			victory = session.respond(InteractionResponse.acknowledge(pending))
		elif pending.kind == InteractionRequest.YES_NO:
			victory = session.respond(InteractionResponse.yes_no(pending, true))
		elif pending.kind == InteractionRequest.TREASURE_DISTRIBUTION:
			var reward_action := "confirm-completion" if pending.body.to_data().get("mode") == "completion-confirmation" else "done" if treasure_shared else "share"
			victory = session.respond(InteractionResponse.from_data(pending.request_id, pending.kind, {"action": reward_action}))
			treasure_shared = true
		else:
			break
	var final_save := session.snapshot()
	if final_save == null:
		printerr("POST_BATTLE_SAVE_UNAVAILABLE")
		quit(1)
		return
	var gold := final_save.game_state.party.characters().map(func(character: CharacterState) -> int: return character.money.gold)
	var disabled := final_save.game_state.world.triggers.trigger_is_disabled("Data DD:0:6")
	print("VICTORY_FINAL ", JSON.stringify({"funded": funded, "gold": gold, "messages": victory_messages, "treasureGold": treasure_gold, "treasureGems": treasure_gems, "treasureItems": treasure_items, "paymentAmount": payment_amount, "paid": paid, "noFundsNotices": no_funds_notices, "ap6Disabled": disabled, "rngDraws": final_save.rng_state.draw_count}))
	var expected_gold := ([0, 80, 130, 0, 180, 280] if ordinary else [0, 83, 133, 0, 182, 283]) if funded else ([2, 2, 2, 2, 1, 1] if ordinary else [4, 4, 4, 3, 3, 3])
	var expected_messages := [247] if funded else [247, 248]
	var expected_continuation := ["battle_returned", "message_shown", "wealth_taken", "trigger_disabled"] if funded else ["battle_returned", "message_shown", "wealth_taken", "message_shown", "action_point_kept"]
	var expected_treasure := [10, 1, 19] if ordinary else [21, 4, 18]
	var expected_rng_draws := 3559 if ordinary else 3134
	if gold != expected_gold or victory_messages != expected_messages or continuation_events != expected_continuation or [treasure_gold, treasure_gems, treasure_items] != expected_treasure or payment_amount != 100 or paid != funded or no_funds_notices != (0 if funded else 1) or disabled != funded or final_save.rng_state.draw_count != expected_rng_draws:
		printerr("VICTORY_LEDGER_MISMATCH")
		quit(1)
		return
	var resumed := GameSession.new()
	var restored_post_battle := resumed.restore(content, final_save)
	if restored_post_battle.state == SessionStep.State.FAILED:
		printerr("POST_BATTLE_RESTORE_FAILED ", restored_post_battle.error_code)
		quit(1)
		return
	session = resumed
	var out := session.submit_intent(ExplorationIntents.move(Vector2i.LEFT))
	var back := session.submit_intent(ExplorationIntents.move(Vector2i.RIGHT))
	var reentry_messages := back.events.filter(func(event: DomainEvent) -> bool: return event.kind == &"message_shown").map(func(event: DomainEvent) -> int: return int(event.payload["messageId"]))
	print("REENTRY ", JSON.stringify({"outState": out.state, "backState": back.state, "messages": reentry_messages, "pending": String(session.view().pending_interaction.kind) if session.view().pending_interaction != null else ""}))
	if out.state == SessionStep.State.FAILED or back.state == SessionStep.State.FAILED or reentry_messages != ([] if funded else [56]):
		printerr("REENTRY_MISMATCH")
		quit(1)
		return
	quit(0)
