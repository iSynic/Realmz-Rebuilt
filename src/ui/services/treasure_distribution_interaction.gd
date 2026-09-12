## Presents the dynamic treasure distribution interaction without owning gameplay state.

class_name TreasureDistributionInteraction
extends InteractionComponent

## Presents Treasure assignment, wealth operations, lore actions, and completion confirmation.


signal recipient_selected(character_id: String)
signal money_workspace_visibility_changed(open: bool)

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")
const INK := Color("111315")
const ITEM_DETAIL_POPOVER_SCENE_PATH := "res://src/ui/inventory/classic_item_detail_popover.tscn"

@export var loot_cell_scene: PackedScene
@export var vacant_slot_scene: PackedScene
@export var recipient_button_scene: PackedScene
@export var fact_label_scene: PackedScene
@export var caster_row_scene: PackedScene
@export var recovery_workspace_scene: PackedScene
@export var completion_confirmation_scene: PackedScene
@export var money_workspace_scene: PackedScene

var _compact := false
var _media: ClassicMediaCatalog
var _game_view: GameView
var _loot_slot_order: Array[String] = []
var _selected_recipient_id: String
var _selected_item: InteractionRequestValue.RewardItem
var _item_buttons: Dictionary = {}
var _recipient_buttons: Dictionary = {}
var _selection_rings: Dictionary = {}
var _selected_item_name: Label
var _selected_item_state: Label
var _selected_item_description: Label
var _selected_item_facts: GridContainer
var _transferring := false
var _transfer_item: InteractionRequestValue.RewardItem
var _transfer_origin := Vector2.ZERO
var _detail_popover: CanvasLayer
var _restore_money_workspace := false


func configure(media: ClassicMediaCatalog, game_view: GameView, compact: bool, selected_recipient_id: String = "", loot_slot_order: Array[String] = [], restore_money_workspace: bool = false) -> void:
	_media = media
	_game_view = game_view
	_compact = compact
	_selected_recipient_id = selected_recipient_id
	_loot_slot_order.assign(loot_slot_order)
	_restore_money_workspace = restore_money_workspace


func capture_browser_state() -> Dictionary:
	var scroll := get_node_or_null("%TreasureItemScroll") as ScrollContainer
	if scroll == null:
		return {}
	return {"slotOrder": _loot_slot_order.duplicate(), "lootScroll": scroll.scroll_vertical}


func restore_browser_state(state: Dictionary) -> void:
	var scroll := get_node_or_null("%TreasureItemScroll") as ScrollContainer
	if scroll == null or not state.get("slotOrder") is Array or state.slotOrder != _loot_slot_order:
		return
	scroll.set_deferred("scroll_vertical", int(state.get("lootScroll", 0)))


func build(request: InteractionRequest) -> void:
	var body := request.body as TreasureRequestBody
	if body == null:
		add_hint("The treasure request is malformed.")
		return
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 500.0 if _compact else 0.0)
	_detail_popover = get_node_or_null("ClassicItemDetailPopover") as ClassicItemDetailPopover
	if _detail_popover == null:
		_detail_popover = (load(ITEM_DETAIL_POPOVER_SCENE_PATH) as PackedScene).instantiate() as ClassicItemDetailPopover
		add_child(_detail_popover)
	_detail_popover.configure(_media, get_theme())
	if body.mode != &"ordinary":
		var ordinary := get_node_or_null("%OrdinaryTreasure")
		if ordinary != null:
			remove_child(ordinary)
			ordinary.free()
	match body.mode:
		&"fumbled-item-recovery":
			_build_recovery_workspace(body)
		&"ordinary":
			_build_classic_treasure_workspace(body)
		&"completion-confirmation":
			_build_completion_confirmation(body)
		_:
			add_hint("The treasure request is malformed.")


func preferred_initial_focus() -> Control:
	var recipient := _recipient_buttons.get(_selected_recipient_id) as Control
	return recipient if recipient != null and recipient.visible and not (recipient is BaseButton and (recipient as BaseButton).disabled) else null


