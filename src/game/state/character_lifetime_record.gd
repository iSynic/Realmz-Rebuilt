class_name CharacterLifetimeRecord
extends RefCounted

var damage_taken: int = 0
var damage_given: int = 0
var hits_given: int = 0
var hits_taken: int = 0
var attacks_missed: int = 0
var enemy_misses: int = 0
var kills: int = 0
var deaths: int = 0
var knockouts: int = 0
var spells_cast: int = 0
var destroyed: int = 0
var turns: int = 0


func prestige(prestige_penalty: int) -> int:
	var damage_delta := damage_given - damage_taken
	var damage_score := floori(float(absi(damage_delta)) / 20.0)
	if damage_delta < 0:
		damage_score = -damage_score
	return _signed_32(hits_given - 2 * hits_taken + enemy_misses - 2 * attacks_missed - 3 * spells_cast + 3 * turns + 2 * destroyed + 3 * kills - 75 * deaths - 35 * knockouts + damage_score - prestige_penalty)


func add_damage_given(amount: int, hit: bool, killed: bool) -> void:
	damage_given = _signed_32(damage_given + amount)
	if hit:
		hits_given = _signed_32(hits_given + 1)
	else:
		attacks_missed = _signed_32(attacks_missed + 1)
	if killed:
		kills = _signed_32(kills + 1)


func add_damage_taken(amount: int, hit: bool) -> void:
	damage_taken = _signed_32(damage_taken + amount)
	if hit:
		hits_taken = _signed_32(hits_taken + 1)
	else:
		enemy_misses = _signed_32(enemy_misses + 1)


func add_damage_taken_without_hit(amount: int) -> void:
	damage_taken = _signed_32(damage_taken + amount)


func add_spell_damage(amount: int, missile_hit: bool, missile_miss: bool, killed: bool) -> void:
	damage_given = _signed_32(damage_given + amount)
	if missile_hit:
		hits_given = _signed_32(hits_given + 1)
	elif missile_miss:
		attacks_missed = _signed_32(attacks_missed + 1)
	if killed:
		kills = _signed_32(kills + 1)


func add_projectile_damage_given(amount: int, hit_count: int, miss_count: int, killed: bool) -> void:
	damage_given = _signed_32(damage_given + amount)
	hits_given = _signed_32(hits_given + hit_count)
	attacks_missed = _signed_32(attacks_missed + miss_count)
	if killed:
		kills = _signed_32(kills + 1)


func add_projectile_damage_taken(amount: int, hit_count: int, miss_count: int) -> void:
	damage_taken = _signed_32(damage_taken + amount)
	hits_taken = _signed_32(hits_taken + hit_count)
	enemy_misses = _signed_32(enemy_misses + miss_count)


func record_knockout() -> void:
	knockouts = _signed_32(knockouts + 1)


func record_death(from_knockout: bool = false) -> void:
	if from_knockout:
		knockouts = _signed_32(knockouts - 1)
	deaths = _signed_32(deaths + 1)


func record_spell_cast() -> void:
	spells_cast = _signed_32(spells_cast + 1)


func record_turn_undead(was_destroyed: bool) -> void:
	if was_destroyed:
		destroyed = _signed_32(destroyed + 1)
	else:
		turns = _signed_32(turns + 1)


func to_data() -> Dictionary:
	return {"damageTaken": damage_taken, "damageGiven": damage_given, "hitsGiven": hits_given, "hitsTaken": hits_taken, "attacksMissed": attacks_missed, "enemyMisses": enemy_misses, "kills": kills, "deaths": deaths, "knockouts": knockouts, "spellsCast": spells_cast, "destroyed": destroyed, "turns": turns}


static func from_data(data: Variant, result: RefCounted) -> RefCounted:
	if not data is Dictionary:
		return null
	var fields: Array[String] = ["damageTaken", "damageGiven", "hitsGiven", "hitsTaken", "attacksMissed", "enemyMisses", "kills", "deaths", "knockouts", "spellsCast", "destroyed", "turns"]
	if result == null:
		return null
	for field: String in fields:
		var value: Variant = data.get(field, 0)
		if not value is int and (not value is float or not is_equal_approx(value, round(value))):
			return null
		result.set(_property_name(field), int(value))
	return result


static func _property_name(field: String) -> String:
	return {"damageTaken": "damage_taken", "damageGiven": "damage_given", "hitsGiven": "hits_given", "hitsTaken": "hits_taken", "attacksMissed": "attacks_missed", "enemyMisses": "enemy_misses", "kills": "kills", "deaths": "deaths", "knockouts": "knockouts", "spellsCast": "spells_cast", "destroyed": "destroyed", "turns": "turns"}[field]


static func _signed_32(value: int) -> int:
	var wrapped := value & 0xffffffff
	return wrapped - 0x1_0000_0000 if wrapped >= 0x8000_0000 else wrapped
