## Presents the dynamic treasure distribution interaction without owning gameplay state.

class_name TreasureDistributionInteraction
extends InteractionComponent

## Presents Treasure assignment, wealth operations, lore actions, and completion confirmation.


signal recipient_selected(character_id: String)
signal money_workspace_visibility_changed(open: bool)
## The open Money workspace absorbed refreshed requests; the presenter rebuilds Treasure from the latest one.
signal stale_request_rebuild_requested

const GOLD := Color("e5c45c")
const CYAN := Color("8fcfd1")
const MUTED := Color("aeb6ba")
const INK := Color("111315")
const ITEM_DETAIL_POPOVER_SCENE_PATH := "res://src/ui/inventory/classic_item_detail_popover.tscn"

@export var loot_cell_scene: PackedScene
@export var vacant_slot_scene: PackedScene
@export var recipient_button_scene: PackedScene
@export var recipient_row_scene: PackedScene
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
var _item_buttons: Dictionary[String, Button] = {}
## The item each retained loot cell currently presents, keyed by instance ID.
var _loot_items: Dictionary[String, InteractionRequestValue.RewardItem] = {}
var _recipient_buttons: Dictionary[String, Button] = {}
var _drop_buttons: Dictionary[String, MenuButton] = {}
var _selection_rings: Dictionary[String, TextureRect] = {}
var _selected_item_name: Label
var _selected_item_state: Label
var _selected_item_description: Label
var _selected_item_facts: GridContainer
var _transferring := false
var _transfer_item: InteractionRequestValue.RewardItem
var _transfer_origin := Vector2.ZERO
var _detail_popover: CanvasLayer
var _restore_money_workspace := false
var _money: TreasureMoneyBinder
var _body: TreasureRequestBody
var _drop_items: Dictionary[String, Array] = {}
## Set when closing a stale Money workspace so the rebuilt Treasure focuses its Money button.
var _focus_money_on_return := false


func configure(media: ClassicMediaCatalog, game_view: GameView, compact: bool, selected_recipient_id: String = "", loot_slot_order: Array[String] = [], restore_money_workspace: bool = false) -> void:
	_media = media
	_game_view = game_view
	_compact = compact
	_selected_recipient_id = selected_recipient_id
	_loot_slot_order.assign(loot_slot_order)
	_restore_money_workspace = restore_money_workspace


func set_layout_profile(compact: bool) -> void:
	_compact = compact
	if get_node_or_null("OrdinaryTreasure") == null:
		var recovery := find_child("TreasureRecoveryCard", true, false) as Control
		if recovery != null: UiSizing.minimum_size(recovery, Vector2(620.0 if compact else 760.0, 0.0))
		return
	var inspector := %TreasureItemRecord as BoxContainer
	inspector.vertical = false
	(%TreasureRecordDetails as BoxContainer).vertical = _compact
	(%TreasureRecordScroll as ScrollContainer).vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if _compact else ScrollContainer.SCROLL_MODE_DISABLED
	UiSizing.minimum_size(inspector, Vector2(0.0, 230.0 if _compact else 260.0))
	UiSizing.minimum_size(find_child("TreasureItemIdentity", true, false) as Control, Vector2(0.0 if _compact else 360.0, 0.0))
	UiSizing.minimum_size(find_child("TreasureItemProperties", true, false) as Control, Vector2(0.0 if _compact else 360.0, 0.0))
	UiSizing.minimum_size(find_child("TreasureCommandPanel", true, false) as Control, Vector2(230.0 if _compact else 300.0, 0.0))
	UiSizing.minimum_size(self, Vector2(0.0, 500.0 if _compact else 0.0))
	UiSizing.minimum_size(%TreasurePartyPanel, Vector2(250.0 if _compact else 330.0, 0.0))
	(%TreasureSelectedItemFacts as GridContainer).columns = 2 if _compact else 4
	(%TreasureItemGrid as GridContainer).columns = 6 if _compact else 16
	for button: Button in _recipient_buttons.values():
		(button.get_parent() as BoxContainer).vertical = _compact
	call_deferred("_update_loot_columns", %TreasureItemScroll, %TreasureItemGrid)


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	set_layout_profile(profile.id == UiLayoutProfile.COMPACT)


func capture_browser_state() -> Dictionary:
	var scroll := get_node_or_null("%TreasureItemScroll") as ScrollContainer
	if scroll == null:
		return {}
	return {"slotOrder": _loot_slot_order.duplicate(), "lootScroll": scroll.scroll_vertical, "focusMoney": _focus_money_on_return}


