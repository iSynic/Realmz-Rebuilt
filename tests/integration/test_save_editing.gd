extends RealmzTestCase

const FIXTURE_PATH: String = "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"


func run() -> void:
	var package_result := load_test_package(FIXTURE_PATH)
	if not package_result.is_ok():
		return
	var content := package_result.content
	var session := _three_member_session(content)
	var snapshot := session.snapshot()
	assert_equal(SaveEditEligibility.reason(snapshot), "", "a save made at rest during exploration can be edited")
	_test_settings_and_undo(content, snapshot)
	_test_party_changes(content, snapshot)
	_test_member_edits_restore(content, snapshot)
	_test_allies(content, snapshot)
	_test_write_back(content, snapshot)
	_test_presentation_helpers()


func _three_member_session(content: RealmzContent) -> GameSession:
	var session := GameSession.new()
	session.start(content, 41)
	var setup_view := session.view()
	var race := setup_view.race_options[0]
	var caste_id := race.related_ids[0] if not race.related_ids.is_empty() else setup_view.caste_options[0].id
	var specs: Array[CharacterCreationSpec] = [
		CharacterCreationSpec.new("Alis", race.id, caste_id, 1),
		CharacterCreationSpec.new("Borin", race.id, caste_id, 1),
		CharacterCreationSpec.new("Cerys", race.id, caste_id, 1),
	]
	assert_equal(session.submit_intent(PartyIntents.create(specs)).state, SessionStep.State.COMPLETED, "the three-member save editor fixture begins")
	return session


func _test_settings_and_undo(content: RealmzContent, snapshot: SessionSnapshot) -> void:
	var draft := SaveEditDraft.new(snapshot.game_state, content)
	assert_false(draft.is_dirty(), "a new draft has no changes")
	assert_true(draft.set_difficulty(1), "difficulty can change to Hard")
	assert_equal([draft.state.difficulty, draft.changes().size()], [1, 1], "the difficulty change is applied and listed once")
	assert_true(draft.set_difficulty(2), "a second difficulty change replaces the first")
	assert_equal(draft.changes().size(), 1, "repeated difficulty changes fold into one row")
	assert_false(draft.set_difficulty(3), "difficulty beyond Veteran is refused")
	assert_equal(draft.state.difficulty, 2, "a refused change leaves the draft unchanged")
	assert_true(draft.set_difficulty(snapshot.game_state.difficulty), "returning to the saved difficulty is accepted")
	assert_false(draft.is_dirty(), "returning to the saved value removes the change")
	assert_false(draft.set_monster_set(99), "an unavailable monster set is refused")
	assert_true(draft.set_difficulty(-1), "difficulty can change to Easy")
	assert_true(draft.undo(0), "the listed change can be undone")
	assert_equal(draft.state.difficulty, snapshot.game_state.difficulty, "undo restores the saved difficulty")


func _test_party_changes(content: RealmzContent, snapshot: SessionSnapshot) -> void:
	var draft := SaveEditDraft.new(snapshot.game_state, content)
	var members := draft.members()
	var dropped_id := members[2].character_id
	assert_true(draft.drop_character(dropped_id, true), "a saved member can be dropped and kept")
	assert_equal(draft.state.party.characters().size(), 2, "the dropped member leaves the replayed party")
	assert_equal(draft.kept_characters().size(), 1, "the kept member is offered to Character Files")
	assert_true(draft.set_keep_in_files(dropped_id, false), "keeping can be turned off")
	assert_equal(draft.kept_characters().size(), 0, "an unkept member is not published")
	assert_true(draft.drop_character(members[1].character_id, false), "a second member can be dropped")
	assert_false(draft.drop_character(members[0].character_id, false), "the last member can't be dropped")
	assert_contains(draft.last_error, "at least one", "the refusal names the rule")
	var visitor := _fixture_character("vault.visitor", "Dara", content)
	assert_true(draft.add_character(visitor, "revision-1", content.transfer_catalog, content.campaign_id), "a Character Files character joins under party admission rules")
	assert_equal(draft.state.party.characters().size(), 2, "the added member is in the replayed party")
	var namesake := _fixture_character("vault.namesake", members[0].state().name, content)
	assert_false(draft.add_character(namesake, "revision-2", content.transfer_catalog, content.campaign_id), "a duplicate party name is refused")
	assert_equal(draft.members().size(), 4, "a refused addition leaves no member behind")
	assert_true(draft.drop_character("vault.visitor", true), "dropping an added member simply removes it")
	assert_equal([draft.members().size(), draft.kept_characters().size()], [3, 0], "a removed addition is never kept in Character Files")
	draft.discard()
	assert_false(draft.is_dirty(), "discard returns to the saved party")
	assert_equal(draft.state.party.characters().size(), 3, "discard restores every saved member")


