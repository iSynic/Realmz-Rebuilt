extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"
const ViewChangeSetScript := preload("res://src/core/view/view_change_set.gd")


func selected_case_arguments() -> Array:
	var loaded := load_test_package(FIXTURE_PATH)
	return [loaded.content] if loaded.is_ok() else []


func run() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok():
		return
	var content := loaded.content
	_test_map_view_projection_edges(content)
	_test_field_heal(content)
	_test_attempted_land_move_search(content)
	_test_terrain_replacement_topology(content)
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "exploration session starts"); _begin_fixture_adventure(session, content)
	assert_equal(session.view().party_coordinate, Vector2i(1, 1), "Providence start coordinate is authoritative"); assert_equal(session.view().map_view.cells().size(), 625, "GameView exposes one complete bounded topology-derived window at the north-west edge")
	assert_true(session.view().map_view.can_move(Vector2i.UP), "the detached view exposes an authoritative passable movement direction"); assert_true(session.view().map_view.can_move(Vector2i.LEFT), "the detached view preserves the hidden land secret's underlying passability")
	assert_equal(session.view().map_view.visited_coordinates(), [Vector2i(1, 1)], "the minimap receives only session-owned visited coordinates"); assert_equal(session.view().map_view.cell_at(Vector2i(2, 2)).overlay_asset_id, "fixture.special-land.neg-99", "the detached presentation view retains the validated special-land overlay identity")
	var search_clock_before := session.snapshot().game_state.clock.total_minutes(); var search_rng_before := session.rng_trace().size()
	var search_mode_on := session.submit_intent(PlayerIntent.toggle_search())
	assert_true(_has_event(search_mode_on, &"search_mode_changed") and session.view().party_summary.searching, "Search toggles Castle party condition 5 on without performing an Area Search")
	assert_equal([session.snapshot().game_state.clock.total_minutes(), session.rng_trace().size()], [search_clock_before, search_rng_before], "Search mode consumes neither gameplay time nor RNG")
	var searching_restore := GameSession.new()
	assert_equal(searching_restore.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "active Search mode restores through the ordinary party-condition snapshot")
	assert_true(searching_restore.view().party_summary.searching, "the detached view preserves restored Search mode"); assert_equal(session.submit_intent(PlayerIntent.toggle_search()).state, SessionStep.State.COMPLETED, "Search toggles off at the same committed boundary")
	assert_false(session.view().party_summary.searching, "the second Search command clears Castle party condition 5")
	_test_contextual_encounter_command(content)
	var open_content := _open_movement_content(content)
	var open_session := GameSession.new()
	open_session.start(open_content, 1); _begin_fixture_adventure(open_session, open_content)
	var before_open_view := open_session.view()
	var open_step := open_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var open_view := open_session.view(open_step.events)
	assert_equal(open_view.domain_revisions.party, before_open_view.domain_revisions.party, "ordinary movement reuses the unchanged party projection"); assert_equal(open_view.domain_revisions.exploration, open_view.revision, "ordinary movement advances the exploration projection revision"); assert_true(open_view.map_view.presentation_delta != null and open_view.map_view.presentation_delta.viewport_shift == Vector2i.RIGHT and open_view.map_view.presentation_delta.newly_visited == [Vector2i(2, 1)], "strict ordinary movement carries only its detached viewport and visibility delta")
	assert_equal([open_view.domain_revisions.party_roster, open_view.domain_revisions.party_status, open_view.domain_revisions.inventory, open_view.domain_revisions.magic], [before_open_view.domain_revisions.party_roster, before_open_view.domain_revisions.party_status, before_open_view.domain_revisions.inventory, before_open_view.domain_revisions.magic], "movement leaves every unchanged party dependency revision stable"); assert_true(not open_view.change_set.complete_refresh and open_view.change_set.has_domain(ViewChangeSetScript.EXPLORATION) and open_view.change_set.has_domain(ViewChangeSetScript.SYSTEM) and not open_view.change_set.has_domain(ViewChangeSetScript.PARTY_STATUS), "movement publishes an explicit exploration-only dependency change set")
	assert_true(open_session.view() == open_view and open_view.map_view.cell_at(Vector2i(2, 1)).has_feature(&"discovered_path"), "repeated reads reuse the detached view and a walked Classic path exposes its saved red-cross marker"); assert_equal([before_open_view.map_view.visited_coordinates(), open_view.map_view.visited_coordinates()], [[Vector2i(1, 1)], [Vector2i(1, 1), Vector2i(2, 1)]], "delta materialization preserves the previous detached history while appending the newly walked cell")
	assert_equal([before_open_view.party_coordinate, before_open_view.map_view.cell_at(Vector2i(2, 1)).visited, before_open_view.map_view.cell_at(Vector2i(2, 1)).has_feature(&"discovered_path")], [Vector2i(1, 1), false, false], "a later chunk patch cannot mutate the previous detached party or map window"); var edge_cell := MapCellView.new(Vector2i(7, 0), "fixture.terrain", 1, "fixture.tileset", true, false, true, true, false, false, [], {}, {}, {}); var next_chunk_cell := MapCellView.new(Vector2i(8, 0), "fixture.terrain", 1, "fixture.tileset", true, false, true, true, false, false, [], {}, {}, {}); var source_cells: Array[MapCellView] = [edge_cell]; var edge_window := MapWindowView.new(Rect2i(7, 0, 1, 1), {}, source_cells); var crossed_window := edge_window.patched(Rect2i(8, 0, 1, 1), {Vector2i(8, 0): next_chunk_cell}); assert_equal([crossed_window.cell_at(Vector2i(8, 0)), edge_window.cell_at(Vector2i(7, 0))], [next_chunk_cell, edge_cell], "an incremental map window allocates a typed destination chunk across an 8x8 boundary without losing or mutating either detached snapshot")
	var full_projection_session := GameSession.new(); full_projection_session.restore(open_content, save_round_trip(open_session.snapshot())); var full_open_view := full_projection_session.view()
	assert_equal([open_view.party_coordinate, open_view.realmz_day, open_view.realmz_hour, open_view.realmz_minute, open_view.map_view.cells().size(), open_view.party_members.size()], [full_open_view.party_coordinate, full_open_view.realmz_day, full_open_view.realmz_hour, full_open_view.realmz_minute, full_open_view.map_view.cells().size(), full_open_view.party_members.size()], "incremental and full projections expose the same movement-owned state"); assert_equal(full_open_view.map_view.presentation_delta, null, "restore reconstructs a complete authoritative map projection without carrying a runtime delta")
	var hourly_snapshot := open_session.snapshot(); var hourly_character := hourly_snapshot.game_state.party.characters()[0]; hourly_character.level = 10; hourly_character.maximum_spell_points = 100; hourly_character.spell_points = 0; var minute_offset := posmod(55 - hourly_snapshot.game_state.clock.total_minutes(), 60); hourly_snapshot.game_state.clock.advance_minutes(minute_offset); assert_equal(open_session.restore(open_content, hourly_snapshot).state, SessionStep.State.COMPLETED, "the hourly movement projection fixture restores at a committed boundary"); var before_hourly_view := open_session.view(); var hourly_step := open_session.submit_intent(PlayerIntent.move(Vector2i.LEFT)); var hourly_view := open_session.view(hourly_step.events)
	assert_true(_has_event(hourly_step, &"spell_points_recovered") and hourly_view.map_view.presentation_delta != null and hourly_view.domain_revisions.is_ordinary_exploration_update_from(before_hourly_view.domain_revisions), "an hour-crossing movement with spell recovery retains the incremental exploration path")
	assert_true(hourly_view.domain_revisions.party_roster == before_hourly_view.domain_revisions.party_roster and hourly_view.domain_revisions.party_status == hourly_view.revision and hourly_view.domain_revisions.magic == hourly_view.revision and hourly_view.change_set.has_domain(ViewChangeSetScript.PARTY_STATUS) and hourly_view.change_set.has_domain(ViewChangeSetScript.MAGIC), "hourly recovery invalidates status and magic without rebuilding roster identity")
	assert_equal([hourly_view.party_members[0].spell_points, hourly_view.domain_revisions.party, hourly_view.domain_revisions.inventory_magic, hourly_view.bestiary_entries.size()], [open_session.snapshot().game_state.party.characters()[0].spell_points, hourly_view.revision, hourly_view.revision, before_hourly_view.bestiary_entries.size()], "hourly movement refreshes mutable party and magic projections while retaining the immutable Bestiary catalog")
	var hourly_full_session := GameSession.new(); hourly_full_session.restore(open_content, save_round_trip(open_session.snapshot())); var hourly_full_view := hourly_full_session.view(); assert_equal([hourly_view.party_members[0].spell_points, hourly_view.party_members[0].condition_values, hourly_view.availability(&"cast_spell").enabled, hourly_view.availability(&"cast_spell").reason], [hourly_full_view.party_members[0].spell_points, hourly_full_view.party_members[0].condition_values, hourly_full_view.availability(&"cast_spell").enabled, hourly_full_view.availability(&"cast_spell").reason], "incremental hourly party and spell availability match a complete restored projection")
	var los_content := _open_movement_content(content, true); var los_session := GameSession.new(); los_session.start(los_content, 1); _begin_fixture_adventure(los_session, los_content); var initial_los_view := los_session.view(); var los_step := los_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); var moved_los_view := los_session.view(los_step.events); assert_true(moved_los_view.map_view.presentation_delta != null and moved_los_view.domain_revisions.party == initial_los_view.domain_revisions.party and moved_los_view.domain_revisions.exploration == moved_los_view.revision, "LOS movement identifies its visibility-sensitive cells while retaining the ordinary shell and unchanged view domains")
	var restored_los_session := GameSession.new(); restored_los_session.restore(los_content, save_round_trip(los_session.snapshot())); var restored_los_view := restored_los_session.view(); var incremental_los_cells := moved_los_view.map_view.cells().map(func(cell: MapCellView) -> Array: return [cell.coordinate, cell.visible, cell.visited]); var restored_los_cells := restored_los_view.map_view.cells().map(func(cell: MapCellView) -> Array: return [cell.coordinate, cell.visible, cell.visited]); assert_equal([incremental_los_cells, moved_los_view.map_view.seen_coordinates()], [restored_los_cells, restored_los_view.map_view.seen_coordinates()], "incremental LOS visibility and sight memory match a complete restored projection")
	for action_id: Variant in full_open_view.action_availability:
		var action := StringName(action_id)
		assert_equal([open_view.availability(action).enabled, open_view.availability(action).reason], [full_open_view.availability(action).enabled, full_open_view.availability(action).reason], "incremental and full projections agree on %s availability" % action)
	_test_boat_movement(content)
	_test_special_dungeon_bits(content)
	_test_location_notes(content)
	var diagonal_session := GameSession.new(); assert_equal(diagonal_session.start(content, 1).state, SessionStep.State.COMPLETED, "a dedicated land-diagonal session starts")
	_begin_fixture_adventure(diagonal_session, content)
	assert_true(diagonal_session.view().map_view.can_move(Vector2i(-1, -1)), "land views expose source-backed diagonal movement availability")
	var diagonal_step := diagonal_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	var diagonal_view := diagonal_session.view(diagonal_step.events)
	assert_equal(diagonal_step.state, SessionStep.State.COMPLETED, "a diagonal land move commits as one ordinary movement step")
	assert_equal(diagonal_view.party_coordinate, Vector2i.ZERO, "diagonal land movement changes both coordinates together")
	assert_equal(diagonal_view.map_view.last_move_direction, Vector2i(-1, -1), "the detached map view exposes the committed movement vector for Classic party facing")
	assert_equal(diagonal_session._state.clock.total_minutes(), content.world.map_by_id("land:0").topology.cell_at(Vector2i.ZERO).movement_cost * 5, "outdoor movement scales the authored Classic timeclick count to five-minute clicks")
	assert_equal(diagonal_session.snapshot().game_state.last_move_direction, Vector2i(-1, -1), "the save aggregate retains the complete diagonal movement vector")
	var restored_diagonal := GameSession.new()
	assert_equal(restored_diagonal.restore(content, save_round_trip(diagonal_session.snapshot())).state, SessionStep.State.COMPLETED, "diagonal movement state restores transactionally")
	assert_equal(restored_diagonal.snapshot().game_state.last_move_direction, Vector2i(-1, -1), "save/reload preserves a diagonal backup direction")
	assert_equal(restored_diagonal.view().map_view.last_move_direction, Vector2i(-1, -1), "the restored detached map view preserves the movement vector used by presentation")
	var layout_maps: Array[MapDefinition] = [content.world.map_by_id("land:0"), content.world.map_by_id("land:1")]
	var layout_transitions: Array[MapTransition] = [MapTransition.new("layout:land:0:northwest:land:1", "land:0", &"northwest", "land:1", &"southeast")]
	var diagonal_layout_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, "land:0", Vector2i.ZERO, WorldDefinition.new(layout_maps, layout_transitions), ScenarioDefinition.new([], []), [], [], [], content.race_definitions(), content.caste_definitions())
	var diagonal_layout_session := GameSession.new()
	assert_equal(diagonal_layout_session.start(diagonal_layout_content, 1).state, SessionStep.State.COMPLETED, "a diagonal Layout transition session starts")
	_begin_fixture_adventure(diagonal_layout_session, diagonal_layout_content)
	var diagonal_layout_step := diagonal_layout_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	assert_equal(diagonal_layout_session.view().party_map_id, "land:1", "diagonal boundary input follows the compiled diagonal Layout neighbor")
	assert_equal(diagonal_layout_session.view().party_coordinate, Vector2i(89, 89), "diagonal boundary input wraps to the opposite target corner")
	assert_true(_has_event(diagonal_layout_step, &"map_transitioned"), "diagonal Layout movement publishes the ordinary transition event")
	var restored_diagonal_layout := GameSession.new()
	assert_equal(restored_diagonal_layout.restore(diagonal_layout_content, save_round_trip(diagonal_layout_session.snapshot())).state, SessionStep.State.COMPLETED, "diagonal Layout movement restores transactionally")
	assert_equal(restored_diagonal_layout.view().party_coordinate, Vector2i(89, 89), "save/reload retains the diagonal Layout destination")

	var north := session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(session.view().party_coordinate, Vector2i(1, 0), "typed movement intent commits through GameSession")
	assert_true(_has_event(north, &"message_shown"), "message AP executes on entry")
	assert_equal(north.state, SessionStep.State.WAITING_FOR_INTERACTION, "positive Classic AP text creates a committed acknowledgement boundary")
	assert_equal(north.interaction.kind, &"acknowledge", "the active AP message uses the dedicated textbox interaction")
	assert_false(_has_event(north, &"tile_replaced"), "later AP mutations do not run before the player advances the text")
	var north_snapshot := save_round_trip(session.snapshot())
	assert_not_null(north_snapshot, "the Classic textbox and movement continuation serialize together")
	var north_restored := GameSession.new()
	assert_equal(north_restored.restore(content, north_snapshot).state, SessionStep.State.COMPLETED, "the Classic textbox boundary restores transactionally")
	var north_completed := north_restored.respond(InteractionResponse.from_data(north_restored.view().pending_interaction.request_id, &"acknowledge", {}))
	assert_true(_has_event(north_completed, &"tile_replaced"), "Classic opcode 12 mutates the world overlay after acknowledgement")
	assert_true(_has_event(north_completed, &"random_region_triggered"), "random rectangle gates after the moved-to AP finishes")
	var north_trigger_id := content.world.map_by_id("land:0").topology.cell_at(Vector2i(1, 0)).trigger_ids()[0]
	assert_true(north_restored.snapshot().game_state.world.trigger_is_disabled(north_trigger_id), "an ordinary placed Action Point becomes one-shot after its complete resumed timeline")
	session = north_restored
	assert_equal(session.view().map_view.cell_at(Vector2i(2, 2)).terrain_id, "classic.terrain.2", "presenter view reads the same tile overlay as simulation")
	var special_snapshot := session.snapshot(); special_snapshot.game_state.world.replace_terrain("land:0", Vector2i(2, 2), "classic.terrain.-1018"); var special_session := GameSession.new(); assert_equal(special_session.restore(content, save_round_trip(special_snapshot)).state, SessionStep.State.COMPLETED, "a signed Classic special-land replacement restores transactionally"); var special_cell := special_session.view().map_view.cell_at(Vector2i(2, 2)); assert_equal([special_cell.render_tile, special_cell.overlay_asset_id], [content.world.battle_terrain_set_for_map(content.world.map_by_id("land:0"), special_snapshot.game_state.world).base_tile, "realmz-special-land-neg-18"], "a restored opcode-12 terrain value projects its landlook base and normalized special-land overlay"); special_snapshot.game_state.world.replace_terrain("land:0", Vector2i(2, 2), "classic.terrain.467"); assert_equal(special_session.restore(content, save_round_trip(special_snapshot)).state, SessionStep.State.COMPLETED, "a positive icon-backed Classic replacement restores transactionally"); special_cell = special_session.view().map_view.cell_at(Vector2i(2, 2)); assert_equal([special_cell.render_tile, special_cell.overlay_asset_id], [content.world.battle_terrain_set_for_map(content.world.map_by_id("land:0"), special_snapshot.game_state.world).base_tile, "realmz-land-cicn-467"], "positive icon-backed terrain uses the landlook base and exact CICN identity")

	session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	var hidden_destination := content.world.map_by_id("land:0").topology.cell_at(Vector2i(0, 1))
	assert_true(session.view().map_view.can_move(Vector2i.LEFT) and not session.view().map_view.cell_at(hidden_destination.coordinate).has_feature(&"secret"), "a concealed land secret is enterable while its marker remains hidden")
	var hidden_start_minutes := session._state.clock.total_minutes()
	var hidden_entry := session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal([hidden_entry.state, session.view().party_coordinate], [SessionStep.State.COMPLETED, Vector2i(0, 1)], "entry onto an undiscovered secret square commits through its underlying terrain")
	assert_true(not _has_event(hidden_entry, &"trigger_fired") and _has_event(hidden_entry, &"random_encounter_checked"), "the concealed square suppresses its placed AP but completes ordinary post-move checks")
	assert_equal(session._state.clock.total_minutes(), hidden_start_minutes + hidden_destination.movement_cost * 5, "concealed-square entry pays the underlying tile's five-minute Classic timeclick cost")
	assert_false(session.view().map_view.cell_at(hidden_destination.coordinate).has_feature(&"secret"), "walking onto a land secret does not discover its marker")
	assert_equal(session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)).state, SessionStep.State.COMPLETED, "ordinary movement leaves the still-concealed square")
	var search := session.submit_intent(PlayerIntent.new(PlayerIntent.Kind.SEARCH))
	assert_equal(_event(search, &"search_completed").payload["roll"], 37, "search follows the centralized RNG after ordinary movement attempts consume their secret-check draws")
	assert_true(_has_event(search, &"secret_discovered"), "search commits secret discovery")
	assert_true(session.view().map_view.can_move(Vector2i.LEFT) and session.view().map_view.cell_at(hidden_destination.coordinate).has_feature(&"secret"), "search reveals the Classic S marker without changing collision")
	var revealed_entry := session.submit_intent(PlayerIntent.move(Vector2i.LEFT)); assert_true(revealed_entry.state == SessionStep.State.WAITING_FOR_INTERACTION and _has_event(revealed_entry, &"message_shown"), "the colocated AP activates when the discovered secret square is entered")
	assert_equal(session.view().party_coordinate, Vector2i(0, 1), "the revealed AP entry commits once")
	assert_equal(session.respond(InteractionResponse.acknowledge(revealed_entry.interaction)).state, SessionStep.State.COMPLETED, "acknowledging the revealed secret AP completes its timeline")

	_restore_fixture_position(session, content, "land:0", Vector2i(88, 1))
	session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var transitioned := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(session.view().party_map_id, "land:1", "edge movement follows the compiled Layout transition")
	assert_equal(session.view().party_coordinate, Vector2i(0, 1), "transition preserves the cross-edge offset")
	assert_true(_has_event(transitioned, &"map_transitioned"), "map transition is an explicit domain event")

	var snapshot := session.snapshot()
	var replacement_cell := content.world.map_by_id("land:0").topology.cell_at(Vector2i(2, 2))
	assert_equal(snapshot.game_state.world.terrain_for("land:0", replacement_cell), "classic.terrain.2", "save aggregate owns tile mutation")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, snapshot).state, SessionStep.State.COMPLETED, "exploration aggregate restores transactionally")
	assert_equal(restored.view().party_map_id, "land:1", "restored session retains transitioned map")
	assert_equal(restored.snapshot().game_state.world.terrain_for("land:0", replacement_cell), "classic.terrain.2", "restored session retains world overlays")
	assert_true(restored.snapshot().game_state.world.trigger_is_disabled(north_trigger_id), "save/reload preserves default one-shot Action Point state")

	var keep_source := content.trigger_by_id("ap.fixture.destination-source"); var keep_program := ScenarioProgramDefinition.new(keep_source.program_id, &"trigger", keep_source.id, [ClassicActionDefinition.new(0, 24, 24, 0, false, [])]); var keep_trigger := TriggerDefinition.new(keep_source.id, keep_program.id, keep_source.map_id, keep_source.coordinate, keep_source.active, keep_source.chance_percent, keep_source.post_action_location, keep_source.classic_record_index); var keep_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, "land:1", Vector2i(0, 1), content.world, ScenarioDefinition.new([keep_program], []), [], [keep_trigger], [], content.race_definitions(), content.caste_definitions())
	var keep_session := GameSession.new(); keep_session.start(keep_content, 1); _begin_fixture_adventure(keep_session, keep_content); var kept := keep_session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_true(_has_event(kept, &"action_point_kept"), "Classic opcode 24 marks the issuing placed Action Point as Keep Codes"); assert_false(keep_session.snapshot().game_state.world.trigger_is_disabled(keep_trigger.id), "Keep Codes is the explicit exception to default one-shot Action Points")
	var self_program := ScenarioProgramDefinition.new(keep_source.program_id, &"trigger", keep_source.id, [ClassicActionDefinition.new(0, 3, 3, 0, false, [1, 0, 0, 0, 0]), ClassicActionDefinition.new(1, 45, 45, 0, false, [-1, 1, 0, 0, 0])]); var self_trigger := TriggerDefinition.new(keep_source.id, self_program.id, keep_source.map_id, keep_source.coordinate, true, 100, TriggerDestinationDefinition.new(keep_source.map_id, keep_source.coordinate), keep_source.classic_record_index)
	var self_content := RealmzContent.new(content.campaign_id, content.package_hash, content.content_id, content.rules_version, "land:1", Vector2i(0, 1), content.world, ScenarioDefinition.new([self_program], []), [], [self_trigger], [], content.race_definitions(), content.caste_definitions()); var self_session := GameSession.new(); self_session.start(self_content, 1); _begin_fixture_adventure(self_session, self_content); var self_wait := self_session.submit_intent(PlayerIntent.move(Vector2i.UP)); var self_completed := self_session.respond(InteractionResponse.from_data(self_wait.interaction.request_id, &"yes_no", {"accepted": true}))
	assert_equal([self_completed.state, self_session.view().party_coordinate], [SessionStep.State.COMPLETED, Vector2i(1, 0)], "an AP header pointing to its own source cell cannot undo its resumed program teleport")
	assert_true(_has_event(self_completed, &"party_teleported") and not _has_event(self_completed, &"trigger_fired"), "the VM teleport completes once without re-firing the source AP")
	_test_classic_backout(content)

	var ordered_ap_content := _duplicate_placed_ap_content(100, content); var ordered_ap_session := GameSession.new(); ordered_ap_session.start(ordered_ap_content, 1); _begin_fixture_adventure(ordered_ap_session, ordered_ap_content)
	var ordered_ap_step := ordered_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal(_event_count(ordered_ap_step, &"trigger_fired"), 1, "one coordinate selects only one placed Action Point"); assert_equal(_event(ordered_ap_step, &"trigger_fired").payload["triggerId"], "ap.first-native", "the lowest Classic record index wins even when cell references are reversed"); assert_false(ordered_ap_session.snapshot().game_state.world.trigger_is_disabled("ap.later-native"), "a later same-cell Action Point is not executed or consumed")

	var chance_ap_content := _duplicate_placed_ap_content(1, content); var chance_ap_session := GameSession.new(); chance_ap_session.start(chance_ap_content, 1); _begin_fixture_adventure(chance_ap_session, chance_ap_content)
	var chance_ap_step := chance_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_false(_has_event(chance_ap_step, &"trigger_fired"), "a failed selected AP chance does not fall through to a later same-cell record"); assert_equal(chance_ap_session.rng_trace().size(), 1, "a positive sub-100 selected AP consumes one chance draw"); assert_equal(chance_ap_session.rng_trace()[0]["tag"], "trigger.ap.first-native", "the chance draw belongs to the first native AP")

	var zero_ap_content := _duplicate_placed_ap_content(0, content); var zero_ap_session := GameSession.new(); zero_ap_session.start(zero_ap_content, 1); _begin_fixture_adventure(zero_ap_session, zero_ap_content)
	var zero_ap_step := zero_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_false(_has_event(zero_ap_step, &"trigger_fired"), "Classic percent zero disables the selected AP without falling through"); assert_equal(zero_ap_session.rng_trace().size(), 0, "a disabled selected AP consumes no random draw")
	var inactive_ap_content := _inactive_placed_ap_content(content); var inactive_ap_session := GameSession.new(); inactive_ap_session.start(inactive_ap_content, 1); _begin_fixture_adventure(inactive_ap_session, inactive_ap_content)
	var enabled_ap_step := inactive_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_true(_has_event(enabled_ap_step, &"trigger_chances_changed"), "opcode 13 ignores an unplaced native row while enabling an initially inactive placed AP")
	var inactive_ap_step := inactive_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_equal(_event(inactive_ap_step, &"trigger_fired").payload["triggerId"], "ap.inactive-placed", "a positive runtime chance override activates the addressed AP")

	var disabled_ap_content := _duplicate_placed_ap_content(100, content); var disabled_ap_source := GameSession.new(); disabled_ap_source.start(disabled_ap_content, 1); _begin_fixture_adventure(disabled_ap_source, disabled_ap_content)
	var disabled_ap_save := disabled_ap_source.snapshot(); disabled_ap_save.game_state.world.disable_trigger("ap.first-native")
	var disabled_ap_session := GameSession.new()
	assert_equal(disabled_ap_session.restore(disabled_ap_content, disabled_ap_save).state, SessionStep.State.COMPLETED, "a disabled first-record fixture restores transactionally")
	var disabled_ap_step := disabled_ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_false(_has_event(disabled_ap_step, &"trigger_fired"), "a world-disabled selected AP does not fall through to a later same-cell record"); assert_false(disabled_ap_session.snapshot().game_state.world.trigger_is_disabled("ap.later-native"), "the unselected later AP remains untouched")

	var dungeon_envelope := session.snapshot()
	dungeon_envelope.game_state.party.map_id = "dungeon:0"
	dungeon_envelope.game_state.party.coordinate = Vector2i(2, 0)
	var dungeon_session := GameSession.new()
	assert_equal(dungeon_session.restore(content, dungeon_envelope).state, SessionStep.State.COMPLETED, "validated restore can establish the synthetic dungeon slice"); var turn_rng := dungeon_session.snapshot().rng_state.to_data(); var turn_minutes := dungeon_session.snapshot().game_state.clock.total_minutes(); var before_turn_view := dungeon_session.view(); var turned_dungeon := dungeon_session.submit_intent(PlayerIntent.dungeon_turn(-1)); var turned_view := dungeon_session.view(turned_dungeon.events); assert_equal([turned_dungeon.state, turned_view.map_view.dungeon_heading, turned_view.party_coordinate, dungeon_session.snapshot().game_state.clock.total_minutes(), dungeon_session.snapshot().rng_state.to_data(), turned_view.map_view.presentation_delta.viewport_shift, turned_view.domain_revisions.party_roster, turned_view.change_set.complete_refresh], [SessionStep.State.COMPLETED, 4, Vector2i(2, 0), turn_minutes, turn_rng, Vector2i.ZERO, before_turn_view.domain_revisions.party_roster, false], "a source-shaped left turn incrementally projects the persisted west heading without moving, rebuilding party state, advancing time, or drawing RNG")
	var rejected_diagonal := dungeon_session.submit_intent(PlayerIntent.move(Vector2i(-1, -1)))
	assert_equal(rejected_diagonal.error_code, &"invalid_direction", "dungeon movement remains cardinal even when land supports diagonals")
	assert_equal(dungeon_session.view().party_coordinate, Vector2i(2, 0), "a rejected dungeon diagonal cannot mutate location")
	var overhead_blocked := dungeon_session.submit_intent(PlayerIntent.overhead_dungeon_move(Vector2i.UP))
	assert_equal([overhead_blocked.state, dungeon_session.view().party_coordinate, dungeon_session.view().map_view.dungeon_heading], [SessionStep.State.COMPLETED, Vector2i(2, 0), 1], "a top-down dungeon direction updates the shared Classic heading even when the attempted step is blocked")
	assert_true(_has_event(overhead_blocked, &"dungeon_heading_changed") and _has_event(overhead_blocked, &"movement_blocked"), "the blocked top-down attempt commits its facing change and collision together")
	var opened_door := dungeon_session.submit_intent(PlayerIntent.overhead_dungeon_move(Vector2i.LEFT))
	var door_id := "dungeon:0:cell:1,0:door"
	assert_true(_has_event(opened_door, &"door_opened"), "entering the explicit dungeon door opens its world overlay")
	assert_true(dungeon_session.snapshot().game_state.world.door_is_open(door_id) and dungeon_session.view().map_view.dungeon_heading == 4, "top-down travel and the 3D projection now share the west heading")
	var reversed_in_first_person := dungeon_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal([reversed_in_first_person.state, dungeon_session.view().party_coordinate, dungeon_session.view().map_view.dungeon_heading], [SessionStep.State.COMPLETED, Vector2i(2, 0), 4], "first-person reverse movement changes position without rotating the shared heading")
	var restored_dungeon := GameSession.new()
	assert_equal(restored_dungeon.restore(content, dungeon_session.snapshot()).state, SessionStep.State.COMPLETED, "door-state save restores transactionally")
	assert_true(restored_dungeon.snapshot().game_state.world.door_is_open(door_id) and restored_dungeon.view().map_view.dungeon_heading == 4, "restored session retains the opened door and Classic dungeon heading")

	var surprise_region := content.world.map_by_id("land:0").random_region_by_id("land:0:randlevel:rect:1"); surprise_region.battle_maximum = -1; var surprise_session := GameSession.new()
	surprise_session.start(content, 1)
	_begin_fixture_adventure(surprise_session, content, 6)
	surprise_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var surprise_wait := surprise_session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(surprise_wait.state, SessionStep.State.WAITING_FOR_INTERACTION, "a source-backed random rectangle can yield a typed surprise choice")
	assert_equal(surprise_wait.interaction.kind, &"yes_no", "the random surprise uses the ordinary interaction presenter ABI")
	assert_equal(surprise_session.rng_trace()[-1]["tag"], "random-region.land:0:randlevel:rect:1.good-surprise", "Castle random-region draw order reaches the surprise roll after three door rolls")
	var surprise_snapshot := surprise_session.snapshot()
	assert_not_null(surprise_snapshot, "the random surprise interaction is a committed save boundary")
	assert_equal(surprise_snapshot.session_interaction.request_id, surprise_wait.interaction.request_id, "the save aggregate owns the non-VM interaction")
	assert_equal(continuation_data(surprise_snapshot)["randomBattleStage"], "surprise-choice", "the save aggregate owns random battle continuation state")
	var restored_surprise := GameSession.new()
	assert_equal(restored_surprise.restore(content, SaveEnvelope.from_data(save_data(surprise_snapshot))).state, SessionStep.State.COMPLETED, "random surprise save restores transactionally")
	var accepted := restored_surprise.respond(InteractionResponse.from_data(surprise_wait.interaction.request_id, &"yes_no", {"accepted": true}))
	assert_true(_has_event(accepted, &"random_encounter_triggered") and _event(accepted, &"random_encounter_triggered").payload["classicId"] == 1, "accepting the surprise choice starts battle one through Castle's inverted-range selection")
	assert_equal(_event(accepted, &"battle_started").payload["surprise"], 1, "accepted random surprise gives the party source-backed initiative"); assert_true(_sound_ids(accepted).has(10049), "battle entry requests Castle sound 10049 before tactical actions"); surprise_region.battle_maximum = 1
	var direct_combat_request := restored_surprise.view().combat_action_request
	assert_not_null(direct_combat_request, "a direct random battle projects the complete typed combat command surface")
	if direct_combat_request != null:
		assert_equal([direct_combat_request.kind, direct_combat_request.body.battle_id], [InteractionRequest.COMBAT, restored_surprise.view().combat_view.battle_id], "the direct command surface belongs to the active random battle")
	assert_equal(restored_surprise.view().party_members.size(), 6, "the direct combat fixture exposes all six visible party rows")
	var direct_auto_character := restored_surprise.view().party_members[5]
	var direct_auto_enabled := restored_surprise.submit_intent(PlayerIntent.set_combat_auto(direct_auto_character.id, true))
	assert_true(direct_auto_enabled.error_code == &"" and _has_event(direct_auto_enabled, &"combat_auto_changed"), "the sixth visible party row can enable persistent Auto during a direct non-VM battle")
	assert_true(restored_surprise.view().combat_view.auto_character_ids.has(direct_auto_character.id), "the direct combat view projects the sixth character's enabled Auto state")
	var direct_auto_disabled := restored_surprise.submit_intent(PlayerIntent.set_combat_auto(direct_auto_character.id, false))
	assert_true(direct_auto_disabled.error_code == &"" and _has_event(direct_auto_disabled, &"combat_auto_changed"), "the sixth visible party row can disable persistent Auto during a direct non-VM battle")
	assert_false(restored_surprise.view().combat_view.auto_character_ids.has(direct_auto_character.id), "the direct combat view removes the sixth character's disabled Auto state")
	var battle_coordinate := restored_surprise.view().party_coordinate
	var blocked_during_battle := restored_surprise.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_equal(blocked_during_battle.error_code, &"battle_in_progress", "active combat rejects exploration intents at the session boundary")
	assert_equal(restored_surprise.view().party_coordinate, battle_coordinate, "rejected combat-time movement cannot mutate topology state")
	var declined_surprise := GameSession.new()
	declined_surprise.restore(content, surprise_snapshot)
	var declined := declined_surprise.respond(InteractionResponse.from_data(surprise_wait.interaction.request_id, &"yes_no", {"accepted": false}))
	assert_equal(declined.state, SessionStep.State.COMPLETED, "declining an only-region surprise cleanly resumes exploration")
	assert_true(declined_surprise.view().combat_view == null, "declining the random encounter does not create combat state")
	assert_equal(declined_surprise.snapshot().continuation, null, "declining the only region clears its continuation")

	var door_session := GameSession.new()
	door_session.start(content, 1)
	_begin_fixture_adventure(door_session, content)
	door_session.submit_intent(PlayerIntent.move(Vector2i.DOWN))
	var first_door := door_session.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_true(_has_event(first_door, &"random_door_triggered"), "a positive random-door chance invokes its XAP through the normal VM")
	var door_region := content.world.map_by_id("land:0").random_region_by_id("land:0:randlevel:rect:2")
	assert_equal(door_session.snapshot().game_state.world.random_region(door_region).random_door_percents()[0], 0, "a positive random-door chance becomes one-shot world state")
	var restored_door := GameSession.new()
	restored_door.restore(content, door_session.snapshot())
	restored_door.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var second_door := restored_door.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_false(_has_event(second_door, &"random_door_triggered"), "save/reload preserves consumed random doors")

	var destination_envelope := session.snapshot()
	destination_envelope.game_state.party.map_id = "land:1"
	destination_envelope.game_state.party.coordinate = Vector2i(0, 1)
	var destination_session := GameSession.new()
	assert_equal(destination_session.restore(content, destination_envelope).state, SessionStep.State.COMPLETED, "validated restore establishes the AP destination fixture")
	var relocated := destination_session.submit_intent(PlayerIntent.move(Vector2i.UP))
	assert_equal(destination_session.view().party_coordinate, Vector2i(0, 0), "the initial movement commits before the source AP textbox is acknowledged")
	assert_equal(_message_ids(relocated), [5], "the source Action Point presents only its current positive message")
	var destination_text := destination_session.respond(InteractionResponse.from_data(relocated.interaction.request_id, &"acknowledge", {}))
	assert_equal(destination_session.view().party_coordinate, Vector2i(1, 0), "the Classic AP header relocates the party after its actions")
	assert_equal(_message_ids(destination_text), [6], "the destination cell Action Point is rechecked exactly once and presents separately")
	var destination_completed := destination_session.respond(InteractionResponse.from_data(destination_text.interaction.request_id, &"acknowledge", {}))
	assert_equal(destination_completed.state, SessionStep.State.COMPLETED, "the destination textbox acknowledgement completes the rechecked AP")
	assert_equal(_event_count(relocated, &"party_moved") + _event_count(destination_text, &"party_moved") + _event_count(destination_completed, &"party_moved"), 2, "the initial move and one AP relocation occur without recursive movement")

	var current_save_data := save_data(session.snapshot())
	for legacy_version in [1, 2, 3]:
		var legacy_data: Dictionary = current_save_data.duplicate(true)
		legacy_data["formatVersion"] = legacy_version
		assert_equal(SaveEnvelope.from_data(legacy_data), null, "save v%d is explicitly incompatible with save v4" % legacy_version)


