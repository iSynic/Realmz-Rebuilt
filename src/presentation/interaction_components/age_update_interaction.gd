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

var _media: ClassicMediaCatalog


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.AgeUpdateBody
	if body == null:
		add_hint("The age update is unavailable.")
		return
	add_theme_constant_override("separation", 8)
	_build_identity(body)
	var changes_panel := PanelContainer.new()
	changes_panel.name = "AgeChangePanel"
	changes_panel.theme_type_variation = &"ClassicTextWell"
	changes_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(changes_panel)
	var changes := body.changes
	var grid := GridContainer.new()
	grid.name = "AgeChangeGrid"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	changes_panel.add_child(grid)
	for index: int in mini(changes.size(), CHANGE_LABELS.size()):
		var amount := changes[index]
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
	var continue_button := add_response("Continue", InteractionResponse.EmptyBody.new())
	continue_button.name = "AgeUpdateContinue"
	continue_button.theme_type_variation = &"ClassicChoiceButton"


func _build_identity(body: InteractionRequest.AgeUpdateBody) -> void:
	var panel := PanelContainer.new()
	panel.name = "AgeIdentityPanel"
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_add_exact_art(row, body.portrait_id, Vector2(80.0, 80.0), "Portrait")
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var identity := Label.new()
	identity.text = "%s • %s" % [body.character_name, body.race_name]
	identity.theme_type_variation = &"ClassicHeading"
	facts.add_child(identity)
	var age_band := Label.new()
	age_band.text = "%s • ages %d–%d" % [body.age_group_name, body.age_minimum_years, body.age_maximum_years]
	age_band.add_theme_color_override("font_color", Color("d5b45d"))
	facts.add_child(age_band)
	if not body.prompt.is_empty():
		var prompt := Label.new()
		prompt.text = body.prompt
		prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		facts.add_child(prompt)
	row.add_child(facts)
	_add_exact_art(row, body.combat_icon_id, Vector2(64.0, 64.0), "Combat icon")
	panel.add_child(row)
	add_child(panel)


func _add_exact_art(parent: Container, asset_id: String, minimum: Vector2, label: String) -> void:
	if _media == null or asset_id.is_empty():
		return
	var texture := _media.image_texture(_media.asset_by_id(asset_id))
	if texture == null:
		return
	var art := TextureRect.new()
	art.name = "Age%s" % label.replace(" ", "")
	art.custom_minimum_size = minimum
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(art)