func _test_member_edits_restore(content: RealmzContent, snapshot: SessionSnapshot) -> void:
	var draft := SaveEditDraft.new(snapshot.game_state, content)
	var member := draft.members()[0]
	var luck := member.state().luck
	var next_luck := luck + 1 if luck < 127 else luck - 1
	assert_true(member.draft.apply({"kind": &"field", "field": &"luck", "value": next_luck}), "a member's character draft accepts an edit")
	assert_true(draft.refresh(), "the save draft replays the member edit")
	assert_equal(draft.state.party.character_by_id(member.character_id).luck, next_luck, "the replayed save carries the edited value")
	assert_true(draft.set_difficulty(1), "an adventure setting changes alongside the member edit")
	var edited := SessionSnapshot.new(snapshot.campaign_id, snapshot.package_hash, snapshot.rules_version, snapshot.view_revision, draft.state, snapshot.rng_state, snapshot.scenario_vm, snapshot.scenario_action_state, null, null, null, snapshot.classic_execution)
	var envelope := save_round_trip(edited)
	assert_not_null(envelope, "the edited save encodes as a current envelope")
	var restored := GameSession.new()
	assert_equal(restored.restore(content, envelope).state, SessionStep.State.COMPLETED, "the edited save restores through the ordinary restore validator")
	var restored_state := restored.snapshot().game_state
	assert_equal([restored_state.difficulty, restored_state.party.character_by_id(member.character_id).luck], [1, next_luck], "restore keeps the edited setting and character")
	assert_equal(restored.snapshot().rng_state.to_data(), snapshot.rng_state.to_data(), "editing never consumes the save's random sequence")


func _test_allies(content: RealmzContent, snapshot: SessionSnapshot) -> void:
	var draft := SaveEditDraft.new(snapshot.game_state, content)
	var candidates := draft.ally_candidates()
	if candidates.is_empty():
		return
	assert_true(draft.add_ally(candidates[0].id, 7), "a scenario creature joins as an ally with fresh dice")
	var allies := draft.state.party.allies()
	assert_equal(allies.size(), snapshot.game_state.party.allies().size() + 1, "the ally travels with the replayed party")
	var added_id := allies[allies.size() - 1].id
	assert_true(added_id.begins_with(SaveEditOperations.ALLY_PREFIX), "draft-added allies use their own identity family")
	assert_true(draft.dismiss_ally(added_id), "an added ally can be dismissed")
	assert_false(draft.is_dirty(), "dismissing an added ally removes the addition")