func restore_browser_state(state: Dictionary) -> void:
	_focus_money_on_return = state.get("focusMoney", false) == true
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
	UiSizing.minimum_size(self, Vector2(0.0, 500.0 if _compact else 0.0))
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
			_body = body
			_connect_ordinary_commands()
			_select_initial_recipient(body)
			%TreasureWorkspaceTitle.text = "Victory Spoils" if body.origin == &"battle" else "Treasure"
			%TreasureWorkspaceSummary.text = TreasureDisplayText.summary(body)
			_build_loot_side(body)
			_build_party_side(body)
			_build_item_inspector(body)
			_refresh_item_availability()
			if _restore_money_workspace:
				_open_money_workspace(body)
		&"completion-confirmation":
			_build_completion_confirmation(body)
		_:
			add_hint("The treasure request is malformed.")


## Rebinds a retained ordinary workspace for the next request from the same Treasure, so taking,
## dropping, pooling, Detect Magic and Identify redraw only what changed instead of every loot cell.
## The nested leave-behind confirmation is its own component without ordinary loot, so it never qualifies.
func refresh_ordinary(request: InteractionRequest, game_view: GameView) -> bool:
	var body := request.body as TreasureRequestBody if request != null else null
	if body == null or _body == null or body.mode != &"ordinary" or body.source_id != _body.source_id or not has_node("OrdinaryTreasure"):
		return false
	var ids := func(source: TreasureRequestBody) -> Array: return source.characters.map(func(character: InteractionRequestValue.RewardCharacter) -> String: return character.id)
	if ids.call(body) != ids.call(_body) or body.items.any(func(item: InteractionRequestValue.RewardItem) -> bool: return not _loot_slot_order.has(item.instance_id)):
		return false
	var focus_owner := get_viewport().gui_get_focus_owner()
	_body = body
	_game_view = game_view if game_view != null else _game_view
	_transferring = false
	_transfer_item = null
	_select_initial_recipient(body)
	%TreasureWorkspaceSummary.text = TreasureDisplayText.summary(body)
	_build_loot_side(body)
	_build_party_side(body)
	_build_item_inspector(body)
	_refresh_item_availability()
	if focus_owner == null or not is_instance_valid(focus_owner) or focus_owner.is_queued_for_deletion() or not focus_owner.is_inside_tree():
		var target := preferred_initial_focus()
		if target != null: target.grab_focus()
	return true


func _connect_ordinary_commands() -> void:
	%TreasureDone.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"done")))
	%TreasureMoney.pressed.connect(func() -> void: _open_money_workspace(_body))
	%TreasurePool.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"pool")))
	%TreasureShare.pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"share")))
	(%TreasureItemScroll as ScrollContainer).resized.connect(_update_loot_columns.bind(%TreasureItemScroll, %TreasureItemGrid))


func preferred_initial_focus() -> Control:
	if _focus_money_on_return and has_node("%TreasureMoney"):
		_focus_money_on_return = false
		return %TreasureMoney as Control
	var recipient: Control = _recipient_buttons[_selected_recipient_id] if _recipient_buttons.has(_selected_recipient_id) else null
	if recipient != null and recipient.visible and not (recipient is BaseButton and (recipient as BaseButton).disabled):
		return recipient
	for drop: Variant in _drop_buttons.values():
		if drop is MenuButton and not drop.disabled:
			return drop
	return null


func _input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	for drop: Variant in _drop_buttons.values():
		var menu := (drop as MenuButton).get_popup() if drop is MenuButton else null
		if menu != null and menu.visible and not Rect2i(menu.position, menu.size).has_point(Vector2i(click.position)):
			menu.hide()
			get_viewport().set_input_as_handled()
			return


func _build_loot_side(body: TreasureRequestBody) -> void:
	var scroll := %TreasureItemScroll as ScrollContainer
	var grid := %TreasureItemGrid as GridContainer
	if grid.get_child_count() == 0:
		grid.columns = 6 if _compact else 16
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
	# Slots only ever append, so child N always presents slot N; unchanged cells are kept.
	for index: int in _loot_slot_order.size():
		var slot_id := _loot_slot_order[index]
		var item := items_by_id.get(slot_id) as InteractionRequestValue.RewardItem
		var current: Node = grid.get_child(index) if index < grid.get_child_count() else null
		var cell: Button = _item_buttons[slot_id] if _item_buttons.has(slot_id) else null
		if current != null and current == cell and item != null and TreasureDisplayText.same_loot_cell(_loot_items[slot_id], item):
			_loot_items[slot_id] = item
			continue
		if current != null and cell == null and item == null:
			continue
		if current != null:
			_item_buttons.erase(slot_id)
			_loot_items.erase(slot_id)
			_selection_rings.erase(slot_id)
			grid.remove_child(current)
			current.queue_free()
		if item != null:
			_add_loot_item(grid, item, index)
		else:
			_add_vacant_loot_slot(grid, slot_id, index)


