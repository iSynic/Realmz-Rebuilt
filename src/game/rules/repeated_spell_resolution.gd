class_name RepeatedSpellResolution
extends GroupSpellResolution

var selected_target_count: int
var excluded_target_ids: Array[String] = []


func _init(was_cast: bool, spell_cost: int, selected_count: int) -> void:
	super(was_cast, spell_cost, 0, 0)
	selected_target_count = selected_count


func exclude_target(target_id: String) -> void:
	excluded_target_ids.append(target_id)
