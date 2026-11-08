## Binds Treasure's shared Party Wealth workspace from detached Treasure request values.
##
## The workspace is built once and rebound in place for each refreshed request, so held
## transfers repeat at classic speed and the selected adventurer survives transfers, Pool and Share.
class_name TreasureMoneyBinder
extends RefCounted

signal response_body_submitted(body: InteractionResponse.Body)
signal close_requested

const DENOMINATIONS: Array[StringName] = [&"gold", &"gems", &"jewelry"]

var workspace: ServicesWorkspace
## True once the workspace absorbed a refreshed request the Treasure layout beneath has not shown.
var stale := false
var _body: TreasureRequestBody
var _media: ClassicMediaCatalog
var _game_view: GameView
var _portrait: Callable
var _character_id := ""
var _hold: MoneyHoldRepeat


func _init(money_workspace: ServicesWorkspace, body: TreasureRequestBody, media: ClassicMediaCatalog, game_view: GameView, portrait: Callable, preferred_id: String) -> void:
	workspace = money_workspace
	_body = body
	_media = media
	_game_view = game_view
	_portrait = portrait
	_hold = MoneyHoldRepeat.new(workspace.repeat_timer())
	workspace.changing_pane().hide()
	var pool := workspace.pool_summary()
	(pool.get_node("Identity/Heading") as Label).text = "Treasure Pool"
	(pool.get_node("Identity/Banked") as Label).hide()
	(pool.get_node("MoneyPoolActions/Pool") as Button).pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"pool")))
	(pool.get_node("MoneyPoolActions/Share") as Button).pressed.connect(func() -> void: response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"share")))
	var done := workspace.done_button()
	done.text = "Back to Treasure"
	done.tooltip_text = "Return to the same Treasure screen."
	done.pressed.connect(func() -> void:
		_hold.stop()
		close_requested.emit())
	var group := ButtonGroup.new()
	for character: InteractionRequestValue.RewardCharacter in characters():
		var row := workspace.money_character_row_scene.instantiate() as MoneyCharacterRow
		row.name = "MoneyCharacter_%s" % TreasureDistributionInteraction.node_fragment(character.id)
		row.button_group = group
		row.set_meta(&"character_id", character.id)
		(row.get_node("Content/Portrait") as TextureRect).texture = _portrait.call(character.id)
		workspace.character_rows().add_child(row)
		row.pressed.connect(_select.bind(character.id))
	workspace.character_picker().item_selected.connect(func(index: int) -> void: _select(_character_ids()[index]))
	for kind: StringName in DENOMINATIONS:
		var row := workspace.money_transfer_row_scene.instantiate() as MoneyTransferRow
		workspace.transfer_rows().add_child(row)
		_hold.attach(row.to_pool_button(), _submit_transfer.bind(&"to-pool", kind))
		_hold.attach(row.to_character_button(), _submit_transfer.bind(&"to-character", kind))
	var ids := _character_ids()
	_character_id = preferred_id if ids.has(preferred_id) else ids[0] if not ids.is_empty() else ""
	_bind()


## Treasure characters that carry a wealth record, in request order.
func characters() -> Array[InteractionRequestValue.RewardCharacter]:
	var rows: Array[InteractionRequestValue.RewardCharacter] = []
	if _body == null:
		return rows
	for character: InteractionRequestValue.RewardCharacter in _body.characters:
		if character.wealth != null and not character.id.is_empty():
			rows.append(character)
	return rows


## Rebinds a refreshed request with the same adventurers; returns false when Treasure must rebuild.
func refresh(body: TreasureRequestBody, game_view: GameView) -> bool:
	var previous := _body
	var ids := _character_ids()
	_body = body
	if _character_ids() != ids:
		_body = previous
		return false
	_game_view = game_view if game_view != null else _game_view
	stale = true
	_bind()
	return true


func stop() -> void:
	_hold.stop()


## Gives controller focus to the selected adventurer so the first direction moves inside the workspace.
func focus_selected() -> void:
	for row: Node in workspace.character_rows().get_children():
		if _row_id(row) == _character_id and (row as Control).is_visible_in_tree():
			(row as Control).grab_focus()
			return
	if workspace.character_picker().is_visible_in_tree():
		workspace.character_picker().grab_focus()


func _character_ids() -> Array[String]:
	var ids: Array[String] = []
	for character: InteractionRequestValue.RewardCharacter in characters():
		ids.append(character.id)
	return ids


