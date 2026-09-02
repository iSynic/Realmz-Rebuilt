class_name SelectionInteraction
extends InteractionComponent

const SpellTargetBadge := preload("res://src/presentation/classic_spell_target_badge.gd")

const GOLD := Color("e0bc53")
const TEXT := Color("d7d9dc")
const CYAN := Color("8fcfd1")
const MUTED := Color("9ca3ad")

var _checks: Array[CheckButton] = []
var _media: ClassicMediaCatalog
var _game_view: GameView
var _ally_summary: Label
var _ally_maximum := 0
func configure(media: ClassicMediaCatalog, game_view: GameView = null) -> void:
	_media = media
	_game_view = game_view


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
	add_hint("Choose %d party member%s from the Party roster." % [body.count, "" if body.count == 1 else "s"])


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
	var target_badge := SpellTargetBadge.new()
	if target_badge.present(context.target_type, context.target_size, _target_label(context.target_type), Vector2(48.0, 48.0)):
		row.add_child(target_badge)
	else:
		target_badge.free()
	panel.add_child(row)
	add_child(panel)


func _spell_icon(context: InteractionRequestValue.SpellTargetContext) -> Texture2D:
	if _media == null or context.icon_id <= 0:
		return null
	return _media.image_texture(_media.asset_by_resource(context.icon_resource_type, context.icon_id))


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
	if body == null:
		return
	_ally_maximum = body.maximum
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 320.0)
	add_theme_constant_override("separation", 6)
	var header := HBoxContainer.new()
	header.name = "AllySelectionHeader"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)
	var title := _label("Surviving Allies", GOLD, 20)
	title.theme_type_variation = &"ClassicHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var capacity := _label("Keep up to %d" % body.maximum, TEXT, 15)
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(capacity)
	var columns := HBoxContainer.new()
	columns.name = "AllySelectionColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	add_child(columns)
	_build_ally_candidates(columns, body)
	_build_ally_decision(columns)
	_refresh_ally_selection()


func _build_ally_candidates(parent: HBoxContainer, body: InteractionRequest.SelectionRequestBody) -> void:
	var panel := PanelContainer.new()
	panel.name = "AllyCandidates"
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.8
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_label("Choose who continues with the party", GOLD, 16))
	panel.add_child(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "AllyCandidateGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)
	if body.candidates.is_empty():
		grid.add_child(_label("No surviving allies were supplied. Continue returns to the adventure.", MUTED, 14))
		return
	for entry: InteractionRequestValue.SelectionCandidate in body.candidates:
		var required := body.required_ids.has(entry.id)
		_add_character_check(grid, entry, required or body.selected_ids.has(entry.id), required)


func _build_ally_decision(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "AllyDecision"
	panel.theme_type_variation = &"ClassicTextWell"
	panel.custom_minimum_size.x = 260.0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.8
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_label("Party Allies", GOLD, 16))
	_ally_summary = _label("", CYAN, 15)
	content.add_child(_ally_summary)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var submit := Button.new()
	submit.name = "AllySelectionContinue"
	submit.text = "Continue"
	submit.custom_minimum_size.y = 44.0
	submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit.pressed.connect(_submit_allies)
	content.add_child(submit)
	panel.add_child(content)


func _add_character_check(parent: Container, entry: InteractionRequestValue.SelectionCandidate, selected: bool, required: bool) -> void:
	var check := CheckButton.new()
	check.name = "AllyCandidate_%s" % entry.id.replace(".", "_")
	check.text = entry.name
	if entry.has_current_health:
		var maximum_health := entry.maximum_health if entry.has_maximum_health else entry.current_health
		check.text += "\nHP %d/%d" % [entry.current_health, maximum_health]
	if required:
		check.text += "  •  Required"
	check.set_meta("character_id", entry.id)
	check.button_pressed = selected
	check.disabled = required
	check.custom_minimum_size.y = 66.0
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.alignment = HORIZONTAL_ALIGNMENT_LEFT
	check.icon = _ally_icon(entry.id)
	check.expand_icon = true
	check.toggled.connect(func(_pressed: bool) -> void: _refresh_ally_selection())
	_checks.append(check)
	parent.add_child(check)


func _submit_allies() -> void:
	var ids := _selected_ids()
	if ids.size() > _ally_maximum:
		_ally_summary.text = "Choose no more than %d allies." % _ally_maximum
		return
	response_body_submitted.emit(InteractionResponse.AllySelectionBody.new(ids))


func _refresh_ally_selection() -> void:
	if _ally_summary == null:
		return
	var selected := _selected_ids()
	_ally_summary.text = "%d of %d selected" % [selected.size(), _ally_maximum]
	for check: CheckButton in _checks:
		var required := check.disabled and check.button_pressed
		check.disabled = required or not check.button_pressed and selected.size() >= _ally_maximum


func _selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for check: CheckButton in _checks:
		if check.button_pressed:
			ids.append(String(check.get_meta("character_id")))
	return ids


func _ally_icon(ally_id: String) -> Texture2D:
	if _game_view == null or _media == null:
		return null
	if _game_view.combat_view != null:
		for ally: MonsterView in _game_view.combat_view.monsters:
			if ally.id == ally_id and ally.icon_id > 0:
				return _media.image_texture(_media.asset_by_resource(ally.icon_resource_type, ally.icon_id))
	for ally: MonsterView in _game_view.party_allies:
		if ally.id == ally_id and ally.icon_id > 0:
			return _media.image_texture(_media.asset_by_resource(ally.icon_resource_type, ally.icon_id))
	return null
