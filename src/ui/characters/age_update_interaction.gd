## Presents the dynamic age update interaction without owning gameplay state.

class_name AgeUpdateInteraction
extends InteractionComponent

const AGE_CHANGE_ROW_SCENE_PATH := "res://src/ui/characters/age_change_row.tscn"

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
	var body := request.body as AgeUpdateRequestBody
	if body == null:
		add_hint("The age update is unavailable.")
		return
	_bind_identity(body)
	var changes := body.changes
	var grid := %AgeChangeGrid as VBoxContainer
	for index: int in mini(changes.size(), CHANGE_LABELS.size()):
		var amount := changes[index]
		if amount == 0:
			continue
		var row := (load(AGE_CHANGE_ROW_SCENE_PATH) as PackedScene).instantiate() as HBoxContainer
		grid.add_child(row)
		(row.get_node("Fact") as Label).text = CHANGE_LABELS[index]
		var value := row.get_node("Value") as Label
		value.text = "%+d" % amount
		value.add_theme_color_override("font_color", Color("7bdc8b") if amount > 0 else Color("e58a8a"))
	(%NoChanges as Label).visible = grid.get_child_count() == 0
	(%AgeUpdateContinue as Button).pressed.connect(
		func() -> void: response_body_submitted.emit(InteractionResponse.EmptyBody.new())
	)


func _bind_identity(body: AgeUpdateRequestBody) -> void:
	_bind_exact_art(%Portrait as TextureRect, body.portrait_id)
	(%Identity as Label).text = "%s • %s" % [body.character_name, body.race_name]
	(%AgeBand as Label).text = "%s • ages %d–%d" % [
		body.age_group_name,
		body.age_minimum_years,
		body.age_maximum_years,
	]
	var prompt := %Prompt as Label
	prompt.text = body.prompt
	prompt.visible = not body.prompt.is_empty()
	_bind_exact_art(%CombatIcon as TextureRect, body.combat_icon_id)


func _bind_exact_art(art: TextureRect, asset_id: String) -> void:
	art.texture = null
	art.visible = false
	if _media != null and not asset_id.is_empty():
		art.texture = _media.image_texture(_media.asset_by_id(asset_id))
		art.visible = art.texture != null
