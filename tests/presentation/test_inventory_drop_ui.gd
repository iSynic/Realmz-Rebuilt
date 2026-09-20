## Proves the ordinary Inventory Drop presentation boundary.
extends "res://tests/presentation/classic_ui_test_support.gd"


func run() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-drop-ui", 11, "Drop Test", "Drop Test", "A direct-drop test item.")
	definition.icon_id = 21; var character := CharacterState.new("drop-ui-character", "Alis", 10, 10)
	var view := GameView.new(5, true, null)
	var character_view := CharacterView.new(character)
	var first := ItemView.new(ItemInstance.new("drop-ui.first", definition.id, 0, false, true), definition)
	var second := ItemView.new(ItemInstance.new("drop-ui.second", definition.id, 0, false, true), definition)
	first.actions.drop = ActionAvailabilityView.new(&"drop_item", true); second.actions.drop = ActionAvailabilityView.new(&"drop_item", true)
	character_view.items = [first, second]
	view.party_members = [character_view]
	for index: int in range(5): view.party_members.append(CharacterView.new(CharacterState.new("drop-ui-companion-%d" % index, "Companion %d" % index, 10, 10)))
	var body := (load("res://src/ui/inventory/inventory_screen.tscn") as PackedScene).instantiate() as InventoryScreen; body.theme = ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme, PresentationSettings.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	body.set_workspace_rect(Rect2(0, 0, 1280, 672))
	var controller := InventoryScreenController.new()
	var intents: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new())
	controller.present(body, view, media, 1.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var outer_scroll := body.scroll_control(); var outer_bar := outer_scroll.get_v_scroll_bar()
	assert_true((body.find_child("InventoryCharacterFacts", true, false) as GridContainer).columns == 3 and outer_bar.max_value <= outer_bar.page and (body.find_child("InventoryDone", true, false) as Button).get_global_rect().end.y <= outer_scroll.get_global_rect().end.y, "the six-member Inventory screen keeps selected-item actions and Done inside the themed 1280x720 viewport without outer scrolling")
	var drop_button := body.find_child("DropAction", true, false) as ClassicBitmapButton
	var operation_stage := body.find_child("InventoryOperationStage", true, false) as Control
	assert_true(drop_button != null and not drop_button.disabled and operation_stage != null and not operation_stage.visible, "Inventory exposes Drop as an enabled direct action without the staged operation panel")
	drop_button.command_requested.emit(&"inventory.action.drop")
	assert_equal([intents.size(), intents[0].kind, intents[0].payload.item_id], [1, PlayerIntent.Kind.DROP_ITEM, first.instance_id], "one Drop activation emits exactly one typed Drop intent")
	character_view.items = [second]
	controller.present(body, view, media, 1.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var selected_after_drop := body.find_child("InventoryItem_drop-ui_second", true, false) as Button
	assert_true(selected_after_drop != null and selected_after_drop.button_pressed and not (body.find_child("InventoryOperationStage", true, false) as Control).visible and outer_bar.max_value <= outer_bar.page, "after the committed item disappears, Inventory keeps the character route and selects the next valid row without exposing confirmation controls or outer scrolling")
	body.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
