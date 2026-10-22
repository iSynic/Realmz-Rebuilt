## FD-SCENARIO-018: bound actor construction while retaining native catalog records.
class_name MonsterConsumptionProbe
extends RefCounted

enum Outcome { USABLE, AUTHORED_UNSAFE, PACKAGE_DEFECT }
enum Construction { ORDINARY, POLYMORPH }

var outcome: Outcome = Outcome.USABLE
var reason: String = ""


static func inspect(content: RealmzContent, definition: MonsterDefinition, construction: Construction = Construction.ORDINARY) -> MonsterConsumptionProbe:
	var result := MonsterConsumptionProbe.new()
	if definition == null:
		result.outcome = Outcome.PACKAGE_DEFECT
		result.reason = "Actor construction requires a resolved monster definition."
		return result
	if content.package_schema_version < 7:
		return result
	if definition.size not in range(4) or definition.attack_count > definition.attacks().size() or construction == Construction.ORDINARY and definition.random_weapon_table > 10:
		result.outcome = Outcome.AUTHORED_UNSAFE
		result.reason = "Monster '%s' has an unsafe footprint, attack extent or random weapon table." % definition.id
		return result
	var items := definition.item_ids()
	if construction == Construction.POLYMORPH:
		# spelllist.c clears the weapon and retains all six native carried slots.
		pass
	elif definition.random_weapon_table > 0:
		# Construction replaces the first carried slot with the selected stock weapon.
		if not items.is_empty(): items.remove_at(0)
		items.append_array(MonsterRules.random_weapon_item_ids(definition.random_weapon_table))
	else:
		items.append(definition.weapon_id)
	for item_id: String in items:
		if item_id.is_empty() or content.items.item_by_id(item_id) != null:
			continue
		var parts := item_id.split(".")
		var native_id := int(parts[2]) if parts.size() == 3 and parts[0] == "classic" and parts[1] == "item" and parts[2].is_valid_int() else 1
		var authored_absence := native_id <= 0 or native_id >= 1000
		if native_id >= 800 and native_id < 1000 and content.classic_records != null:
			authored_absence = content.classic_records.lookup("Data NI", native_id - 800).availability != ClassicRecordCatalog.Availability.COMPLETE
		result.outcome = Outcome.AUTHORED_UNSAFE if authored_absence else Outcome.PACKAGE_DEFECT
		result.reason = "Monster '%s' requires unavailable carried item '%s'." % [definition.id, item_id]
		return result
	return result
