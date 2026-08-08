extends RealmzTestCase


func run() -> void:
	_test_route_catalog()
	_test_layout_profiles()
	_test_settings_schema_and_migration()
	_test_safe_item_display()
	_test_action_availability()
	_test_fixture_gallery_coverage()
	_test_interaction_identity()
	_test_classic_choice_context()
	_test_classic_asset_catalog()
	_test_stone_surface_tiling()
	_test_spatial_stage_visibility()
	_test_scene_composition()


func _test_route_catalog() -> void:
	assert_equal(UiRouteCatalog.ROUTES.size(), 9, "the canonical route registry contains all nine workspaces")
	var ids: Dictionary = {}
	var shortcuts: Dictionary = {}
	var primary_count: int = 0
	for route: Dictionary in UiRouteCatalog.ROUTES:
		ids[route["id"]] = true
		shortcuts[route["shortcut"]] = true
		primary_count += 1 if bool(route["primary"]) else 0
		assert_false(String(route.get("description", "")).is_empty(), "every route has presentation guidance")
		assert_true(ResourceLoader.exists(String(route.get("scene", "")), "PackedScene"), "every route owns a scene-backed workspace")
	assert_equal(ids.size(), 9, "route identifiers are unique")
	assert_equal(shortcuts.size(), 9, "route shortcuts are unique")
	assert_equal(primary_count, 6, "compact and standard layouts keep six primary workspaces")


func _test_layout_profiles() -> void:
	assert_equal(UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.COMPACT, "800x600 uses compact layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.STANDARD, "960x600 uses standard layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1280, 720), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1280x720 uses wide layout")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1920, 1080), PresentationSettings.UI_SCALE_AUTO).id, UiLayoutProfile.WIDE, "1920x1080 remains wide after automatic density")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_125), 1.25, "explicit interface density is independent of viewport")
	assert_equal(UiLayoutProfile.scale_for(Vector2(800, 600), PresentationSettings.UI_SCALE_150), 1.5, "150 percent interface density is supported")
	var compact := UiLayoutProfile.for_viewport(Vector2(800, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(compact.party_width, 208.0, "compact Classic roster uses the specified width")
	assert_equal(compact.bottom_height, 156.0, "compact Classic textbox uses the specified height")
	var standard := UiLayoutProfile.for_viewport(Vector2(960, 600), PresentationSettings.UI_SCALE_AUTO)
	assert_equal(standard.party_width, 256.0, "standard Classic roster uses the specified width")
	assert_equal(standard.bottom_height, 176.0, "standard Classic textbox uses the specified height")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1600, 900), PresentationSettings.UI_SCALE_AUTO).bitmap_scale, 2, "large automatic layouts may use exact 2x bitmap controls")
	assert_equal(UiLayoutProfile.for_viewport(Vector2(1599, 899), PresentationSettings.UI_SCALE_AUTO).bitmap_scale, 1, "bitmap controls remain 1x below the approved threshold")


func _test_settings_schema_and_migration() -> void:
	var settings := PresentationSettings.new()
	settings.ui_scale_mode = PresentationSettings.UI_SCALE_125
	settings.window_mode = PresentationSettings.BORDERLESS_FULLSCREEN
	settings.text_scale = 1.5
	var restored := PresentationSettings.from_data(settings.to_data())
	assert_not_null(restored, "schema-three presentation settings round-trip")
	assert_equal(restored.ui_scale_mode, PresentationSettings.UI_SCALE_125, "interface density persists separately")
	assert_equal(restored.window_mode, PresentationSettings.BORDERLESS_FULLSCREEN, "window mode persists")
	assert_equal(restored.text_scale, 1.5, "text scale remains independent")
	var version_two := PresentationSettings.from_data({"kind": "realmz2.presentation-settings", "schemaVersion": 2, "masterVolume": 0.5, "topologyDebug": false, "textScale": 1.0, "reducedMotion": false, "dungeon3d": true})
	assert_not_null(version_two, "schema-two settings migrate")
	assert_equal(version_two.ui_scale_mode, PresentationSettings.UI_SCALE_AUTO, "migrated settings default to automatic interface density")
	assert_equal(version_two.window_mode, PresentationSettings.WINDOWED, "migrated settings retain windowed behavior")


