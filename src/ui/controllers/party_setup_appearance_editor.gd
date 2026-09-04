## Binds the character creator's authored portrait and battle-icon browser.

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
	assert(owner.appearance_step_scene != null, "The party-setup workspace must export its appearance step scene.")
	var selected_asset_ids: Array[String] = []
	if not owner.draft_portrait_id.is_empty():
		selected_asset_ids.append(owner.draft_portrait_id)
	if not owner.draft_combat_icon_id.is_empty():
		selected_asset_ids.append(owner.draft_combat_icon_id)
	owner.ensure_appearance_textures(selected_asset_ids)
	var step := owner.appearance_step_scene.instantiate() as CharacterCreationAppearanceStep
	owner.creator_page.add_child(step)
	owner.portrait_preview = step.get_node("%PortraitPreview") as TextureRect
	owner.combat_icon_preview = step.get_node("%CombatIconPreview") as TextureRect
	owner.portrait_option = step.get_node("%PortraitOption") as OptionButton
	owner.combat_icon_option = step.get_node("%CombatIconOption") as OptionButton
	var portrait_options := _sorted_options(owner, owner.view.portrait_options if owner.view != null else [])
	var combat_options := _sorted_options(owner, owner.view.combat_icon_options if owner.view != null else [])
	_populate_option_control(owner, owner.portrait_option, portrait_options, true)
	_populate_option_control(owner, owner.combat_icon_option, combat_options, false)
	_bind_strip(step, owner, owner.portrait_option, portrait_options, true)
	_bind_strip(step, owner, owner.combat_icon_option, combat_options, false)
	var catalog_error := step.get_node("%AppearanceCatalogError") as Label
	catalog_error.visible = portrait_options.is_empty() or combat_options.is_empty()
	_refresh_preview(owner)


func _populate_option_control(owner, control: OptionButton, options: Array[CharacterAppearanceOptionView], portrait: bool) -> void:
	control.clear()
	for option: CharacterAppearanceOptionView in options:
		_add_option(owner, control, option)
	_select_default(owner, control, owner.draft_portrait_id if portrait else owner.draft_combat_icon_id, portrait)
	if control.selected < 0:
		return
	if portrait:
		owner.draft_portrait_id = String(control.get_item_metadata(control.selected))
	else:
		owner.draft_combat_icon_id = String(control.get_item_metadata(control.selected))


func _bind_strip(step: CharacterCreationAppearanceStep, owner, control: OptionButton, options: Array[CharacterAppearanceOptionView], portrait: bool) -> void:
	var prefix := "Portrait" if portrait else "CombatIcon"
	var rows_host := step.get_node("%%%sRows" % prefix) as VBoxContainer
	var previous := step.get_node("%%%sPrevious" % prefix) as Button
	var next_button := step.get_node("%%%sNext" % prefix) as Button
	var page_label := step.get_node("%%%sPage" % prefix) as Label
	var empty_label := step.get_node("%%%sEmpty" % prefix) as Label
	var rows := _rows(owner, options)
	var page := _portrait_page if portrait else _combat_icon_page
	var page_count := maxi(1, int(ceil(float(rows.size()) / float(ROWS_PER_PAGE))))
	page = clampi(page, 0, page_count - 1)
	if portrait:
		_portrait_page = page
	else:
		_combat_icon_page = page
	previous.disabled = page == 0
	next_button.disabled = page >= page_count - 1
	page_label.text = "Page %d of %d" % [page + 1, page_count]
	previous.pressed.connect(_change_page.bind(-1, portrait))
	next_button.pressed.connect(_change_page.bind(1, portrait))
	empty_label.visible = rows.is_empty()
	var group := ButtonGroup.new()
	var selected_id := String(control.get_item_metadata(control.selected)) if control.selected >= 0 else ""
	var start_row := page * ROWS_PER_PAGE
	var finish_row := mini(start_row + ROWS_PER_PAGE, rows.size())
	var visible_asset_ids: Array[String] = []
	for row_index: int in range(start_row, finish_row):
		for option: CharacterAppearanceOptionView in (rows[row_index]["options"] as Array):
			visible_asset_ids.append(option.id)
	owner.ensure_appearance_textures(visible_asset_ids)
	var textures: Dictionary = owner.appearance_textures()
	for row_index: int in range(start_row, finish_row):
		var row_record: Dictionary = rows[row_index]
		var row := step.thumbnail_row_scene.instantiate() as AppearanceThumbnailRow
		rows_host.add_child(row)
		row.bind(prefix, String(row_record["label"]), row_index, row_record["options"] as Array, textures, selected_id, group)
		row.option_selected.connect(func(option_id: String) -> void: _select_thumbnail(control, option_id, portrait))


func _rows(owner, options: Array[CharacterAppearanceOptionView]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ordered_races: Array[DefinitionOptionView] = []
	if owner.view != null:
		for race: DefinitionOptionView in owner.view.race_options:
			if race.id == owner.selected_race_id:
				ordered_races.push_front(race)
			else:
				ordered_races.append(race)
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
		if not assigned.has(option.id):
			ungrouped.append(option)
	_append_rows(rows, "Classic catalog", ungrouped)
	return rows


static func _append_rows(rows: Array[Dictionary], label: String, options: Array[CharacterAppearanceOptionView]) -> void:
	for start: int in range(0, options.size(), COLUMNS):
		var chunk: Array[CharacterAppearanceOptionView] = []
		for option_index: int in range(start, mini(start + COLUMNS, options.size())):
			chunk.append(options[option_index])
		rows.append({"label": label, "options": chunk})


func _change_page(delta: int, portrait: bool) -> void:
	if portrait:
		_portrait_page += delta
	else:
		_combat_icon_page += delta
	_owner().render_creator_step()


func _select_thumbnail(control: OptionButton, option_id: String, portrait: bool) -> void:
	var owner = _owner()
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)) != option_id:
			continue
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
		if left_recommended != right_recommended:
			return left_recommended
		return left.classic_resource_id < right.classic_resource_id
	)
	return result


static func _add_option(owner, control: OptionButton, option: CharacterAppearanceOptionView) -> void:
	var texture := owner.appearance_textures().get(option.id) as Texture2D
	if texture != null:
		control.add_icon_item(texture, option.label)
	else:
		control.add_item(option.label)
	var index := control.item_count - 1
	control.set_item_metadata(index, option.id)
	control.set_item_tooltip(index, option.label)


func _select_default(owner, control: OptionButton, selected_id: String, portrait: bool) -> void:
	if control.item_count == 0:
		return
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
		owner.portrait_preview.texture = owner.appearance_textures().get(portrait_id) as Texture2D
	if owner.combat_icon_preview != null:
		var icon_id := String(owner.combat_icon_option.get_item_metadata(owner.combat_icon_option.selected)) if owner.combat_icon_option != null and owner.combat_icon_option.selected >= 0 else ""
		owner.combat_icon_preview.texture = owner.appearance_textures().get(icon_id) as Texture2D


func selected(control: OptionButton, portrait: bool) -> CharacterAppearanceOptionView:
	if control == null or control.selected < 0:
		return null
	return option_by_id(String(control.get_item_metadata(control.selected)), portrait)


func option_by_id(option_id: String, portrait: bool) -> CharacterAppearanceOptionView:
	var owner = _owner()
	var options: Array[CharacterAppearanceOptionView] = owner.view.portrait_options if portrait else owner.view.combat_icon_options
	for option: CharacterAppearanceOptionView in options:
		if option.id == option_id:
			return option
	return null