func _test_write_back(content: RealmzContent, snapshot: SessionSnapshot) -> void:
	var repository := SaveRepository.new("user://realmz2-tests/save-editing/saves")
	var host := SaveHostController.new(repository)
	var vault := CharacterVaultController.new(CharacterVaultRepository.new("user://realmz2-tests/save-editing/characters"))
	var store := SaveHoldStore.new("user://realmz2-tests/save-editing/held")
	var holds := SaveEditHolds.new(store, vault)
	assert_true(host.save(content, "A", snapshot), "the fixture adventure is saved to a slot")
	var files_before := vault.revisions(content).size()
	var session := SaveEditorSession.new(host, vault, holds, content, "A")
	assert_true(session.open(), "a save at rest opens in the save editor")
	var dropped := session.draft.members()[2]
	var dropped_name := dropped.state().name
	assert_true(session.set_difficulty(1) and session.drop_character(dropped.character_id, true), "the editor accepts a setting change and a kept drop")
	var editor := session.member_editor(session.draft.members()[0].character_id)
	assert_not_null(editor, "a party member opens in a character editor")
	var signals := [0]
	session.changed.connect(func() -> void: signals[0] += 1)
	assert_true(editor.apply({"kind": &"field", "field": &"luck", "value": 21}), "the member editor changes the member's luck")
	assert_equal(signals[0], 1, "a member edit refreshes the save draft once")
	assert_equal(session.draft.state.party.character_by_id(editor.character_id()).luck, 21, "the member edit reaches the save draft")
	assert_equal(session.save(), &"saved", "the edited save is written and the dropped character kept")
	assert_true(session.save() == &"failed" and not session.is_dirty(), "a written session can't save again, so it can't disturb what it already wrote")
	var written := host.load(content, "A")
	assert_equal([written.game_state.difficulty, written.game_state.party.characters().size(), written.game_state.party.character_by_id(editor.character_id()).luck], [1, 2, 21], "the slot holds the edited adventure")
	var backup := repository.load_backup(content.campaign_id, "A", content.package_hash)
	assert_equal([backup.game_state.difficulty, backup.game_state.party.characters().size()], [snapshot.game_state.difficulty, 3], "the original save becomes the slot's backup")
	assert_equal(vault.revisions(content).size(), files_before + 1, "the dropped character is kept as a new Character File")
	assert_true(vault.revisions(content).any(func(view: CharacterVaultRevisionView) -> bool: return view.name == dropped_name and view.publication_label.ends_with("Slot A")), "the kept Character File carries the dropped character's name and its source slot")
	var no_packages: Array[PackageDiscoveryResult] = []
	vault.configure_rule_sources(content, no_packages)
	var kept_view: CharacterVaultRevisionView = vault.revisions(content).filter(func(view: CharacterVaultRevisionView) -> bool: return view.name == dropped_name)[0]
	var rejoin := SaveEditorSession.new(host, vault, holds, content, "A")
	assert_true(rejoin.open() and rejoin.add_character(kept_view.character_id, kept_view.revision_hash), "the kept Character File can rejoin the edited save")
	assert_equal(rejoin.draft.state.party.characters().size(), 3, "the rejoining character is in the draft party")
	rejoin.discard()
	var stale := SaveEditorSession.new(host, vault, holds, content, "A")
	assert_true(stale.open() and stale.set_difficulty(2), "a second editor opens the written save")
	assert_true(host.save(content, "A", snapshot), "the slot is saved over while the editor is open")
	assert_equal(stale.save(), &"failed", "an editor never overwrites a slot that changed while it was open")
	assert_contains(stale.last_error, "changed on disk", "the refusal explains the changed file")
	_test_holds(content, snapshot, store, holds, vault)
	_test_hold_failure(content, snapshot, host, vault)
	_test_workspace(content, snapshot, host, vault, holds)


func _test_holds(content: RealmzContent, snapshot: SessionSnapshot, store: SaveHoldStore, holds: SaveEditHolds, vault: CharacterVaultController) -> void:
	var envelope := SaveEnvelope.from_snapshot(snapshot)
	var waiting: Array[CharacterState] = [snapshot.game_state.party.characters()[0], snapshot.game_state.party.characters()[1]]
	var held := store.hold("A", envelope, waiting)
	assert_not_null(held, "a save is held for characters whose Character File waits")
	assert_equal(store.holds(content.campaign_id).size(), 1, "the hold is listed for its campaign")
	assert_equal(store.load(held).to_data(), envelope.to_data(), "the held copy is the exact original save")
	assert_true(holds.let_go(held, waiting[1].id), "one waiting character can be let go")
	assert_equal(store.holds(content.campaign_id)[0].character_ids, [waiting[0].id], "letting go keeps the hold for the rest")
	var files_before := vault.revisions(content).size()
	var other_version := store.holds(content.campaign_id)[0]
	other_version.package_hash = "another-revision"
	assert_false(holds.settle(content, other_version), "Retry refuses content from another package revision")
	assert_equal(vault.revisions(content).size(), files_before, "a refused retry creates no Character File")
	assert_true(holds.settle(content, store.holds(content.campaign_id)[0]), "Retry creates the waiting Character File")
	assert_equal([vault.revisions(content).size(), store.holds(content.campaign_id).size()], [files_before + 1, 0], "the Character File exists and the held copy is gone")
	# A publish whose release failed: the reserved file already exists, so Retry only releases it.
	var again := store.hold("B", envelope, [waiting[0]] as Array[CharacterState])
	var identity := vault.next_character_file_identity()
	assert_true(store.reserve_file(again, waiting[0].id, "%s|%d" % [identity.character_id, identity.seed]), "a Character File identity is reserved before publishing")
	assert_true(store.hold("B", envelope, [waiting[0]] as Array[CharacterState]) == null, "a live hold for the same original is never overwritten")
	var title := content.campaign.title if content.campaign != null and not content.campaign.title.is_empty() else content.campaign_id
	assert_false(vault.publish_party_character(waiting[0], content, "save-editor/%s/%s" % [again.hold_id, waiting[0].id], "%s · from %s Slot B" % [waiting[0].name, title], identity).is_empty(), "the reserved file is published")
	files_before = vault.revisions(content).size()
	assert_true(holds.settle(content, store.holds(content.campaign_id)[0]), "Retry after an unreleased publish settles the hold")
	assert_equal([vault.revisions(content).size(), store.holds(content.campaign_id).size()], [files_before, 0], "no second Character File is made for the same kept character")
	# A publish that stored its file yet reported failure clears the reservation; Retry still finds the file by its source.
	var lost := store.hold("E", envelope, [waiting[0]] as Array[CharacterState])
	assert_false(vault.publish_party_character(waiting[0], content, "save-editor/%s/%s" % [lost.hold_id, waiting[0].id], "%s · from %s Slot E" % [waiting[0].name, title]).is_empty(), "the file is stored without a reservation")
	files_before = vault.revisions(content).size()
	assert_true(holds.settle(content, store.holds(content.campaign_id)[0]), "Retry without a reservation settles the hold")
	assert_equal([vault.revisions(content).size(), store.holds(content.campaign_id).size()], [files_before, 0], "Retry finds the stored file by its source instead of publishing again")


