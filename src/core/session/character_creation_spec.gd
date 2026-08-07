class_name CharacterCreationSpec
extends RefCounted

var name: String
var race_id: String
var caste_id: String
var gender: int
var portrait_id: String = ""
var combat_icon_id: String = ""


func _init(character_name: String, selected_race_id: String, selected_caste_id: String, selected_gender: int = 1, selected_portrait_id: String = "", selected_combat_icon_id: String = "") -> void:
	name = character_name.strip_edges()
	race_id = selected_race_id
	caste_id = selected_caste_id
	gender = selected_gender
	portrait_id = selected_portrait_id
	combat_icon_id = selected_combat_icon_id
