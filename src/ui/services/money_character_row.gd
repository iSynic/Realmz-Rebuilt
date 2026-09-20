## Binds one party-ledger selector to a detached money character.
class_name MoneyCharacterRow
extends Button


func bind(character: MoneyCharacterView, selected: bool, group: ButtonGroup, media: ClassicMediaCatalog) -> void:
	name = "MoneyCharacter_%s" % character.character_id
	var portrait := $Content/Portrait as TextureRect
	portrait.texture = media.image_texture(media.asset_by_id(character.portrait_id)) if media != null else null
	($Content/Facts/Name as Label).text = character.name
	($Content/Facts/Wealth as Label).text = "%d gold  ·  %d %s  ·  %d jewelry" % [character.gold, character.gems, "gem" if character.gems == 1 else "gems", character.jewelry]
	button_group = group
	button_pressed = selected
