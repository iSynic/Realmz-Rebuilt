## Presents the dynamic treasure display text interaction without owning gameplay state.

class_name TreasureDisplayText
extends RefCounted

## Formats the player-visible summaries and item facts in the Treasure workspace.


static func summary(body: TreasureRequestBody) -> String:
	var parts: Array[String] = []
	if body.has_remaining:
		parts.append("%d item%s" % [body.remaining, "" if body.remaining == 1 else "s"])
	if body.wealth != null:
		parts.append("%d gold" % body.wealth.gold)
	if body.experience_share > 0:
		parts.append("%d experience each" % body.experience_share)
	return " • ".join(parts)


static func recipient(character: InteractionRequestValue.RewardCharacter) -> String:
	if character.has_health:
		return "%s\nStamina %d/%d" % [character.name, character.current_health, character.maximum_health]
	if character.wealth != null:
		return "%s\nItems %d • Move %d • Load %d/%d" % [character.name, character.item_count, character.maximum_movement, character.carried_load, character.maximum_load]
	return character.name


static func wealth(wealth_record: InteractionRequestValue.Wealth) -> String:
	if wealth_record == null:
		return "Gold 0 • Gems 0 • Jewelry 0"
	return "Gold %d • Gems %d • Jewelry %d" % [wealth_record.gold, wealth_record.gems, wealth_record.jewelry]


static func item_state(item: InteractionRequestValue.RewardItem) -> String:
	if item.magical:
		return "Identified • magic detected" if item.identified else "Magic detected • unidentified"
	return "Identified" if item.identified else "Unidentified"


static func item_detail(item: InteractionRequestValue.RewardItem) -> Dictionary:
	var facts: Array[Dictionary] = []
	for fact: InteractionRequestValue.RewardFact in item.facts:
		facts.append({"label": fact.label, "value": fact.value})
	if item.charges != 0:
		facts.append({"label": "Charges", "value": "Unlimited" if item.charges < 0 else str(item.charges)})
	return {"title": item.name, "subtitle": item_state(item), "description": item.description, "facts": facts, "iconResourceType": item.icon_resource_type, "iconId": item.icon_id}