func _build_classic_treasure_workspace(body: TreasureRequestBody) -> void:
	_select_initial_recipient(body)
	%TreasureWorkspaceTitle.text = "Victory Spoils" if body.origin == &"battle" else "Treasure"
	%TreasureWorkspaceSummary.text = TreasureDisplayText.summary(body)
	_build_loot_side(body)
	_build_party_side(body)
	_build_item_inspector(body)
	_refresh_item_availability()
	if _restore_money_workspace:
		_open_money_workspace(body)


func _build_loot_side(body: TreasureRequestBody) -> void:
	var scroll := %TreasureItemScroll as ScrollContainer
	var grid := %TreasureItemGrid as GridContainer
	grid.columns = 6 if _compact else 16
	if not _compact:
		scroll.resized.connect(_update_loot_columns.bind(scroll, grid))
		call_deferred("_update_loot_columns", scroll, grid)
	var items_by_id: Dictionary = {}
	for item: InteractionRequestValue.RewardItem in body.items:
		items_by_id[item.instance_id] = item
		if not _loot_slot_order.has(item.instance_id):
			_loot_slot_order.append(item.instance_id)
	%TreasureEmptyField.visible = _loot_slot_order.is_empty()
	grid.visible = not _loot_slot_order.is_empty()
	if not _loot_slot_order.is_empty():
		_selected_item = body.items[0] if not body.items.is_empty() else null
		for slot_id: String in _loot_slot_order:
			var item := items_by_id.get(slot_id) as InteractionRequestValue.RewardItem
			if item != null:
				_add_loot_item(grid, item)
			else:
				_add_vacant_loot_slot(grid, slot_id)


func _build_item_inspector(body: TreasureRequestBody) -> void:
	var inspector := %TreasureItemRecord as BoxContainer
	inspector.vertical = _compact
	inspector.custom_minimum_size.y = 390.0 if _compact else 260.0
	find_child("TreasureItemIdentity", true, false).custom_minimum_size.x = 0.0 if _compact else 360.0
	find_child("TreasureItemProperties", true, false).custom_minimum_size.x = 0.0 if _compact else 360.0
	find_child("TreasureCommandPanel", true, false).custom_minimum_size.x = 0.0 if _compact else 300.0
	var record_icon := %TreasureRecordIcon as TextureRect
	_selected_item_name = %TreasureSelectedItemName as Label
	_selected_item_state = %TreasureSelectedItemState as Label
	_selected_item_description = %TreasureSelectedItemDescription as Label
	_selected_item_facts = %TreasureSelectedItemFacts as GridContainer
	_selected_item_facts.columns = 2 if _compact else 4
	var commands := %TreasureDynamicCommands as VBoxContainer
	_build_compact_commands(commands, body)
	%TreasureDone.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"done")))
	_refresh_item_record(record_icon)


func _update_loot_columns(scroll: ScrollContainer, grid: GridContainer) -> void:
	if scroll == null or grid == null or _compact or not is_inside_tree():
		return
	var host := get_parent() as Control
	var viewport_width := get_viewport_rect().size.x
	var assigned_width := minf(host.size.x, viewport_width) if host != null and host.size.x > 0.0 else viewport_width
	var workspace := %ClassicTreasureWorkspace as HBoxContainer
	var party_panel := %TreasurePartyPanel as PanelContainer
	var loot_margin := %TreasureItemScroll.get_parent() as MarginContainer
	var horizontal_chrome := (
		loot_margin.get_theme_constant("margin_left")
		+ loot_margin.get_theme_constant("margin_right")
		+ scroll.get_v_scroll_bar().get_combined_minimum_size().x
	)
	var loot_width := maxf(50.0, assigned_width - party_panel.custom_minimum_size.x - workspace.get_theme_constant("separation") - horizontal_chrome)
	var cell_pitch := 50.0 + grid.get_theme_constant("h_separation")
	grid.columns = maxi(1, floori((loot_width + grid.get_theme_constant("h_separation")) / cell_pitch))