func _build_item_inspector(body: TreasureRequestBody) -> void:
	set_layout_profile(_compact)
	var record_icon := %TreasureRecordIcon as TextureRect
	_selected_item_name = %TreasureSelectedItemName as Label
	_selected_item_state = %TreasureSelectedItemState as Label
	_selected_item_description = %TreasureSelectedItemDescription as Label
	_selected_item_facts = %TreasureSelectedItemFacts as GridContainer
	_selected_item_facts.columns = 2 if _compact else 4
	var commands := %TreasureDynamicCommands as VBoxContainer
	_build_compact_commands(commands, body)
	_refresh_item_record(record_icon)


func _update_loot_columns(scroll: ScrollContainer, grid: GridContainer) -> void:
	if scroll == null or grid == null or not is_inside_tree():
		return
	var cell_width := 1.0
	for child: Node in grid.get_children():
		if child is Control:
			cell_width = maxf(cell_width, (child as Control).get_combined_minimum_size().x)
	var gap := grid.get_theme_constant("h_separation")
	var loot_width := maxf(0.0, scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x)
	grid.columns = maxi(1, floori((loot_width + gap) / (cell_width + gap)))


func _add_loot_item(parent: GridContainer, item: InteractionRequestValue.RewardItem, index: int = -1) -> void:
	var cell := loot_cell_scene.instantiate() as Button
	cell.name = "TreasureItem_%s" % node_fragment(item.instance_id)
	cell.tooltip_text = item.name
	_loot_items[item.instance_id] = item
	parent.add_child(cell)
	if index >= 0: parent.move_child(cell, index)
	var magic_glow := cell.get_node("%MagicGlow") as TextureRect
	if item.magical:
		magic_glow.name = "TreasureMagicGlow_%s" % node_fragment(item.instance_id)
		magic_glow.texture = ClassicUiAssetCatalog.texture(&"loot.item.glow")
		magic_glow.visible = true
	else:
		magic_glow.get_parent().remove_child(magic_glow)
		magic_glow.free()
	var item_icon := cell.get_node("%ItemIcon") as TextureRect
	item_icon.name = "TreasureLootIcon_%s" % node_fragment(item.instance_id)
	item_icon.texture = _item_texture(item)
	var ring := cell.get_node("%SelectionRing") as TextureRect
	ring.name = "TreasureHoverCircle_%s" % node_fragment(item.instance_id)
	ring.texture = ClassicUiAssetCatalog.texture(&"loot.selection")
	_item_buttons[item.instance_id] = cell
	_selection_rings[item.instance_id] = ring
	cell.mouse_entered.connect(_focus_loot_item.bind(item, cell))
	cell.focus_entered.connect(_focus_loot_item.bind(item, cell))
	cell.mouse_exited.connect(_hide_loot_ring.bind(item.instance_id))
	cell.focus_exited.connect(_hide_loot_ring.bind(item.instance_id))
	cell.pressed.connect(_begin_item_transfer.bind(item, cell))
	_detail_popover.bind_hover(cell, TreasureDisplayText.item_detail(item))


func _add_vacant_loot_slot(parent: GridContainer, instance_id: String, index: int = -1) -> void:
	var slot := vacant_slot_scene.instantiate() as Control
	slot.name = "TreasureVacantSlot_%s" % node_fragment(instance_id)
	parent.add_child(slot)
	if index >= 0: parent.move_child(slot, index)


func _build_party_side(body: TreasureRequestBody) -> void:
	UiSizing.minimum_size(find_child("TreasurePartyPanel", true, false) as Control, Vector2(250.0 if _compact else 330.0, 0.0))
	var rows := %TreasureRecipientRows as VBoxContainer
	for character: InteractionRequestValue.RewardCharacter in body.characters:
		_add_recipient_row(rows, character)
	%TreasureMessagePanel.visible = not body.prompt.is_empty()
	%TreasureNarrative.text = body.prompt


