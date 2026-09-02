class_name InventoryItemActionsView
extends RefCounted

var equip := ActionAvailabilityView.new(&"equip_item", false, "This item cannot be equipped.")
var unequip := ActionAvailabilityView.new(&"unequip_item", false, "This item is not equipped.")
var use := ActionAvailabilityView.new(&"use_item", false, "This item's use effect is not implemented.")
var identify := ActionAvailabilityView.new(&"identify_item", false, "Identification requires a shop, temple, or Identify spell.")
var identify_caster_id: String = ""
var identify_spell_id: String = ""
var split := ActionAvailabilityView.new(&"split_item", false, "This item cannot be split.")
var join := ActionAvailabilityView.new(&"join_item", false, "This item cannot be joined.")
var drop := ActionAvailabilityView.new(&"drop_item", false, "This item cannot be dropped.")
var trade := ActionAvailabilityView.new(&"trade_item", false, "This item cannot be traded.")
var trade_targets: Array[ItemTransferTargetView] = []


func block_all(reason: String) -> void:
	equip = ActionAvailabilityView.new(&"equip_item", false, reason)
	unequip = ActionAvailabilityView.new(&"unequip_item", false, reason)
	use = ActionAvailabilityView.new(&"use_item", false, reason)
	identify = ActionAvailabilityView.new(&"identify_item", false, reason)
	split = ActionAvailabilityView.new(&"split_item", false, reason)
	join = ActionAvailabilityView.new(&"join_item", false, reason)
	drop = ActionAvailabilityView.new(&"drop_item", false, reason)
	trade = ActionAvailabilityView.new(&"trade_item", false, reason)
