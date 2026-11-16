extends RealmzTestCase

## Interface themes: role recolouring, the stored preference, and live application to menu-style screens.


func run() -> void:
	_test_palette()
	_test_setting()
	_test_vital_colors()
	_test_hud_scales()
	_test_default_layouts()
	_test_edge_flash()
	await _test_service()
	_test_sounds()


func _test_palette() -> void:
	var base := UiThemeCatalog.default_palette()
	var ice := UiThemeCatalog.by_id("slate-ice")
	assert_equal(UiThemeCatalog.by_id("no-such-theme").id, UiThemeCatalog.DEFAULT_ID, "an unknown theme id falls back to the default")
	var adopted := UiThemePalette.new("slate", "Art test", ["000000", "000000", "000000", "000000", "000000", "000000", "000000", "000000", "000000", "000000", "000000", "000000"])
	UiThemeCatalog.adopt_theme_art(adopted, "res://src/ui/shared/assets/ui/theme-")
	assert_true(adopted.background_texture == "res://src/ui/shared/assets/ui/theme-slate-tile.png" and UiThemeCatalog.by_id("slate-gold").background_texture == UiThemeCatalog.SLATE_TILE and adopted.background_dim == UiThemeCatalog.DEFAULT_TILE_DIM and adopted.frame_texture.is_empty(), "a theme adopts a tile named after its id and keeps the shared frame when it has none of its own")
	assert_true(UiThemeCatalog.by_id("ember").background_texture.ends_with("themes/ember-tile.png") and UiThemeCatalog.by_id("ember").frame_style == &"forged" and base.background_texture.is_empty() and base.frame_style == &"plain", "themes pick up their own tiles and frames while the default theme stays plain")
	assert_true(UiThemeCatalog.options().size() == UiThemeCatalog.all().size() and UiThemeCatalog.all().size() >= 5, "every theme is offered as an option")
	assert_equal(ice.recolor(base.colors[&"accent"], base), ice.colors[&"accent"], "a role colour becomes the same role in the new theme")
	var veil := ice.recolor(Color(base.colors[&"surface"], 0.4), base)
	assert_true(is_equal_approx(veil.a, 0.4) and veil.is_equal_approx(Color(ice.colors[&"surface"], 0.4)), "recolouring keeps the authored alpha")
	var hover := base.colors[&"accent"].lightened(0.2)
	var shifted := ice.recolor(hover, base)
	assert_true(shifted.get_luminance() > ice.colors[&"accent"].get_luminance(), "a lighter shade of a role stays lighter than that role")
	assert_equal(base.recolor(hover, base), hover, "the default theme leaves authored colours alone")


func _test_hud_scales() -> void:
	var fresh := PresentationSettings.new()
	assert_true(is_equal_approx(fresh.combat_hud.panels[0].scale, 1.0) and is_equal_approx(fresh.combat_hud.panels[1].scale, 1.25) and is_equal_approx(fresh.combat_hud.panels[2].scale, 1.25) and is_equal_approx(fresh.combat_hud.panels[3].scale, 1.5) and is_equal_approx(fresh.combat_hud.extra_panels[1].scale, 1.5) and is_equal_approx(fresh.hud.panels[2].scale, 1.0), "the combat card and turn order start a quarter larger and the command groups half as large again, while the roster and the overworld HUD keep their ordinary size")
	fresh.hud.panels[2].scale = 1.25
	fresh.combat_hud.extra_panels[0].scale = 2.0
	var loaded := PresentationSettings.from_data(fresh.to_data())
	assert_true(is_equal_approx(loaded.hud.panels[2].scale, 1.25) and is_equal_approx(loaded.combat_hud.extra_panels[0].scale, 2.0) and is_equal_approx(loaded.combat_hud.panels[1].scale, 1.25), "each panel's scale round-trips, the combat extras included")
	var older := fresh.to_data()
	for panel: Dictionary in older["combatHud"]["panels"]:
		panel.erase("scale")
	older["combatHud"].erase("extraPanels")
	older["combatHud"].erase("bucketCount")
	var adopted := PresentationSettings.from_data(older)
	assert_true(adopted != null and is_equal_approx(adopted.combat_hud.panels[3].scale, 1.5) and is_equal_approx(adopted.combat_hud.extra_panels[0].scale, 1.5) and is_equal_approx(adopted.combat_hud.panels[0].scale, 1.0), "a combat HUD saved before scales existed takes the larger default")
	var wild := fresh.to_data()
	wild["hud"]["panels"][0]["scale"] = 9.0
	assert_true(PresentationSettings.from_data(wild) == null and is_equal_approx(fresh.hud.panels[2].stepped_scale(1), 1.5) and is_equal_approx(HudPanelPreferences.new().stepped_scale(-1), 0.75) and is_equal_approx(fresh.combat_hud.extra_panels[0].stepped_scale(1), 2.0), "an out-of-range scale is rejected and stepping stays within 75 to 200 percent")


