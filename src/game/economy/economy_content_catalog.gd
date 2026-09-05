## Indexes immutable treasure and shop definitions used by rewards and services.

class_name EconomyContentCatalog
extends RefCounted

var _treasures: Dictionary = {}
var _treasure_by_classic_id: Dictionary = {}
var _shops: Dictionary = {}
var _shop_by_classic_id: Dictionary = {}


func _init(treasures: Array[TreasureDefinition] = [], shops: Array[ShopDefinition] = []) -> void:
	for treasure: TreasureDefinition in treasures:
		_treasures[treasure.id] = treasure
	for value: Variant in _treasures.values():
		var treasure := value as TreasureDefinition
		if not _treasure_by_classic_id.has(treasure.classic_id):
			_treasure_by_classic_id[treasure.classic_id] = treasure
	for shop: ShopDefinition in shops:
		_shops[shop.id] = shop
	for value: Variant in _shops.values():
		var shop := value as ShopDefinition
		if not _shop_by_classic_id.has(shop.classic_id):
			_shop_by_classic_id[shop.classic_id] = shop


func treasure_by_id(definition_id: String) -> TreasureDefinition:
	return _treasures.get(definition_id) as TreasureDefinition


func treasure_by_classic_id(classic_id: int) -> TreasureDefinition:
	return _treasure_by_classic_id.get(classic_id) as TreasureDefinition


func shop_by_id(definition_id: String) -> ShopDefinition:
	return _shops.get(definition_id) as ShopDefinition


func shop_by_classic_id(classic_id: int) -> ShopDefinition:
	return _shop_by_classic_id.get(classic_id) as ShopDefinition
