## Projects detached battle identities into the activity strip's fact shape.
class_name BattlePlaybackFacts
extends RefCounted


static func from_combatants(combatants: Array[InteractionRequestValue.Combatant], icons: Dictionary) -> Dictionary:
	var facts: Dictionary = {}
	for combatant: InteractionRequestValue.Combatant in combatants:
		facts[combatant.id] = _entry(combatant.name, combatant.maximum_health, combatant.current_health, combatant.armor, combatant.weapon, combatant.attacks, combatant.conditions, icons.get(combatant.id) as Texture2D)
		facts[combatant.id]["weaponCharges"] = combatant.weapon_charges if combatant.has_weapon_charges else -1
	return facts


static func from_view(view: GameView, media: ClassicMediaCatalog) -> Dictionary:
	var facts: Dictionary = {}
	if view == null or view.combat_view == null:
		return facts
	for character: CharacterView in view.party_members:
		var conditions: Array[String] = []
		for index: int in character.condition_values.size():
			if character.condition_values[index] != 0 and index < CharacterView.CONDITION_NAMES.size():
				conditions.append(CharacterView.CONDITION_NAMES[index])
		var icon := media.image_texture(media.asset_by_id(character.combat_icon_id)) if media != null else null
		facts[character.id] = _entry(character.name, character.maximum_health, character.current_health, character.armor, "", character.attacks_per_round, conditions, icon)
	for monster: MonsterView in view.combat_view.monsters:
		var icon := media.image_texture(media.asset_by_resource(monster.icon_resource_type, monster.icon_id)) if media != null else null
		facts[monster.id] = _entry(monster.name, monster.maximum_health, monster.current_health, monster.armor, monster.weapon_name, str(monster.attack_count), monster.conditions, icon)
	return facts


static func _entry(actor_name: String, maximum_health: int, current_health: int, armor: int, weapon: String, attacks: String, conditions: Array[String], icon: Texture2D) -> Dictionary:
	return {
		"name": actor_name,
		"maximumHealth": maximum_health,
		"currentHealth": current_health,
		"armor": armor,
		"weapon": weapon,
		"weaponCharges": -1,
		"attacks": attacks,
		"conditions": conditions.duplicate(),
		"icon": icon,
	}
