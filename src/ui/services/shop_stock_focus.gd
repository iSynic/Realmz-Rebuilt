## After a sale, points the shop's stock list at the category the sold item went into, so
## the player sees it arrive instead of an unchanged list.

class_name ShopStockFocus
extends RefCounted

const SOLD_ITEM := &"shop_sold_item_id"


## Remembers on `shop` which item definition was just sold.
static func remember(shop: Node, item_id: String) -> void:
	shop.set_meta(SOLD_ITEM, item_id)


## The category to show: the sold item's once it appears in `stock`, otherwise `current`.
static func category_after_sale(shop: Node, stock: Array, current: StringName) -> StringName:
	var sold := String(shop.get_meta(SOLD_ITEM, ""))
	if sold.is_empty():
		return current
	for entry: InteractionRequestValue.ShopStock in stock:
		if entry.item_id == sold and not entry.category.is_empty():
			shop.remove_meta(SOLD_ITEM)
			return entry.category
	return current