func _has_event(step: SessionStep, event_kind: StringName) -> bool:
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			return true
	return false


func _event(step: SessionStep, event_kind: StringName) -> DomainEvent:
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			return event
	return null


func _event_count(step: SessionStep, event_kind: StringName) -> int:
	var count := 0
	for event: DomainEvent in step.events:
		if event.kind == event_kind:
			count += 1
	return count


func _message_ids(step: SessionStep) -> Array[int]:
	var ids: Array[int] = []
	for event: DomainEvent in step.events:
		if event.kind == &"message_shown":
			ids.append(int(event.payload.get("messageId", -1)))
	return ids


func _test_location_notes(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 17).state, SessionStep.State.COMPLETED, "a dedicated location-note session starts")
	_begin_fixture_adventure(session, content)
	var original_coordinate := session._state.party.coordinate
	var initial_view := session.view()
	assert_not_null(initial_view.current_location_note, "the detached view identifies the party's current mapped location")
	assert_equal(initial_view.current_location_note.text, "", "a location without a saved note exposes an empty editor value")
	assert_true(initial_view.location_notes.is_empty(), "a new adventure begins without player-authored location notes")
	assert_true(initial_view.availability(&"set_location_note").enabled, "the core exposes location-note editing at an ordinary exploration boundary")
	var rng_before := session.rng_trace().size()
	var clock_before := session._state.clock.total_minutes()
	var created := session.submit_intent(PlayerIntent.set_location_note("The road narrows beside the old stones."))
	assert_equal(created.state, SessionStep.State.COMPLETED, "saving a current-location note commits synchronously")
	assert_true(_has_event(created, &"location_note_updated"), "location-note creation publishes one explicit domain event")
	assert_equal(session.view().current_location_note.text, "The road narrows beside the old stones.", "the current-location view reflects the committed note")
	assert_equal(session.view().location_notes.size(), 1, "the detached journal list exposes the committed note")
	assert_equal([session.view().location_notes[0].record_ordinal, session.view().location_notes[0].level_type], [0, &"land"], "the first land note preserves Castle's separate source-record order")
	assert_equal([session.rng_trace().size(), session._state.clock.total_minutes()], [rng_before, clock_before], "editing a location note consumes no gameplay RNG or time")
	var unchanged := session.submit_intent(PlayerIntent.set_location_note("The road narrows beside the old stones."))
	assert_equal(unchanged.error_code, &"location_note_unchanged", "an unchanged note is rejected without a false committed revision")
	var dark_envelope := session.snapshot()
	dark_envelope.game_state.world.set_map_darkness("land:0", true)
	dark_envelope.game_state.party.conditions.set_value(0, 60)
	assert_equal(session.restore(content, dark_envelope).state, SessionStep.State.COMPLETED, "the fixture can establish a source-shaped dark land-note boundary")
	var darkness_refresh := session.submit_intent(PlayerIntent.set_location_note("The road narrows beside the old stones."))
	assert_equal(darkness_refresh.state, SessionStep.State.COMPLETED, "saving unchanged text may refresh Castle's saved darkness metadata")
	assert_equal([session.view().current_location_note.darkness_value, session.view().location_notes[0].preview_map.party_coordinate, session.view().location_notes[0].preview_map.dark, session.view().location_notes[0].preview_map.darkness_level, session.view().location_notes[0].preview_map.cells().size() <= 195, SessionViewProjectionPolicy.classic_darkness_level(0), SessionViewProjectionPolicy.classic_darkness_level(119), SessionViewProjectionPolicy.classic_darkness_level(999)], [3, original_coordinate, true, 3, true, 0, 4, 6], "a dark land note and live authored darkness retain Castle's clamped torch-derived level in a bounded detached preview recentered on the saved coordinate")
	var too_long := session.submit_intent(PlayerIntent.set_location_note("é".repeat(128)))
	assert_equal(too_long.error_code, &"location_note_too_long", "the core enforces Castle's 255-byte note field at the typed boundary")
	assert_equal(session.view().current_location_note.text, "The road narrows beside the old stones.", "an oversized note cannot replace committed text")
	var second_land_coordinate := original_coordinate + Vector2i(1, 0)
	assert_not_null(content.world.map_by_id("land:0").topology.cell_at(second_land_coordinate), "the fixture provides a second land-note cell")
	_restore_fixture_position(session, content, "land:0", second_land_coordinate)
	assert_equal(session.submit_intent(PlayerIntent.set_location_note("The lower road.")).state, SessionStep.State.COMPLETED, "a second land note commits at a different current location")
	assert_equal([session.view().location_notes[0].record_ordinal, session.view().location_notes[1].record_ordinal], [0, 1], "land notes browse in source-record order rather than coordinate order")
	_restore_fixture_position(session, content, "dungeon:0", Vector2i(1, 1))
	assert_equal(session.submit_intent(PlayerIntent.set_location_note("Dungeon entrance.")).state, SessionStep.State.COMPLETED, "a dungeon note commits into its independent record stream")
	assert_equal([session.view().location_notes.size(), session.view().location_notes[0].record_ordinal, session.view().location_notes[0].level_type], [1, 0, &"dungeon"], "the detached browser exposes only the current map-kind stream")
	_restore_fixture_position(session, content, "land:0", original_coordinate)
	var saved := SaveEnvelope.from_data(JSON.parse_string(JSON.stringify(save_data(session.snapshot()))))
	assert_not_null(saved, "location-note state survives canonical save-envelope serialization")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, saved).state, SessionStep.State.COMPLETED, "location-note state restores transactionally")
	assert_equal(restored.view().location_notes[0].text, "The road narrows beside the old stones.", "restored views retain the exact note text")
	assert_equal([restored.view().location_notes.size(), restored.view().location_notes[1].text], [2, "The lower road."], "restore retains separate stream order without exposing dungeon records on land")
	var cleared := restored.submit_intent(PlayerIntent.set_location_note(""))
	assert_true(_has_event(cleared, &"location_note_removed"), "saving empty text removes the current location note")
	assert_equal([restored.view().location_notes.size(), restored.view().location_notes[0].record_ordinal], [1, 1], "clearing a note frees its record without renumbering later source records")

	var capacity_seed := GameSession.new()
	assert_equal(capacity_seed.start(content, 18).state, SessionStep.State.COMPLETED, "a dedicated capacity session starts")
	_begin_fixture_adventure(capacity_seed, content)
	var capacity_envelope := capacity_seed.snapshot()
	var added: int = 0
	for y: int in 90:
		for x: int in 90:
			var coordinate := Vector2i(x, y)
			if coordinate == capacity_envelope.game_state.party.coordinate:
				continue
			capacity_envelope.game_state.world.upsert_location_note(LocationNoteState.new("land:0", &"land", 0, coordinate, "Note %d" % added, 0, added))
			added += 1
			if added == LocationNoteState.MAX_NOTES_PER_MAP_KIND:
				break
		if added == LocationNoteState.MAX_NOTES_PER_MAP_KIND:
			break
	var capacity_session := GameSession.new()
	assert_equal(capacity_session.restore(content, capacity_envelope).state, SessionStep.State.COMPLETED, "the corrected bounded Classic location-note file restores at exact capacity")
	var capacity_rejection := capacity_session.submit_intent(PlayerIntent.set_location_note("One note too many"))
	assert_equal(capacity_rejection.error_code, &"location_note_capacity", "a new note cannot reproduce Castle's append-beyond-scan record defect")
	var duplicate_ordinal := LocationNoteState.new("land:0", &"land", 0, capacity_envelope.game_state.party.coordinate, "Corrupt duplicate ordinal", 0, 0)
	capacity_envelope.game_state.world._location_notes[duplicate_ordinal.id()] = duplicate_ordinal
	var corrupt_capacity := GameSession.new()
	assert_equal(corrupt_capacity.restore(content, capacity_envelope).error_code, &"invalid_game_state", "restore rejects duplicate source ordinals transactionally")