func _add_loot_item(parent: GridContainer, item: InteractionRequestValue.RewardItem) -> void:
	var cell := loot_cell_scene.instantiate() as Button
	cell.name = "TreasureItem_%s" % _node_fragment(item.instance_id)
	cell.tooltip_text = item.name
	cell.set_meta("reward_item", item)
	parent.add_child(cell)
	var magic_glow := cell.get_node("%MagicGlow") as TextureRect
	if item.magical:
		magic_glow.name = "TreasureMagicGlow_%s" % _node_fragment(item.instance_id)
		magic_glow.texture = ClassicUiAssetCatalog.texture(&"loot.item.glow")
		magic_glow.visible = true
	else:
		magic_glow.get_parent().remove_child(magic_glow)
		magic_glow.free()
	var item_icon := cell.get_node("%ItemIcon") as TextureRect
	item_icon.name = "TreasureLootIcon_%s" % _node_fragment(item.instance_id)
	item_icon.texture = _item_texture(item)
	var ring := cell.get_node("%SelectionRing") as TextureRect
	ring.name = "TreasureHoverCircle_%s" % _node_fragment(item.instance_id)
	ring.texture = ClassicUiAssetCatalog.texture(&"loot.selection")
	_item_buttons[item.instance_id] = cell
	_selection_rings[item.instance_id] = ring
	cell.mouse_entered.connect(_focus_loot_item.bind(item, cell))
	cell.focus_entered.connect(_focus_loot_item.bind(item, cell))
	cell.mouse_exited.connect(_hide_loot_ring.bind(item.instance_id))
	cell.focus_exited.connect(_hide_loot_ring.bind(item.instance_id))
	cell.pressed.connect(_begin_item_transfer.bind(item, cell))
	_detail_popover.bind_hover(cell, TreasureDisplayText.item_detail(item))


func _add_vacant_loot_slot(parent: GridContainer, instance_id: String) -> void:
	var slot := vacant_slot_scene.instantiate() as Control
	slot.name = "TreasureVacantSlot_%s" % _node_fragment(instance_id)
	parent.add_child(slot)


func _build_party_side(body: TreasureRequestBody) -> void:
	find_child("TreasurePartyPanel", true, false).custom_minimum_size.x = 250.0 if _compact else 330.0
	var rows := %TreasureRecipientRows as VBoxContainer
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		_add_recipient_row(rows, character)
	%TreasureMessagePanel.visible = not body.prompt.is_empty()
	%TreasureNarrative.text = body.prompt


func _add_recipient_row(parent: VBoxContainer, character: InteractionRequestValue.RewardCharacter) -> void:
	var button := recipient_button_scene.instantiate() as Button
	button.name = "TreasureRecipient_%s" % character.id
	button.button_pressed = character.id == _selected_recipient_id
	button.text = TreasureDisplayText.recipient(character)
	button.icon = _portrait(character.id)
	button.disabled = not character.enabled
	button.tooltip_text = character.reason
	button.pressed.connect(_select_recipient.bind(character.id))
	parent.add_child(button)
	_recipient_buttons[character.id] = button


func _build_compact_commands(parent: VBoxContainer, body: TreasureRequestBody) -> void:
	%TreasurePooledWealth.text = TreasureDisplayText.wealth(body.wealth)
	var money_rows := body.characters.filter(func(character: InteractionRequestValue.RewardCharacter) -> bool:
		return character.wealth != null and not character.id.is_empty()
	)
	%TreasureMoney.disabled = money_rows.is_empty()
	%TreasureMoney.tooltip_text = "No adventurer wealth is available." if money_rows.is_empty() else "Open the Party Wealth screen."
	%TreasureMoney.pressed.connect(_open_money_workspace.bind(body))
	var has_carried_wealth := body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool:
		return character.wealth != null and (character.wealth.gold > 0 or character.wealth.gems > 0 or character.wealth.jewelry > 0)
	)
	%TreasurePool.disabled = not has_carried_wealth
	%TreasurePool.tooltip_text = "" if has_carried_wealth else "No adventurer carries wealth to pool."
	%TreasurePool.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"pool")))
	var has_pool := body.wealth != null and (body.wealth.gold > 0 or body.wealth.gems > 0 or body.wealth.jewelry > 0)
	%TreasureShare.disabled = not (has_pool and body.has_share_capacity)
	%TreasureShare.tooltip_text = "" if has_pool and body.has_share_capacity else "The pool is empty or no adventurer can carry another unit."
	%TreasureShare.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"share")))
	if body.detect != null and body.detect.visible:
		_add_caster_control(parent, "Detect Magic", &"detect", body.detect)
	if body.identify != null and body.identify.visible:
		_add_caster_control(parent, "Identify", &"identify", body.identify)


