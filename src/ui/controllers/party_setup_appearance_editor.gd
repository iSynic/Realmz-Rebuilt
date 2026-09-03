## Builds and manages the character creator's portrait and battle-icon browser.
class_name PartySetupAppearanceEditor
extends RefCounted

const COLUMNS: int = 6
const ROWS_PER_PAGE: int = 2

var _owner_ref: WeakRef
var _portrait_page: int = 0
var _combat_icon_page: int = 0


func _init(owner: RefCounted) -> void:
	_owner_ref = weakref(owner)


func _owner():
	return _owner_ref.get_ref()


func reset_pages() -> void:
	_portrait_page = 0
	_combat_icon_page = 0


func build() -> void:
	var owner = _owner()
	owner.creator_page.add_child(owner._label("Appearance", owner.GOLD, 20))
	var selected_asset_ids: Array[String] = []
	if not owner.draft_portrait_id.is_empty(): selected_asset_ids.append(owner.draft_portrait_id)
	if not owner.draft_combat_icon_id.is_empty(): selected_asset_ids.append(owner.draft_combat_icon_id)
	owner._ensure_appearance_textures(selected_asset_ids)
	var appearance_row := HBoxContainer.new()
	appearance_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appearance_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	appearance_row.add_theme_constant_override("separation", 14)
	appearance_row.add_child(_build_preview(owner))
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 8)
	var portrait_options := _sorted_options(owner, owner.view.portrait_options if owner.view != null else [])
	owner.portrait_option = _build_option_control(owner, portrait_options, true)
	choices.add_child(owner.portrait_option)
	choices.add_child(_build_thumbnail_strip(owner, owner.portrait_option, portrait_options, "PortraitThumbnailStrip", true))
	var combat_options := _sorted_options(owner, owner.view.combat_icon_options if owner.view != null else [])
	owner.combat_icon_option = _build_option_control(owner, combat_options, false)
	choices.add_child(owner.combat_icon_option)
	choices.add_child(_build_thumbnail_strip(owner, owner.combat_icon_option, combat_options, "CombatIconThumbnailStrip", false))
	appearance_row.add_child(choices)
	owner.creator_page.add_child(appearance_row)
	_refresh_preview(owner)
	if portrait_options.is_empty() or combat_options.is_empty():
		owner._add_label(owner.creator_page, "This package does not expose the complete Classic appearance catalog. Character generation is unavailable until the package is re-exported.", owner.ERROR)


