extends SceneTree

const PACKAGE_REPOSITORY_SCRIPT := preload("res://src/infrastructure/packages/package_repository.gd")
const DEFAULT_BATTLE_ID := 46


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 1 or arguments.size() > 2:
		printerr("Usage: godot --headless --path <project> --script res://tools/combat_performance_probe.gd -- <package.realmz2> [classic-battle-id]")
		call_deferred("_quit_cleanly", 2)
		return
	var loaded := PACKAGE_REPOSITORY_SCRIPT.new().load_package(arguments[0])
	if not loaded.is_ok():
		printerr("PACKAGE_REJECTED %s: %s" % [loaded.error_code, loaded.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var content: RealmzContent = loaded.content
	var package_media: PackageMediaCatalog = loaded.media
	var battle_id := int(arguments[1]) if arguments.size() == 2 else DEFAULT_BATTLE_ID
	var battle := content.battle_by_classic_id(battle_id)
	if battle == null:
		printerr("BATTLE_REJECTED: Classic battle %d is unavailable" % battle_id)
		call_deferred("_quit_cleanly", 1)
		return
	var state := _fresh_state(content)
	if state == null:
		printerr("STATE_REJECTED: package has no compatible race/caste pair")
		call_deferred("_quit_cleanly", 1)
		return
	var rules := RealmzRules.new()
	var rng := RealmzRng.new(17)
	var setup_started := Time.get_ticks_usec()
	var setup := rules.combat_flow.start_battle(state, content, battle, rng)
	var setup_us := Time.get_ticks_usec() - setup_started
	if not setup.ok or state.combat == null:
		printerr("BATTLE_REJECTED %s: %s" % [setup.error_code, setup.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var character_ids: Array[String] = []
	for character: CharacterState in state.party.characters():
		if character.current_health > 0 and state.combat.battlefield.has_actor(character.id):
			character_ids.append(character.id)
	var monster_ids: Array[String] = []
	for monster: MonsterState in state.combat.monsters():
		if monster.current_health > 0 and state.combat.battlefield.has_actor(monster.id):
			monster_ids.append(monster.id)
	if character_ids.is_empty() or monster_ids.is_empty():
		printerr("BATTLE_REJECTED: probe requires living party and monster actors")
		call_deferred("_quit_cleanly", 1)
		return
	state.combat.set_turn_order(character_ids + monster_ids)
	var previous_view := _combat_view(state, content, rules, 1)
	var view_started := Time.get_ticks_usec()
	var view := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow, state)
	var view_us := Time.get_ticks_usec() - view_started
	var checkpoint_started := Time.get_ticks_usec()
	state.to_data()
	var checkpoint_us := Time.get_ticks_usec() - checkpoint_started
	var auto_started := Time.get_ticks_usec()
	var auto := rules.combat_flow.submit_action(state, content, character_ids[0], &"auto", "", rng)
	var auto_us := Time.get_ticks_usec() - auto_started
	if not auto.ok:
		printerr("AUTO_REJECTED %s: %s" % [auto.error_code, auto.error_message])
		call_deferred("_quit_cleanly", 1)
		return
	var final_view := _combat_view(state, content, rules, 2)
	var auto_playback := _playback_metrics(previous_view, auto.events, final_view)
	var setup_view := _combat_view(state, content, rules, 3)
	var setup_playback := _playback_metrics(null, setup.events, setup_view)
	var combat_assets: Array[MediaAsset] = []
	for monster: MonsterState in state.combat.monsters():
		var definition := content.monster_by_id(monster.definition_id)
		if definition == null:
			continue
		var asset := package_media.asset_by_resource("cicn", definition.icon_id)
		if asset != null and not combat_assets.has(asset):
			combat_assets.append(asset)
	var individual_media_started := Time.get_ticks_usec()
	for asset: MediaAsset in combat_assets:
		package_media.read_bytes(asset)
	var individual_media_us := Time.get_ticks_usec() - individual_media_started
	var batch_media_started := Time.get_ticks_usec()
	package_media.read_bytes_batch(combat_assets)
	var batch_media_us := Time.get_ticks_usec() - batch_media_started
	print(CanonicalJson.encode({
		"autoEventCount": auto.events.size(),
		"autoEventKinds": auto.events.map(func(event: DomainEvent) -> String: return String(event.kind)),
		"autoMs": _milliseconds(auto_us),
		"autoPlaybackFrames": auto_playback["frames"],
		"autoPlaybackSeconds": auto_playback["seconds"],
		"battleClassicId": battle_id,
		"battleSetupEventCount": setup.events.size(),
		"battleSetupEventKinds": setup.events.map(func(event: DomainEvent) -> String: return String(event.kind)),
		"battleSetupMs": _milliseconds(setup_us),
		"battleSetupPlaybackFrames": setup_playback["frames"],
		"battleSetupPlaybackSeconds": setup_playback["seconds"],
		"combatViewMs": _milliseconds(view_us),
		"combatPackageAssetCount": combat_assets.size(),
		"combatPackageAssetIndividualReadMs": _milliseconds(individual_media_us),
		"combatPackageAssetBatchReadMs": _milliseconds(batch_media_us),
		"monsterCount": monster_ids.size(),
		"partySize": character_ids.size(),
		"rngDrawCount": rng.snapshot().draw_count,
		"stateCheckpointMs": _milliseconds(checkpoint_us),
		"viewMovementOptionCount": view.movement_options.size(),
	}))
	call_deferred("_quit_cleanly", 0)


func _combat_view(state: GameState, content: RealmzContent, rules: RealmzRules, revision: int) -> GameView:
	var members: Array[CharacterView] = []
	for character: CharacterState in state.party.characters():
		var member := CharacterView.new(character, content)
		member.apply_equipment(rules.inventory.combat_equipment(character, content.item_definitions()))
		members.append(member)
	var combat := CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow, state) if state.combat != null else null
	return GameView.new(revision, true, null, state.party.map_id, state.party.coordinate, state.clock.day(), state.clock.hour(), state.clock.minute(), null, members, state.party.fatigue, state.party.pooled_wealth.gold, combat)


func _playback_metrics(previous: GameView, events: Array[DomainEvent], final: GameView) -> Dictionary:
	var controller := CombatPlaybackController.new()
	if not controller.begin(previous, events, final, false):
		return {"frames": 0, "seconds": 0.0}
	var frames := 0
	var seconds := 0.0
	while controller.is_active() and frames < 10_000:
		var frame := controller.current_frame()
		if frame == null:
			break
		frames += 1
		seconds += frame.duration_seconds
		controller.advance(frame.duration_seconds + 0.001, false)
	return {"frames": frames, "seconds": snappedf(seconds, 0.001)}


func _fresh_state(content: RealmzContent) -> GameState:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	if races.is_empty() or castes.is_empty():
		return null
	var race := races[0]
	var caste: CasteDefinition = null
	for candidate: CasteDefinition in castes:
		if race.eligible_caste_ids.is_empty() or race.eligible_caste_ids.has(candidate.id):
			caste = candidate
			break
	if caste == null:
		return null
	var characters: Array[CharacterState] = []
	for index: int in 6:
		var character := CharacterState.new("combat-probe-%d" % index, "Probe %d" % (index + 1), 40, 40)
		character.race_id = race.id
		character.caste_id = caste.id
		character.level = 5
		character.maximum_movement = 12
		character.movement = 12
		character.normal_attacks = 2
		characters.append(character)
	var state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, characters), RealmzClock.new())
	state.party_setup_completed = true
	state.world.mark_visited(content.start_map_id, content.start_coordinate)
	return state


static func _milliseconds(microseconds: int) -> float:
	return snappedf(float(microseconds) / 1000.0, 0.001)


func _quit_cleanly(exit_code: int) -> void:
	quit(exit_code)