func _test_hold_failure(content: RealmzContent, snapshot: SessionSnapshot, host: SaveHostController, vault: CharacterVaultController) -> void:
	# A hold root that is a file can't take a folder, so nothing can be held.
	var blocker := FileAccess.open("user://realmz2-tests/save-editing/held-blocker", FileAccess.WRITE)
	blocker.store_string("x")
	blocker.close()
	var broken := SaveEditHolds.new(SaveHoldStore.new("user://realmz2-tests/save-editing/held-blocker"), vault)
	assert_true(host.save(content, "D", snapshot), "a slot is saved for the hold failure")
	var session := SaveEditorSession.new(host, vault, broken, content, "D")
	assert_true(session.open() and session.drop_character(session.draft.members()[0].character_id, true), "a kept drop is listed")
	assert_equal(session.save(), &"failed", "a save whose kept characters can't be held is refused")
	assert_contains(session.last_error, "Nothing was written", "the refusal says the slot is untouched")
	assert_equal(host.load(content, "D").game_state.party.characters().size(), snapshot.game_state.party.characters().size(), "the slot still holds the original party")
	assert_true(session.is_dirty(), "the edits stay in the editor")


func _test_workspace(content: RealmzContent, snapshot: SessionSnapshot, host: SaveHostController, vault: CharacterVaultController, holds: SaveEditHolds) -> void:
	assert_true(host.save(content, "C", snapshot), "a slot is saved for the save editor screen")
	var session := SaveEditorSession.new(host, vault, holds, content, "C")
	assert_true(session.open(), "the screen's session opens")
	var workspace := (load("res://src/ui/setup/save_editor_workspace.tscn") as PackedScene).instantiate() as SaveEditorWorkspace
	(Engine.get_main_loop() as SceneTree).root.add_child(workspace)
	var closed := [""]
	session.closed.connect(func(message: String, _is_error: bool) -> void: closed[0] = message)
	workspace.bind(session, null, false)
	var save := workspace.find_child("Save", true, false) as Button
	assert_true(workspace.visible and (workspace.find_child("AdventurePage", true, false) as Control).visible and save.disabled, "the editor opens on Adventure settings with nothing to save")
	(workspace.find_child("Hard", true, false) as Button).pressed.emit()
	assert_equal([session.draft.state.difficulty, (workspace.find_child("ChangeList", true, false) as Node).get_child_count(), save.disabled], [1, 1, false], "choosing Hard lists one change and enables Save")
	assert_true(workspace.handle_controller_shortcut(&"realmz_controller_action_radial") and session.draft.state.difficulty == snapshot.game_state.difficulty and not session.is_dirty(), "controller X undoes the latest change")
	assert_true(workspace.handle_controller_shortcut(&"realmz_controller_system") and not (workspace.get_node("Dialog") as Control).visible, "Start with nothing to save explains instead of opening the review")
	(workspace.find_child("Hard", true, false) as Button).pressed.emit()
	workspace.set_controller_prompts(ControllerPreferences.PROMPT_XBOX, ControllerPreferences.new())
	assert_equal((workspace.find_child("Prompts", true, false) as Control).get_child_count(), 8, "a controller shows the save editor's glyph bar")
	assert_false(workspace.handle_controller_shortcut(&"realmz_controller_confirm"), "ordinary controller actions stay with workspace navigation")
	var members := workspace.find_child("Members", true, false) as BoxContainer
	assert_equal(members.get_child_count(), 3, "the roster lists every party member")
	var second := members.get_child(1) as SaveEditorMemberRow
	second.pressed.emit()
	var editor := workspace.find_child("MemberEditor", true, false) as CharacterEditor
	assert_true((workspace.find_child("MemberPage", true, false) as Control).visible and editor.visible and editor.session() != null and not (editor.get_node("Layout/Header") as Control).visible, "a member opens in the embedded character editor without its own header")
	var dialog := workspace.get_node("Dialog") as EditorDialog
	(workspace.find_child("DropMember", true, false) as Button).pressed.emit()
	assert_true(dialog.visible, "dropping a saved member asks first")
	dialog.chosen.emit(&"drop_keep")
	assert_equal([second.page_id, (second.find_child("Tag", true, false) as Label).text, session.draft.state.party.characters().size()], [session.draft.members()[1].character_id, "Leaves", 2], "the dropped member stays listed as leaving")
	save.pressed.emit()
	assert_true(dialog.visible, "Save opens the review first")
	dialog.chosen.emit(&"save")
	assert_contains(closed[0], "Slot C saved", "saving from the review writes the slot and closes the editor")
	assert_equal(host.load(content, "C").game_state.party.characters().size(), 2, "the slot holds the edited party")
	(members.get_child(0) as SaveEditorMemberRow).pressed.emit()
	var reopened := SaveEditorSession.new(host, vault, holds, content, "C")
	assert_true(reopened.open(), "the edited slot opens again")
	workspace.bind(reopened, null, false)
	(members.get_child(0) as SaveEditorMemberRow).pressed.emit()
	assert_true(editor.session() != null and editor.session().apply({"kind": &"field", "field": &"luck", "value": 19}) and reopened.is_dirty(), "a member opened after rebinding edits the new session, not the last one")
	(workspace.find_child("AdventureRow", true, false) as BaseButton).pressed.emit()
	(workspace.find_child("Easy" if reopened.draft.state.difficulty == 1 else "Hard", true, false) as Button).pressed.emit()
	var change_list := workspace.find_child("ChangeList", true, false) as Node
	var undo_button := change_list.get_child(0).get_child(change_list.get_child(0).get_child_count() - 1) as Button
	undo_button.grab_focus()
	undo_button.pressed.emit()
	var focused := workspace.get_viewport().gui_get_focus_owner()
	assert_true(focused != null and workspace.is_ancestor_of(focused) and not focused.is_queued_for_deletion(), "undoing from the Changes list keeps controller focus in the editor")
	var open_button: Button = null
	for row: Node in change_list.get_children():
		var action := row.get_child(row.get_child_count() - 1) as Button
		if action != null and action.text == "Open":
			open_button = action
	if open_button != null:
		open_button.grab_focus()
		open_button.pressed.emit()
		focused = workspace.get_viewport().gui_get_focus_owner()
		assert_true(focused != null and focused.is_visible_in_tree(), "opening a member from Changes moves focus to something visible")
	reopened.discard()
	workspace.queue_free()