func _test_default_layouts() -> void:
	var fresh := PresentationSettings.new()
	assert_true(not fresh.hud.modular and not fresh.combat_hud.modular and fresh.hud.panels[0].custom_position and fresh.hud.status_strip_custom_position and fresh.hud.strip_orientations == ["vertical", "horizontal", "auto"], "a new profile starts on the Fixed HUD with the project's modular arrangement ready for the map")
	assert_true(is_equal_approx(fresh.combat_hud.panel_at(1).scale, 1.25) and is_equal_approx(fresh.combat_hud.panel_at(3).scale, 1.5) and fresh.combat_hud.bucket_count == 4 and fresh.combat_hud.panels[0].auto_hide, "and with the project's combat pieces, sizes and tucked-away roster")
	var round_trip := PresentationSettings.from_data(fresh.to_data())
	assert_true(round_trip != null and round_trip.hud.to_data() == fresh.hud.to_data() and round_trip.combat_hud.to_data() == fresh.combat_hud.to_data(), "the default arrangements survive saving and loading unchanged")
	assert_true(not HudPreferences.new().modular and not HudPreferences.new().panels[0].custom_position, "the plain base that saved settings are read over stays the docked Fixed arrangement")


func _test_vital_colors() -> void:
	assert_true(RosterVitalColors.stamina_text(1.0) == Color.WHITE and RosterVitalColors.stamina_text(0.25).is_equal_approx(RosterVitalColors.STAMINA_TEXT_LOW) and RosterVitalColors.stamina_text(0.6).g < 1.0 and RosterVitalColors.stamina_text(0.6).g > RosterVitalColors.stamina_text(0.4).g, "stamina numbers redden steadily as stamina falls and are fully red at a quarter")
	assert_true(RosterVitalColors.stamina_bar(1.0).is_equal_approx(RosterVitalColors.STAMINA_BAR_FULL) and RosterVitalColors.stamina_bar(0.0).is_equal_approx(RosterVitalColors.STAMINA_BAR_LOW), "the dock's stamina bar follows the same scale")
	assert_true(RosterVitalColors.spell_text(1.0) == Color.WHITE and RosterVitalColors.spell_text(0.0).is_equal_approx(RosterVitalColors.SPELL_TEXT_LOW) and RosterVitalColors.spell_text(0.5).get_luminance() > RosterVitalColors.spell_text(0.2).get_luminance() and RosterVitalColors.spell_bar(0.0).is_equal_approx(RosterVitalColors.SPELL_BAR_LOW) and RosterVitalColors.spell_bar(0.5).get_luminance() < RosterVitalColors.spell_bar(1.0).get_luminance(), "spell points darken towards purple the closer they are to zero, on the number and the bar")


func _edge_view(health: int, condition: int = -1) -> GameView:
	var state := CharacterState.new("edge.hero", "Hero", health, 20)
	if condition >= 0:
		state.conditions.set_value(condition, 3)
	var view := GameView.new(1, true, null)
	view.party_members = [CharacterView.new(state)]
	return view