func _build_preview(owner) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "AppearancePreview"
	panel.theme_type_variation = &"ClassicInset"
	panel.custom_minimum_size = Vector2(220.0, 300.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var portrait_heading: Label = owner._label("Character Portrait", owner.GOLD, 14)
	portrait_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(portrait_heading)
	owner.portrait_preview = _preview_texture("PortraitPreview", Vector2(176.0, 176.0))
	column.add_child(owner.portrait_preview)
	var icon_row := HBoxContainer.new()
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_row.add_theme_constant_override("separation", 8)
	owner.combat_icon_preview = _preview_texture("CombatIconPreview", Vector2(96.0, 96.0))
	icon_row.add_child(owner.combat_icon_preview)
	icon_row.add_child(owner._label("Battle icon", owner.MUTED, 13))
	column.add_child(icon_row)
	return panel


static func _preview_texture(node_name: String, minimum_size: Vector2) -> TextureRect:
	var preview := TextureRect.new()
	preview.name = node_name
	preview.custom_minimum_size = minimum_size
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return preview


func _build_option_control(owner, options: Array[CharacterAppearanceOptionView], portrait: bool) -> OptionButton:
	var control := OptionButton.new()
	control.name = "PortraitOption" if portrait else "CombatIconOption"
	control.fit_to_longest_item = false
	for option: CharacterAppearanceOptionView in options:
		_add_option(owner, control, option)
	_select_default(owner, control, owner.draft_portrait_id if portrait else owner.draft_combat_icon_id, portrait)
	if control.selected >= 0:
		if portrait: owner.draft_portrait_id = String(control.get_item_metadata(control.selected))
		else: owner.draft_combat_icon_id = String(control.get_item_metadata(control.selected))
	control.visible = false
	return control


func _build_thumbnail_strip(owner, control: OptionButton, options: Array[CharacterAppearanceOptionView], strip_name: String, portrait: bool) -> Control:
	var panel := PanelContainer.new()
	panel.name = strip_name
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(body)
	var header := HBoxContainer.new()
	header.add_child(owner._label("Portraits" if portrait else "Combat Icons", owner.GOLD, 15))
	header.add_spacer(true)
	var rows := _rows(owner, options)
	var page := _portrait_page if portrait else _combat_icon_page
	var page_count := maxi(1, int(ceil(float(rows.size()) / float(ROWS_PER_PAGE))))
	page = clampi(page, 0, page_count - 1)
	if portrait: _portrait_page = page
	else: _combat_icon_page = page
	var previous := Button.new()
	previous.text = "Previous"
	previous.disabled = page == 0
	previous.pressed.connect(_change_page.bind(-1, portrait))
	header.add_child(previous)
	header.add_child(owner._label("Page %d of %d" % [page + 1, page_count], owner.MUTED, 12))
	var next_button := Button.new()
	next_button.text = "Next"
	next_button.disabled = page >= page_count - 1
	next_button.pressed.connect(_change_page.bind(1, portrait))
	header.add_child(next_button)
	body.add_child(header)
	var group := ButtonGroup.new()
	var selected_id := String(control.get_item_metadata(control.selected)) if control.selected >= 0 else ""
	var start_row := page * ROWS_PER_PAGE
	var finish_row := mini(start_row + ROWS_PER_PAGE, rows.size())
	var visible_asset_ids: Array[String] = []
	for row_index: int in range(start_row, finish_row):
		for option: CharacterAppearanceOptionView in (rows[row_index]["options"] as Array): visible_asset_ids.append(option.id)
	owner._ensure_appearance_textures(visible_asset_ids)
	for row_index: int in range(start_row, finish_row):
		_add_thumbnail_row(owner, body, group, control, rows[row_index], row_index, selected_id, portrait)
	if rows.is_empty(): body.add_child(owner._label("No exact Classic appearance media is available.", owner.MUTED, 12))
	return panel


func _add_thumbnail_row(owner, body: VBoxContainer, group: ButtonGroup, control: OptionButton, row_record: Dictionary, row_index: int, selected_id: String, portrait: bool) -> void:
	var section := VBoxContainer.new()
	section.name = "%sRaceRow%d" % ["Portrait" if portrait else "CombatIcon", row_index]
	section.add_theme_constant_override("separation", 2)
	var row_label: Label = owner._label(String(row_record["label"]), owner.MUTED, 12)
	row_label.name = "%sRaceLabel%d" % ["Portrait" if portrait else "CombatIcon", row_index]
	section.add_child(row_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(row)
	body.add_child(section)
	var options: Array = row_record["options"] as Array
	for column_index: int in COLUMNS:
		if column_index >= options.size():
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spacer)
			continue
		var option: CharacterAppearanceOptionView = options[column_index]
		var choice := Button.new()
		choice.name = "%s_%d" % ["PortraitChoice" if portrait else "CombatIconChoice", option.classic_resource_id]
		choice.custom_minimum_size = Vector2(72.0, 72.0)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.toggle_mode = true
		choice.button_group = group
		choice.button_pressed = option.id == selected_id
		choice.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var texture := owner._appearance_textures.get(option.id) as Texture2D
		if texture != null:
			choice.icon = texture
			choice.expand_icon = true
		else: choice.text = "Unavailable"
		choice.tooltip_text = option.label
		choice.pressed.connect(_select_thumbnail.bind(control, option.id, portrait))
		row.add_child(choice)


func _rows(owner, options: Array[CharacterAppearanceOptionView]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ordered_races: Array[DefinitionOptionView] = []
	if owner.view != null:
		for race: DefinitionOptionView in owner.view.race_options:
			if race.id == owner.selected_race_id: ordered_races.push_front(race)
			else: ordered_races.append(race)
	var assigned: Dictionary = {}
	for race: DefinitionOptionView in ordered_races:
		var recommended: Array[CharacterAppearanceOptionView] = []
		for option: CharacterAppearanceOptionView in options:
			if option.is_recommended_for(race.id):
				recommended.append(option)
				assigned[option.id] = true
		_append_rows(rows, race.name, recommended)
	var ungrouped: Array[CharacterAppearanceOptionView] = []
	for option: CharacterAppearanceOptionView in options:
		if not assigned.has(option.id): ungrouped.append(option)
	_append_rows(rows, "Classic catalog", ungrouped)
	return rows


static func _append_rows(rows: Array[Dictionary], label: String, options: Array[CharacterAppearanceOptionView]) -> void:
	for start: int in range(0, options.size(), COLUMNS):
		var chunk: Array[CharacterAppearanceOptionView] = []
		for option_index: int in range(start, mini(start + COLUMNS, options.size())): chunk.append(options[option_index])
		rows.append({"label": label, "options": chunk})


func _change_page(delta: int, portrait: bool) -> void:
	if portrait: _portrait_page += delta
	else: _combat_icon_page += delta
	_owner().render_creator_step()


func _select_thumbnail(control: OptionButton, option_id: String, portrait: bool) -> void:
	var owner = _owner()
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) != option_id: continue
		control.select(index)
		if portrait:
			owner.draft_portrait_id = option_id
			_portrait_selected(owner)
		else:
			owner.draft_combat_icon_id = option_id
			_combat_icon_selected(owner)
		owner.render_creator_step()
		return


func _sorted_options(owner, source: Array[CharacterAppearanceOptionView]) -> Array[CharacterAppearanceOptionView]:
	var result := source.duplicate()
	result.sort_custom(func(left: CharacterAppearanceOptionView, right: CharacterAppearanceOptionView) -> bool:
		var left_recommended := left.is_recommended_for(owner.selected_race_id)
		var right_recommended := right.is_recommended_for(owner.selected_race_id)
		if left_recommended != right_recommended: return left_recommended
		return left.classic_resource_id < right.classic_resource_id)
	return result


static func _add_option(owner, control: OptionButton, option: CharacterAppearanceOptionView) -> void:
	var texture := owner._appearance_textures.get(option.id) as Texture2D
	if texture != null: control.add_icon_item(texture, option.label)
	else: control.add_item(option.label)
	var index := control.item_count - 1
	control.set_item_metadata(index, option.id)
	control.set_item_tooltip(index, option.label)


func _select_default(owner, control: OptionButton, selected_id: String, portrait: bool) -> void:
	if control.item_count == 0: return
	var target_id := selected_id
	if target_id.is_empty() and portrait:
		for index: int in control.item_count:
			var option := option_by_id(String(control.get_item_metadata(index)), true)
			if option != null and option.is_recommended_for(owner.selected_race_id):
				target_id = option.id
				break
	if target_id.is_empty() and not portrait:
		var portrait_value := selected(owner.portrait_option, true)
		if portrait_value != null:
			var wanted_resource_id := 9000 - 257 + portrait_value.classic_resource_id
			for option: CharacterAppearanceOptionView in owner.view.combat_icon_options:
				if option.classic_resource_id == wanted_resource_id:
					target_id = option.id
					break
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) == target_id:
			control.select(index)
			return
	control.select(0)


