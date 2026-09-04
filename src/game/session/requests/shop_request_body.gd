## Carries the detached shop inventory, shoppers, prices, and actions.

class_name ShopRequestBody
extends ServiceRequestBody

var shop_id: String
var inflation_percent: int
var party_gold: int
var identify_price: int
var stock: Array[InteractionRequestValue.ShopStock] = []
var accept_ranges: Array[int] = []


func to_data() -> Dictionary:
	return {"shopId": shop_id, "inflationPercent": inflation_percent, "partyGold": party_gold, "identifyPrice": identify_price, "stock": stock.map(func(value: InteractionRequestValue.ShopStock) -> Dictionary: return value.to_data()), "characters": characters.map(func(value: InteractionRequestValue.ServiceCharacter) -> Dictionary: return value.to_shop_data()), "acceptRanges": accept_ranges.duplicate(), "actions": actions.duplicate()}
