class_name CharacterCreationSpec
extends RefCounted

var name: String
var race_id: String
var caste_id: String
var gender: int


func _init(character_name: String, selected_race_id: String, selected_caste_id: String, selected_gender: int = 1) -> void:
	name = character_name.strip_edges()
	race_id = selected_race_id
	caste_id = selected_caste_id
	gender = selected_gender
