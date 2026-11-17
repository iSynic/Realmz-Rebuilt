## Shades a party member's stamina and spell-point readouts by how much is left, for the
## roster's numbers and the party dock's bars alike.
class_name RosterVitalColors
extends RefCounted

const TEXT_FULL := Color.WHITE
## Stamina numbers redden as stamina falls and are fully red at a quarter or less.
const STAMINA_TEXT_LOW := Color("e66e6d")
const STAMINA_BAR_FULL := Color(0.85, 0.33, 0.31)
const STAMINA_BAR_LOW := Color(1.0, 0.2, 0.16)
## Spell points darken towards purple all the way down. The number stops at a purple that
## still reads on a dark panel; the bar, which is nearly empty by then, goes darker.
const SPELL_TEXT_LOW := Color(0.52, 0.34, 0.76)
const SPELL_BAR_FULL := Color(0.36, 0.55, 0.94)
const SPELL_BAR_LOW := Color(0.3, 0.14, 0.48)


static func stamina_text(fraction: float) -> Color:
	return TEXT_FULL.lerp(STAMINA_TEXT_LOW, _stamina_loss(fraction))


static func stamina_bar(fraction: float) -> Color:
	return STAMINA_BAR_FULL.lerp(STAMINA_BAR_LOW, _stamina_loss(fraction))


static func spell_text(fraction: float) -> Color:
	return TEXT_FULL.lerp(SPELL_TEXT_LOW, clampf(1.0 - fraction, 0.0, 1.0))


static func spell_bar(fraction: float) -> Color:
	return SPELL_BAR_FULL.lerp(SPELL_BAR_LOW, clampf(1.0 - fraction, 0.0, 1.0))


static func _stamina_loss(fraction: float) -> float:
	return clampf((1.0 - fraction) / 0.75, 0.0, 1.0)