func _test_classic_backout(source_content: RealmzContent) -> void:
	var content := _classic_backout_content(source_content); var session := GameSession.new(); assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "Classic Choice backout session starts"); _begin_fixture_adventure(session, content); var waiting := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_equal([waiting.state, waiting.interaction.kind, session.view().party_coordinate], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO, Vector2i(1, 0)], "entering the Choice AP commits its step before asking")
	var saved := save_round_trip(session.snapshot()); var restored := GameSession.new(); assert_equal(restored.restore(content, saved).state, SessionStep.State.COMPLETED, "pending Classic Choice restores with its post-move owner"); var minutes_before_backout := restored.snapshot().game_state.clock.total_minutes(); var rng_before_backout := restored.rng_trace().size(); var backed_out := restored.respond(InteractionResponse.yes_no(restored.view().pending_interaction, true)); assert_equal([backed_out.state, restored.view().party_coordinate], [SessionStep.State.COMPLETED, Vector2i.ZERO], "selected Choice mode zero reverses the just-entered overland step"); assert_true(_has_event(backed_out, &"classic_choice_backout_completed") and _event(backed_out, &"party_moved").payload.get("source") == "classic-choice-backout", "the public session identifies the source-backed backout movement"); assert_false(_has_event(backed_out, &"trigger_disabled") or _has_event(backed_out, &"random_encounter_checked"), "backout preserves the issuing AP and skips destination-cell random checks")
	assert_equal([restored.snapshot().game_state.clock.total_minutes(), restored.rng_trace().size()], [minutes_before_backout, rng_before_backout], "backout consumes neither additional time nor RNG"); assert_false(restored.snapshot().game_state.world.trigger_is_disabled("ap.choice-backout"), "backout leaves the Choice AP available for another entry"); var repeated := restored.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_equal([repeated.state, repeated.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO], "re-entering the preserved AP asks the same authored Choice")
	var continued := restored.respond(InteractionResponse.yes_no(repeated.interaction, false)); assert_equal([continued.state, restored.view().party_coordinate], [SessionStep.State.COMPLETED, Vector2i(2, 0)], "the unselected Choice branch continues and applies the AP header destination"); assert_true(_has_event(continued, &"action_point_kept") and _event(continued, &"party_moved").payload.get("source") == "action-point-destination", "the following authored slot executes before ordinary destination handling"); assert_false(restored.snapshot().game_state.world.trigger_is_disabled("ap.choice-backout"), "the following Keep Codes instruction remains authoritative")
	for encounter_kind: StringName in [&"simple", &"complex"]:
		var encounter_content := _classic_backout_content(source_content, encounter_kind); var encounter_session := GameSession.new(); assert_equal(encounter_session.start(encounter_content, 1).state, SessionStep.State.COMPLETED, "%s Encounter backout session starts" % encounter_kind); _begin_fixture_adventure(encounter_session, encounter_content); var encounter_waiting := encounter_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); var encounter_saved := save_round_trip(encounter_session.snapshot()); var encounter_restored := GameSession.new(); assert_equal(encounter_restored.restore(encounter_content, encounter_saved).state, SessionStep.State.COMPLETED, "pending %s Encounter restores with its post-move owner" % encounter_kind)
		var response_data: Dictionary = {"cancelled": true} if encounter_kind == &"simple" else {"action": "back"}; var encounter_backout := encounter_restored.respond(InteractionResponse.from_data(encounter_restored.view().pending_interaction.request_id, encounter_waiting.interaction.kind, response_data)); assert_equal([encounter_backout.state, encounter_restored.view().party_coordinate, _has_event(encounter_backout, &"classic_encounter_backout_completed"), encounter_restored.snapshot().game_state.world.trigger_is_disabled("ap.%s-backout" % encounter_kind)], [SessionStep.State.COMPLETED, Vector2i.ZERO, true, false], "Castle-authored %s Encounter cancellation reverses the entered land step and preserves its AP" % encounter_kind); var encounter_repeated := encounter_restored.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_equal([encounter_repeated.state, encounter_repeated.interaction.kind], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.ENCOUNTER_CHOICE if encounter_kind == &"simple" else InteractionRequest.WORD_AND_ACTION], "re-entering the preserved %s Encounter AP asks again" % encounter_kind)


