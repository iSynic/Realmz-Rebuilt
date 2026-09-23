## Binds the Shop's selected transaction facts and source-backed two-pack transfer availability.
class_name ShopTransactionPresenter
extends RefCounted

signal trade_requested(body: InteractionResponse.ShopBody)

var _summary: Label
var _transaction_facts: Label
var _item_stats: Label
var _buy_button: Button
var _sell_button: Button
var _identify_button: Button
var _game_view: GameView
var _selected_item: InteractionRequestValue.InventoryItem
var _selected_item_owner_id: String


func bind_controls(summary: Label, transaction_facts: Label, item_stats: Label, buy_button: Button, sell_button: Button, identify_button: Button) -> void:
	_summary = summary
	_transaction_facts = transaction_facts
	_item_stats = item_stats
	_buy_button = buy_button
	_sell_button = sell_button
	_identify_button = identify_button


func render(game_view: GameView, stock: InteractionRequestValue.ShopStock, item: InteractionRequestValue.InventoryItem, owner_id: String, shopper_id: String, right_id: String) -> void:
	_game_view = game_view
	_selected_item = item
	_selected_item_owner_id = owner_id
	var pair_trade := not right_id.is_empty()
	if pair_trade:
		var take := trade_target(shopper_id) if owner_id == right_id else null
		var give := trade_target(right_id) if owner_id == shopper_id else null
		_buy_button.text = "Take"
		_sell_button.text = "Give"
		_buy_button.disabled = take == null or not take.enabled
		_sell_button.disabled = give == null or not give.enabled
		_buy_button.tooltip_text = "Select an item in the right pack." if take == null else take.reason
		_sell_button.tooltip_text = "Select an item in the left pack." if give == null else give.reason
		_identify_button.disabled = true
		_identify_button.tooltip_text = "Return to Shop Keeper to identify items."
	else:
		_buy_button.text = "Buy"
		_sell_button.text = "Sell"
		_buy_button.disabled = stock == null or shopper_id.is_empty() or not stock.can_buy
		_sell_button.disabled = item == null or owner_id.is_empty() or not item.can_sell
		_identify_button.disabled = item == null or owner_id.is_empty() or not item.can_identify
		_buy_button.tooltip_text = "Select shop stock." if stock == null else "No shopper is available." if shopper_id.is_empty() else stock.buy_reason if not stock.can_buy else ""
		_sell_button.tooltip_text = "Select a carried item." if item == null else item.sell_reason if not item.can_sell else ""
		_identify_button.tooltip_text = "Select a carried item." if item == null else item.identify_reason if not item.can_identify else ""
	if stock != null:
		_summary.text = stock.description if not stock.description.is_empty() else stock.name
		_summary.tooltip_text = stock.buy_reason
		_transaction_facts.text = "Cost %d  •  Offer —  •  Weight %d" % [stock.buy_price, stock.weight]
		_item_stats.text = _facts_text(stock.facts, "Quantity", str(stock.quantity))
	elif item != null:
		var state := "Equipped" if item.equipped else "Carried"
		var knowledge := "Identified" if item.identified else "Unidentified"
		_summary.text = item.description if not item.description.is_empty() else item.name
		_summary.tooltip_text = item.sell_reason if not item.can_sell else item.identify_reason if not item.can_identify else ""
		_transaction_facts.text = "Trade  •  Weight %d" % item.weight if pair_trade else "Cost —  •  Offer %d  •  Weight %d" % [item.sell_price, item.weight]
		_item_stats.text = _facts_text(item.facts, "State", "%s / %s" % [state, knowledge])
	else:
		_summary.text = "Choose stock or a carried item."
		_summary.tooltip_text = ""
		_transaction_facts.text = "Cost —  •  Offer —  •  Weight —"
		_item_stats.text = ""


func submit_trade(destination_id: String) -> void:
	var target := trade_target(destination_id)
	if target == null or not target.enabled:
		return
	trade_requested.emit(InteractionResponse.ShopBody.new(&"trade", _selected_item_owner_id, _selected_item.instance_id, "", "", 0, destination_id))


func trade_target(destination_id: String) -> ItemTransferTargetView:
	if _game_view == null or _selected_item == null or _selected_item_owner_id.is_empty():
		return null
	var owner := InventoryViewQueries.character_by_id(_game_view, _selected_item_owner_id)
	var item := InventoryViewQueries.item_by_id(owner, _selected_item.instance_id)
	if item == null or item.actions == null:
		return null
	return InventoryViewQueries.trade_target(item, destination_id)


func _facts_text(facts: Array[InteractionRequestValue.ItemDetailFact], extra_label: String, extra_value: String) -> String:
	var lines: Array[String] = []
	for fact: InteractionRequestValue.ItemDetailFact in facts:
		lines.append("%s  %s" % [fact.label, fact.value])
	lines.append("%s  %s" % [extra_label, extra_value])
	return "  •  ".join(lines)


static func detail_facts(facts: Array[InteractionRequestValue.ItemDetailFact], suffix: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact: InteractionRequestValue.ItemDetailFact in facts:
		result.append({"label": fact.label, "value": fact.value})
	result.append_array(suffix)
	return result
