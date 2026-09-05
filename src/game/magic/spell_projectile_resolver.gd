## Resolves character and monster projectile spell attacks.

class_name SpellProjectileResolver
extends SpellResolutionSupport

func resolve_character_projectile(caster: CharacterState, caste: CasteDefinition, projectile_item: ItemDefinition, target: MonsterState, spell: SpellDefinition, power_level: int, rng: RealmzRng) -> ProjectileResolution:
	if caster == null or projectile_item == null or target == null or spell == null or rng == null or power_level < 0 or absi(spell.spell_class) != 9 or absi(spell.damage_type) != 9 or spell.special != 0:
		return null
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"combat.projectile.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"combat.projectile.damage")
	damage += projectile_item.damage_bonus
	var effective_to_hit := spell.to_hit_bonus + 5 * projectile_item.damage_bonus
	if caste != null and caste.gets_missile_bonus:
		damage += rng.draw_between(1, maxi(1, caster.level / 2), &"combat.projectile.caste-bonus")
	var hit_count := 0
	var miss_count := 0
	var total_damage := 0
	var maximum_hits := maxi(1, spell.fixed_target_count)
	for hit_index: int in maximum_hits:
		if target.conditions.is_active(ConditionRules.SHIELD_FROM_PROJECTILES):
			miss_count += 1
			break
		var miss_chance := 10 + 5 * target.agility - caster.missile - effective_to_hit
		if rng.draw(100, StringName("combat.projectile.miss.%d" % hit_index)) <= miss_chance:
			miss_count += 1
			break
		target.current_health -= damage
		hit_count += 1
		total_damage += damage
		if target.current_health <= 0:
			break
	return ProjectileResolution.new(true, hit_count, miss_count, total_damage, damage, duration, target.current_health <= 0)


func resolve_monster_projectile(caster: MonsterState, projectile_item: ItemDefinition, target: CharacterState, spell: SpellDefinition, power_level: int, rng: RealmzRng) -> ProjectileResolution:
	if caster == null or projectile_item == null or target == null or spell == null or rng == null or power_level < 0 or absi(spell.spell_class) != 9 or absi(spell.damage_type) != 9 or spell.special != 0:
		return null
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"combat.monster-projectile.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"combat.monster-projectile.damage")
	damage += projectile_item.damage_bonus
	var effective_to_hit := spell.to_hit_bonus + 5 * projectile_item.damage_bonus
	var miss_count := 0
	if target.conditions.is_active(ConditionRules.SHIELD_FROM_PROJECTILES):
		miss_count = 1
	elif rng.draw(100, &"combat.monster-projectile.miss") <= target.dodge - effective_to_hit:
		miss_count = 1
	if miss_count > 0:
		return ProjectileResolution.new(true, 0, miss_count, 0, damage, duration, false)
	target.current_health -= damage
	return ProjectileResolution.new(true, 1, 0, damage, damage, duration, target.current_health <= 0)