func _test_safe_item_display() -> void:
	var definition := ItemDefinition.new("classic.item.607", 607, "Improvement", "Potion", "Raises a random attribute.")
	definition.icon_id = 555
	definition.cost = 7500
	definition.initial_charges = 1
	definition.item_type = 21
	definition.cursed_item_id = "classic.item.608"
	var hidden := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, false), definition)
	assert_equal(hidden.name, "Potion", "unidentified items expose only the player-knowable name")
	assert_false(hidden.description.contains("random attribute"), "unidentified items do not leak effect text")
	assert_equal(hidden.value, 0, "unidentified items do not leak identified value")
	assert_equal(hidden.definition_id, "", "unidentified items do not leak stable definition identity")
	assert_equal(hidden.classic_id, 0, "unidentified items do not leak Classic item identity")
	assert_equal(hidden.icon_id, 555, "the authored content icon identity remains available to presentation")
	assert_equal(hidden.icon_resource_type, "CICN", "item icons carry an exact resource type for collision-free lookup")
	assert_equal(hidden.item_type, 21, "the player-visible item type remains available while identity is hidden")
	var known := ItemView.new(ItemInstance.new("item-607", definition.id, 1, false, true), definition)
	assert_equal(known.name, "Improvement", "identified items expose their identified name")
	assert_contains(known.description, "random attribute", "identified items expose their description")
	assert_equal(known.definition_id, definition.id, "identified items expose their stable definition identity")


func _test_action_availability() -> void:
	var view := GameView.new(1, true, null)
	view.set_action_availability(&"search", true)
	assert_true(view.availability(&"search").enabled, "declared available actions are enabled")
	assert_equal(view.availability(&"search").reason, "", "enabled actions carry no misleading disabled reason")
	var unknown := view.availability(&"imaginary_action")
	assert_false(unknown.enabled, "undeclared actions remain disabled")
	assert_contains(unknown.reason, "unavailable", "undeclared actions explain their state")


func _test_fixture_gallery_coverage() -> void:
	assert_equal(ClassicUiFixtureGallery.screen_cases().size(), 81, "all nine screens have nine fixture states")
	assert_equal(ClassicUiFixtureGallery.interaction_cases().size(), 99, "all eleven interaction kinds have nine fixture states")
	for interaction: StringName in ClassicUiFixtureGallery.INTERACTIONS:
		assert_true(ClassicUiFixtureGallery.request_for(interaction).is_supported_kind(), "gallery interaction %s is a supported typed request" % interaction)


func _test_interaction_identity() -> void:
	var request := InteractionRequest.yes_no("request-identity", "Proceed?", "Yes", "No")
	var response := InteractionPresenter.response_for(request, {"accepted": true})
	assert_equal(response.request_id, request.request_id, "interaction response preserves request identity")
	assert_equal(response.kind, request.kind, "interaction response preserves request kind")
	assert_equal(response.payload, {"accepted": true}, "interaction response preserves the exact selected payload")


func _test_classic_choice_context() -> void:
	var classic_request := InteractionRequest.new("classic-choice", InteractionRequest.YES_NO, {"yesLabel": "Yes", "noLabel": "No"})
	assert_equal(InteractionPresenter._prompt_for(classic_request, "Will you enter the ruined keep?"), "Will you enter the ruined keep?", "a label-only Classic choice retains its source-authored textbox context")
	assert_equal(InteractionPresenter._prompt_for(classic_request, ""), "Choose Yes or No to continue.", "a context-free Classic choice explains the required decision without presenting button labels as a prompt")
	var explicit_request := InteractionRequest.yes_no("explicit-choice", "Enter battle?", "Fight", "Avoid")
	assert_equal(InteractionPresenter._prompt_for(explicit_request, "Stale textbox text"), "Enter battle?", "an explicit typed prompt remains authoritative over prior Classic textbox context")