func _test_presentation_helpers() -> void:
	# A map preview's off-map black band is trimmed; the map itself is kept whole.
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color(0.4, 0.5, 0.4))
	image.fill_rect(Rect2i(0, 0, 64, 16), Color.BLACK)
	var preview := MapPreviewImage.texture(image.save_jpg_to_buffer(0.9))
	assert_true(preview != null and preview.get_height() <= 50 and preview.get_height() >= 46 and preview.get_width() == 64, "the map preview drops the black band above the map")
	# A mostly dark map (lit paths in black) is trimmed by at most a quarter on each side.
	var dark := Image.create(64, 64, false, Image.FORMAT_RGB8)
	dark.fill(Color.BLACK)
	dark.fill_rect(Rect2i(30, 0, 4, 64), Color(0.6, 0.6, 0.5))
	var dark_preview := MapPreviewImage.texture(dark.save_jpg_to_buffer(0.9))
	assert_true(dark_preview != null and dark_preview.get_width() >= 32 and dark_preview.get_height() == 64, "a dark map keeps at least half its width and every row")
	var arrows := ArrowLabel.new()
	arrows.set_arrow_text("Normal → Hard", 12, &"")
	assert_equal(arrows.get_child_count(), 3, "a change detail splits into before, a larger arrow and after")
	assert_true((arrows.get_child(1) as Label).get_theme_font_size(&"font_size") > (arrows.get_child(0) as Label).get_theme_font_size(&"font_size"), "the arrow is drawn larger than the words around it")
	arrows.free()
