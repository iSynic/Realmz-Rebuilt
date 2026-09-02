class_name CharacterFileIdentity
extends RefCounted

var character_id: String
var seed: int


func _init(value_character_id: String, value_seed: int) -> void:
	character_id = value_character_id
	seed = value_seed