func _test_contextual_encounter_command(source_content: RealmzContent) -> void:
	var region_id := "contextual.fixture.region"
	var empty_ids: Array[String] = []; var random_regions: Array[String] = [region_id]
	var empty_edges := {
		&"north": MapEdge.new(&"open", true, false),
		&"east": MapEdge.new(&"open", true, false),
		&"south": MapEdge.new(&"open", true, false),
		&"west": MapEdge.new(&"open", true, false),
	}
	var empty_features: Array[MapFeature] = []
	var origin := MapCell.new("contextual:cell:0,0", Vector2i.ZERO, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", empty_ids, empty_ids, empty_edges, empty_features)
	var faced := MapCell.new("contextual:cell:1,0", Vector2i.RIGHT, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", empty_ids, random_regions, empty_edges, empty_features)
	var region := RandomEncounterRegion.new(region_id, Rect2i(Vector2i.RIGHT, Vector2i.ONE), -1, 0, 0, [42, 0, 0], [100, 0, 0], false, 0, 0, 0)
	var regions: Array[RandomEncounterRegion] = [region]
	var map := MapDefinition.new("contextual", "Land level 0", &"land", 0, MapTopology.new(2, 1, [origin, faced]), false, false, -1, regions, "fixture.tileset")
	var maps: Array[MapDefinition] = [map]
	var programs: Array[ScenarioProgramDefinition] = [ScenarioProgramDefinition.new("xap:42", &"extra-action-point", region_id, []), ScenarioProgramDefinition.new("xap:0", &"extra-action-point", "0", [])]
	var content := RealmzContent.new("contextual-command", source_content.package_hash, "contextual-command-content", source_content.rules_version, map.id, Vector2i.ZERO, WorldDefinition.new(maps), ScenarioDefinition.new(programs, []), [], [], [], source_content.race_definitions(), source_content.caste_definitions())
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "the seamless Encounter command fixture starts")
	_begin_fixture_adventure(session, content); var facing := session.snapshot(); facing.game_state.last_move_direction = Vector2i.RIGHT; assert_equal(session.restore(content, facing).state, SessionStep.State.COMPLETED, "the fixture faces the neighboring land cell through the save boundary")
	assert_true(session.view().availability(&"contextual_encounter").enabled, "the core exposes Encounter throughout ordinary exploration")
	session._rng = ScriptedRng.new([0])
	var opened := session.submit_intent(PlayerIntent.contextual_encounter())
	assert_equal(opened.state, SessionStep.State.COMPLETED, "Encounter resolves its selected seamless XAP through the ordinary VM boundary")
	assert_equal([_event(opened, &"contextual_encounter_triggered").payload["programId"], _event(opened, &"contextual_encounter_triggered").payload["coordinate"]], ["xap:42", Vector2i.RIGHT], "land Encounter scans the faced cell and publishes the selected random-door program")
	assert_equal(session.rng_trace()[0]["tag"], "contextual-encounter.contextual.fixture.region.door.0", "Encounter records the source-ordered door roll")
	assert_equal(session.snapshot().game_state.world.random_region(region).random_door_percents()[0], 0, "a positive seamless door chance is consumed after it opens")
	var restored := GameSession.new(); assert_equal(restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "the consumed seamless Encounter door restores transactionally")
	assert_true(restored.view().availability(&"contextual_encounter").enabled, "a consumed seamless door does not disable Castle's persistent Encounter control"); var fallback := restored.submit_intent(PlayerIntent.contextual_encounter()); var fallback_event := _event(fallback, &"contextual_encounter_triggered")
	assert_equal([fallback.state, fallback_event.payload["programId"], fallback_event.payload["coordinate"], fallback_event.payload["defaultProgram"]], [SessionStep.State.COMPLETED, "xap:0", Vector2i.RIGHT, true], "Encounter runs XAP 0 at the faced land coordinate when no seamless door fires")
	for repeat_index: int in 8:
		var repeated := restored.submit_intent(PlayerIntent.contextual_encounter())
		assert_equal([repeated.state, repeated.error_code, _event(repeated, &"contextual_encounter_triggered").payload["programId"]], [SessionStep.State.COMPLETED, &"", "xap:0"], "repeated Explore Encounter activation %d retains its typed coordinator result" % (repeat_index + 1))


func _test_map_view_projection_edges(content: RealmzContent) -> void:
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "the edge-projection session starts")
	_begin_fixture_adventure(session, content)
	assert_equal(session.view().map_view.cells().size(), 625, "the detached projection keeps its full dimensions at the north-west map edge")
	assert_not_null(session.view().map_view.cell_at(Vector2i.ZERO), "the north-west projection begins at the map edge")
	assert_not_null(session.view().map_view.cell_at(Vector2i(24, 24)), "the north-west projection shifts inward instead of shrinking around the party"); var winter_snapshot := session.snapshot(); winter_snapshot.game_state.world.set_map_landlook("land:0", 10); var winter_session := GameSession.new(); assert_equal(winter_session.restore(content, winter_snapshot).state, SessionStep.State.COMPLETED, "a save-owned seasonal landlook restores through the public session boundary"); assert_equal([winter_session.view().map_view.landlook, winter_session.view().map_view.cell_at(Vector2i.ZERO).tileset_id, winter_session.view().map_view.cell_at(Vector2i.ZERO).render_tile], [10, "landlook-10", content.world.map_by_id("land:0").topology.cell_at(Vector2i.ZERO).render_tile], "seasonal projection changes every land cell to the effective Snow atlas without changing its authored tile number")
	_restore_fixture_position(session, content, "land:0", Vector2i(88, 1))
	assert_equal(session.view().map_view.cells().size(), 625, "the detached projection keeps its full dimensions at the east map edge")
	assert_not_null(session.view().map_view.cell_at(Vector2i(65, 0)), "the east-edge projection shifts west to retain the complete viewport")
	assert_not_null(session.view().map_view.cell_at(Vector2i(89, 24)), "the east-edge projection still reaches the authoritative map boundary"); assert_true(session.view().map_view.cell_at(Vector2i(64, 0)) == null, "the shifted east-edge projection remains bounded to twenty-five columns")
	var before_projection := session.snapshot()
	var projection_state := [JSON.stringify(before_projection.game_state.to_data()), JSON.stringify(before_projection.rng_state.to_data()), JSON.stringify(before_projection.scenario_vm.to_data()), JSON.stringify(before_projection.scenario_action_state.to_data())]
	assert_true(session.set_map_projection_size(Vector2i(55, 18)), "the detached presentation projection accepts the current rendered cell span without mutating gameplay")
	var expanded_view := session.view()
	assert_equal(expanded_view.map_view.cells().size(), 990, "a maximized 55-by-18 map stage receives one matching detached projection")
	assert_not_null(expanded_view.map_view.cell_at(Vector2i(35, 0)), "the expanded east-edge projection begins at the same camera column as the maximized presenter")
	assert_not_null(expanded_view.map_view.cell_at(Vector2i(89, 17)), "the expanded projection reaches the authoritative east edge and complete visible height")
	assert_true(expanded_view.map_view.cell_at(Vector2i(34, 0)) == null and not session.set_map_projection_size(Vector2i(55, 18)), "the projection remains exactly viewport-sized and an unchanged layout does not invalidate it again")
	var after_projection := session.snapshot()
	var resized_state := [JSON.stringify(after_projection.game_state.to_data()), JSON.stringify(after_projection.rng_state.to_data()), JSON.stringify(after_projection.scenario_vm.to_data()), JSON.stringify(after_projection.scenario_action_state.to_data())]
	assert_equal([expanded_view.revision, resized_state], [before_projection.view_revision, projection_state], "responsive projection sizing changes neither the committed revision nor any save-owned state")
	var controller := GameSessionController.new()
	assert_true(controller.set_map_projection_size(Vector2i(55, 18)) and controller.start(content, 2).state == SessionStep.State.COMPLETED, "the host retains its layout projection request while replacing the session")
	assert_equal(controller.view().map_view.cells().size(), 990, "a replacement session is first projected at the retained host viewport size")
	controller.free()


