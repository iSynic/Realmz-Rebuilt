## Binds detached inventory item text data to scene-owned controls.

class_name InventoryItemText
extends RefCounted

## Formats detached item records for Inventory ledgers, details, and confirmations.


static func detail(item: ItemView) -> Dictionary:
	var facts: Array[Dictionary] = []
	for fact: ItemFactView in item.facts:
		facts.append({"label": fact.label, "value": fact.value})
	return {"title": item.name, "subtitle": "%s  •  Weight %d  •  %s" % ["Equipped" if item.equipped else "Carried", item.weight, "Unlimited charges" if item.charges < 0 else "%d charges" % item.charges], "description": item.description, "facts": facts, "properties": item.properties.duplicate(), "restrictions": item.restrictions.duplicate(), "iconResourceType": item.icon_resource_type, "iconId": item.icon_id}


static func line_fact(item: ItemView) -> ItemFactView:
	for fact_id: StringName in [&"damage-range", &"armor"]:
		for fact: ItemFactView in item.facts:
			if fact.id == fact_id:
				return fact
	return null


static func operation_description(action: StringName, item: ItemView, character: CharacterView) -> String:
	match action:
		&"equip": return "Move this exact carried item into its legal equipment position."
		&"unequip": return "Return this exact equipped item to the carried pack."
		&"use": return "Use this exact carried item through its source-backed field effect."
		&"identify": return "Cast Identify Objects on every carried item owned by %s." % character.name
		&"join": return "Join this charged record with the first compatible carried stack."
		&"split": return "Split this charged record into two stable carried instances."
		&"drop": return "Continue to the required source-backed drop confirmation for this exact item."
	return "Apply %s to this exact item." % String(action)


static func trade_line(item: ItemView) -> String:
	var parts: Array[String] = ["Equipped" if item.equipped else "Carried", "Weight %d" % item.weight]
	if item.charges > 0:
		parts.append("%d charges" % item.charges)
	return " • ".join(parts)
