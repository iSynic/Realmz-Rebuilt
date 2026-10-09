extends RealmzTestCase

const FIXTURE_PATH := "res://tests/fixtures/packages/realmz2-synthetic-fixture.realmz2"

func instantiate_ui_scene(path: String) -> Node: return (load(path) as PackedScene).instantiate()


func _test_encounter_dock_scaling() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var host := Control.new()
	tree.root.add_child(host)
	var presenter := instantiate_ui_scene("res://src/ui/shared/interactions/interaction_presenter.tscn") as InteractionPresenter
	host.add_child(presenter)
	var request := ClassicUiFixtureGallery.request_for(InteractionRequest.WORD_AND_ACTION)
	var dock_id := 0
	for sample: Array in [[Vector2(1280, 720), "auto", 1.0], [Vector2(2560, 1440), "auto", 1.0], [Vector2(3840, 2160), "auto", 1.0], [Vector2(800, 600), "auto", 1.5], [Vector2(2560, 1440), "300", 1.5], [Vector2(1280, 720), "auto", 1.0]]:
		host.size = sample[0]
		var settings := PresentationSettings.new()
		settings.text_scale = sample[2]
		var profile := UiLayoutProfile.for_viewport(host.size, sample[1], PresentationSettings.DISPLAY_RESPONSIVE, settings.text_scale)
		host.theme = ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme, settings, profile.ui_scale)
		UiSizing.apply(host, profile)
		var compact := profile.id == UiLayoutProfile.COMPACT
		var textbox := Rect2(10.0 * profile.ui_scale if compact else host.size.x * 0.25, host.size.y * 0.75, host.size.x * (0.38 if compact else 0.5), host.size.y * 0.25)
		presenter.set_classic_regions(Rect2(8, 40, host.size.x - 368, textbox.position.y - 40), textbox, Rect2(0, textbox.position.y, host.size.x, textbox.size.y))
		if dock_id == 0:
			presenter.present(request)
			UiSizing.apply(host, profile)
		for frame: int in 4:
			await tree.process_frame
		var dock := host.find_child("EncounterCommandDock", true, false) as Control
		if dock_id == 0: dock_id = dock.get_instance_id()
		assert_equal(dock.get_instance_id(), dock_id, "live scaling retains the encounter dock and its active request")
		assert_true(dock.get_rect().end.y <= textbox.position.y - 5.0 * profile.ui_scale and dock.position.y >= 40.0, "the settled encounter dock remains completely above narration at %s" % str(sample))
		assert_true(is_equal_approx(dock.position.x, textbox.position.x) and is_equal_approx(dock.size.x, textbox.size.x), "the encounter dock stays aligned with the narrative well")
		var strip := dock.find_child("EncounterCommandStrip", true, false) as GridContainer
		assert_equal(strip.columns, 3 if host.size.x == 800.0 else 6, "encounter commands wrap only where the narrative well is too narrow for one row")
		for command: Control in strip.get_children():
			assert_true(dock.get_global_rect().encloses(command.get_global_rect()), "every encounter command stays inside the scaled dock")
	host.free()
	await tree.process_frame


func _fixture_request(id: String, kind: StringName, overrides: Dictionary = {}) -> InteractionRequest:
	var payload := ClassicUiFixtureGallery.payload_for(kind)
	payload.merge(overrides, true)
	return InteractionRequest.from_payload(id, kind, payload)