func _test_field_heal(content: RealmzContent) -> void:
	var session := GameSession.new(); assert_equal(session.start(content, 9).state, SessionStep.State.COMPLETED, "the public Heal session starts")
	_begin_fixture_adventure(session, content, 2); var members := session._state.party.characters()
	var healer := members[0]; healer.spellcaster_type = 1; healer.spell_points = 25; healer.maximum_spell_points = 25; healer.set_known_spells(["classic.spell.1506"])
	var wounded := members[1]; wounded.current_health = 1; var before_minutes := session.snapshot().game_state.clock.total_minutes()
	var healed := session.submit_intent(PlayerIntent.heal()); assert_true(_has_event(healed, &"health_recovered") and _has_event(healed, &"spell_points_spent"), "Heal publishes its source-ordered recovery and spell-point events")
	assert_equal([session._state.clock.total_minutes() - before_minutes, healer.spell_points, wounded.current_health > 1, wounded.current_health <= wounded.maximum_health], [5, 15, true, true], "one land Heal pulse spends five minutes and ten spell points for its eligible wounded recipient")
	var restored := GameSession.new(); assert_equal(restored.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "Heal state restores through the public save boundary")
	assert_equal([restored._state.party.character_by_id(healer.id).spell_points, restored._state.party.character_by_id(wounded.id).current_health], [healer.spell_points, wounded.current_health], "Heal spell points and stamina persist together")
	var blocked_before := JSON.stringify(session._state.to_data())
	session._state.character_spellcasting_blocked = true
	blocked_before = JSON.stringify(session._state.to_data())
	var blocked_rng_before := session.rng_trace().size()
	var blocked := session.submit_intent(PlayerIntent.heal())
	var warning := _event(blocked, &"classic_notification_requested")
	assert_true(warning != null and warning.payload.get("text") == "Your characters can't cast spells in this area." and warning.payload.get("soundId") == 6000, "blocked field Heal requests Castle warning 113 as its compact sounded notification")
	assert_equal([JSON.stringify(session._state.to_data()), session.rng_trace().size()], [blocked_before, blocked_rng_before], "blocked field Heal changes no health, spell points, clock, fatigue, RNG-owned state, or scenario state")