func _select_initial_recipient(body: TreasureRequestBody) -> void:
	if body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool: return character.id == _selected_recipient_id and character.enabled):
		return
	_selected_recipient_id = ""
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		if character.enabled:
			_selected_recipient_id = character.id
			break


func _select_recipient(character_id: String) -> void:
	if _transferring or not _recipient_buttons.has(character_id):
		return
	_selected_recipient_id = character_id
	recipient_selected.emit(character_id)
	for id: Variant in _recipient_buttons:
		(_recipient_buttons[id] as Button).set_pressed_no_signal(String(id) == character_id)
	_refresh_item_availability()


func _focus_loot_item(item: InteractionRequestValue.RewardItem, _button: Button) -> void:
	_selected_item = item
	var ring := _selection_rings.get(item.instance_id) as TextureRect
	if ring != null:
		ring.visible = true
	var record_icon := find_child("TreasureRecordIcon", true, false) as TextureRect
	_refresh_item_record(record_icon)
	_refresh_item_availability()


func _hide_loot_ring(instance_id: String) -> void:
	var ring := _selection_rings.get(instance_id) as TextureRect
	var button := _item_buttons.get(instance_id) as Button
	if ring != null and (button == null or not button.has_focus()):
		ring.visible = false


func _refresh_item_record(icon: TextureRect) -> void:
	if _selected_item_name == null or _selected_item_state == null or _selected_item_description == null or _selected_item_facts == null:
		return
	for child: Node in _selected_item_facts.get_children():
		child.queue_free()
	if _selected_item == null:
		_selected_item_name.theme_type_variation = &"ClassicHeading"
		_selected_item_name.add_theme_color_override("font_color", GOLD)
		_selected_item_name.text = "No items remain"
		_selected_item_state.text = ""
		_selected_item_description.text = ""
		if icon != null: icon.texture = null
		return
	_selected_item_name.theme_type_variation = &"ClassicHeading" if _selected_item.identified else &"ClassicUnidentifiedItem"
	if _selected_item.identified:
		_selected_item_name.add_theme_color_override("font_color", GOLD)
	else:
		_selected_item_name.remove_theme_color_override("font_color")
	_selected_item_name.text = _selected_item.name
	_selected_item_state.text = TreasureDisplayText.item_state(_selected_item)
	_selected_item_description.text = _selected_item.description
	for fact: InteractionRequestValue.RewardFact in _selected_item.facts:
		var label := _add_muted_label(_selected_item_facts, fact.label, "TreasureFact_%s" % fact.label.to_snake_case())
		label.add_theme_color_override("font_color", GOLD)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 96.0
		var value := _add_muted_label(_selected_item_facts, fact.value, "TreasureFactValue_%s" % fact.label.to_snake_case())
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if icon != null: icon.texture = _item_texture(_selected_item)


func _refresh_item_availability() -> void:
	for item_id: Variant in _item_buttons:
		var button := _item_buttons[item_id] as Button
		var item := _item_by_id(String(item_id))
		var assignment := _assignment_for(item, _selected_recipient_id)
		button.disabled = _transferring or assignment == null or not assignment.enabled
		button.tooltip_text = item.name if assignment != null and assignment.enabled else "%s — %s" % [item.name, assignment.reason if assignment != null else "Choose an eligible recipient."]


