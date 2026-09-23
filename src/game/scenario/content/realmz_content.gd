## Aggregates one immutable campaign identity, world, program, and feature catalogs.

class_name RealmzContent
extends RefCounted

var campaign_id: String
var package_hash: String
var content_id: String
var rules_version: String
var start_map_id: String
var start_coordinate: Vector2i
var world: WorldDefinition
var scenario: ScenarioDefinition
var campaign: CampaignDefinition
var scenario_records: ScenarioContentCatalog
var characters: CharacterCatalog
var items: ItemCatalog
var magic: SpellCatalog
var combat: CombatCatalog
var economy: EconomyContentCatalog
var media_assets: Array[MediaAsset] = []
var compatibility_warnings: Array[ScenarioCompatibilityWarning] = []
var requires_deferred_references: bool = false


func _init(campaign_identity: String, package_identity: String, content_identity: String, rules: String, start_map: String, start_position: Vector2i, world_definition: WorldDefinition, scenario_definition: ScenarioDefinition, messages: Array[MessageDefinition], triggers: Array[TriggerDefinition], simple_encounters: Array[SimpleEncounterDefinition] = [], races: Array[RaceDefinition] = [], castes: Array[CasteDefinition] = [], item_definitions: Array[ItemDefinition] = [], spell_definitions: Array[SpellDefinition] = [], monsters: Array[MonsterDefinition] = [], battles: Array[BattleDefinition] = [], treasures: Array[TreasureDefinition] = [], shops: Array[ShopDefinition] = [], complex_encounters: Array[ComplexEncounterDefinition] = [], thief_encounters: Array[ThiefEncounterDefinition] = [], timed_encounters: Array[TimedEncounterDefinition] = [], option_labels: Array[OptionLabelDefinition] = [], campaign_definition: CampaignDefinition = null, appearance_options: Array[CharacterAppearanceDefinition] = [], monster_sets: Dictionary = {}, deferred_warnings: Array[ScenarioCompatibilityWarning] = [], deferred_references: bool = false, effective_media_assets: Array[MediaAsset] = []) -> void:
	campaign_id = campaign_identity
	package_hash = package_identity
	content_id = content_identity
	rules_version = rules
	start_map_id = start_map
	start_coordinate = start_position
	world = world_definition
	scenario = scenario_definition
	campaign = campaign_definition if campaign_definition != null else CampaignDefinition.new()
	campaign.id = campaign_id if campaign.id.is_empty() else campaign.id
	scenario_records = ScenarioContentCatalog.new(campaign, messages, triggers, simple_encounters, complex_encounters, thief_encounters, timed_encounters, option_labels)
	characters = CharacterCatalog.new(races, castes, appearance_options)
	items = ItemCatalog.new(item_definitions)
	magic = SpellCatalog.new(spell_definitions)
	combat = CombatCatalog.new(monsters, battles, monster_sets)
	economy = EconomyContentCatalog.new(treasures, shops)
	media_assets.assign(effective_media_assets)
	compatibility_warnings.assign(deferred_warnings)
	requires_deferred_references = deferred_references


func compatibility_warning_for(source_kind: StringName, source_id: String, slot: int = -1) -> ScenarioCompatibilityWarning:
	for warning: ScenarioCompatibilityWarning in compatibility_warnings:
		if warning.source_kind == source_kind and warning.source_id == source_id and (slot < 0 or warning.slot == slot):
			return warning
	return null


func has_media_resource(resource_type: String, resource_id: int) -> bool:
	var normalized_type := resource_type.strip_edges().to_upper()
	for asset: MediaAsset in media_assets:
		if asset.resource_type.strip_edges().to_upper() == normalized_type and asset.resource_id == resource_id:
			return true
	return false
