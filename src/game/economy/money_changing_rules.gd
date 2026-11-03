## Applies Castle's three pooled-wealth conversion rates.
class_name MoneyChangingRules
extends RefCounted

const JEWELRY_TO_GEMS: StringName = &"change-jewelry-to-gems"
const GEMS_TO_GOLD: StringName = &"change-gems-to-gold"
const GOLD_TO_GEMS: StringName = &"change-gold-to-gems"
const ACTIONS: Array[StringName] = [JEWELRY_TO_GEMS, GEMS_TO_GOLD, GOLD_TO_GEMS]
const MAXIMUM_BATCH := 100


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


## Castle changes one unit per button poll; a held pulse may request whole units up to the batch limit.
static func valid_amount(action: StringName, denomination: String, amount: int) -> bool:
	var conversion := rate(action)
	return conversion != null and denomination == String(conversion.source) and amount >= conversion.source_amount and amount <= conversion.source_amount * MAXIMUM_BATCH and amount % conversion.source_amount == 0


## Changes as many requested units as the pool affords and returns that count, so a final batch stops where Castle's loop would.
static func convert(party: PartyState, location_available: bool, action: StringName, amount: int) -> int:
	if not probe(party, location_available, action).allowed:
		return 0
	var conversion := rate(action)
	@warning_ignore("integer_division")
	var units := mini(amount, party.pooled_wealth.amount(_kind(conversion.source))) / conversion.source_amount
	party.pooled_wealth.add(_kind(conversion.source), -conversion.source_amount * units)
	party.pooled_wealth.add(_kind(conversion.result), conversion.result_amount * units)
	return units


static func _kind(denomination: StringName) -> WealthState.Kind:
	match denomination:
		&"gold": return WealthState.Kind.GOLD
		&"gems": return WealthState.Kind.GEMS
	return WealthState.Kind.JEWELRY
