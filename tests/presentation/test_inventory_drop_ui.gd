## Proves the ordinary Inventory Drop presentation boundary.
extends "res://tests/presentation/classic_ui_test_support.gd"


func run() -> void:
	var definition := ItemDefinition.new("classic.item.inventory-drop-ui", 11, "Drop Test", "Drop Test", "A direct-drop test item.")
	definition.icon_id = 21
	var character := CharacterState.new("drop-ui-character", "Alis", 10, 10)
	var view := GameView.new(5, true, null)
	var character_view := CharacterView.new(character)
	var first := ItemView.new(ItemInstance.new("drop-ui.first", definition.id, 0, false, true), definition)
	var second := ItemView.new(ItemInstance.new("drop-ui.second", definition.id, 0, false, true), definition)
	first.actions.drop = ActionAvailabilityView.new(&"drop_item", true)
	second.actions.drop = ActionAvailabilityView.new(&"drop_item", true)
	character_view.items = [first, second]
	view.party_members = [character_view]
	var body := VBoxContainer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	var controller := InventoryScreenController.new()
	var intents: Array[PlayerIntent] = []
	controller.intent_submitted.connect(func(intent: PlayerIntent) -> void: intents.append(intent))
	var media := ClassicMediaCatalog.new(null, ApplicationMediaCatalog.new())
	controller.present(body, view, media, 1.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var drop_button := body.find_child("DropAction", true, false) as ClassicBitmapButton
	var operation_stage := body.find_child("InventoryOperationStage", true, false) as Control
	assert_true(drop_button != null and not drop_button.disabled and operation_stage != null and not operation_stage.visible, "Inventory exposes Drop as an enabled direct action without the staged operation panel")
	drop_button.command_requested.emit(&"inventory.action.drop")
	assert_equal([intents.size(), intents[0].kind, intents[0].payload.item_id], [1, PlayerIntent.Kind.DROP_ITEM, first.instance_id], "one Drop activation emits exactly one typed Drop intent")
	character_view.items = [second]
	controller.present(body, view, media, 1.0)
	await (Engine.get_main_loop() as SceneTree).process_frame
	var selected_after_drop := body.find_child("InventoryItem_drop-ui_second", true, false) as Button
	assert_true(selected_after_drop != null and selected_after_drop.button_pressed and not (body.find_child("InventoryOperationStage", true, false) as Control).visible, "after the committed item disappears, Inventory keeps the character route and selects the next valid row without exposing confirmation controls")
	body.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
