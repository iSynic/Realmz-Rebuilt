## Binds one party-ledger selector to a detached money character.
class_name MoneyCharacterRow
extends Button


func bind(character: MoneyCharacterView, selected: bool, group: ButtonGroup) -> void:
	name = "MoneyCharacter_%s" % character.character_id
	text = "%s\n%d gold  •  %d gems  •  %d jewelry  •  Load %d/%d" % [
		character.name,
		character.gold,
		character.gems,
		character.jewelry,
		character.carried_load,
		character.maximum_load,
	]
	button_group = group
	button_pressed = selected