func _add_recipient_row(parent: VBoxContainer, character: InteractionRequestValue.RewardCharacter) -> void:
	_drop_items[character.id] = character.drop_items
	var button: Button = _recipient_buttons[character.id] if _recipient_buttons.has(character.id) else null
	var drop: MenuButton = _drop_buttons[character.id] if _drop_buttons.has(character.id) else null
	if button == null:
		var row := recipient_row_scene.instantiate() as BoxContainer
		row.name = "TreasureRecipientRow_%s" % node_fragment(character.id)
		parent.add_child(row)
		button = row.get_node("TreasureRecipientSelect") as Button
		button.name = "TreasureRecipient_%s" % character.id
		button.pressed.connect(_select_recipient.bind(character.id))
		drop = row.get_node("TreasureRecipientDrop") as MenuButton
		drop.name = "TreasureDrop_%s" % node_fragment(character.id)
		drop.get_popup().exclusive = false
		drop.get_popup().close_requested.connect(drop.get_popup().hide)
		drop.get_popup().id_pressed.connect(_drop_recipient_item.bind(character.id))
	button.set_pressed_no_signal(character.id == _selected_recipient_id)
	button.text = TreasureDisplayText.recipient(character)
	button.icon = _portrait(character.id)
	button.disabled = not character.enabled
	button.tooltip_text = character.name if character.reason.is_empty() else "%s: %s" % [character.name, character.reason]
	_recipient_buttons[character.id] = button
	drop.disabled = character.drop_items.is_empty()
	drop.tooltip_text = "No carried items to drop." if drop.disabled else "Drop an item carried by %s." % character.name
	var menu := drop.get_popup()
	menu.clear()
	for index: int in character.drop_items.size():
		var item := character.drop_items[index]
		menu.add_item("%s%s" % [item.name, " (equipped)" if item.equipped else ""], index)
		menu.set_item_disabled(index, not item.enabled)
		menu.set_item_tooltip(index, item.reason)
	_drop_buttons[character.id] = drop


func _drop_recipient_item(index: int, character_id: String) -> void:
	var items: Array[InteractionRequestValue.RewardDropItem] = []
	if _drop_items.has(character_id): items.assign(_drop_items[character_id])
	if index < 0 or index >= items.size() or not items[index].enabled:
		return
	response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"drop", items[index].instance_id, character_id))


func _build_compact_commands(parent: VBoxContainer, body: TreasureRequestBody) -> void:
	%TreasurePooledWealth.text = TreasureDisplayText.wealth(body.wealth)
	var money_rows := body.characters.filter(func(character: InteractionRequestValue.RewardCharacter) -> bool:
		return character.wealth != null and not character.id.is_empty()
	)
	%TreasureMoney.disabled = money_rows.is_empty()
	%TreasureMoney.tooltip_text = "No adventurer wealth is available." if money_rows.is_empty() else "Open the Party Wealth screen."
	var has_carried_wealth := body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool:
		return character.wealth != null and (character.wealth.gold > 0 or character.wealth.gems > 0 or character.wealth.jewelry > 0)
	)
	%TreasurePool.disabled = not has_carried_wealth
	%TreasurePool.tooltip_text = "" if has_carried_wealth else "No adventurer carries wealth to pool."
	var has_pool := body.wealth != null and (body.wealth.gold > 0 or body.wealth.gems > 0 or body.wealth.jewelry > 0)
	%TreasureShare.disabled = not (has_pool and body.has_share_capacity)
	%TreasureShare.tooltip_text = "" if has_pool and body.has_share_capacity else "The pool is empty or no adventurer can carry another unit."
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
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
	for id: String in _recipient_buttons:
		_recipient_buttons[id].set_pressed_no_signal(id == character_id)
	_refresh_item_availability()


func _focus_loot_item(item: InteractionRequestValue.RewardItem, _button: Button) -> void:
	_selected_item = item
	var ring: TextureRect = _selection_rings[item.instance_id] if _selection_rings.has(item.instance_id) else null
	if ring != null:
		ring.visible = true
	var record_icon := find_child("TreasureRecordIcon", true, false) as TextureRect
	_refresh_item_record(record_icon)
	_refresh_item_availability()


func _hide_loot_ring(instance_id: String) -> void:
	var ring: TextureRect = _selection_rings[instance_id] if _selection_rings.has(instance_id) else null
	var button: Button = _item_buttons[instance_id] if _item_buttons.has(instance_id) else null
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
		var label := _add_colored_label(_selected_item_facts, fact.label, MUTED, "TreasureFact_%s" % fact.label.to_snake_case())
		label.add_theme_color_override("font_color", GOLD)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		UiSizing.minimum_size(label, Vector2(96.0, 0.0))
		var value := _add_colored_label(_selected_item_facts, fact.value, MUTED, "TreasureFactValue_%s" % fact.label.to_snake_case())
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if icon != null: icon.texture = _item_texture(_selected_item)


