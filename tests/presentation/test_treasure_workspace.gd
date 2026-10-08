## Proves Treasure slot retention, pickup presentation, and carried-item Drop controls.
extends "res://tests/presentation/classic_ui_test_support.gd"


func run() -> void:
	await _test_treasure_slot_and_pickup_origin()
	await _test_treasure_drop_menu()
	await _test_populated_treasure_scaling()


func _test_populated_treasure_scaling() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	tree.root.add_child(viewport)
	var host := Control.new()
	viewport.add_child(host)
	var settings := PresentationSettings.new()
	var profile := UiLayoutProfile.for_viewport(Vector2(viewport.size), "auto")
	UiSizing.apply(host, profile)
	var presenter := load("res://src/ui/shared/interactions/interaction_presenter.tscn").instantiate() as InteractionPresenter
	host.add_child(presenter)
	UiSizing.bind_added(presenter.get_instance_id())
	var payload := ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"oversized").body.to_data()
	var lore := ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"unidentified").body.to_data()
	payload["detect"] = lore["detect"]
	payload["identify"] = lore["identify"]
	var request := InteractionRequest.from_payload("fixture.treasure.scaling", InteractionRequest.TREASURE_DISTRIBUTION, payload)
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new())
	var native := media.image_texture(media.asset_by_resource("cicn", 40))
	var native_pixels := native.get_image().get_data()
	presenter.present(request, "", null, media)
	var selected := presenter.find_child("TreasureItem_reward_item_3", true, false) as Button
	selected.mouse_entered.emit()
	for setting: Array in [[Vector2i(1280, 720), "auto", 1.0], [Vector2i(1920, 1080), "auto", 1.0], [Vector2i(2560, 1440), "auto", 1.0], [Vector2i(3840, 2160), "auto", 1.0], [Vector2i(800, 600), "auto", 1.5], [Vector2i(1280, 720), "auto", 1.5], [Vector2i(2560, 1440), "300", 1.5], [Vector2i(1280, 720), "auto", 1.0]]:
		viewport.size = setting[0]
		host.size = viewport.size
		settings.text_scale = setting[2]
		profile = UiLayoutProfile.for_viewport(Vector2(viewport.size), setting[1], PresentationSettings.DISPLAY_RESPONSIVE, settings.text_scale)
		host.theme = ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres"), settings, profile.ui_scale)
		UiSizing.apply(host, profile)
		var stage := Rect2(0, profile.menu_height, viewport.size.x - profile.party_width, viewport.size.y - profile.bottom_height - profile.menu_height)
		var footer := Rect2(0, viewport.size.y - profile.bottom_height, viewport.size.x, profile.bottom_height)
		presenter.set_classic_regions(stage, footer, footer)
		for frame: int in 5:
			await tree.process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size)).grow(1.0)
		var scroll := presenter.find_child("TreasureItemScroll", true, false) as ScrollContainer
		var grid := presenter.find_child("TreasureItemGrid", true, false) as GridContainer
		assert_true(bounds.encloses(presenter.get_global_rect()) and grid.get_combined_minimum_size().x <= scroll.size.x, "populated Treasure wraps its actual scaled cells inside the assigned viewport at %s/%s/%s" % setting)
		for control_name: String in ["TreasureDone", "TreasurePartyPanel", "TreasureCommandPanel"]:
			var control := presenter.find_child(control_name, true, false) as Control
			assert_true(control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()), "Treasure keeps %s inside the window during live scaling" % control_name)
		assert_true(grid.get_child_count() == 35 and grid.get_child(2) == selected and (presenter.find_child("TreasureSelectedItemName", true, false) as Label).text == "Fixture Wand 3", "live scaling preserves every loot slot and the inspected item")
	assert_equal(native.get_image().get_data(), native_pixels, "repeated sizing of shared item art never mutates the source pixels")
	viewport.queue_free()
	await tree.process_frame