func _test_classic_asset_catalog() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/classic-ui-assets.json"))
	assert_equal(manifest["source_commit"], "86cf2bf391ef0c43ba31c1633ddd63b7e67e3d61", "Classic controls retain exact Remake commit provenance")
	assert_equal(manifest["assets"].size(), 60, "the curated Classic UI corpus is complete")
	var ids: Dictionary = {}
	for entry: Dictionary in manifest["assets"]:
		ids[entry["id"]] = true
		assert_true(ResourceLoader.exists(entry["path"], "Texture2D"), "Classic bitmap exists: %s" % entry["id"])
		var texture := load(entry["path"]) as Texture2D
		assert_equal(texture.get_width(), int(entry["native_width"]), "Classic bitmap width is unchanged: %s" % entry["id"])
		assert_equal(texture.get_height(), int(entry["native_height"]), "Classic bitmap height is unchanged: %s" % entry["id"])
		assert_equal(_sha256(entry["path"]), entry["sha256"], "Classic bitmap hash is unchanged: %s" % entry["id"])
		assert_equal(entry["rendering"]["allowed_scales"], [1.0, 2.0], "Classic bitmap scaling remains integral")
		assert_false(bool(entry["rendering"]["source_pixels_modified"]), "Classic source pixels are never repainted")
	assert_equal(ids.size(), manifest["assets"].size(), "Classic semantic asset IDs are unique")
	assert_not_null(ClassicUiAssetCatalog.texture(&"command.camp"), "runtime asset catalog resolves the Camp bitmap")
	var fonts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/fonts/font-assets.json"))
	assert_equal(fonts["source_commit"], "2d85e20401920891efb7cd6272d6339685df2820", "bundled fonts retain pinned source provenance")
	for entry: Dictionary in fonts["assets"]:
		assert_equal(_sha256(entry["path"]), entry["sha256"], "bundled font or license hash matches: %s" % entry["id"])


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _test_stone_surface_tiling() -> void:
	var tile_path := "res://src/presentation/assets/ui/classic-charcoal-slate-tile.png"
	var tile_texture := load(tile_path) as Texture2D
	var tile_image := tile_texture.get_image()
	assert_not_null(tile_image, "the derived seamless stone tile loads")
	assert_equal(tile_image.get_size(), Vector2i(512, 512), "the tiled surface retains the selected 512-pixel texture scale")
	var horizontal_edges_match := true
	var vertical_edges_match := true
	for coordinate: int in range(tile_image.get_height()):
		horizontal_edges_match = horizontal_edges_match and tile_image.get_pixel(0, coordinate) == tile_image.get_pixel(tile_image.get_width() - 1, coordinate)
	for coordinate: int in range(tile_image.get_width()):
		vertical_edges_match = vertical_edges_match and tile_image.get_pixel(coordinate, 0) == tile_image.get_pixel(coordinate, tile_image.get_height() - 1)
	assert_true(horizontal_edges_match, "the derived stone tile has identical left and right edge pixels")
	assert_true(vertical_edges_match, "the derived stone tile has identical top and bottom edge pixels")
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	var stone := application.get_node("StoneTexture") as TextureRect
	assert_equal(stone.texture.resource_path, tile_path, "the application background uses the seamless derived tile")
	assert_equal(int(stone.stretch_mode), 1, "the application background tiles instead of scaling")
	assert_equal(int(stone.texture_repeat), 2, "the application background enables texture repeat sampling")
	var stage_frame := application.get_node("ClassicShell/StageFrame") as NinePatchRect
	assert_equal(int(stage_frame.axis_stretch_horizontal), 1, "stage-frame horizontal edges tile instead of stretching")
	assert_equal(int(stage_frame.axis_stretch_vertical), 1, "stage-frame vertical edges tile instead of stretching")
	assert_equal(stage_frame.patch_margin_right, 0, "the stage frame leaves its shared roster boundary open")
	assert_true(stage_frame.texture is AtlasTexture and (stage_frame.texture as AtlasTexture).region.size.x == 520.0, "the open-right stage frame crops only the source texture's eight-pixel right edge")
	application.free()
	var ui_theme := load("res://src/presentation/classic_ui_theme.tres") as Theme
	var menu_normal := ui_theme.get_stylebox("normal", "MenuButton")
	for menu_state: StringName in [&"hover", &"pressed", &"disabled"]:
		var menu_style := ui_theme.get_stylebox(menu_state, "MenuButton")
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			assert_equal(menu_style.get_content_margin(side), menu_normal.get_content_margin(side), "MenuButton %s keeps the measured text margins on every side" % menu_state)
	var open_right_style := ui_theme.get_stylebox("panel", "ClassicOpenRight") as StyleBoxTexture
	assert_true(open_right_style != null and open_right_style.get_texture_margin(SIDE_RIGHT) == 0.0, "shared-stage panels use the open-right frame variation instead of drawing a vertical seam")
	assert_true(ui_theme.get_stylebox("panel", "ClassicSharedStone") is StyleBoxEmpty, "stage overlays expose the already aligned root stone instead of restarting the texture inside another panel")
	var tiled_styles: Array[StyleBox] = [
		ui_theme.get_stylebox("panel", "PanelContainer"),
		ui_theme.get_stylebox("panel", "ClassicInset"),
		ui_theme.get_stylebox("normal", "Button"),
		ui_theme.get_stylebox("hover", "Button"),
		ui_theme.get_stylebox("pressed", "Button"),
		ui_theme.get_stylebox("disabled", "Button"),
	]
	for style: StyleBox in tiled_styles:
		assert_true(style is StyleBoxTexture, "stone-backed panels and buttons use texture styleboxes")
		if style is StyleBoxTexture:
			assert_equal(int(style.axis_stretch_horizontal), 1, "stone stylebox centers tile horizontally")
			assert_equal(int(style.axis_stretch_vertical), 1, "stone stylebox centers tile vertically")