func _refresh_item_availability() -> void:
	for item_id: String in _item_buttons:
		var button := _item_buttons[item_id]
		var item := _loot_items[item_id]
		var assignment := _assignment_for(item, _selected_recipient_id)
		button.disabled = _transferring or assignment == null or not assignment.enabled
		button.tooltip_text = item.name if assignment != null and assignment.enabled else "%s — %s" % [item.name, assignment.reason if assignment != null else "Choose an eligible recipient."]


func _begin_item_transfer(item: InteractionRequestValue.RewardItem, source: Button) -> void:
	var assignment := _assignment_for(item, _selected_recipient_id)
	var target: Button = _recipient_buttons[_selected_recipient_id] if _recipient_buttons.has(_selected_recipient_id) else null
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


static func node_fragment(value: String) -> String: return value.replace(".", "_").replace(":", "_").replace("/", "_").replace("@", "_").replace('"', "_")


func _build_recovery_workspace(body: TreasureRequestBody) -> void:
	if body.item == null:
		add_hint("The recovery request is malformed.")
		return
	var workspace := recovery_workspace_scene.instantiate() as VBoxContainer
	add_child(workspace)
	var recovery_card := workspace.get_node("TreasureRecoveryCenter/TreasureRecoveryCard") as PanelContainer
	UiSizing.minimum_size(recovery_card, Vector2(620.0 if _compact else 760.0, 0.0))
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
	var fact_text: Array[String] = []
	for fact: InteractionRequestValue.RewardFact in item.facts:
		if fact.label.strip_edges().is_empty() or fact.value.strip_edges().is_empty() or fact.label.to_lower() == "charges":
			continue
		fact_text.append("%s %s" % [fact.label, fact.value])
	var facts := workspace.get_node("%TreasureSelectedItemFacts") as Label
	facts.text = " • ".join(fact_text)
	facts.visible = not fact_text.is_empty()
	var description := workspace.get_node("%TreasureSelectedItemDescription") as Label
	description.text = item.description
	description.visible = not item.description.strip_edges().is_empty()
	var charges := workspace.get_node("%TreasureSelectedItemCharges") as Label
	charges.visible = item.charges > 0
	charges.text = "%d charge%s" % [item.charges, "" if item.charges == 1 else "s"]


func _open_money_workspace(body: TreasureRequestBody) -> void:
	if not body.characters.any(func(character: InteractionRequestValue.RewardCharacter) -> bool: return character.wealth != null and not character.id.is_empty()):
		return
	var workspace := money_workspace_scene.instantiate() as ServicesWorkspace
	workspace.name = "TreasureMoneyWorkspace"
	workspace.prepare(_compact)
	_money = TreasureMoneyBinder.new(workspace, body, _media, _game_view, _portrait, _selected_recipient_id)
	_money.response_body_submitted.connect(response_body_submitted.emit)
	_money.close_requested.connect(_close_money_workspace)
	money_workspace_visibility_changed.emit(true)
	application_workspace_requested.emit(workspace)
	_money.focus_selected.call_deferred()


## Rebinds the open Money workspace from a refreshed request; Treasure beneath rebuilds when Money closes.
func refresh_money_workspace(request: InteractionRequest, game_view: GameView) -> bool:
	var body := request.body as TreasureRequestBody if request != null else null
	if _money == null or not is_instance_valid(_money.workspace) or not _money.workspace.is_inside_tree() or body == null or body.mode != &"ordinary":
		return false
	_game_view = game_view if game_view != null else _game_view
	return _money.refresh(body, game_view)


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
	var stale := _money != null and _money.stale
	if _money != null:
		_money.stop()
		_money.stale = false
	money_workspace_visibility_changed.emit(false)
	application_workspace_closed.emit()
	if stale:
		_focus_money_on_return = true
		stale_request_rebuild_requested.emit()
	elif has_node("%TreasureMoney"):
		(%TreasureMoney as Control).grab_focus.call_deferred()


func _add_colored_label(parent: Container, text: String, color: Color, label_name: String) -> Label:
	var label := fact_label_scene.instantiate() as Label
	label.name = label_name
	label.text = text
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
