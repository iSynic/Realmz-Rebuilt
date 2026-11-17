## Exposes reusable scene dependencies owned by the party-setup workspace.
class_name PartySetupWorkspace
extends PanelContainer

@export_group("Responsive layout")
@export var compact_scenario_minimum_width := 190.0
@export_group("")

@export var character_sheet_scene: PackedScene
@export_file("*.tscn") var identity_step_scene_path: String = "res://src/ui/setup/character_creation_identity_step.tscn"
@export_file("*.tscn") var race_caste_step_scene_path: String = "res://src/ui/setup/character_creation_race_caste_step.tscn"
@export var appearance_step_scene: PackedScene
@export_file("*.tscn") var review_step_scene_path: String = "res://src/ui/setup/character_creation_review_step.tscn"
@export_file("*.tscn") var spells_step_scene_path: String = "res://src/ui/setup/character_creation_spells_step.tscn"

const LEVEL_METER_HEADROOM := 1.25


func _ready() -> void:
	(%SetupBack as Button).pressed.connect(func() -> void: (get_node("Layout/ScenarioPartyWorkspace/ScenarioColumn") as CampaignSelectionPanel).back_requested.emit())
	(%PartyLevelMeter as ProgressBar).resized.connect(_place_recommended_tick)


## Shows the party's total levels against the scenario's recommendation and limit.
func show_party_levels(current: int, recommended: int, maximum: int, experience_percent: int) -> void:
	(%PartyLevelGuidance as Label).text = "Party levels %d" % current
	var facts: PackedStringArray = []
	if recommended > 0: facts.append("Recommended %d" % recommended)
	if maximum > 0: facts.append("Max %d" % maximum)
	facts.append("XP %d%%" % experience_percent if experience_percent > 0 else "XP varies with levels")
	(%ExperienceRatio as Label).text = " · ".join(facts)
	var meter := %PartyLevelMeter as ProgressBar
	meter.visible = recommended > 0 or maximum > 0
	meter.max_value = maxf(1.0, maxf(float(maximum), float(recommended) * LEVEL_METER_HEADROOM))
	meter.value = minf(float(current), meter.max_value)
	meter.set_meta(&"recommended", recommended)
	meter.tooltip_text = "Party levels %d of a recommended %d." % [current, recommended] if recommended > 0 else ""
	_place_recommended_tick()


## Explains why Begin adventure is unavailable; an empty reason hides the line.
func show_begin_reason(reason: String) -> void:
	(%BeginReason as Label).text = reason
	(%BeginReason as Label).visible = not reason.is_empty()


func _place_recommended_tick() -> void:
	var meter := %PartyLevelMeter as ProgressBar
	var recommended: int = meter.get_meta(&"recommended", 0)
	(%RecommendedTick as ColorRect).visible = recommended > 0
	(%RecommendedTick as ColorRect).position.x = meter.size.x * float(recommended) / meter.max_value - 1.0