func _test_terrain_replacement_topology(content: RealmzContent) -> void:
	var map := content.world.map_by_id("land:0")
	var terrain_set := content.world.battle_terrain_set_for_map(map, null)
	var coordinate := Vector2i(4, 4)
	var source_cell := map.topology.cell_at(coordinate)
	var world_state := WorldState.new()
	world_state.replace_terrain(map.id, coordinate, "classic.terrain.200")
	var closed_cell := map.topology.effective_cell_at(coordinate, world_state)
	var closed_definition := terrain_set.tile_by_id(200)
	assert_equal(
		[closed_cell.passable, closed_cell.blocks_los, closed_cell.movement_cost, closed_cell.movement_sound_id, closed_cell.render_tile],
		[closed_definition.solid == 0, closed_definition.blocks_los, closed_definition.movement_time, closed_definition.sound, 200],
		"an ordinary terrain replacement projects the active landlook's complete movement and LOS facts",
	)
	assert_false(map.topology.probe_land_entry(coordinate, world_state).allowed, "a replacement with solid mapstats blocks the authoritative exploration probe")
	world_state.replace_terrain(map.id, coordinate, "classic.terrain.1")
	var opened_cell := map.topology.effective_cell_at(coordinate, world_state)
	var open_definition := terrain_set.tile_by_id(1)
	assert_equal(
		[opened_cell.passable, opened_cell.blocks_los, opened_cell.movement_cost, opened_cell.movement_sound_id, opened_cell.render_tile, source_cell.id],
		[true, open_definition.blocks_los, open_definition.movement_time, open_definition.sound, 1, opened_cell.id],
		"replacing that same coordinate with open terrain retains cell identity while changing every topology consumer's effective facts",
	)
	assert_true(map.topology.probe_land_entry(coordinate, world_state).allowed, "an opened replacement immediately becomes traversable without rebuilding immutable map content")


func _test_special_dungeon_bits(source_content: RealmzContent) -> void:
	var cases: Array[Dictionary] = [
		{"id": "solid-wall", "cellPassable": false, "edgeKind": &"wall", "edgePassable": false, "allowed": false},
		{"id": "door", "cellPassable": true, "edgeKind": &"door", "edgePassable": true, "doorId": "dungeon-special:door", "allowed": true, "event": &"door_opened"},
		{"id": "note-marker", "cellPassable": true, "edgeKind": &"open", "edgePassable": true, "allowed": true},
		{"id": "action-point-marker", "cellPassable": true, "edgeKind": &"open", "edgePassable": true, "allowed": true},
		{"id": "matching-secret", "cellPassable": true, "edgeKind": &"secret", "edgePassable": true, "secretId": "dungeon-special:secret:east", "secretOrientation": &"east", "allowed": true, "event": &"secret_discovered"},
		{"id": "nonmatching-secret", "cellPassable": true, "edgeKind": &"wall", "edgePassable": false, "secretId": "dungeon-special:secret:north", "secretOrientation": &"north", "allowed": false},
		{"id": "visible-arch", "cellPassable": false, "edgeKind": &"archway", "edgePassable": false, "allowed": false},
	]
	var baseline_content := _dungeon_special_content(source_content, cases[0])
	var baseline := GameSession.new()
	assert_equal(baseline.start(baseline_content, 31).state, SessionStep.State.COMPLETED, "the special dungeon-bit table starts from one public session boundary")
	_begin_fixture_adventure(baseline, baseline_content)
	var baseline_save := baseline.snapshot()
	for dungeon_case: Dictionary in cases:
		var content := _dungeon_special_content(source_content, dungeon_case)
		var session := GameSession.new()
		assert_equal(session.restore(content, baseline_save).state, SessionStep.State.COMPLETED, "%s topology restores through the shared public fixture" % dungeon_case["id"])
		var start_minutes := session.snapshot().game_state.clock.total_minutes()
		var moved := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
		var allowed: bool = dungeon_case["allowed"]
		assert_equal([session.view().party_coordinate, session.snapshot().game_state.clock.total_minutes() - start_minutes], [Vector2i(1, 0) if allowed else Vector2i.ZERO, 1 if allowed else 0], "%s preserves Castle movement and time semantics" % dungeon_case["id"])
		var expected_event: StringName = dungeon_case.get("event", &"")
		if not expected_event.is_empty():
			assert_true(_has_event(moved, expected_event), "%s publishes its topology-owned discovery event" % dungeon_case["id"])


func _begin_fixture_adventure(session: GameSession, content: RealmzContent, party_size: int = 1) -> void:
	var races := content.race_definitions()
	var castes := content.caste_definitions()
	assert_false(races.is_empty() or castes.is_empty(), "playable exploration fixture provides one race and caste")
	if races.is_empty() or castes.is_empty():
		return
	for character_index: int in range(clampi(party_size, 1, 6)):
		var character_id := "fixture.party.member" if party_size == 1 else "fixture.party.member.%d" % (character_index + 1)
		var character := CharacterState.new(character_id, "Fixture Hero %d" % (character_index + 1), 10, 10)
		character.race_id = races[0].id
		character.caste_id = castes[0].id
		assert_equal(session.submit_intent(PlayerIntent.import_vault_character(character.id, "1".repeat(64), character, "fixture", content.package_hash)).state, SessionStep.State.COMPLETED, "fixture party import does not consume gameplay RNG")
	var started := session.submit_intent(PlayerIntent.begin_adventure())
	if content.scenario.application_hook_program_id(ScenarioApplicationHooks.START_GAME).is_empty():
		assert_equal(started.state, SessionStep.State.COMPLETED, "exploration content without a Start Game hook leaves party setup synchronously")
	else:
		assert_equal(started.state, SessionStep.State.WAITING_FOR_INTERACTION, "exploration fixture reaches the Start Game hook after party setup")
		assert_equal(session.respond(InteractionResponse.acknowledge(started.interaction)).state, SessionStep.State.COMPLETED, "exploration fixture explicitly leaves party setup")


func _restore_fixture_position(session: GameSession, content: RealmzContent, map_id: String, coordinate: Vector2i) -> void:
	var envelope := session.snapshot()
	envelope.game_state.party.map_id = map_id
	envelope.game_state.party.coordinate = coordinate
	assert_equal(session.restore(content, envelope).state, SessionStep.State.COMPLETED, "fixture position changes through the validated save boundary")


