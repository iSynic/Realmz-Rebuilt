## Attaches Castle's positive post-defense elemental results to committed attacks.
class_name CombatElementalFeedback
extends RefCounted

const ELEMENT_MEDIA: Dictionary = {
	"fire": [162, 645],
	"cold": [163, 686],
	"electrical": [164, 681],
	"chemical": [165, 640],
	"mental": [166, 630],
}


static func append_attack(event: DomainEvent, resolution: AttackResolution) -> void:
	var recipient := String(event.payload.get("actorId")) if resolution.reflected else String(event.payload.get("targetId"))
	event.payload["resultTargetId"] = recipient
	event.payload["weaponEffects"] = resolution.weapon_effects.duplicate(true)
	event.payload["physicalDamage"] = resolution.physical_damage
	if resolution.physical_damage_skipped: return
	var components: Array[Dictionary] = []
	for effect: Dictionary in resolution.weapon_effects:
		var component := _component(String(effect.get("element", "")), int(effect.get("amount", 0)), recipient, "classic-weapon-element")
		if not component.is_empty(): components.append(component)
	if resolution.special_code >= 11 and resolution.special_code <= 15:
		var special := _component(String(resolution.special_element), resolution.special_damage_amount, recipient, "classic-monster-element")
		if not special.is_empty(): components.append(special)
	if not components.is_empty(): event.payload["elementalResults"] = components


static func _component(element: String, amount: int, recipient: String, source: String) -> Dictionary:
	if amount <= 0 or not ELEMENT_MEDIA.has(element): return {}
	# Castle showdamage selects these cues; misc.c sound(positive ID) uses asynchronous SndPlay.
	var media: Array = ELEMENT_MEDIA[element]
	return {"element": element, "amount": amount, "targetId": recipient, "effectResourceType": "cicn", "effectResourceId": media[0], "soundRequest": {"soundId": media[1], "waitForCompletion": false, "source": source}}
