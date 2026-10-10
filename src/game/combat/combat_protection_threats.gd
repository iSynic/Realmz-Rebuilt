## Rebuilt tactical policy: defensive buffs require a matching current threat.
class_name CombatProtectionThreats
extends RefCounted

var _conditions: Dictionary = {}
var _unknown_macro := false


func _init(state: GameState, content: RealmzContent, friendly_traitor: bool) -> void:
	if state.combat == null: return
	for character: CharacterState in state.party.characters():
		if character.current_health <= 0 or character.traitor == friendly_traitor or not state.combat.battlefield.actors.has_actor(character.id): continue
		if not state.character_spellcasting_blocked:
			for spell_id: String in character.known_spells():
				var spell := content.magic.spell_by_id(spell_id)
				if spell != null and character.spell_points >= absi(spell.cost): _spell(spell)
		for instance: ItemInstance in character.inventory():
			var item := content.items.item_by_id(instance.definition_id)
			if item == null: continue
			if instance.equipped: _weapon(item)
			if instance.charges != 0: _spell(content.magic.spell_by_classic_id(absi(item.special_2)))
		for slot: int in 5:
			var scroll := character.scroll_at(slot)
			if scroll != null and not scroll.is_empty(): _spell(content.magic.spell_by_id(scroll.spell_id))
	for monster: MonsterState in state.combat.roster.monsters():
		if monster.current_health <= 0 or monster.traitor == friendly_traitor or not state.combat.battlefield.actors.has_actor(monster.id): continue
		var definition := content.combat.monster_by_id(monster.definition_id)
		if definition == null: continue
		_unknown_macro = _unknown_macro or definition.death_macro != 0
		_weapon(content.items.item_by_id(monster.weapon_id))
		for attack: MonsterAttackDefinition in definition.attacks():
			if attack.damage_min > 0 and attack.special >= 11 and attack.special <= 15:
				_conditions[attack.special] = true
		if not state.monster_spellcasting_blocked and definition.magic_attack_count > 0:
			for spell_id: String in definition.spell_ids():
				var spell := content.magic.spell_by_id(spell_id)
				if spell != null and spell.cost >= 0 and monster.spell_points >= spell.cost: _spell(spell)
		if definition.missile_percent > 0:
			var item := content.items.item_by_id(definition.item_id_at(1))
			if item != null: _spell(content.magic.spell_by_classic_id(absi(item.special_2)))
	# Fields can affect either allegiance, including after their caster dies.
	for field: PersistentCombatField in state.combat.spell_runtime.persistent_fields():
		_spell(content.magic.spell_by_id(field.spell_id))


func supports(condition_index: int) -> bool:
	if not is_ward(condition_index): return true
	return _unknown_macro or _conditions.has(condition_index)


static func is_ward(condition_index: int) -> bool:
	return condition_index == ConditionRules.SHIELD_FROM_PROJECTILES or condition_index >= 11 and condition_index <= 20


func _weapon(item: ItemDefinition) -> void:
	if item == null: return
	if item.heat != 0: _conditions[ConditionRules.FIRE_PROTECTION] = true
	if item.cold != 0: _conditions[ConditionRules.COLD_PROTECTION] = true
	if item.electric != 0: _conditions[ConditionRules.ELECTRICAL_PROTECTION] = true


func _spell(spell: SpellDefinition) -> void:
	if spell == null or not spell.in_combat: return
	if spell.cannot == 4 or spell.target_type in [5, 7, 9] and spell.queue_icon == 0: return
	var damage_type := absi(spell.damage_type)
	if damage_type in range(1, 8) and maxi(spell.damage_min, spell.damage_max) + 7 * maxi(spell.power_damage_min, spell.power_damage_max) > 0:
		_conditions[ConditionRules.FIRE_PROTECTION + damage_type - 1] = true
	if absi(spell.spell_class) == 9: _conditions[ConditionRules.SHIELD_FROM_PROJECTILES] = true
	# Match the resolver's cumulative level ward gate, including its cannot bypass.
	if spell.cannot != 1 and spell.cannot <= 2 or absi(spell.spell_class) == 9:
		for level: int in range(spell.classic_tier(), 5): _conditions[16 + level] = true
