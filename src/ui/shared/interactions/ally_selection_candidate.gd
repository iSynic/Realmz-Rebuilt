## Binds one detached surviving-ally candidate to an authored selection row.

extends CheckButton


func bind_candidate(entry: InteractionRequestValue.SelectionCandidate, selected: bool, required: bool, icon_texture: Texture2D) -> void:
	name = "AllyCandidate_%s" % entry.id.replace(".", "_")
	text = entry.name
	if entry.has_current_health:
		var maximum_health := entry.maximum_health if entry.has_maximum_health else entry.current_health
		text += "\nHP %d/%d" % [entry.current_health, maximum_health]
	if required:
		text += "  •  Required"
	set_meta(&"character_id", entry.id)
	set_meta(&"required", required)
	button_pressed = selected
	disabled = required
	icon = icon_texture