func _test_boat_movement(source_content: RealmzContent) -> void:
	var content := _boat_movement_content(source_content)
	var session := GameSession.new()
	assert_equal(session.start(content, 1).state, SessionStep.State.COMPLETED, "boat workflow session starts")
	_begin_fixture_adventure(session, content)
	var initial_minutes := session.snapshot().game_state.clock.total_minutes()
	var board_prompt := session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_not_null(board_prompt.interaction, "boardable movement yields an interaction (state %s, error %s: %s)" % [board_prompt.state, board_prompt.error_code, board_prompt.error_message])
	if board_prompt.interaction == null:
		return
	assert_equal([board_prompt.state, board_prompt.interaction.kind, session.view().party_coordinate], [SessionStep.State.WAITING_FOR_INTERACTION, InteractionRequest.YES_NO, Vector2i.ZERO], "a boardable Classic tile asks before moving the party")
	assert_equal([board_prompt.interaction.body.prompt, board_prompt.interaction.body.yes_label, board_prompt.interaction.body.no_label], ["Board this boat?", "Board", "Stay ashore"], "the board prompt uses one typed yes/no interaction")
	var restored_board := GameSession.new()
	assert_equal(restored_board.restore(content, save_round_trip(session.snapshot())).state, SessionStep.State.COMPLETED, "the board prompt restores with its typed continuation")
	var boarded := restored_board.respond(InteractionResponse.yes_no(restored_board.view().pending_interaction, true))
	assert_equal([boarded.state, restored_board.view().party_coordinate, restored_board.snapshot().game_state.party_in_boat, restored_board.view().party_summary.in_boat], [SessionStep.State.COMPLETED, Vector2i(1, 0), true, true], "accepting boards once and detaches the active boat marker fact")
	assert_equal(restored_board.snapshot().game_state.clock.total_minutes(), initial_minutes + 20, "boarding pays the original boat tile's four outdoor timeclicks")
	assert_equal(_sound_ids(boarded), [11], "boarding uses the original boat tile sound before its replacement profile")
	assert_equal([restored_board.view().map_view.cell_at(Vector2i(1, 0)).render_tile, restored_board.view().map_view.cell_at(Vector2i(1, 0)).terrain_id], [60, "classic.terrain.60"], "boarding exposes Castle's tile-60 replacement through the authoritative view")
	var crossed_water := restored_board.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal([crossed_water.state, restored_board.view().party_coordinate, _sound_ids(crossed_water)], [SessionStep.State.COMPLETED, Vector2i(2, 0), [22]], "an embarked party traverses exact needBoat-2 water")
	for attempt: int in 2:
		var shore_block := restored_board.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
		assert_equal([shore_block.state, restored_board.view().party_coordinate, _sound_ids(shore_block)], [SessionStep.State.COMPLETED, Vector2i(2, 0), [-148, 44]], "shore attempt %d collides, sounds, and remains aboard" % (attempt + 1))
	var restored_attempts := GameSession.new()
	assert_equal(restored_attempts.restore(content, save_round_trip(restored_board.snapshot())).state, SessionStep.State.COMPLETED, "the bounded shore retry count restores deterministically")
	var leave_prompt := restored_attempts.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal([leave_prompt.state, _sound_ids(leave_prompt), leave_prompt.interaction.body.prompt], [SessionStep.State.WAITING_FOR_INTERACTION, [-148], "Leave the boat here and go ashore?"], "the third shore collision opens Castle's disembark question after its collision sound")
	var restored_leave := GameSession.new()
	assert_equal(restored_leave.restore(content, save_round_trip(restored_attempts.snapshot())).state, SessionStep.State.COMPLETED, "the disembark prompt restores without losing its source cell")
	var disembarked := restored_leave.respond(InteractionResponse.yes_no(restored_leave.view().pending_interaction, true))
	assert_equal([disembarked.state, restored_leave.view().party_coordinate, restored_leave.snapshot().game_state.party_in_boat, restored_leave.view().party_summary.in_boat, _sound_ids(disembarked)], [SessionStep.State.COMPLETED, Vector2i(2, 0), false, false, [44]], "accepting leaves the boat at the current water cell, clears its marker fact, and applies the attempted shore facts")
	assert_equal([restored_leave.view().map_view.cell_at(Vector2i(2, 0)).render_tile, restored_leave.view().map_view.cell_at(Vector2i(2, 0)).terrain_id], [147, "classic.terrain.147"], "disembarking exposes Castle's tile-147 replacement through the same topology view")
	var stepped_ashore := restored_leave.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	assert_equal([stepped_ashore.state, restored_leave.view().party_coordinate], [SessionStep.State.COMPLETED, Vector2i(3, 0)], "after disembarking the party may enter the shore normally")
	var declined_session := GameSession.new()
	declined_session.start(content, 1)
	_begin_fixture_adventure(declined_session, content)
	var declined_prompt := declined_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT))
	var declined := declined_session.respond(InteractionResponse.yes_no(declined_prompt.interaction, false))
	assert_equal([declined.state, declined_session.view().party_coordinate, declined_session.snapshot().game_state.party_in_boat, _sound_ids(declined)], [SessionStep.State.COMPLETED, Vector2i.ZERO, false, [11]], "declining a boat retains the party and still applies Castle's target sound/time")
	var ap_content := _boat_action_point_content(source_content); var ap_session := GameSession.new(); assert_equal(ap_session.start(ap_content, 1).state, SessionStep.State.COMPLETED, "boat action-point fixture starts"); _begin_fixture_adventure(ap_session, ap_content); var aboard_envelope := ap_session.snapshot(); aboard_envelope.game_state.party_in_boat = true; assert_equal(ap_session.restore(ap_content, aboard_envelope).state, SessionStep.State.COMPLETED, "the source-shaped fixture restores aboard its water origin")
	var entered_ap := ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_equal([entered_ap.state, ap_session.view().party_coordinate, _has_event(entered_ap, &"trigger_fired")], [SessionStep.State.COMPLETED, Vector2i(1, 0), true], "an embarked party enters a placed land action point through Castle's door-band branch")
	var ordinary_land_block := ap_session.submit_intent(PlayerIntent.move(Vector2i.RIGHT)); assert_equal([ordinary_land_block.state, ap_session.view().party_coordinate, _sound_ids(ordinary_land_block)], [SessionStep.State.COMPLETED, Vector2i(1, 0), [-148, 11]], "the action-point exception does not let an embarked party traverse ordinary needBoat-0 terrain")


