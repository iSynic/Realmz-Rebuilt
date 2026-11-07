## Walks Trouble's Land 14 until rect 15 fires XAP 1794, then proves it never fires again, across save/restore.
extends SceneTree

const LAND := "land:14"
const RECT := "land:14:rect:15"
const WALK_STEPS := 4000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var package_path := ""
	var expected_hash := ""
	var expect_once := true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--package-path="):
			package_path = argument.substr("--package-path=".length())
		elif argument.begins_with("--package-hash="):
			expected_hash = argument.substr("--package-hash=".length())
		elif argument == "--expect-repeat":
			expect_once = false
	if package_path.is_empty() or expected_hash.length() != 64:
		printerr("USAGE: --package-path=<archive> --package-hash=<sha256> [--expect-repeat]")
		quit(2)
		return
	var repository := PackageRepository.new()
	var application := repository.load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH)
	repository.set_application_content(application.content, application.media.assets())
	var package := repository.load_package(package_path)
	if not package.is_ok() or package.content.package_hash != expected_hash:
		printerr("PACKAGE_ERROR ", package.error_code, " ", package.error_message)
		quit(1)
		return
	var content: RealmzContent = package.content
	content.characters.install_application_catalog(application.content.characters)
	var session := GameSession.new()
	session.start(content, 853)
	var records := ClassicStarterCharacterCatalog.new().load_records(CharacterVaultController.CLASSIC_STARTER_CATALOG_PATH, ApplicationLibraryIdentity.PACKAGE_HASH)
	var snapshot := session.snapshot()
	var rules := RealmzRules.new()
	for record: CharacterVaultRecord in records:
		var state := CharacterStateCodec.copy(record.state)
		state.carried_load = rules.inventory.calculated_load(state, content.items.definitions())
		snapshot.game_state.party.add_character(state)
	snapshot.game_state.party_setup_completed = true
	session.restore(content, snapshot)
	var map := content.world.map_by_id(LAND)
	var start := _walkable_pair(map)
	var warp := session.apply_debug_command(SessionDebugCommand.warp(LAND, start))
	if warp.state == SessionStep.State.FAILED:
		printerr("WARP_ERROR ", warp.error_code)
		quit(1)
		return
	var fires: Array[int] = []
	var sounds: Array[int] = []
	var step_index := 0
	var restored_at := -1
	var moves := 0
	var rests := 0
	for index: int in WALK_STEPS:
		if index == WALK_STEPS / 2 and not fires.is_empty():
			# Save and restore mid-walk: the disabled chance must persist.
			var saved := session.snapshot()
			var reopened := GameSession.new()
			if reopened.restore(content, saved).state == SessionStep.State.FAILED:
				printerr("RESTORE_FAILED")
				quit(1)
				return
			session = reopened
			restored_at = index
		var direction := Vector2i.RIGHT if moves % 2 == 0 else Vector2i.LEFT
		var step := session.submit_intent(ExplorationIntents.move(direction))
		if step.events.any(func(e: DomainEvent) -> bool: return e.kind == &"classic_notification_requested" and e.payload.get("source") == "classic-movement-fatigue"):
			# Restore the party with the debug command so fatigue never stops the walk.
			var rest := session.apply_debug_command(SessionDebugCommand.restore_party())
			if rest.state == SessionStep.State.FAILED:
				printerr("RESTORE_PARTY_FAILED ", rest.error_code, " ", rest.error_message)
				quit(1)
				return
			rests += 1
			step = session.submit_intent(ExplorationIntents.move(direction))
		if step.events.any(func(e: DomainEvent) -> bool: return e.kind == &"party_moved"):
			moves += 1
		step_index = index
		if step.state == SessionStep.State.FAILED:
			printerr("STEP_FAILED ", index, " ", step.error_code)
			quit(1)
			return
		var step_sounds: Array[int] = []
		var xap_ran := false
		for event: DomainEvent in step.events:
			if event.kind == &"sound_requested":
				step_sounds.append(str(event.payload["soundId"]).to_int())
			if event.kind == &"random_region_changed" and event.payload["regionId"] == RECT:
				xap_ran = true
		# The rumble's four Play Sound steps (10090, 642, 645, 10090) mark each XAP 1794 run.
		if step_sounds.has(642) and step_sounds.has(645):
			fires.append(index)
			sounds = step_sounds
			if expect_once and not xap_ran:
				printerr("RUMBLE_WITHOUT_CODE_23 ", index)
				quit(1)
				return
		var guard := 0
		while session.view().pending_interaction != null and guard < 20:
			var request := session.view().pending_interaction
			guard += 1
			if request.kind == InteractionRequest.ACKNOWLEDGE:
				session.respond(InteractionResponse.acknowledge(request))
			else:
				printerr("UNEXPECTED_INTERACTION ", String(request.kind), " step ", index, " at ", session.view().party_coordinate, " ", JSON.stringify(step.events.map(func(e: DomainEvent) -> String: return String(e.kind))))
				quit(1)
				return
		if OS.get_environment("RUMBLE_TRACE") != "" and index % 250 == 0:
			var kinds := {}
			for event: DomainEvent in step.events:
				kinds[String(event.kind)] = kinds.get(String(event.kind), 0) + 1
			print("TRACE ", index, " at ", session.view().party_coordinate, " ", JSON.stringify(kinds), " ", JSON.stringify(step.events.filter(func(e: DomainEvent) -> bool: return e.kind == &"classic_notification_requested").map(func(e: DomainEvent) -> Dictionary: return e.payload)))
		if session.view().party_coordinate.y != start.y:
			printerr("LEFT_ROW ", session.view().party_coordinate)
			quit(1)
			return
	var region_state := session.snapshot().game_state.world.triggers.random_region(map.random_region_by_id(RECT))
	var report := {"start": [start.x, start.y], "steps": step_index + 1, "moves": moves, "rests": rests, "fires": fires, "restoredAt": restored_at, "chance": region_state.chance_ten_thousand, "sounds": sounds}
	print("RUMBLE ", JSON.stringify(report))
	if expect_once and (fires.size() != 1 or region_state.chance_ten_thousand != 0 or restored_at < 0 or fires[0] >= restored_at or moves != WALK_STEPS):
		printerr("RUMBLE_MISMATCH")
		quit(1)
		return
	quit(0)


func _walkable_pair(map: MapDefinition) -> Vector2i:
	for y: int in range(10, map.topology.height - 10):
		for x: int in range(10, map.topology.width - 10):
			var a := map.topology.cell_at(Vector2i(x, y))
			var b := map.topology.cell_at(Vector2i(x + 1, y))
			if a == null or b == null or not (a.passable and b.passable and a.is_land and b.is_land):
				continue
			if not (a.trigger_ids().is_empty() and b.trigger_ids().is_empty()):
				continue
			var shared := false
			for region: RandomEncounterRegion in map.random_regions():
				if region.id != RECT and (region.bounds.has_point(Vector2i(x, y)) or region.bounds.has_point(Vector2i(x + 1, y))):
					shared = true
			if not shared:
				return Vector2i(x, y)
	return Vector2i(-1, -1)