func _portrait_selected(owner) -> void:
	if not owner.combat_icon_touched and owner.combat_icon_option != null:
		var portrait_value := selected(owner.portrait_option, true)
		if portrait_value != null:
			var wanted_resource_id := 9000 - 257 + portrait_value.classic_resource_id
			for index: int in owner.combat_icon_option.item_count:
				var icon := option_by_id(String(owner.combat_icon_option.get_item_metadata(index)), false)
				if icon != null and icon.classic_resource_id == wanted_resource_id:
					owner.combat_icon_option.select(index)
					owner.draft_combat_icon_id = icon.id
					break
	_refresh_preview(owner)


func _combat_icon_selected(owner) -> void:
	owner.combat_icon_touched = true
	_refresh_preview(owner)


func _refresh_preview(owner) -> void:
	if owner.portrait_preview != null:
		var portrait_id := String(owner.portrait_option.get_item_metadata(owner.portrait_option.selected)) if owner.portrait_option != null and owner.portrait_option.selected >= 0 else ""
		owner.portrait_preview.texture = owner._appearance_textures.get(portrait_id) as Texture2D
	if owner.combat_icon_preview != null:
		var icon_id := String(owner.combat_icon_option.get_item_metadata(owner.combat_icon_option.selected)) if owner.combat_icon_option != null and owner.combat_icon_option.selected >= 0 else ""
		owner.combat_icon_preview.texture = owner._appearance_textures.get(icon_id) as Texture2D


func selected(control: OptionButton, portrait: bool) -> CharacterAppearanceOptionView:
	if control == null or control.selected < 0: return null
	return option_by_id(String(control.get_item_metadata(control.selected)), portrait)


func option_by_id(option_id: String, portrait: bool) -> CharacterAppearanceOptionView:
	var owner = _owner()
	var options: Array[CharacterAppearanceOptionView] = owner.view.portrait_options if portrait else owner.view.combat_icon_options
	for option: CharacterAppearanceOptionView in options:
		if option.id == option_id: return option
	return null
