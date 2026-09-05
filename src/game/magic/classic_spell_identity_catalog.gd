## Classifies packed Classic spell identities by application-library ownership.

class_name ClassicSpellIdentityCatalog
extends RefCounted

const ROLE_STOCK_PLAYER: StringName = &"stock-player"
const ROLE_APPLICATION_EFFECT: StringName = &"application-effect"
const ROLE_RESERVED_STANDARD: StringName = &"reserved-standard-slot"
const ROLE_UNKNOWN: StringName = &"unknown"


static func packed_family(spell: SpellDefinition) -> int:
	return spell.classic_id / 1000


static func packed_level(spell: SpellDefinition) -> int:
	return spell.classic_id % 1000 / 100


static func packed_slot(spell: SpellDefinition) -> int:
	return spell.classic_id % 100


static func application_role(spell: SpellDefinition) -> StringName:
	var family := packed_family(spell)
	var level := packed_level(spell)
	var slot := packed_slot(spell)
	if family in [1, 2, 3] and level in range(1, 8):
		return ROLE_STOCK_PLAYER if slot in range(1, 13) else ROLE_RESERVED_STANDARD if slot in range(13, 16) else ROLE_UNKNOWN
	if family == 4 and level in range(1, 8) and slot in range(1, 16):
		return ROLE_APPLICATION_EFFECT
	return ROLE_UNKNOWN