func _boat_movement_content(source_content: RealmzContent) -> RealmzContent:
	var rows: Array = [
		_compact_land_row(1, 1, 1, 0, false),
		_compact_land_row(10, 4, 11, 1, false),
		_compact_land_row(60, 2, 22, 2, false),
		_compact_land_row(30, 5, 44, 0, true),
	]
	var removed := LandTileProfile.new("classic.terrain.60", 2, 77, 22, 60, 2, 2)
	var placed := LandTileProfile.new("classic.terrain.147", 3, 69, 33, 147, 1, 3)
	var map := MapDefinition.new("boat-land", "Boat Land", &"land", 0, MapTopology.from_compact_rows("boat-land", 4, 1, rows, removed, placed))
	var maps: Array[MapDefinition] = [map]
	return RealmzContent.new("boat-movement", "0".repeat(64), "boat-movement-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new(maps), ScenarioDefinition.new([], []), [], [], [], source_content.race_definitions(), source_content.caste_definitions())


func _boat_action_point_content(source_content: RealmzContent) -> RealmzContent:
	var rows: Array = [
		_compact_land_row(60, 2, 22, 2, false),
		_compact_land_row(60, 7, 88, 0, false),
		_compact_land_row(1, 1, 11, 0, false),
	]
	var trigger_id := "Data DD:1:6"
	rows[1][4] = [trigger_id]
	rows[1][7] = [["boat-action-point", "action-point", "active", null]]
	var map := MapDefinition.new("boat-action-point", "Boat Action Point", &"land", 1, MapTopology.from_compact_rows("boat-action-point", 3, 1, rows))
	var program := ScenarioProgramDefinition.new("program.boat-action-point", &"trigger", trigger_id, [])
	var trigger := TriggerDefinition.new(trigger_id, program.id, map.id, Vector2i(1, 0), true, 100, null, 6)
	return RealmzContent.new("boat-action-point", "0".repeat(64), "boat-action-point-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new([map]), ScenarioDefinition.new([program], []), [], [trigger], [], source_content.race_definitions(), source_content.caste_definitions())


func _compact_land_row(tile: int, movement_cost: int, sound_id: int, boat_requirement: int, shore: bool) -> Array:
	var flags := 1 | 4
	if boat_requirement == 2:
		flags |= 8
	if shore:
		flags |= 16
	if boat_requirement != 0:
		flags |= 64
	var edge := ["open", 5, null, null]
	return ["classic.terrain.%d" % tile, movement_cost, flags, sound_id, [], [], [edge, edge, edge, edge], [], tile, "fixture.tileset", null, boat_requirement, movement_cost]


func _sound_ids(step: SessionStep) -> Array[int]:
	var result: Array[int] = []
	for event: DomainEvent in step.events:
		if event.kind == &"sound_requested":
			result.append(int(event.payload["soundId"]))
	return result


func _duplicate_placed_ap_content(first_chance: int, source_content: RealmzContent) -> RealmzContent:
	var empty_features: Array[MapFeature] = []; var empty_ids: Array[String] = []; var origin_triggers: Array[String] = []; var target_triggers: Array[String] = ["ap.later-native", "ap.first-native"]
	var cells: Array[MapCell] = [MapCell.new("ap-order:cell:0,0", Vector2i.ZERO, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", origin_triggers, empty_ids, {}, empty_features), MapCell.new("ap-order:cell:1,0", Vector2i(1, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", target_triggers, empty_ids, {}, empty_features)]
	var map := MapDefinition.new("ap-order", "Placed AP Order", &"land", 0, MapTopology.new(2, 1, cells)); var maps: Array[MapDefinition] = [map]
	var first := TriggerDefinition.new("ap.first-native", "program.first-native", map.id, Vector2i(1, 0), true, first_chance, null, 2); var later := TriggerDefinition.new("ap.later-native", "program.later-native", map.id, Vector2i(1, 0), true, 100, null, 9); var triggers: Array[TriggerDefinition] = [later, first]
	var programs: Array[ScenarioProgramDefinition] = [
		ScenarioProgramDefinition.new(first.program_id, &"trigger", first.id, []),
		ScenarioProgramDefinition.new(later.program_id, &"trigger", later.id, []),
	]
	return RealmzContent.new("ap-order", "0".repeat(64), "ap-order-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new(maps), ScenarioDefinition.new(programs, []), [], triggers, [], source_content.race_definitions(), source_content.caste_definitions())


func _inactive_placed_ap_content(source_content: RealmzContent) -> RealmzContent:
	var empty_ids: Array[String] = []; var empty_features: Array[MapFeature] = []
	var cells: Array[MapCell] = [MapCell.new("inactive-ap:cell:0,0", Vector2i.ZERO, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", empty_ids, empty_ids, {}, empty_features), MapCell.new("inactive-ap:cell:1,0", Vector2i(1, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", ["ap.enable-inactive"], empty_ids, {}, empty_features), MapCell.new("inactive-ap:cell:2,0", Vector2i(2, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", ["ap.inactive-placed"], empty_ids, {}, empty_features)]
	var map := MapDefinition.new("inactive-ap", "Inactive AP", &"land", 0, MapTopology.new(3, 1, cells)); var enable := TriggerDefinition.new("ap.enable-inactive", "program.enable-inactive", map.id, Vector2i(1, 0), true, 100, null, 1); var inactive := TriggerDefinition.new("ap.inactive-placed", "program.inactive-placed", map.id, Vector2i(2, 0), false, 0, null, 57)
	var programs: Array[ScenarioProgramDefinition] = [ScenarioProgramDefinition.new(enable.program_id, &"trigger", enable.id, [ClassicActionDefinition.new(0, 13, 13, 0, false, [0, 57, 100, 59, 59])]), ScenarioProgramDefinition.new(inactive.program_id, &"trigger", inactive.id, [])]
	return RealmzContent.new("inactive-ap", "0".repeat(64), "inactive-ap-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new([map]), ScenarioDefinition.new(programs, []), [], [enable, inactive], [], source_content.race_definitions(), source_content.caste_definitions())


func _classic_backout_content(source_content: RealmzContent, encounter_kind: StringName = &"choice") -> RealmzContent:
	var empty_ids: Array[String] = []; var empty_features: Array[MapFeature] = []; var open_edges := {&"north": MapEdge.new(&"open", true, false), &"east": MapEdge.new(&"open", true, false), &"south": MapEdge.new(&"open", true, false), &"west": MapEdge.new(&"open", true, false)}; var trigger_id := "ap.%s-backout" % encounter_kind; var cells: Array[MapCell] = [MapCell.new("backout:cell:0,0", Vector2i.ZERO, "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", empty_ids, empty_ids, open_edges, empty_features), MapCell.new("backout:cell:1,0", Vector2i(1, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", [trigger_id], empty_ids, open_edges, empty_features), MapCell.new("backout:cell:2,0", Vector2i(2, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", empty_ids, empty_ids, open_edges, empty_features)]
	var opcode := 3 if encounter_kind == &"choice" else 4 if encounter_kind == &"simple" else 5; var extra_code: Array[int] = [0, 0, 0, 0, 0]; var actions: Array[Variant] = [ClassicActionDefinition.new(0, opcode, opcode, 0, false, extra_code), ClassicActionDefinition.new(1, 24, 24, 0, false, [])] if encounter_kind == &"choice" else [ClassicActionDefinition.new(0, opcode, opcode, 0, false, extra_code)]; var messages: Array[MessageDefinition] = [MessageDefinition.new(1, "Back out?")]; var simple: Array[SimpleEncounterDefinition] = [SimpleEncounterDefinition.new(0, 1, [SimpleEncounterResponse.new("continue", "Continue", "unused")], true, 1, 0)]; var complex: Array[ComplexEncounterDefinition] = [ComplexEncounterDefinition.new(0, 1, 4, 0, [1, 0, 0, 0, 0, 0, 0, 0], [], [], [], [], true, false, 1, 0, 0, 0, ["Try", "", "", "", "", "", "", "", ""])]
	var map := MapDefinition.new("backout", "Classic Backout", &"land", 0, MapTopology.new(3, 1, cells)); var program := ScenarioProgramDefinition.new("program.%s-backout" % encounter_kind, &"trigger", trigger_id, actions); var destination := TriggerDestinationDefinition.new(map.id, Vector2i(2, 0)); var trigger := TriggerDefinition.new(trigger_id, program.id, map.id, Vector2i(1, 0), true, 100, destination, 0)
	return RealmzContent.new("classic-backout", "0".repeat(64), "classic-backout-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new([map]), ScenarioDefinition.new([program], []), messages, [trigger], simple, source_content.race_definitions(), source_content.caste_definitions(), [], [], [], [], [], [], complex)


func _open_movement_content(source_content: RealmzContent, uses_los: bool = false) -> RealmzContent:
	var cells: Array[MapCell] = []
	var empty_ids: Array[String] = []
	var empty_features: Array[MapFeature] = []
	var open_edges := {
		&"north": MapEdge.new(&"open", true, false),
		&"east": MapEdge.new(&"open", true, false),
		&"south": MapEdge.new(&"open", true, false),
		&"west": MapEdge.new(&"open", true, false),
	}
	for y: int in 3:
		for x: int in 3:
			var coordinate := Vector2i(x, y)
			cells.append(MapCell.new("open:cell:%d,%d" % [x, y], coordinate, "classic.terrain.1", true, 1, false, true, false, false, true, false, false, 151, 1, "fixture.tileset", empty_ids, empty_ids, open_edges, empty_features))
	var map := MapDefinition.new("open", "Open movement", &"land", 0, MapTopology.new(3, 3, cells), false, uses_los)
	var maps: Array[MapDefinition] = [map]
	return RealmzContent.new("open-movement", "0".repeat(64), "open-movement-content", "realmz-classic-1", map.id, Vector2i(1, 1), WorldDefinition.new(maps), ScenarioDefinition.new([], []), [], [], [], source_content.race_definitions(), source_content.caste_definitions())


func _test_attempted_land_move_search(source_content: RealmzContent) -> void:
	var content := _attempted_land_move_content(source_content)
	var ordinary := GameSession.new(); ordinary.start(content, 1); _begin_fixture_adventure(ordinary, content); var rng_before := ordinary.rng_trace().size(); var ordinary_attempt := ordinary.submit_intent(PlayerIntent.move(Vector2i.LEFT)); var ordinary_search := _event(ordinary_attempt, &"movement_secret_search_completed")
	assert_true(ordinary_attempt.state == SessionStep.State.COMPLETED and ordinary.view().party_coordinate == Vector2i(1, 0) and _has_event(ordinary_attempt, &"movement_blocked") and ordinary_search != null and ordinary.rng_trace().size() == rng_before + 1, "a blocked valid land move remains in place but still performs Castle's ordinary deterministic secret check")
	assert_false(ordinary.view().map_view.cell_at(Vector2i.ZERO).has_feature(&"secret"), "an unsuccessful ordinary check leaves the hidden land secret concealed")
	var searching := GameSession.new(); searching.start(content, 1); _begin_fixture_adventure(searching, content); assert_equal(searching.submit_intent(PlayerIntent.toggle_search()).state, SessionStep.State.COMPLETED, "the blocked-attempt fixture enables persistent Search mode"); var minutes_before := searching.snapshot().game_state.clock.total_minutes(); var searched_attempt := searching.submit_intent(PlayerIntent.move(Vector2i.LEFT))
	assert_true(searched_attempt.state == SessionStep.State.COMPLETED and searching.view().party_coordinate == Vector2i(1, 0) and _has_event(searched_attempt, &"movement_blocked") and _has_event(searched_attempt, &"secret_discovered") and searching.view().map_view.cell_at(Vector2i.ZERO).has_feature(&"secret"), "Search mode makes the same blocked land attempt reveal the adjacent secret without admitting the party through the wall")
	assert_equal(searching.snapshot().game_state.clock.total_minutes(), minutes_before + 30, "the attempted blocked tile pays its two outdoor time-clicks before Search mode pays Castle's separate four")


func _attempted_land_move_content(source_content: RealmzContent) -> RealmzContent:
	var empty_ids: Array[String] = []
	var open_edges := {&"north": MapEdge.new(&"open", true, false), &"east": MapEdge.new(&"open", true, false), &"south": MapEdge.new(&"open", true, false), &"west": MapEdge.new(&"open", true, false)}
	var secret_features: Array[MapFeature] = [MapFeature.new("blocked-land-secret", &"secret", &"hidden")]
	var no_features: Array[MapFeature] = []
	var cells: Array[MapCell] = [
		MapCell.new("attempted-search:cell:0,0", Vector2i.ZERO, "classic.terrain.39", false, 2, true, true, false, false, false, false, false, 0, 39, "fixture.tileset", empty_ids, empty_ids, open_edges, secret_features),
		MapCell.new("attempted-search:cell:1,0", Vector2i(1, 0), "classic.terrain.1", true, 1, false, true, false, false, false, false, false, 0, 1, "fixture.tileset", empty_ids, empty_ids, open_edges, no_features),
	]
	var map := MapDefinition.new("attempted-search", "Attempted Search", &"land", 0, MapTopology.new(2, 1, cells))
	return RealmzContent.new("attempted-search", "0".repeat(64), "attempted-search-content", "realmz-classic-1", map.id, Vector2i(1, 0), WorldDefinition.new([map]), ScenarioDefinition.new([], []), [], [], [], source_content.race_definitions(), source_content.caste_definitions())


func _dungeon_special_content(source_content: RealmzContent, dungeon_case: Dictionary) -> RealmzContent:
	var empty_ids: Array[String] = []
	var empty_features: Array[MapFeature] = []
	var open_edges := {
		&"north": MapEdge.new(&"open", true, false),
		&"east": MapEdge.new(&"open", true, false),
		&"south": MapEdge.new(&"open", true, false),
		&"west": MapEdge.new(&"open", true, false),
	}
	var origin := MapCell.new("dungeon-special:cell:0,0", Vector2i.ZERO, "classic.dungeon.0", true, 1, false, false, false, false, false, false, false, 0, 0, "fixture.dungeon", empty_ids, empty_ids, open_edges, empty_features)
	var door_id: String = dungeon_case.get("doorId", "")
	var secret_id: String = dungeon_case.get("secretId", "")
	var edge_kind: StringName = dungeon_case["edgeKind"]
	var edge_passable: bool = dungeon_case["edgePassable"]
	var target_edges := {
		&"north": MapEdge.new(edge_kind, edge_passable, not edge_passable, door_id),
		&"east": MapEdge.new(edge_kind, edge_passable, not edge_passable, door_id),
		&"south": MapEdge.new(edge_kind, edge_passable, not edge_passable, door_id),
		&"west": MapEdge.new(edge_kind, edge_passable, not edge_passable, door_id),
	}
	var target_features: Array[MapFeature] = []
	if not secret_id.is_empty():
		var orientation: StringName = dungeon_case["secretOrientation"]
		for direction: StringName in [&"north", &"east", &"south", &"west"]:
			target_edges[direction] = MapEdge.new(&"wall", false, true)
		target_edges[orientation] = MapEdge.new(&"secret", true, true, "", secret_id, false)
		target_features.append(MapFeature.new(secret_id, &"secret", &"hidden", orientation))
	var target := MapCell.new("dungeon-special:cell:1,0", Vector2i(1, 0), "classic.dungeon.1", dungeon_case["cellPassable"], 1, not dungeon_case["cellPassable"], false, false, false, false, false, false, 0, 1, "fixture.dungeon", empty_ids, empty_ids, target_edges, target_features)
	var cells: Array[MapCell] = [origin, target]
	var map := MapDefinition.new("dungeon-special", "Dungeon level 0", &"dungeon", 0, MapTopology.new(2, 1, cells))
	var maps: Array[MapDefinition] = [map]
	return RealmzContent.new("dungeon-special", "0".repeat(64), "dungeon-special-content", "realmz-classic-1", map.id, Vector2i.ZERO, WorldDefinition.new(maps), ScenarioDefinition.new([], []), [], [], [], source_content.race_definitions(), source_content.caste_definitions())
