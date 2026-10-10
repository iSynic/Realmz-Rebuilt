## Formats committed combat result facts for presentation-only playback.
class_name CombatPlaybackResultText
extends RefCounted


static func kind(payload: Dictionary) -> StringName:
	if bool(payload.get("fumble", false)):
		return &"fumble"
	if bool(payload.get("blocked", false)):
		return &"blocked"
	if bool(payload.get("immune", false)):
		return &"immune"
	if bool(payload.get("resisted", false)):
		return &"resisted"
	if bool(payload.get("saved", false)):
		return &"saved"
	if not bool(payload.get("hit", true)):
		return &"miss"
	if int(payload.get("healing", 0)) > 0:
		return &"healing"
	if int(payload.get("damage", 0)) > 0:
		return &"damage"
	if payload.has("appliedCondition") or payload.has("partyCondition"):
		return &"condition"
	if int(payload.get("clearedConditionCount", 0)) > 0 or payload.has("clearedCondition"):
		return &"condition_cleared"
	if int(payload.get("spellPointDelta", 0)) != 0:
		return &"spell_points"
	if bool(payload.get("allegianceChanged", false)) or payload.has("traitorAfter"):
		return &"allegiance"
	if payload.has("transformedDefinitionAfter"):
		return &"transformed"
	if not String(payload.get("specialResult", "")).is_empty():
		return StringName(payload.get("specialResult"))
	if int(payload.get("duration", 0)) > 0:
		return &"affected"
	return &"no_effect"


static func text_for(result_kind: StringName, amount: int, payload: Dictionary = {}) -> String:
	if result_kind == &"condition" or result_kind == &"condition_cleared":
		var prefix := "Condition applied" if result_kind == &"condition" else "Condition cleared"
		var character_key := "appliedCondition" if result_kind == &"condition" else "clearedCondition"
		if payload.has(character_key):
			var index := int(payload[character_key])
			var name := CharacterView.CONDITION_NAMES[index] if index >= 0 and index < CharacterView.CONDITION_NAMES.size() else "Classic condition %d" % (index + 1)
			return "%s: %s" % [prefix, name]
		if result_kind == &"condition" and payload.has("partyCondition"):
			var index := int(payload["partyCondition"])
			var name := "Torch Lit" if index == ConditionRules.PARTY_TORCH_LIT else ClassicPartyEffects.NAMES[index - 1] if index > 0 and index <= ClassicPartyEffects.NAMES.size() else "Party condition %d" % (index + 1)
			return "%s: %s" % [prefix, name]
		return prefix
	match result_kind:
		&"miss":
			return "Miss"
		&"blocked":
			return "Blocked"
		&"immune":
			return "Immune"
		&"resisted":
			return "Resist"
		&"saved":
			return "Saved"
		&"fumble":
			return "Fumble"
		&"healing":
			return "+%d" % amount
		&"damage":
			return str(amount)
		&"spell_points":
			return "Spell points changed"
		&"allegiance":
			return "Allegiance changed"
		&"transformed":
			return "Transformed"
		&"affected":
			return "Affected"
	return "No effect"