func _begin_item_transfer(item: InteractionRequestValue.RewardItem, source: Button) -> void:
	var assignment := _assignment_for(item, _selected_recipient_id)
	var target := _recipient_buttons.get(_selected_recipient_id) as Button
	if _transferring or assignment == null or not assignment.enabled or target == null:
		return
	_transferring = true
	_transfer_item = item
	_transfer_origin = source.get_global_rect().get_center()
	_refresh_item_availability()
	response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"assign", item.instance_id, _selected_recipient_id))


func take_committed_transfer_path() -> Dictionary:
	if not _transferring or _transfer_item == null:
		return {}
	var path := {
		"from": _transfer_origin,
		"texture": _item_texture(_transfer_item),
		"instanceId": _transfer_item.instance_id,
	}
	_transferring = false
	_transfer_item = null
	_transfer_origin = Vector2.ZERO
	return path


func _assignment_for(item: InteractionRequestValue.RewardItem, character_id: String) -> InteractionRequestValue.RewardAssignment:
	if item == null:
		return null
	for assignment: InteractionRequestValue.RewardAssignment in item.assignments:
		if assignment.character_id == character_id:
			return assignment
	return null


func _item_by_id(instance_id: String) -> InteractionRequestValue.RewardItem:
	if _selected_item != null and _selected_item.instance_id == instance_id:
		return _selected_item
	for child_item_id: Variant in _item_buttons:
		if String(child_item_id) == instance_id:
			var button := _item_buttons[child_item_id] as Button
			var item: Variant = button.get_meta("reward_item") if button.has_meta("reward_item") else null
			return item if item is InteractionRequestValue.RewardItem else null
	return null


func _item_texture(item: InteractionRequestValue.RewardItem) -> Texture2D:
	if _media == null or item == null or item.icon_id == 0:
		return null
	return _media.image_texture(_media.asset_by_resource(item.icon_resource_type, item.icon_id))


func _portrait(character_id: String) -> Texture2D:
	if _game_view == null or _media == null:
		return null
	for character: CharacterView in _game_view.party_members:
		if character.id == character_id and not character.portrait_id.is_empty():
			return _media.image_texture(_media.asset_by_id(character.portrait_id))
	return null


static func _node_fragment(value: String) -> String: return value.replace(".", "_").replace(":", "_").replace("/", "_").replace("@", "_").replace('"', "_")


func _build_recovery_workspace(body: TreasureRequestBody) -> void:
	if body.item == null:
		add_hint("The recovery request is malformed.")
		return
	var workspace := recovery_workspace_scene.instantiate() as VBoxContainer
	add_child(workspace)
	(workspace.get_node("%TreasureWorkspaceSummary") as Label).text = TreasureDisplayText.summary(body)
	var loot_field := workspace.get_node("%TreasureLootField") as CenterContainer
	loot_field.custom_minimum_size.y = 104.0 if _compact else 132.0
	var stage := loot_field.get_node("Stage") as Control
	stage.custom_minimum_size = Vector2(100.0, 96.0) if _compact else Vector2(130.0, 124.0)
	_bind_recovery_item(workspace, body.item)
	var remaining := "No items remain." if body.remaining <= 0 else "This is the final item." if body.remaining == 1 else "%d items remain including this selection." % body.remaining
	(workspace.get_node("%TreasureRemainingItems") as Label).text = remaining
	var prompt := workspace.get_node("%TreasurePrompt") as Label
	prompt.visible = not body.prompt.is_empty()
	prompt.text = body.prompt
	var rows := workspace.get_node("%TreasureRecoveryRecipientRows") as VBoxContainer
	var no_recipients := workspace.get_node("%TreasureNoRecipients") as Label
	no_recipients.visible = body.characters.is_empty()
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		var button := recipient_button_scene.instantiate() as Button
		button.name = "TreasureRecipient_%s" % character.id
		button.toggle_mode = false
		button.text = "Recover to %s" % TreasureDisplayText.recipient(character)
		button.icon = _portrait(character.id)
		button.disabled = not character.enabled
		button.tooltip_text = character.reason
		button.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"assign", body.item.instance_id, character.id)))
		rows.add_child(button)
	var leave := workspace.get_node("%TreasureLeaveItem") as Button
	leave.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"discard", body.item.instance_id)))


