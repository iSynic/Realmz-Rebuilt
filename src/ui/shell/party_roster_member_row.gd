## Exposes the stable controls for one variable party member record.
class_name PartyRosterMemberRow
extends HBoxContainer


func current_marker() -> ColorRect:
	return $CurrentCharacterMarker as ColorRect


func character_button() -> Button:
	return $Character as Button


func selection_number() -> Label:
	return $SelectionNumber as Label


func auto_toggle() -> Button:
	return $CombatAuto as Button
