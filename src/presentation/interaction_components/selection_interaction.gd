class_name SelectionInteraction
extends InteractionComponent

const GOLD := Color("e0bc53")
const TEXT := Color("d7d9dc")
const MUTED := Color("9ca3ad")

var _checks: Array[CheckButton] = []
var _media: ClassicMediaCatalog


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	if request.kind == &"character_selection":
		_build_character_selection(request)
	else:
		_build_ally_selection(request)


func _build_character_selection(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.CharacterSelectionRequestBody
	if body == null: return
	if body.spell_context != null:
		_add_spell_target_context(body.spell_context)
	add_hint("Pick %d party member%s from the Party roster." % [body.count, "" if body.count == 1 else "s"])


func _add_spell_target_context(context: InteractionRequestValue.SpellTargetContext) -> void:
	var panel := PanelContainer.new()
	panel.name = "SpellTargetContext"
	panel.theme_type_variation = &"ClassicInset"
	panel.tooltip_text = context.description
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon_texture := _spell_icon(context)
	if icon_texture != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(48.0, 48.0)
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)
	var facts := VBoxContainer.new()
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.add_theme_constant_override("separation", 1)
	facts.add_child(_label(context.spell_name, GOLD, 16))
	var source_label: String = String({&"field-spell": "Memorized spell", &"scroll-use": "Scroll", &"item-use": "Item magic"}.get(context.source_kind, "Spell"))
	var cost_label := " • Cost %d SP" % context.spell_point_cost if context.spell_point_cost > 0 else ""
	facts.add_child(_label("%s • Power %d%s" % [source_label, context.power, cost_label], TEXT, 12))
	facts.add_child(_label("%s • %d target%s" % [_target_label(context.target_type), context.target_count, "" if context.target_count == 1 else "s"], MUTED, 12))
	row.add_child(facts)
	var target_art_id := _target_art_id(context.target_type, context.target_size)
	if not target_art_id.is_empty():
		var target_art := TextureRect.new()
		target_art.custom_minimum_size = Vector2(48.0, 48.0)
		target_art.texture = ClassicUiAssetCatalog.texture(target_art_id)
		target_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		target_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		target_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(target_art)
	panel.add_child(row)
	add_child(panel)


func _spell_icon(context: InteractionRequestValue.SpellTargetContext) -> Texture2D:
	if _media == null or context.icon_id <= 0:
		return null
	return _media.image_texture(_media.asset_by_resource(context.icon_resource_type, context.icon_id))


static func _target_art_id(target_type: int, target_size: int) -> StringName:
	if target_type == 5 and target_size == 0:
		return &"spells.target.self"
	return {9: &"spells.target.all_friendly", 10: &"spells.target.all_enemy", 12: &"spells.target.everyone"}.get(target_type, &"")


static func _target_label(target_type: int) -> String:
	return {0: "Up to power", 1: "Party member", 3: "Fixed area", 4: "Power-sized area", 5: "Caster", 7: "Party state", 9: "All friendly", 10: "All enemies", 12: "Everybody"}.get(target_type, "Classic target type %d" % target_type)


static func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label


func _build_ally_selection(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.SelectionRequestBody
	if body == null: return
	var maximum := body.maximum
	var selected := body.selected_ids
	add_hint("Choose up to %d surviving allies. Required allies stay selected." % maximum)
	for entry: InteractionRequestValue.SelectionCandidate in body.candidates:
		var ally_id := entry.id
		var required := body.required_ids.has(ally_id)
		_add_character_check(entry, required or selected.has(ally_id), required)
	var submit := Button.new()
	submit.text = "Continue"
	submit.pressed.connect(_submit_allies.bind(maximum))
	add_child(submit)


func _add_character_check(entry: InteractionRequestValue.SelectionCandidate, selected: bool, required: bool) -> void:
	var check := CheckButton.new()
	check.text = entry.name
	if entry.has_current_health:
		var maximum_health := entry.maximum_health if entry.has_maximum_health else entry.current_health
		check.text += " • HP %d/%d" % [entry.current_health, maximum_health]
	if required:
		check.text += " • Required"
	check.set_meta("character_id", entry.id)
	check.button_pressed = selected
	check.disabled = required
	_checks.append(check)
	add_child(check)


func _submit_allies(maximum: int) -> void:
	var ids := _selected_ids()
	if ids.size() > maximum:
		add_hint("Choose no more than %d allies." % maximum)
		return
	response_body_submitted.emit(InteractionResponse.AllySelectionBody.new(ids))


func _selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for check: CheckButton in _checks:
		if check.button_pressed:
			ids.append(String(check.get_meta("character_id")))
	return ids