func _bind_recovery_item(workspace: VBoxContainer, item: InteractionRequestValue.RewardItem) -> void:
	(workspace.get_node("%TreasureItemGlow") as TextureRect).texture = ClassicUiAssetCatalog.texture(&"loot.item.glow")
	(workspace.get_node("%TreasureSelectionCircle") as TextureRect).texture = ClassicUiAssetCatalog.texture(&"loot.selection")
	var icon := workspace.get_node("%TreasureItemIcon") as TextureRect
	var unavailable := workspace.get_node("%TreasureItemIconUnavailable") as Label
	icon.texture = _item_texture(item)
	icon.tooltip_text = item.name
	icon.visible = icon.texture != null
	unavailable.visible = icon.texture == null
	unavailable.tooltip_text = "Item image unavailable"
	(workspace.get_node("%TreasureSelectedItemName") as Label).text = item.name
	(workspace.get_node("%TreasureSelectedItemState") as Label).text = TreasureDisplayText.item_state(item)
	var charges := workspace.get_node("%TreasureSelectedItemCharges") as Label
	charges.visible = item.charges > 0
	charges.text = "%d charge%s" % [item.charges, "" if item.charges == 1 else "s"]


func _open_money_workspace(body: TreasureRequestBody) -> void:
	var rows: Array[InteractionRequestValue.RewardCharacter] = []
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		if character.wealth != null and not character.id.is_empty():
			rows.append(character)
	if rows.is_empty():
		return
	var workspace := money_workspace_scene.instantiate() as VBoxContainer
	var selector := workspace.get_node("%TreasureMoneyCharacter") as OptionButton
	for row: InteractionRequestValue.RewardCharacter in rows:
		selector.add_item(row.name)
	(workspace.get_node("%TreasureMoneyPoolSummary") as Label).text = TreasureDisplayText.wealth(body.wealth)
	var summary := workspace.get_node("%TreasureMoneySummary") as Label
	var specs: Array[Dictionary] = [
		{"label": "+5 Gold", "direction": "to-character", "kind": "gold", "amount": 5},
		{"label": "-5 Gold", "direction": "to-pool", "kind": "gold", "amount": 5},
		{"label": "+1 Gem", "direction": "to-character", "kind": "gems", "amount": 1},
		{"label": "-1 Gem", "direction": "to-pool", "kind": "gems", "amount": 1},
		{"label": "+1 Jewelry", "direction": "to-character", "kind": "jewelry", "amount": 1},
		{"label": "-1 Jewelry", "direction": "to-pool", "kind": "jewelry", "amount": 1},
	]
	var button_paths := ["TreasureMoneyPane/Content/TreasureMoneyGrid/GoldToCharacter", "TreasureMoneyPane/Content/TreasureMoneyGrid/GoldToPool", "TreasureMoneyPane/Content/TreasureMoneyGrid/GemsToCharacter", "TreasureMoneyPane/Content/TreasureMoneyGrid/GemsToPool", "TreasureMoneyPane/Content/TreasureMoneyGrid/JewelryToCharacter", "TreasureMoneyPane/Content/TreasureMoneyGrid/JewelryToPool"]
	var buttons: Array[Button] = []
	for button_index: int in specs.size():
		var spec: Dictionary = specs[button_index]
		var button := workspace.get_node(button_paths[button_index]) as Button
		button.name = "TreasureMoney_%s_%s" % [spec["direction"], spec["kind"]]
		button.pressed.connect(_submit_money_transfer.bind(selector, rows, String(spec["direction"]), String(spec["kind"]), int(spec["amount"])))
		buttons.append(button)
	selector.item_selected.connect(_refresh_money_workspace.bind(selector, rows, summary, buttons, specs))
	(workspace.get_node("%TreasureMoneyBack") as Button).pressed.connect(_close_money_workspace)
	_refresh_money_workspace(0, selector, rows, summary, buttons, specs)
	money_workspace_visibility_changed.emit(true)
	application_workspace_requested.emit(workspace)