func _buttons_in(root: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in root.find_children("*", "Button", true, false):
		if child is Button: buttons.append(child as Button)
	return buttons


func _direct_buttons_in(root: Node) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in root.get_children():
		if child is Button: buttons.append(child as Button)
	return buttons


func _base_buttons_in(root: Node) -> Array[BaseButton]:
	var buttons: Array[BaseButton] = []
	for child: Node in root.find_children("*", "BaseButton", true, false):
		if child is BaseButton: buttons.append(child as BaseButton)
	return buttons


func _labels_in(root: Node) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		if child is Label: labels.append((child as Label).text)
	return labels


func _visible_control_texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in root.find_children("*", "Control", true, false):
		if child is Label and child.visible: texts.append(child.text)
		elif child is Button and child.visible: texts.append(child.text)
	return texts


func _test_shared_scrollbar_controls() -> void:
	var theme := load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme
	assert_true(theme != null and theme.has_icon(&"decrement", &"VScrollBar") and theme.has_icon(&"increment", &"VScrollBar") and theme.has_icon(&"decrement", &"HScrollBar") and theme.has_icon(&"increment", &"HScrollBar"), "the shared Classic theme gives every native vertical and horizontal scrollbar dedicated step buttons")
	if theme != null: assert_true([theme.get_icon(&"decrement", &"VScrollBar"), theme.get_icon(&"increment", &"VScrollBar"), theme.get_icon(&"decrement", &"HScrollBar"), theme.get_icon(&"increment", &"HScrollBar")].all(func(icon: Texture2D) -> bool: return icon != null and icon.get_size() == Vector2(12, 12)), "the four native scrollbar step regions use compact direction-specific glyphs")
	var scroll := ScrollContainer.new(); ClassicScrollArrowController.configure(scroll, 32.0); assert_equal([scroll.scroll_vertical_custom_step, scroll.scroll_horizontal_custom_step], [32.0, 32.0], "the application-wide native scrollbar arrows move by one useful shared step instead of the engine's zero-step default")
	var vertical := VScrollBar.new(); vertical.size = Vector2(12.0, 100.0); assert_equal([ClassicScrollArrowController.arrow_direction(vertical, Vector2(6.0, 6.0), true), ClassicScrollArrowController.arrow_direction(vertical, Vector2(6.0, 50.0), true), ClassicScrollArrowController.arrow_direction(vertical, Vector2(6.0, 94.0), true)], [-1, 0, 1], "the shared scrollbar recognizes both held arrow regions without treating the track as an arrow")
	vertical.free(); scroll.free()


func _test_player_map_workspace() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok(): return
	var media := ClassicMediaCatalog.new(loaded.media, ApplicationMediaCatalog.new()); var package_sound := loaded.media.assets().filter(func(asset: MediaAsset) -> bool: return asset.resource_type == "snd ")[0] as MediaAsset; var decoded_sound := media.audio_stream_by_resource("snd ", package_sound.resource_id); assert_true(decoded_sound != null and media.audio_stream_by_resource("snd ", package_sound.resource_id) == decoded_sound, "repeated package sound requests reuse one catalog-lifetime decoded stream"); var battleaxe_icon := media.asset_by_resource("cicn", 6195); assert_true(battleaxe_icon != null and media.image_texture(battleaxe_icon) != null, "the exact stock CICN selected when Battleaxe +2 becomes identified remains available to treasure and inventory presentation"); var first_effect_icon := media.asset_by_resource("cicn", 14000); var search_effect_icon := media.asset_by_resource("cicn", 14032); var last_effect_icon := media.asset_by_resource("cicn", 14063); var masked_search_effect := ClassicSearchCommandButton.remove_classic_matte(media.image_texture(search_effect_icon)); var masked_search_image := masked_search_effect.get_image(); assert_true(first_effect_icon != null and search_effect_icon != null and last_effect_icon != null and media.image_texture(first_effect_icon) != null and masked_search_effect != null and masked_search_image.get_size() == Vector2i(32, 32) and masked_search_image.get_pixel(31, 31).a == 0.0 and media.image_texture(last_effect_icon) != null, "the complete Castle party-effect range has decodable application fallbacks while Search reuses the established neutral-gray matte removal at native size"); var definition := loaded.content.world.player_map_by_classic_id(1)
	var character_library := PackageRepository.new().load_bundled_package(ApplicationLibraryIdentity.PATH, ApplicationLibraryIdentity.CAMPAIGN_ID, ApplicationLibraryIdentity.PACKAGE_HASH); var local_marker := MediaAsset.new("realmz-player-map-cicn-267", "Map marker", "player-map-marker", "image/png", "cicn", 267, 1, "0".repeat(64), "missing.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1); var negative_marker := MediaAsset.new("realmz-player-map-cicn--18", "Negative map marker", "player-map-marker", "image/png", "cicn", -18, 1, "0".repeat(64), "missing.png", 1, 1, 0, 0, 0, 0, 0, 0, 0, -1, -1); var composed_media := ClassicMediaCatalog.new(PackageMediaCatalog.new("", "", [local_marker, negative_marker]), ApplicationMediaCatalog.new(), character_library.media); assert_equal([composed_media.asset_by_id("realmz-portrait-267").id, composed_media.asset_by_resource("cicn", 267).id, composed_media.asset_by_id("realmz-special-land-neg-18").id, composed_media.asset_by_id("realmz-land-cicn-409").id], ["realmz-portrait-267", "realmz-player-map-cicn-267", "realmz-special-land-neg-18", "realmz-application-cicn-409"], "stable application portraits, exact scenario CICN overrides, and normalized application land CICNs remain available through scenario-before-application precedence"); var setup_router := instantiate_ui_scene("res://src/ui/shell/screen_navigator.tscn") as ScreenNavigator; (Engine.get_main_loop() as SceneTree).root.add_child(setup_router); setup_router.initialize(); setup_router.set_media_catalog(composed_media); var setup_character := CharacterState.new("setup.portrait", "Magus", 12, 12); setup_character.portrait_id = "realmz-portrait-267"; var setup_view := GameView.new(1, true, null); setup_view.party_setup_available = true; setup_view.party_setup = PartySetupView.new(); setup_view.campaign_summary = CampaignSummaryView.new(); setup_view.party_members = [CharacterView.new(setup_character)]; var setup_revision := CharacterVaultRevisionView.new(); setup_revision.character_id = setup_character.id; setup_revision.revision_hash = "a".repeat(64); setup_revision.name = setup_character.name; setup_revision.is_current = true; setup_revision.eligible = true; setup_revision.character = CharacterView.new(setup_character); setup_router.set_vault_revisions([setup_revision]); setup_router.present(setup_view); setup_router.show_campaign_selection(); var magus_portraits := setup_router.find_children("Portrait", "TextureRect", true, false).filter(func(node: Node) -> bool: return (node as TextureRect).tooltip_text == "Magus's portrait"); var stored_rows := setup_router.find_children("StoredCharacter_*", "PartySetupCharacterRow", true, false); var stored_row := stored_rows[0] as PartySetupCharacterRow if not stored_rows.is_empty() else null; var cursor_identity := stored_row.drag_cursor_texture_identity() if stored_row != null else 0; assert_true(magus_portraits.size() == 2 and magus_portraits.all(func(node: Node) -> bool: return (node as TextureRect).texture != null), "party setup resolves a stock portrait used only by the admitted party and Character Files row even when the scenario overrides its exact CICN resource"); assert_true(stored_row != null and stored_row.drag_cursor_prepared() and cursor_identity != 0 and stored_row.drag_cursor_texture_identity() == cursor_identity and stored_row.drag_payload() == {"kind": "party-setup-character", "characterId": setup_character.id, "revisionHash": setup_revision.revision_hash}, "the stored row prepares one revision-keyed translucent cursor before drag and preserves the same stable import identity for drop"); var drop_list := PartySetupPartyList.new(); drop_list.configure_drop_target(true, ""); var drop_slot := load("res://src/ui/setup/party_setup_party_slot.tscn").instantiate() as PartySetupPartySlot; drop_list.add_child(drop_slot); var dropped_imports: Array[Array] = []; drop_list.import_requested.connect(func(character_id: String, revision_hash: String) -> void: dropped_imports.append([character_id, revision_hash])); var payload: Dictionary = stored_row.drag_payload(); assert_true(drop_slot.accepts_drop_payload(payload), "each retained party slot forwards the stored-character drag to the owning party-list drop target"); drop_slot.submit_drop_payload(payload); assert_equal(dropped_imports, [[setup_character.id, setup_revision.revision_hash]], "dropping on a visible party slot emits the same stable-ID import as Add"); drop_list.free(); setup_router.free()
	var session := GameSession.new(); assert_equal(session.start(loaded.content, 1).state, SessionStep.State.COMPLETED, "the player-map view fixture starts from validated content")
	var map_snapshot := session.snapshot(); map_snapshot.game_state.world.exploration.acquire_map(definition.id); assert_equal(session.restore(loaded.content, map_snapshot).state, SessionStep.State.COMPLETED, "acquired player-map state enters presentation through the public restore boundary")
	var view := session.view(); assert_equal([view.acquired_player_maps.size(), view.acquired_player_maps[0].id, view.acquired_player_maps[0].cells.size()], [1, definition.id, 100], "the detached player-map view derives its 320-pixel crop from authoritative topology"); assert_equal(view.player_map_menu_entries.size(), 4, "the detached menu retains every package player-map slot, not only acquired definitions")
	var body := VBoxContainer.new(); (Engine.get_main_loop() as SceneTree).root.add_child(body); var controller := MapsJournalScreenController.new(); controller.present(body, view, media); assert_not_null(body.find_child("AcquiredMapChooser", true, false), "the Journal route exposes a presentation-owned acquired-map chooser")
	var map_buttons: Array[Node] = body.find_child("AcquiredMapChooser", true, false).find_children("*", "Button", true, false); assert_equal(map_buttons.size(), 1, "Maps/Notes shows only acquired maps without unavailable placeholders"); assert_true(not (map_buttons[0] as Button).disabled and map_buttons[0].get_meta("player_map_id") == definition.id, "filtering retains the acquired map's stable identity"); var map_stage := body.find_child("PlayerMapCartographicStage", true, false); var map_header := body.find_child("PlayerMapStageHeader", true, false) as PanelContainer; var map_note := body.find_child("PlayerMapNote", true, false); var map_scroll := body.find_child("PlayerMapScroll", true, false); var parchment := body.find_child("PlayerMapParchmentMat", true, false) as PanelContainer; var parchment_style := parchment.get_theme_stylebox("panel") as StyleBoxTexture if parchment != null else null; assert_true(body.find_child("PlayerMapCanvas", true, false) != null and map_stage != null and map_header != null and map_header.theme_type_variation == &"ClassicInset" and map_note != null and map_scroll.is_ancestor_of(map_note) and map_note.get_index() > map_note.get_parent().get_node("Center").get_index() and body.find_child("PlayerMapZoomIn", true, false) != null and map_stage.find_child("PlayerMapTitle", true, false) != null and map_stage.find_child("PlayerMapZoomToolbar", true, false) != null and parchment_style != null and parchment_style.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE and parchment_style.axis_stretch_vertical == StyleBoxTexture.AXIS_STRETCH_MODE_TILE and PlayerMapParchmentMat.border_size(1.0) == 40.0, "the selected crop fills one tiled-slate stage with an inset corner header, readable post-map description, and exact 12.5-percent tiled parchment mat")
	var note := body.find_child("PlayerMapNote", true, false) as Label; assert_not_null(note, "non-scrolling maps retain their authored note"); if note != null: assert_contains(note.text, "deterministic map", "the displayed note comes from immutable player-map content"); assert_equal(note.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "map descriptions are centered beneath the parchment background")
	var immediate := instantiate_ui_scene("res://src/ui/journal/player_map_interaction.tscn") as PlayerMapInteraction; immediate.configure(view, media); var payloads: Array[Dictionary] = []; immediate.response_body_submitted.connect(func(response_body: InteractionResponse.Body) -> void: payloads.append(response_body.to_data())); immediate.build(InteractionRequest.from_payload("player-map.immediate", InteractionRequest.ACKNOWLEDGE, {"prompt": definition.name, "presentation": "player-map", "playerMapId": definition.id})); assert_not_null(immediate.find_child("ImmediatePlayerMap", true, false), "negative opcode 29 uses the same typed presenter as Journal browsing"); var continue_button := immediate.find_children("*", "Button", true, false).filter(func(button: Node) -> bool: return (button as Button).text == "Continue")[0] as Button; continue_button.pressed.emit(); assert_equal(payloads, [{}], "the immediate player-map stage emits only the empty acknowledgement accepted by the VM")
	map_snapshot = session.snapshot()
	for player_map_definition: PlayerMapDefinition in loaded.content.world.player_maps(): map_snapshot.game_state.world.exploration.acquire_map(player_map_definition.id)
	assert_equal(session.restore(loaded.content, map_snapshot).state, SessionStep.State.COMPLETED, "the complete acquired-map collection restores through the public session boundary")
	var complete_view := session.view(); var views_by_mode: Dictionary = {}; for player_map_view: PlayerMapView in complete_view.acquired_player_maps: views_by_mode[player_map_view.mode] = player_map_view
	assert_equal(views_by_mode.keys().size(), 4, "the fixture exercises land crop, dungeon crop, picture, and scrolling-text read models"); controller.present(body, complete_view, media); var map_tabs := body.find_child("MapsNotesTabs", true, false) as TabContainer; var selected_tab_before := map_tabs.current_tab; var map_tabs_id := map_tabs.get_instance_id(); var complete_map_buttons := body.find_child("AcquiredMapChooser", true, false).find_children("*", "Button", true, false); (complete_map_buttons[1] as Button).pressed.emit(); map_tabs = body.find_child("MapsNotesTabs", true, false) as TabContainer; assert_true(map_tabs.get_instance_id() == map_tabs_id and map_tabs.current_tab == selected_tab_before and (complete_map_buttons[1] as Button).button_pressed, "choosing another acquired map updates its selected presenter in place and preserves the active Maps tab")
	var picture_view := views_by_mode[PlayerMapDefinition.PICTURE] as PlayerMapView; assert_equal(picture_view.picture_rect, Rect2i(36, 24, 240, 160), "picture-backed maps preserve their authored destination rectangle"); assert_true(picture_view.party_marker_visible, "picture-backed maps retain source playable-map identity for Castle's party marker"); var picture_canvas := PlayerMapCanvas.new(); picture_canvas.present(picture_view, media); picture_canvas.set_zoom(2.0); assert_equal([picture_canvas.custom_minimum_size, picture_canvas.zoom()], [Vector2(640, 640), 2.0], "picture-backed maps preserve the public 320-pixel Classic canvas while allowing integer-clean inspection zoom")
	var dungeon_view := views_by_mode[PlayerMapDefinition.DUNGEON_CROP] as PlayerMapView; var dungeon_cells: Dictionary = {}; for cell: MapCellView in dungeon_view.cells: dungeon_cells[cell.coordinate] = cell
	assert_equal([dungeon_view.map_id, dungeon_view.cells.size(), dungeon_view.cell_size, dungeon_view.icon_size], ["dungeon:0", 400, 16, 32], "Castle dungeon maps derive a fixed 20-by-20 16-pixel topology crop while retaining the authored marker scale"); assert_equal([MapTextureCache.dungeon_tile_ids(dungeon_cells[Vector2i.ZERO]), MapTextureCache.dungeon_tile_ids(dungeon_cells[Vector2i(1, 0)]), MapTextureCache.dungeon_tile_ids(dungeon_cells[Vector2i(0, 1)]), MapTextureCache.dungeon_tile_ids(dungeon_cells[Vector2i(1, 2)])], [[16, 1], [16, 1, 2], [16, 1], [16, 8]], "the public renderer composes PICT 302 layers in Castle bit order while concealed directional secrets remain ordinary walls and unmapped cells remain hidden")
	var scrolling_view := views_by_mode[PlayerMapDefinition.SCROLLING_TEXT] as PlayerMapView; var scrolling_presenter := PlayerMapPresenter.new(); scrolling_presenter.present(scrolling_view, media); var style_bytes := PackedByteArray([0, 1, 0, 0, 0, 0, 0, 12, 0, 9, 0, 0, 1, 0, 0, 12, 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc]); var style_runs := ClassicScrollingTextSurface.decode_style_runs(style_bytes, 5); var unsorted_style_bytes := PackedByteArray([0, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0xff, 0xff, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0]); var sorted_style_runs := ClassicScrollingTextSurface.decode_style_runs(unsorted_style_bytes, 5); var styled_surface := instantiate_ui_scene("res://src/ui/journal/classic_scrolling_text_surface.tscn") as ClassicScrollingTextSurface; styled_surface.configure(media); styled_surface.present_text("Color", style_bytes); assert_not_null(scrolling_presenter.find_child("PlayerMapScrollingText", true, false), "scrolling maps use the shared Castle text stage"); assert_contains((scrolling_presenter.find_child("PlayerMapScrollingText", true, false) as RichTextLabel).text, "turns north", "the exact packaged TEXT resource decodes into the scrolling map stage")
	assert_true(scrolling_presenter.find_child("ClassicScrollingTextBackground", true, false) != null and style_runs.size() == 1 and style_runs[0]["font"] == 0 and style_runs[0]["face"] == 1 and style_runs[0]["size"] == 12 and is_equal_approx((style_runs[0]["color"] as Color).r, 0x1234 / 65535.0) and sorted_style_runs.map(func(run: Dictionary) -> int: return int(run["start"])) == [0, 4] and styled_surface.text_label().get_parsed_text() == "Color" and styled_surface.text_label().tab_size == 1 and ClassicScrollingTextSurface.classic_font_role(1602) == &"ornament" and ClassicScrollingTextSurface.classic_font_role(21) == &"utility" and [ClassicScrollingTextSurface.classic_font_size(1601, 0), ClassicScrollingTextSurface.classic_font_size(4, 9), ClassicScrollingTextSurface.classic_font_size(21, 12)] == [10, 11, 9] and ClassicScrollingTextSurface.automatic_scroll_distance(0.15) == 3.0 and [ClassicScrollingTextSurface.drag_scroll_delta(20.0, 19.0), ClassicScrollingTextSurface.drag_scroll_delta(20.0, 21.0)] == [25.0, -25.0], "scrolling maps share opcode 62's tiled background, Castle-sorted style decoding, font and point-size rules, one-space tabs, automatic cadence, and signed drag steps")
	assert_true(scrolling_presenter.find_child("PlayerMapNote", true, false) == null, "Castle's scrolling map path skips the ordinary map note"); styled_surface.free()
	var scaled_mat := PlayerMapParchmentMat.new()
	scaled_mat.add_child(picture_canvas)
	for map_zoom: float in [1.0, 2.0, 1.0]:
		picture_canvas.set_zoom(map_zoom)
		scaled_mat.set_map_zoom(map_zoom)
		for interface_scale: float in [2.0, 3.0, 1.0]:
			var profile := UiLayoutProfile.for_viewport(Vector2(1280, 720) * interface_scale, "auto")
			UiSizing.apply(scaled_mat, profile)
			assert_equal(picture_canvas.custom_minimum_size, Vector2(320, 320) * map_zoom, "interface resizing preserves the map zoom's exact drawable canvas")
			assert_equal(scaled_mat.get_theme_stylebox("panel").get_minimum_size(), Vector2(80, 80) * map_zoom, "the applied parchment border follows map zoom independently of interface scale")
	scrolling_presenter.free(); scaled_mat.free(); immediate.free(); body.free()


func _test_player_map_scrolling() -> void:
	var loaded := load_test_package(FIXTURE_PATH)
	if not loaded.is_ok(): return
	var definition := loaded.content.world.player_map_by_classic_id(1)
	var selected := PlayerMapView.new(definition)
	var view := GameView.new(1, true, null)
	view.acquired_player_maps = [selected]
	view.player_map_menu_entries = [selected]
	for index: int in range(32):
		var entry := PlayerMapView.new(definition)
		entry.id = "acquired-map-%d" % index
		entry.name = "Acquired map %d" % index
		view.player_map_menu_entries.append(entry)
		view.acquired_player_maps.append(entry)
	var viewport := SubViewport.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(viewport)
	var screen := instantiate_ui_scene("res://src/ui/journal/journal_screen.tscn") as JournalScreen
	viewport.add_child(screen)
	var controller := MapsJournalScreenController.new()
	controller.present(screen, view, ClassicMediaCatalog.new(loaded.media, ApplicationMediaCatalog.new()))
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(800, 600), Vector2i(1280, 720)]:
		viewport.size = dimensions
		var profile := UiLayoutProfile.for_viewport(dimensions, "auto")
		screen.theme = ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres"), PresentationSettings.new(), profile.ui_scale)
		UiSizing.apply(screen, profile)
		screen.set_workspace_rect(Rect2(Vector2.ZERO, dimensions))
		for frame: int in range(4): await tree.process_frame
		var chooser := screen.find_child("AcquiredMapScroll", true, false) as ScrollContainer
		var map_scroll := screen.find_child("PlayerMapScroll", true, false) as ScrollContainer
		var mat := screen.find_child("PlayerMapParchmentMat", true, false) as PlayerMapParchmentMat
		var note := screen.find_child("PlayerMapNote", true, false) as Label
		assert_true(chooser != null and chooser.get_v_scroll_bar().visible and not screen.scroll_control().get_v_scroll_bar().visible, "a long map list scrolls independently without creating a page scrollbar")
		assert_equal(mat.size, Vector2(400, 400), "opening or resizing Maps retains native map pixels and a matching parchment mat")
		assert_true(absf(note.global_position.y - mat.get_global_rect().end.y - 4.0 * profile.ui_scale) <= 1.0, "the description follows the map background immediately without expanded blank space")
		assert_equal(map_scroll.get_v_scroll_bar().visible, map_scroll.get_child(0).get_combined_minimum_size().y > map_scroll.size.y + 1.0, "map scrolling appears only when its content exceeds the viewport")
		(screen.find_child("PlayerMapZoomIn", true, false) as Button).pressed.emit()
		(screen.find_child("PlayerMapZoomIn", true, false) as Button).pressed.emit()
		for frame: int in range(4): await tree.process_frame
		assert_equal(mat.size, Vector2(800, 800), "map zoom resizes the canvas and all four parchment borders together")
		(screen.find_child("PlayerMapZoomFit", true, false) as Button).pressed.emit()
		for frame: int in range(4): await tree.process_frame
	viewport.free()
