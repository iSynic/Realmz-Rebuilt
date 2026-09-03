## Implements deterministic spell rolls rules without presentation dependencies.

class_name SpellRolls
extends RefCounted

## Resolves the repeated base-and-power dice pattern shared by Realmz spell effects.


static func scaled(base_min: int, base_max: int, power_min: int, power_max: int, power_level: int, rng: RealmzRng, tag: StringName) -> int:
	var total := rng.draw_between(base_min, base_max, tag) if base_max >= base_min else 0
	if power_min != 0:
		for index: int in power_level:
			if power_max >= power_min:
				total += rng.draw_between(power_min, power_max, StringName("%s.power.%d" % [tag, index]))
	return total
