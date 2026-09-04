## Routes immutable package record families to focused strict decoders.

class_name PackageContentDecoder
extends PackageDecoderBase

var _story: PackageStoryContentDecoder
var _characters: PackageCharacterContentDecoder
var _encounters: PackageEncounterContentDecoder


func _init(diagnostic: Dictionary = {}) -> void:
	super(diagnostic)
	_story = PackageStoryContentDecoder.new(_diagnostic)
	_characters = PackageCharacterContentDecoder.new(_diagnostic)
	_encounters = PackageEncounterContentDecoder.new(_diagnostic)


func decode_campaign_definition(value: Variant) -> CampaignDefinition:
	return _story.decode_campaign_definition(value)


func decode_messages(value: Variant) -> Variant:
	return _story.decode_messages(value)


func decode_option_labels(value: Variant) -> Variant:
	return _story.decode_option_labels(value)


func decode_items(value: Variant) -> Variant:
	return _characters.decode_items(value)


func decode_races(value: Variant) -> Variant:
	return _characters.decode_races(value)


func decode_castes(value: Variant) -> Variant:
	return _characters.decode_castes(value)


func decode_spells(value: Variant) -> Variant:
	return _characters.decode_spells(value)


func decode_monsters(value: Variant) -> Variant:
	return _encounters.decode_monsters(value)


func decode_monster_sets(value: Variant) -> Variant:
	return _encounters.decode_monster_sets(value)


func decode_battles(value: Variant) -> Variant:
	return _encounters.decode_battles(value)


func decode_treasures(value: Variant) -> Variant:
	return _encounters.decode_treasures(value)


func decode_shops(value: Variant) -> Variant:
	return _encounters.decode_shops(value)


func decode_simple_encounters(value: Variant) -> Variant:
	return _encounters.decode_simple_encounters(value)


func decode_complex_encounters(value: Variant) -> Variant:
	return _encounters.decode_complex_encounters(value)


func decode_thief_encounters(value: Variant) -> Variant:
	return _encounters.decode_thief_encounters(value)


func decode_timed_encounters(value: Variant) -> Variant:
	return _encounters.decode_timed_encounters(value)