func _test_edge_flash() -> void:
	assert_equal([ScreenEdgeFlash.cause(_edge_view(20), _edge_view(14)), ScreenEdgeFlash.cause(_edge_view(14), _edge_view(20)), ScreenEdgeFlash.cause(_edge_view(20), _edge_view(20)), ScreenEdgeFlash.cause(null, _edge_view(5))], [&"harm", &"", &"", &""], "stamina lost is harm; healing, no change and a first view are quiet")
	assert_equal([ScreenEdgeFlash.cause(_edge_view(20), _edge_view(20, ConditionRules.POISONED)), ScreenEdgeFlash.cause(_edge_view(20, ConditionRules.POISONED), _edge_view(18, ConditionRules.POISONED)), ScreenEdgeFlash.cause(_edge_view(20), _edge_view(20, ConditionRules.DISEASED)), ScreenEdgeFlash.cause(_edge_view(20, ConditionRules.POISONED), _edge_view(20, ConditionRules.POISONED))], [&"poison", &"poison", &"disease", &""], "poison and disease are named when they start or cost stamina, and a standing condition is quiet")
	var settings := PresentationSettings.new()
	var saved := settings.to_data()
	saved.erase("harmEdgeFlash")
	assert_true(settings.harm_edge_flash and PresentationSettings.from_data(saved).harm_edge_flash, "the edge glow is on by default and for settings saved before it existed")
	settings.harm_edge_flash = false
	assert_true(not PresentationSettings.from_data(settings.to_data()).harm_edge_flash, "the edge glow choice round-trips")
	var flash := (load("res://src/ui/shell/screen_edge_flash.tscn") as PackedScene).instantiate() as ScreenEdgeFlash
	(Engine.get_main_loop() as SceneTree).root.add_child(flash)
	flash.observe(_edge_view(20), _edge_view(14), settings)
	var quiet := flash.strength()
	settings.harm_edge_flash = true
	flash.observe(_edge_view(14), _edge_view(10), settings)
	assert_true(is_zero_approx(quiet) and is_equal_approx(flash.strength(), ScreenEdgeFlash.PEAK) and flash.mouse_filter == Control.MOUSE_FILTER_IGNORE, "harm lights the edge only while the setting is on, and the glow never takes input")
	var blow := CombatPlaybackFrame.new(&"result", 0.4)
	blow.combatant_health = {"edge.hero": 9}
	var timed := (load("res://src/ui/shell/screen_edge_flash.tscn") as PackedScene).instantiate() as ScreenEdgeFlash
	(Engine.get_main_loop() as SceneTree).root.add_child(timed)
	var steady := CombatPlaybackFrame.new(&"move", 0.2)
	steady.combatant_health = {"edge.hero": 14}
	timed.observe_frame(steady, _edge_view(14), settings)
	var before_blow := timed.strength()
	timed.observe_frame(blow, _edge_view(14), settings)
	assert_true(is_zero_approx(before_blow) and is_equal_approx(timed.strength(), ScreenEdgeFlash.PEAK) and ScreenEdgeFlash.cause(_edge_view(14), _edge_view(9), {"edge.hero": 9}) == &"", "a blow glows as its playback frame arrives and is not counted again when the turn settles")
	timed.free()
	settings.reduced_motion = true
	flash.observe(_edge_view(10), _edge_view(6), settings)
	assert_true(is_equal_approx(flash.strength(), ScreenEdgeFlash.STILL_PEAK), "reduced motion shows a fainter, steady glow")
	flash.free()


func _test_setting() -> void:
	var settings := PresentationSettings.new()
	assert_equal(settings.interface_theme, PresentationSettings.DEFAULT_INTERFACE_THEME, "fresh settings use the default interface theme")
	settings.interface_theme = "slate-gold"
	var data := settings.to_data()
	assert_equal(PresentationSettings.from_data(data).interface_theme, "slate-gold", "the chosen interface theme round-trips")
	var older := data.duplicate(true)
	older["schemaVersion"] = 28
	older.erase("interfaceTheme")
	assert_equal(PresentationSettings.from_data(older).interface_theme, PresentationSettings.AUTHORED_INTERFACE_THEME, "schema-28 settings keep the authored look they were using")
	assert_true(settings.theme_surface_tile and settings.theme_surface_tile_opacity_percent == 25 and PresentationSettings.from_data(older) != null and PresentationSettings.from_data(older).theme_surface_tile, "the panel texture is on by default at 25 percent, and settings saved without it load with it on")
	settings.theme_surface_tile = false
	settings.theme_surface_tile_opacity_percent = 40
	var textured := PresentationSettings.from_data(settings.to_data())
	assert_true(not textured.theme_surface_tile and textured.theme_surface_tile_opacity_percent == 40, "the panel texture choice and strength round-trip")
	var off_step := settings.to_data()
	off_step["themeSurfaceTileOpacityPercent"] = 133
	assert_true(PresentationSettings.from_data(off_step) == null, "an out-of-range panel texture strength is rejected")
	var broken := data.duplicate(true)
	broken["interfaceTheme"] = ""
	assert_true(PresentationSettings.from_data(broken) == null, "an empty theme id is rejected")


