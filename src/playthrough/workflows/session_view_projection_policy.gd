class_name SessionViewProjectionPolicy
extends RefCounted


static func field_spell_effect_supported(spell: SpellDefinition) -> bool:
	return ClassicSpellCapabilityCatalog.field_character_disposition(spell) == ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE


static func first_empty_scroll_slot(character: CharacterState) -> int:
	if character == null:
		return -1
	for index: int in character.scroll_case().size():
		if character.scroll_at(index).is_empty():
			return index
	return -1


static func item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null or instance_id.is_empty():
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func money_kind(value: StringName) -> int:
	match value:
		&"gold": return WealthState.Kind.GOLD
		&"gems": return WealthState.Kind.GEMS
		&"jewelry": return WealthState.Kind.JEWELRY
	return -1


static func classic_darkness_level(torch_value: int) -> int:
	return 0 if torch_value <= 0 else clampi(floori(float(torch_value) / 30.0) + 1, 0, 6)