func _test_spatial_stage_visibility() -> void:
	var active_view := GameView.new(1, true, null)
	assert_true(PresentationCoordinator.should_show_spatial_stage(&"exploration", active_view, true), "the map may render only inside an active Explore play stage")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"exploration", active_view, false), "full-stage campaign and party-setup overlays suppress the map beneath their shared-stone surface")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"inventory", active_view, true), "non-Explore workspaces suppress spatial renderers")
	assert_false(PresentationCoordinator.should_show_spatial_stage(&"exploration", GameView.new(0, false, null), true), "an inactive session cannot expose a stale map")


func _test_scene_composition() -> void:
	var shell_scene := load("res://src/presentation/classic_application_shell.tscn") as PackedScene
	var shell := shell_scene.instantiate() as ClassicApplicationShell
	assert_not_null(shell, "the canonical application shell is scene-backed")
	var router := shell.get_node("ScreenRouter") as Control
	var roster := shell.get_node("PartyRoster") as Control
	var bottom_region := shell.get_node("BottomRegion") as Control
	assert_not_null(router, "the shell owns one workspace router")
	assert_not_null(shell.get_node("PartyRoster"), "the shell owns the persistent six-slot roster")
	assert_true((roster as PanelContainer).get_theme_stylebox("panel") is StyleBoxEmpty, "the roster shares the uninterrupted root stone surface instead of restarting a second framed tile at the stage boundary")
	assert_equal((bottom_region as PanelContainer).theme_type_variation, &"ClassicOpenRight", "the bottom narrative region also leaves the shared roster boundary open")
	assert_not_null(shell.get_node("BottomRegion/BottomRow/NarrativeWell"), "the shell owns a Classic narrative well")
	assert_not_null(shell.get_node("BottomRegion/BottomRow/CommandPanel"), "the shell owns a contextual command deck")
	assert_equal(shell.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the structural shell cannot mask earlier root-level interaction controls")
	assert_equal(router.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the full-window router cannot mask menus or sibling controls")
	assert_true(router.get_index() > roster.get_index() and router.get_index() > bottom_region.get_index(), "modal router children are ordered above roster and textbox input regions")
	for viewport_size: Vector2 in [Vector2(800, 600), Vector2(960, 600), Vector2(1280, 720), Vector2(1920, 1080)]:
		var profile := UiLayoutProfile.for_viewport(viewport_size, PresentationSettings.UI_SCALE_AUTO)
		var campaign_rect := ClassicScreenRouter.campaign_rect_for(profile, viewport_size)
		var stage_width := viewport_size.x - profile.party_width
		assert_true(campaign_rect.position.x >= 0.0 and campaign_rect.position.x + campaign_rect.size.x <= stage_width, "campaign controls stay out of the roster hit region at %s" % str(viewport_size))
		assert_true(campaign_rect.position.y >= profile.menu_height and campaign_rect.position.y + campaign_rect.size.y <= viewport_size.y, "campaign controls stay inside the viewport at %s" % str(viewport_size))
	assert_false(shell.has_node("TopBar"), "the dashboard title bar is removed")
	assert_false(shell.has_node("RightPanel"), "the persistent Chronicle column is removed")
	shell.free()
	var application_scene := load("res://src/presentation/realmz_application.tscn") as PackedScene
	var application := application_scene.instantiate() as Control
	assert_true(application.get_node("InteractionPanel").get_index() > application.get_node("ClassicShell").get_index(), "AP and encounter presenter controls are ordered above the shell for mouse input")
	application.free()
	var texture_path := "res://src/presentation/assets/ui/classic-charcoal-slate.png"
	assert_true(ResourceLoader.exists(texture_path, "Texture2D"), "the selected low-contrast stone texture imports as a Godot texture")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://src/presentation/assets/ui/spritecook-assets.json"))
	assert_equal(manifest["selected_asset"]["asset_id"], "3f355030-0f8c-4d4e-b079-26ba8d3dbc32", "the committed texture retains selected SpriteCook provenance")
	assert_equal(manifest["files"].size(), 4, "the selected surface, seamless tile, and two deterministic frames ship together")
	for entry: Dictionary in manifest["files"]:
		assert_equal(_sha256(entry["path"]), entry["sha256"], "generated stone surface hash matches its manifest: %s" % entry["path"])
		var texture := load(entry["path"]) as Texture2D
		assert_equal(texture.get_width(), int(entry["width"]), "generated stone surface width matches its manifest: %s" % entry["path"])
		assert_equal(texture.get_height(), int(entry["height"]), "generated stone surface height matches its manifest: %s" % entry["path"])