func _bind() -> void:
	var rows := characters()
	var pool := workspace.pool_summary()
	for kind: StringName in DENOMINATIONS:
		(pool.get_node("MoneyPoolValues/%s" % String(kind).capitalize()) as WealthChip).bind(kind, _amount(_body.wealth, kind), _media)
	var pool_button := pool.get_node("MoneyPoolActions/Pool") as Button
	pool_button.disabled = not rows.any(func(character: InteractionRequestValue.RewardCharacter) -> bool: return character.wealth.gold > 0 or character.wealth.gems > 0 or character.wealth.jewelry > 0)
	pool_button.tooltip_text = "No adventurer carries wealth to pool." if pool_button.disabled else "Pool all carried wealth."
	var share_button := pool.get_node("MoneyPoolActions/Share") as Button
	share_button.disabled = not (_body.has_share_capacity and _body.wealth != null and (_body.wealth.gold > 0 or _body.wealth.gems > 0 or _body.wealth.jewelry > 0))
	share_button.tooltip_text = "The pool is empty or no adventurer can carry another unit." if share_button.disabled else "Share the Treasure pool."
	var picker := workspace.character_picker()
	picker.clear()
	for character: InteractionRequestValue.RewardCharacter in rows:
		picker.add_item("%s  •  Load %d/%d" % [character.name, character.carried_load, character.maximum_load])
		picker.set_item_metadata(picker.item_count - 1, character.id)
	for row: Node in workspace.character_rows().get_children():
		var character := _character(_row_id(row))
		if character != null:
			(row.get_node("Content/Facts/Name") as Label).text = character.name
			(row.get_node("Content/Facts/Wealth") as Label).text = "%d gold  ·  %d gems  ·  %d jewelry" % [character.wealth.gold, character.wealth.gems, character.wealth.jewelry]
	_select(_character_id, false)


func _select(character_id: String, user_choice: bool = true) -> void:
	var selected := _character(character_id)
	if selected == null:
		return
	if user_choice:
		_hold.stop()
	_character_id = character_id
	for child: Node in workspace.character_rows().get_children():
		(child as Button).set_pressed_no_signal(_row_id(child) == character_id)
	workspace.character_picker().select(_character_ids().find(character_id))
	var exchange := workspace.swap_pane().get_node("Content/MoneyExchangeScroll/MoneyExchangeBody")
	(exchange.get_node("Header/Heading") as Label).text = "Give or take wealth"
	(exchange.get_node("Header/SelectedName") as Label).text = selected.name
	(exchange.get_node("Header/SelectedPortrait") as TextureRect).texture = _portrait.call(character_id)
	var summary := workspace.selected_summary()
	for kind: StringName in DENOMINATIONS:
		(summary.get_node(String(kind).capitalize()) as WealthChip).bind(kind, _amount(selected.wealth, kind), _media)
	(summary.get_node("Load") as Label).text = "Carried load\n%d / %d" % [selected.carried_load, selected.maximum_load]
	var transfer_rows := workspace.transfer_rows().get_children()
	for index: int in range(transfer_rows.size()):
		var kind := DENOMINATIONS[index]
		var row := transfer_rows[index] as MoneyTransferRow
		row.bind(MoneyTransferView.new(kind, _step(kind), null, null), _amount(_body.wealth, kind), _amount(selected.wealth, kind), _media)
		var to_pool := row.to_pool_button()
		to_pool.disabled = not _can_give(selected, kind)
		to_pool.tooltip_text = "This adventurer does not carry enough %s." % String(kind) if to_pool.disabled else "Return wealth to the Treasure pool · Hold to repeat."
		var to_character := row.to_character_button()
		to_character.disabled = not _can_take(selected, kind)
		to_character.tooltip_text = (selected.gold_reason if kind == &"gold" else selected.gems_reason if kind == &"gems" else selected.jewelry_reason) if to_character.disabled else "Take wealth from the Treasure pool · Hold to repeat."


## Reads the current request so every repeated step uses refreshed facts.
func _submit_transfer(direction: StringName, kind: StringName) -> void:
	var selected := _character(_character_id)
	if selected != null and (_can_take(selected, kind) if direction == &"to-character" else _can_give(selected, kind)):
		response_body_submitted.emit(InteractionResponse.TreasureBody.new(&"transfer", "", selected.id, direction, kind, _step(kind)))


static func _row_id(row: Node) -> String:
	var id: String = row.get_meta(&"character_id", "")
	return id


func _character(character_id: String) -> InteractionRequestValue.RewardCharacter:
	for character: InteractionRequestValue.RewardCharacter in characters():
		if character.id == character_id:
			return character
	return null


func _step(kind: StringName) -> int:
	return EconomyRules.transfer_step(_wealth_kind(kind), _game_view.adventure_rules if _game_view != null else null)


func _can_give(character: InteractionRequestValue.RewardCharacter, kind: StringName) -> bool:
	return _amount(character.wealth, kind) >= EconomyRules.classic_transfer_increment(_wealth_kind(kind))


static func _can_take(character: InteractionRequestValue.RewardCharacter, kind: StringName) -> bool:
	return character.can_take_gold if kind == &"gold" else character.can_take_gems if kind == &"gems" else character.can_take_jewelry


static func _wealth_kind(kind: StringName) -> WealthState.Kind:
	return WealthState.Kind.GOLD if kind == &"gold" else WealthState.Kind.GEMS if kind == &"gems" else WealthState.Kind.JEWELRY


static func _amount(wealth: InteractionRequestValue.Wealth, kind: StringName) -> int:
	if wealth == null:
		return 0
	return wealth.gold if kind == &"gold" else wealth.gems if kind == &"gems" else wealth.jewelry