func _add_caster_control(parent: VBoxContainer, label: String, action: StringName, method: InteractionRequestValue.RewardMethod) -> void:
	if method.casters.is_empty():
		add_response_to(parent, label, InteractionResponse.TreasureBody.new(action), false, method.reason if not method.reason.is_empty() else "Unavailable.")
		return
	var row := caster_row_scene.instantiate() as HBoxContainer
	row.name = "Treasure%sRow" % label.replace(" ", "")
	parent.add_child(row)
	var selector := row.get_node("%Caster") as OptionButton
	selector.name = "Treasure%sCaster" % label.replace(" ", "")
	for caster: InteractionRequestValue.RewardCaster in method.casters:
		selector.add_item("%s • SP %d • Cost %d" % [caster.name, caster.spell_points, caster.cost])
	var button := row.get_node("%Action") as Button
	button.name = "Treasure%sAction" % label.replace(" ", "")
	button.text = label
	button.pressed.connect(func() -> void:
		if selector.selected >= 0 and selector.selected < method.casters.size():
			response_body_submitted.emit(InteractionResponse.TreasureBody.new(action, "", method.casters[selector.selected].id))
	)


func _build_completion_confirmation(body: TreasureRequestBody) -> void:
	var panel := completion_confirmation_scene.instantiate() as PanelContainer
	add_child(panel)
	(panel.get_node("%TreasureCompletionSummary") as Label).text = body.summary if not body.summary.is_empty() else "Unclaimed treasure will be left behind."
	(panel.get_node("%TreasureReturn") as Button).pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"cancel-completion")))
	(panel.get_node("%TreasureConfirmLeave") as Button).pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"confirm-completion")))


func _close_money_workspace() -> void:
	money_workspace_visibility_changed.emit(false)
	application_workspace_closed.emit()


func _submit_money_transfer(selector: OptionButton, rows: Array[InteractionRequestValue.RewardCharacter], direction: String, kind: String, amount: int) -> void:
	if selector.selected < 0 or selector.selected >= rows.size():
		return
	response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"transfer", "", rows[selector.selected].id, StringName(direction), StringName(kind), amount))


func _refresh_money_workspace(index: int, selector: OptionButton, rows: Array[InteractionRequestValue.RewardCharacter], summary: Label, buttons: Array[Button], specs: Array[Dictionary]) -> void:
	if index < 0 or index >= rows.size():
		return
	selector.select(index)
	var row := rows[index]
	var carried := row.wealth
	summary.text = "%s: %d gold • %d gems • %d jewelry" % [row.name, carried.gold, carried.gems, carried.jewelry]
	for button_index: int in buttons.size():
		var spec: Dictionary = specs[button_index]
		var enabled := false
		var reason := ""
		if spec["direction"] == "to-character":
			match String(spec["kind"]):
				"gold":
					enabled = row.can_take_gold
					reason = row.gold_reason
				"gems":
					enabled = row.can_take_gems
					reason = row.gems_reason
				"jewelry":
					enabled = row.can_take_jewelry
					reason = row.jewelry_reason
		else:
			var carried_amount := carried.gold if spec["kind"] == "gold" else carried.gems if spec["kind"] == "gems" else carried.jewelry
			enabled = carried_amount >= int(spec["amount"])
			reason = "This adventurer does not carry enough %s." % String(spec["kind"])
		buttons[button_index].disabled = not enabled
		buttons[button_index].tooltip_text = "" if enabled else reason


func _add_muted_label(parent: Container, text: String, label_name: String) -> Label:
	return _add_colored_label(parent, text, MUTED, label_name)


func _add_colored_label(parent: Container, text: String, color: Color, label_name: String) -> Label:
	var label := fact_label_scene.instantiate() as Label
	label.name = label_name
	label.text = text
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