func _test_service() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var base := UiThemeCatalog.default_palette()
	var ice := UiThemeCatalog.by_id("slate-ice")
	var vault := load("res://src/ui/characters/vault_theme.tres") as Theme
	var root := Panel.new()
	root.theme = vault
	root.add_to_group(UiThemeService.BACKDROP_GROUP)
	root.add_to_group(UiThemeService.FRAME_GROUP)
	var label := Label.new()
	label.add_theme_color_override(&"font_color", base.colors[&"accent"])
	var card := StyleBoxFlat.new()
	card.bg_color = base.colors[&"surface"]
	card.border_color = base.colors[&"border"]
	var panel := Panel.new()
	panel.add_theme_stylebox_override(&"panel", card)
	root.add_child(label)
	root.add_child(panel)
	var fill := ColorRect.new()
	fill.color = base.colors[&"good"]
	root.add_child(fill)
	# A classic subtree inside a menu screen: its own theme keeps it out of the interface theme.
	var classic_host := Control.new()
	classic_host.theme = Theme.new()
	var classic_label := Label.new()
	classic_label.add_theme_color_override(&"font_color", base.colors[&"accent"])
	classic_host.add_child(classic_label)
	root.add_child(classic_host)
	var outside := Label.new()
	outside.add_theme_color_override(&"font_color", base.colors[&"accent"])
	tree.root.add_child(root)
	tree.root.add_child(outside)
	var authored_gold := vault.get_color(&"font_color", &"VaultStatusGold")
	UiThemeService.apply(tree, "slate-ice")
	assert_equal(UiThemeService.current().id, "slate-ice", "the service reports the applied theme")
	assert_true(label.get_theme_color(&"font_color").is_equal_approx(ice.colors[&"accent"]), "a colour override under a themed screen is recoloured")
	assert_true(card.bg_color.is_equal_approx(ice.colors[&"surface"]) and card.border_color.is_equal_approx(ice.colors[&"border"]), "a style override under a themed screen is recoloured")
	assert_true(vault.get_color(&"font_color", &"VaultStatusGold").is_equal_approx(ice.recolor(authored_gold, base)), "the shared theme's own colours are recoloured")
	assert_true(outside.get_theme_color(&"font_color").is_equal_approx(base.colors[&"accent"]), "controls outside menu-style screens keep their colours")
	var backdrop := root.get_node_or_null(^"UiThemeBackdrop") as UiThemeBackdrop
	assert_true(backdrop != null and backdrop.visible and root.get_child_count() == 4, "a backdrop node gains the theme's tiled background without changing its ordinary children")
	assert_true(fill.color.is_equal_approx(ice.colors[&"good"]) and classic_label.get_theme_color(&"font_color").is_equal_approx(base.colors[&"accent"]), "a colour fill is recoloured, and a subtree with its own theme inside a menu screen is not")
	var classic_style := StyleBoxFlat.new()
	classic_style.bg_color = base.colors[&"surface"]
	var menu_style := classic_style.duplicate() as StyleBoxFlat
	UiThemeService.restyle_for(outside, classic_style)
	UiThemeService.restyle_for(panel, menu_style)
	assert_true(classic_style.bg_color.is_equal_approx(base.colors[&"surface"]) and menu_style.bg_color.is_equal_approx(ice.colors[&"surface"]), "a style resized for a classic control keeps its colours; one for a menu control takes the theme")
	var late := Label.new()
	late.add_theme_color_override(&"font_color", base.colors[&"accent"])
	root.add_child(late)
	var fresh := StyleBoxFlat.new()
	fresh.bg_color = base.colors[&"raised"]
	panel.add_theme_stylebox_override(&"panel", fresh)
	await tree.process_frame
	assert_true(late.get_theme_color(&"font_color").is_equal_approx(ice.colors[&"accent"]) and fresh.bg_color.is_equal_approx(ice.colors[&"raised"]), "a control added later and a style a script swaps in later both take the theme on the next frame")
	UiThemeService.apply(tree, "slate-ice")
	await tree.process_frame
	assert_true(root.get_children(true).filter(func(child: Node) -> bool: return child is UiThemeBackdrop).size() == 1 and late.get_theme_color(&"font_color").is_equal_approx(ice.colors[&"accent"]), "applying the same theme again changes nothing and adds no second backdrop")
	var frame := root.get_node_or_null(^"UiThemeFrame") as UiThemeFrame
	assert_true(frame != null and frame.visible, "a frame node gains the theme's ornamental frame")
	assert_true(root.get_node_or_null(^"UiThemeTile") == null, "panels stay flat until the panel texture is switched on")
	UiThemeService.set_surface_tile(tree, true, 10)
	var tile := root.get_node_or_null(^"UiThemeTile") as UiThemeTile
	assert_true(tile != null and tile.visible and tile.get_index(true) < frame.get_index(true), "the panel texture lays the theme's tile on a framed panel, beneath its content and frame")
	UiThemeService.set_surface_tile(tree, false, 10)
	assert_true(not tile.visible, "switching the panel texture off returns framed panels to their flat surface")
	var well := PanelContainer.new()
	well.add_to_group(UiThemeService.TEXTURE_GROUP)
	tree.root.add_child(well)
	await tree.process_frame
	UiThemeService.set_surface_tile(tree, true, 10)
	var well_tile := well.get_node_or_null(^"UiThemeTile") as UiThemeTile
	assert_true(well_tile != null and well_tile.visible and well.get_node_or_null(^"UiThemeFrame") == null, "an unframed surface in the texture group takes the tile without a frame, even outside a menu-style screen")
	var late_well := PanelContainer.new()
	late_well.add_to_group(UiThemeService.TEXTURE_GROUP)
	tree.root.add_child(late_well)
	await tree.process_frame
	assert_true(late_well.get_node_or_null(^"UiThemeTile") != null, "a textured surface added later takes the tile on the next frame")
	UiThemeService.set_surface_tile(tree, false, 10)
	assert_true(not well_tile.visible, "switching the panel texture off clears unframed surfaces as well")
	well.free()
	late_well.free()
	var copy := card.duplicate() as StyleBoxFlat
	UiThemeService.restyle(copy)
	assert_true(copy.bg_color.is_equal_approx(ice.colors[&"surface"]), "a copied style stays in the current theme instead of being recoloured twice")
	var classic := load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme
	var application := ClassicTypography.themed_copy(classic, PresentationSettings.new())
	var heading := classic.get_color(&"font_color", &"MenuHeading")
	assert_true(application.get_color(&"font_color", &"MenuHeading").is_equal_approx(ice.recolor(heading, base)) and heading.get_luminance() > 0.5 and not application.get_color(&"font_color", &"MenuHeading").is_equal_approx(heading) and application.get_color(&"font_color", &"MenuButton").is_equal_approx(ice.recolor(classic.get_color(&"font_color", &"MenuButton"), base)), "an application theme copy takes the theme on its menu and classic types alike, and the authored classic theme is untouched")
	UiThemeService.apply(tree, "slate-gold")
	assert_true(label.get_theme_color(&"font_color").is_equal_approx(UiThemeCatalog.by_id("slate-gold").colors[&"accent"]), "switching themes recolours from the authored colour, not the previous theme")
	label.add_theme_color_override(&"font_color", base.colors[&"bad"])
	await tree.process_frame
	assert_true(label.get_theme_color(&"font_color").is_equal_approx(UiThemeCatalog.by_id("slate-gold").colors[&"bad"]), "a colour a script sets later is treated as newly authored")
	UiThemeService.apply(tree, UiThemeCatalog.DEFAULT_ID)
	assert_true(fresh.bg_color.is_equal_approx(base.colors[&"raised"]) and vault.get_color(&"font_color", &"VaultStatusGold").is_equal_approx(authored_gold) and not backdrop.visible and not frame.visible, "returning to the default theme restores every authored colour and hides the background and frame")
	UiThemeService.restyle_for(panel, copy)
	assert_true(copy.bg_color.is_equal_approx(base.colors[&"surface"]), "a style copied while a theme was shown returns to its authored colours when reused under the default theme")
	var untouched := StyleBoxFlat.new()
	untouched.bg_color = base.colors[&"surface"]
	UiThemeService.restyle(untouched)
	assert_true(fill.color.is_equal_approx(base.colors[&"good"]) and not untouched.has_meta(UiThemeService.AUTHORED), "the default theme switches the service off again")
	root.queue_free()
	outside.queue_free()


func _test_sounds() -> void:
	var expected := {"Apply changes": &"apply", "Save revision": &"apply", "‹ Back": &"cancel", "Discard": &"cancel", "Edit save…": &"confirm", "Begin adventure": &""}
	var matched := true
	for text: String in expected:
		var button := Button.new()
		button.text = text
		matched = matched and UiSoundService.sound_for(button) == expected[text]
		button.free()
	var toggle := CheckButton.new()
	toggle.text = "CRT effect"
	matched = matched and UiSoundService.sound_for(toggle) == &"toggle"
	toggle.free()
	assert_true(matched, "buttons pick their interface sound from their label and kind")
	var present := true
	for sound: StringName in UiSoundService.SOUNDS:
		present = present and ResourceLoader.exists("%sui-%s.wav" % [UiSoundService.SOUND_DIR, sound])
	assert_true(present, "every interface sound has its file")