func _test_treasure_slot_and_pickup_origin() -> void:
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var presenter := load("res://src/ui/shared/interactions/interaction_presenter.tscn").instantiate() as InteractionPresenter
	host.add_child(presenter)
	await (Engine.get_main_loop() as SceneTree).process_frame
	presenter.set_classic_regions(Rect2(0.0, 28.0, 928.0, 532.0), Rect2(330.0, 568.0, 620.0, 152.0), Rect2(0.0, 568.0, 1280.0, 152.0))
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new())
	var request := ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION, &"oversized")
	presenter.present(request, "", null, media)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var source := presenter.find_child("TreasureItem_reward_item_2", true, false) as Button
	var original_grid := presenter.find_child("TreasureItemGrid", true, false) as GridContainer
	var original_third := presenter.find_child("TreasureItem_reward_item_3", true, false) as Button
	var source_center := source.get_global_rect().get_center()
	var original_child_count := original_grid.get_child_count()
	var original_third_index := original_third.get_index()
	source.pressed.emit()
	assert_true(presenter.capture_treasure_transfer(), "a committed Treasure assignment captures its source before the request rebuild")
	var payload := (request.body as TreasureRequestBody).to_data()
	var remaining_items: Array = payload["items"]
	payload["items"] = remaining_items.filter(func(item: Dictionary) -> bool: return item["instanceId"] != "reward.item.2")
	payload["remaining"] = (payload["items"] as Array).size()
	var updated := InteractionRequest.from_payload("fixture.treasure.after-assignment", InteractionRequest.TREASURE_DISTRIBUTION, payload)
	presenter.present(updated, "", null, media)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var updated_grid := presenter.find_child("TreasureItemGrid", true, false) as GridContainer
	var vacant_second := presenter.find_child("TreasureVacantSlot_reward_item_2", true, false) as Control
	var retained_third := presenter.find_child("TreasureItem_reward_item_3", true, false) as Button
	assert_true(updated.request_id != request.request_id and updated_grid.get_child_count() == original_child_count and vacant_second != null and vacant_second.get_index() == 1 and retained_third.get_index() == original_third_index, "a newly issued post-assignment Treasure request leaves an empty authored slot instead of compacting later loot")
	assert_true(presenter.begin_treasure_transfer(false), "the captured Treasure pickup starts after the committed request is presented")
	await (Engine.get_main_loop() as SceneTree).process_frame
	var effect := presenter.find_child("TreasureTakeEffect", true, false) as Control
	assert_true(effect != null and effect.get_parent() is CanvasLayer and effect.get_global_rect().get_center().is_equal_approx(source_center), "the Treasure pickup overlay remains centered on the clicked item instead of being arranged by the interaction container")
	host.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _test_treasure_drop_menu() -> void:
	var payload := (ClassicUiFixtureGallery.request_for(InteractionRequest.TREASURE_DISTRIBUTION).body as TreasureRequestBody).to_data()
	var first: Dictionary = payload["characters"][0]
	first["enabled"] = false
	first["reason"] = "Inventory is full."
	first["dropItems"] = [{"instanceId": "carried.one", "name": "Old boots", "equipped": false, "enabled": true, "reason": ""}, {"instanceId": "carried.cursed", "name": "Cursed mail", "equipped": true, "enabled": false, "reason": "This cursed item cannot be removed."}]
	var request := InteractionRequest.from_payload("fixture.treasure.drop", InteractionRequest.TREASURE_DISTRIBUTION, payload)
	assert_not_null(request, "Treasure Drop retains exact per-character carried-item records through its strict request decoder")
	var component := instantiate_ui_scene("res://src/ui/services/treasure_distribution_interaction.tscn") as TreasureDistributionInteraction
	component.configure(null, null, true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.gui_embed_subwindows = true
	(Engine.get_main_loop() as SceneTree).root.add_child(viewport)
	viewport.add_child(component)
	component.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var submitted: Array[Dictionary] = []
	component.response_body_submitted.connect(func(body: InteractionResponse.Body) -> void: submitted.append(body.to_data()))
	component.build(request)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var recipient := component.find_child("TreasureRecipient_hero-0", true, false) as Button
	var drop := component.find_child("TreasureDrop_hero-0", true, false) as MenuButton
	assert_true(recipient.disabled and not drop.disabled and component.preferred_initial_focus() == drop, "a capacity-blocked recipient still has a focusable Drop menu")
	assert_true(drop.get_theme_stylebox("normal") == recipient.get_theme_stylebox("normal"), "Treasure Drop uses the same raised slate surface as a recipient button")
	assert_false(drop.flat, "Treasure Drop draws its raised button frame")
	assert_true((load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme).get_font("font", "ClassicTreasureDropButton") == load("res://src/ui/shared/assets/fonts/BlackChancery-Realmz.ttf"), "Treasure Drop retains the Classic caption font")
	assert_true(not drop.get_popup().exclusive, "Treasure Drop leaves embedded viewport input available for outside-click dismissal")
	assert_true(drop.get_parent().get_combined_minimum_size().x <= 250.0, "the recipient and Drop control fit the compact Treasure column")
	assert_equal([drop.get_popup().item_count, drop.get_popup().get_item_text(0), drop.get_popup().is_item_disabled(1), drop.get_popup().get_item_tooltip(1)], [2, "Old boots", true, "This cursed item cannot be removed."], "Treasure Drop lists exact items and explains an equipped item that cannot be removed")
	drop.show_popup()
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(drop.get_popup().visible, "the carried-item menu opens in the embedded viewport")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.position = Vector2(40.0, 300.0)
	outside.global_position = outside.position
	outside.pressed = true
	viewport.push_input(outside)
	outside.pressed = false
	viewport.push_input(outside)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_true(not drop.get_popup().visible and submitted.is_empty(), "clicking outside the open Treasure Drop menu dismisses it without dropping an item")
	drop.get_popup().id_pressed.emit(1)
	drop.show_popup()
	await (Engine.get_main_loop() as SceneTree).process_frame
	var item_click := InputEventMouseButton.new()
	item_click.button_index = MOUSE_BUTTON_LEFT
	item_click.position = Vector2(drop.get_popup().position) + Vector2(drop.get_popup().size.x * 0.5, 12.0)
	item_click.global_position = item_click.position
	item_click.pressed = true
	viewport.push_input(item_click)
	item_click.pressed = false
	viewport.push_input(item_click)
	await (Engine.get_main_loop() as SceneTree).process_frame
	assert_equal(submitted, [{"action": "drop", "instanceId": "carried.one", "characterId": "hero-0"}], "Treasure Drop submits only the enabled exact character and item identity")
	viewport.free()
