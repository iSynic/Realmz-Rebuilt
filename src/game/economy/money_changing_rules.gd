## Applies Castle's three pooled-wealth conversion rates.
class_name MoneyChangingRules
extends RefCounted

const JEWELRY_TO_GEMS: StringName = &"change-jewelry-to-gems"
const GEMS_TO_GOLD: StringName = &"change-gems-to-gold"
const GOLD_TO_GEMS: StringName = &"change-gold-to-gems"
const ACTIONS: Array[StringName] = [JEWELRY_TO_GEMS, GEMS_TO_GOLD, GOLD_TO_GEMS]


static func rate(action: StringName) -> MoneyChangeView:
	match action:
		JEWELRY_TO_GEMS:
			return MoneyChangeView.new(action, &"jewelry", 1, &"gems", 5, null)
		GEMS_TO_GOLD:
			return MoneyChangeView.new(action, &"gems", 1, &"gold", 100, null)
		GOLD_TO_GEMS:
			return MoneyChangeView.new(action, &"gold", 115, &"gems", 1, null)
	return null


static func probe(party: PartyState, location_available: bool, action: StringName) -> EconomyActionProbe:
	var conversion := rate(action)
	if conversion == null:
		return EconomyActionProbe.new(false, "This money-changing rate is unavailable.")
	if not location_available:
		return EconomyActionProbe.new(false, "Money changing is available only at a shop or temple.")
	if party == null or party.pooled_wealth.amount(_kind(conversion.source)) < conversion.source_amount:
		return EconomyActionProbe.new(false, "The party pool lacks %d %s." % [conversion.source_amount, conversion.source])
	return EconomyActionProbe.new(true)


static func convert(party: PartyState, location_available: bool, action: StringName) -> bool:
	if not probe(party, location_available, action).allowed:
		return false
	var conversion := rate(action)
	party.pooled_wealth.add(_kind(conversion.source), -conversion.source_amount)
	party.pooled_wealth.add(_kind(conversion.result), conversion.result_amount)
	return true


static func _kind(denomination: StringName) -> WealthState.Kind:
	match denomination:
		&"gold": return WealthState.Kind.GOLD
		&"gems": return WealthState.Kind.GEMS
	return WealthState.Kind.JEWELRY
