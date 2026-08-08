class_name AgeUpdateInteraction
extends InteractionComponent

const CHANGE_LABELS: Array[String] = [
	"Brawn",
	"Knowledge",
	"Judgment",
	"Agility",
	"Vitality",
	"Luck",
	"Magic resistance",
	"Maximum movement",
	"Save 1",
	"Save 2",
	"Save 3",
	"Save 4",
	"Save 5",
	"Save 6",
	"Save 7",
]


func build(request: InteractionRequest) -> void:
	var identity := Label.new()
	identity.text = "%s • %s" % [request.payload.get("characterName", "Character"), request.payload.get("raceName", "Unknown race")]
	identity.theme_type_variation = &"ClassicHeading"
	add_child(identity)

	var age_group := String(request.payload.get("ageGroupName", "Unknown"))
	var minimum_years := int(request.payload.get("ageMinimumYears", 0))
	var maximum_years := int(request.payload.get("ageMaximumYears", 0))
	add_hint("%s • ages %d–%d" % [age_group, minimum_years, maximum_years])

	var changes: Variant = request.payload.get("changes", [])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	if changes is Array:
		for index: int in mini(changes.size(), CHANGE_LABELS.size()):
			var amount := int(changes[index])
			if amount == 0:
				continue
			var label := Label.new()
			label.text = CHANGE_LABELS[index]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(label)
			var value := Label.new()
			value.text = "%+d" % amount
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value.add_theme_color_override("font_color", Color("7bdc8b") if amount > 0 else Color("e58a8a"))
			grid.add_child(value)
	if grid.get_child_count() == 0:
		add_hint("This transition changes no listed statistics.")
	add_response("Continue", {})
