## Decides when the interaction presenter rebinds a mounted component instead of rebuilding it.
##
## Shop, Bank and an open Treasure Money workspace keep their nodes across responses so held
## money transfers repeat and selections survive each step. Ordinary Treasure keeps its loot
## cells and recipient rows across requests for the same Treasure and redraws only what changed.
class_name InteractionRefreshPolicy
extends RefCounted


## Rebinds the mounted component in place; false means the presenter must rebuild.
static func refresh_in_place(component: InteractionComponent, request: InteractionRequest, game_view: GameView, treasure_money_open: bool) -> bool:
	if component is ShopInteraction:
		return (component as ShopInteraction).refresh_workspace(request, game_view)
	if component is BankInteraction:
		return (component as BankInteraction).refresh(request, game_view)
	if component is TreasureDistributionInteraction and treasure_money_open and request != null and request.kind == InteractionRequest.TREASURE_DISTRIBUTION:
		return (component as TreasureDistributionInteraction).refresh_money_workspace(request, game_view)
	if component is TreasureDistributionInteraction and not treasure_money_open and request != null and request.kind == InteractionRequest.TREASURE_DISTRIBUTION:
		return (component as TreasureDistributionInteraction).refresh_ordinary(request, game_view)
	return false


## Whether a response keeps the presenter visible and its application workspace mounted for an in-place refresh.
static func retains_workspace(component: InteractionComponent, body: InteractionResponse.Body, treasure_money_open: bool) -> bool:
	if component is ShopInteraction and body is InteractionResponse.ShopBody:
		var state := (component as ShopInteraction).capture_browser_state()
		return state.get("moneyOpen", false) == true or state.get("itemsOpen", false) == true
	if component is BankInteraction and body is InteractionResponse.BankBody:
		return (body as InteractionResponse.BankBody).action in [&"to-pool", &"to-character", &"pool", &"share"]
	if component is TreasureDistributionInteraction and body is InteractionResponse.TreasureBody:
		return treasure_money_open and (body as InteractionResponse.TreasureBody).action in [&"transfer", &"pool", &"share"]
	return false


## Keeps Treasure's loot slot order across consecutive requests for the same loot layout.
static func update_treasure_slot_order(order: Array[String], request: InteractionRequest) -> void:
	var body := request.body as TreasureRequestBody
	if body == null or body.mode != &"ordinary":
		return
	var continues_current_layout := body.items.is_empty() or body.items.any(func(item: InteractionRequestValue.RewardItem) -> bool: return order.has(item.instance_id))
	if not order.is_empty() and not continues_current_layout:
		order.clear()
	for item: InteractionRequestValue.RewardItem in body.items:
		if not order.has(item.instance_id):
			order.append(item.instance_id)
