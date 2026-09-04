## Exposes reusable scene dependencies owned by the party-setup workspace.
class_name PartySetupWorkspace
extends PanelContainer

@export var character_sheet_scene: PackedScene
@export_file("*.tscn") var identity_step_scene_path: String = "res://src/ui/setup/character_creation_identity_step.tscn"
@export_file("*.tscn") var race_caste_step_scene_path: String = "res://src/ui/setup/character_creation_race_caste_step.tscn"
@export var appearance_step_scene: PackedScene
@export_file("*.tscn") var review_step_scene_path: String = "res://src/ui/setup/character_creation_review_step.tscn"
@export_file("*.tscn") var spells_step_scene_path: String = "res://src/ui/setup/character_creation_spells_step.tscn"
