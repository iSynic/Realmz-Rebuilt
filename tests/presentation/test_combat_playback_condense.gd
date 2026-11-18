extends RealmzTestCase

## Hurried resolution: one Turn Undead over several undead plays as a single shared result.


func run() -> void:
	var events := _turning_events(["destroyed", "resisted", "turned", "turned"])
	var projected := CombatPlaybackCondense.project(events)
	var groups := _events_of(projected, &"combat_multi_turn_undead_resolved")
	var grouped: Array = groups[0].payload["results"] if groups.size() == 1 else []
	assert_true(grouped.size() == 4 and _events_of(projected, &"combat_turn_undead_resolved").is_empty(), "several Turn Undead results become one shared resolution")
	var sound_ids: Array[int] = []
	for sound: DomainEvent in _events_of(projected, &"sound_requested"):
		sound_ids.append(RowFields.number(sound.payload, "soundId"))
	assert_equal(sound_ids, [659, 132, 630], "each Turn Undead sound is kept once, in order")
	var lone := CombatPlaybackCondense.project(_turning_events(["turned"]))
	assert_equal(_events_of(lone, &"combat_turn_undead_resolved").size(), 1, "a single undead keeps its ordinary result")
	var previous := _view()
	var ordinary := CombatPlaybackController.new()
	assert_true(ordinary.begin(previous, events, previous, false), "ordinary Turn Undead playback starts")
	var resisting := CombatPlaybackController.new()
	var resist_frames: Array[CombatPlaybackFrame] = []
	resisting.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0: resist_frames.append(frame))
	assert_true(resisting.begin(previous, _turning_events(["resisted", "destroyed", "resisted", "resisted"]), previous, false) and resisting.total_duration_seconds() < 1.5, "three resists do not hold one after another")
	while resisting.is_active(): resisting.advance(1.0, false)
	var shared_resists := _frames_of(resist_frames, &"group_result")
	assert_true(shared_resists.size() == 1 and shared_resists[0].group_frames.size() == 3 and _frames_of(resist_frames, &"result").size() == 1, "every resist of one attempt shows in a single frame")
	var hurried := CombatPlaybackController.new()
	hurried.set_hurry_spell_resolution(true)
	var frames: Array[CombatPlaybackFrame] = []
	hurried.frame_changed.connect(func(frame: CombatPlaybackFrame) -> void:
		if frame.progress == 0.0: frames.append(frame))
	assert_true(hurried.begin(previous, events, previous, false), "hurried Turn Undead playback starts")
	assert_true(ordinary.total_duration_seconds() < 2.0, "ordinary Turn Undead over four undead uses the spell pacing: %.2f seconds" % ordinary.total_duration_seconds())
	assert_true(hurried.total_duration_seconds() < ordinary.total_duration_seconds(), "hurried Turn Undead is shorter still: %.2f against %.2f seconds" % [hurried.total_duration_seconds(), ordinary.total_duration_seconds()])
	while hurried.is_active(): hurried.advance(1.0, false)
	var results := _frames_of(frames, &"group_result")
	var effects := _frames_of(frames, &"spell_effect")
	var defeats := _frames_of(frames, &"group_defeat")
	assert_true(results.size() == 1 and results[0].group_frames.size() == 4 and not results[0].hides("undead.0"), "one result frame shows every undead, with the destroyed one still standing")
	assert_true(effects.size() == 8 and effects.all(func(frame: CombatPlaybackFrame) -> bool: return frame.group_frames.size() == 1 and not frame.hides("undead.0")), "both turned undead share the eight glow frames")
	assert_true(defeats.size() == 1 and defeats[0].group_frames.size() == 1 and defeats[0].hides("undead.0"), "the destroyed undead leaves at the shared defeat")


func _events_of(events: Array[DomainEvent], kind: StringName) -> Array[DomainEvent]:
	var found: Array[DomainEvent] = []
	for event: DomainEvent in events:
		if event.kind == kind:
			found.append(event)
	return found


func _frames_of(frames: Array[CombatPlaybackFrame], kind: StringName) -> Array[CombatPlaybackFrame]:
	var found: Array[CombatPlaybackFrame] = []
	for frame: CombatPlaybackFrame in frames:
		if frame.kind == kind:
			found.append(frame)
	return found


func _turning_events(outcomes: Array[String]) -> Array[DomainEvent]:
	var target_ids: Array[String] = []
	for index: int in outcomes.size():
		target_ids.append("undead.%d" % index)
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"sound_requested", {"soundId": 659, "waitForCompletion": false, "source": "classic-combat-turn-undead"}),
		DomainEvent.new(&"combat_turn_undead_attempted", {"actorId": "hero", "targetIds": target_ids, "source": "classic"}),
	]
	for index: int in outcomes.size():
		var outcome := outcomes[index]
		if outcome != "resisted":
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 132 if outcome == "destroyed" else 630, "waitForCompletion": false, "source": "classic-combat-turn-undead"}))
		var turned := outcome == "turned"
		events.append(DomainEvent.new(&"combat_turn_undead_resolved", {"actorId": "hero", "targetId": target_ids[index], "result": outcome, "effectResourceId": 12056 if turned else 0, "effectFrameCount": 8 if turned else 0, "source": "classic"}))
	return events


func _view() -> GameView:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldGrid.CELL_COUNT)
	tiles.fill(232)
	var battlefield := BattlefieldState.new("land:0", tiles)
	var monsters: Array[MonsterState] = []
	assert_true(battlefield.actors.place_character("hero", Vector2i(45, 45)), "the fixture places the priest")
	for index: int in 4:
		var monster := MonsterState.new("undead.%d" % index, "classic.monster.1", "Skeleton", 20, 20)
		monster.icon_id = 384
		monsters.append(monster)
		assert_true(battlefield.actors.place_monster(monster.id, Vector2i(47 + index, 45), 0), "the fixture places each undead")
	var combat := CombatState.new("classic.battle.turning", monsters, 0, battlefield)
	combat.set_turn_order(["hero", "undead.0"])
	var character := CharacterState.new("hero", "Hero", 10, 10)
	var view := GameView.new(1, true, null)
	view.party_members = [CharacterView.new(character)]
	view.combat_view = CombatView.new(combat, [character])
	return view
