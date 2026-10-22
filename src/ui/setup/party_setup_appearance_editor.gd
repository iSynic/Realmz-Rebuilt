## Binds the character creator's authored portrait and battle-icon browser.

class_name PartySetupAppearanceEditor
extends RefCounted

const COLUMNS: int = 6
const ROWS_PER_PAGE: int = 2

var _owner_ref: WeakRef
var _portrait_page: int = 0
var _combat_icon_page: int = 0
var _selected_art_group := ""
var _imported_groups_by_kind: Dictionary = {}
var _retained_imported_options: Dictionary = {}
var _retained_only_ids: Dictionary = {}


func _init(owner: RefCounted) -> void:
	_owner_ref = weakref(owner)


func _owner() -> PartySetupCharacterCreationController:
	return _owner_ref.get_ref()


func reset_pages() -> void:
	_portrait_page = 0
	_combat_icon_page = 0


func build() -> void:
	var owner := _owner()
	assert(owner.appearance_step_scene != null, "The party-setup workspace must export its appearance step scene.")
	var selected_asset_ids: Array[String] = []
	if not owner.draft_portrait_id.is_empty():
		selected_asset_ids.append(owner.draft_portrait_id)
	if not owner.draft_combat_icon_id.is_empty():
		selected_asset_ids.append(owner.draft_combat_icon_id)
	owner.ensure_appearance_textures(selected_asset_ids)
	var step := owner.appearance_step_scene.instantiate() as CharacterCreationAppearanceStep
	owner.creator_page.add_child(step)
	var import_button := step.get_node("%ImportCharacterArt") as Button
	import_button.visible = owner.character_art_dialog != null
	import_button.pressed.connect(_open_character_art)
	if owner.character_art_dialog != null and not owner.character_art_dialog.dismissed.is_connected(_artwork_library_dismissed):
		owner.character_art_dialog.dismissed.connect(_artwork_library_dismissed)
	owner.portrait_preview = step.get_node("%PortraitPreview") as TextureRect
	owner.combat_icon_preview = step.get_node("%CombatIconPreview") as TextureRect
	owner.portrait_option = step.get_node("%PortraitOption") as OptionButton
	owner.combat_icon_option = step.get_node("%CombatIconOption") as OptionButton
	_imported_groups_by_kind.clear()
	_retained_only_ids.clear()
	var portrait_options := _sorted_options(owner, _options(true))
	var combat_options := _sorted_options(owner, _options(false))
	_prune_retained_options(owner)
	_populate_option_control(owner, owner.portrait_option, portrait_options, true)
	_populate_option_control(owner, owner.combat_icon_option, combat_options, false)
	_bind_group_filter(step, owner, portrait_options, combat_options)
	_bind_strip(step, owner, owner.portrait_option, _filtered_options(owner, portrait_options), true)
	_bind_strip(step, owner, owner.combat_icon_option, _filtered_options(owner, combat_options), false)
	var catalog_error := step.get_node("%AppearanceCatalogError") as Label
	catalog_error.visible = portrait_options.is_empty() or combat_options.is_empty()
	_refresh_preview(owner)


func _populate_option_control(owner: PartySetupCharacterCreationController, control: OptionButton, options: Array[CharacterAppearanceOptionView], portrait: bool) -> void:
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


func _bind_strip(step: CharacterCreationAppearanceStep, owner: PartySetupCharacterCreationController, control: OptionButton, options: Array[CharacterAppearanceOptionView], portrait: bool) -> void:
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


func _rows(owner: PartySetupCharacterCreationController, options: Array[CharacterAppearanceOptionView]) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ordered_races: Array[DefinitionOptionView] = []
	if owner.view != null:
		for race: DefinitionOptionView in owner.view.race_options:
			if not race.available_for_creation:
				continue
			if race.id == owner.selected_race_id:
				ordered_races.push_front(race)
			else:
				ordered_races.append(race)
	var assigned: Dictionary = {}
	var grouped_names := _active_imported_group_names()
	grouped_names.sort()
	for race: DefinitionOptionView in ordered_races:
		var race_options: Array[CharacterAppearanceOptionView] = []
		for option: CharacterAppearanceOptionView in options:
			if option.is_recommended_for(race.id) or _has_imported_group(option.id, race.name):
				race_options.append(option)
				assigned[option.id] = true
		_append_rows(rows, race.name, race_options)
	for group_name: String in grouped_names:
		if _race_id_for_name(owner, group_name).is_empty():
			var group_options: Array[CharacterAppearanceOptionView] = []
			for option: CharacterAppearanceOptionView in options:
				if _has_imported_group(option.id, group_name):
					group_options.append(option)
					assigned[option.id] = true
			_append_rows(rows, group_name, group_options)
	_append_retained_rows(rows, options, assigned)
	var ungrouped: Array[CharacterAppearanceOptionView] = []
	for option: CharacterAppearanceOptionView in options:
		if not assigned.has(option.id):
			ungrouped.append(option)
	_append_rows(rows, "Classic catalog", ungrouped)
	return rows


func _bind_group_filter(step: CharacterCreationAppearanceStep, owner: PartySetupCharacterCreationController, portraits: Array[CharacterAppearanceOptionView], icons: Array[CharacterAppearanceOptionView]) -> void:
	var control := step.get_node("%ArtworkGroupFilter") as OptionButton
	control.clear()
	control.add_item("All artwork")
	control.set_item_metadata(0, "")
	var group_names := PackedStringArray()
	if owner.view != null:
		for race: DefinitionOptionView in owner.view.race_options:
			if race.available_for_creation and _has_recommended_art(race.id, portraits, icons):
				_append_group_name(group_names, race.name)
	for group_name: String in _active_imported_group_names():
		_append_group_name(group_names, group_name)
	group_names.sort()
	for group_name: String in group_names:
		control.add_item(group_name)
		control.set_item_metadata(control.item_count - 1, group_name)
	var selection := _group_item_index(control, _selected_art_group)
	if selection < 0:
		_selected_art_group = ""
		selection = 0
	control.select(selection)
	control.item_selected.connect(_select_art_group.bind(control))


func _filtered_options(owner: PartySetupCharacterCreationController, options: Array[CharacterAppearanceOptionView]) -> Array[CharacterAppearanceOptionView]:
	var result: Array[CharacterAppearanceOptionView] = []
	var race_id := _race_id_for_name(owner, _selected_art_group)
	for option: CharacterAppearanceOptionView in options:
		if _selected_art_group.is_empty() or _retained_only_ids.has(option.id) or _has_imported_group(option.id, _selected_art_group) or not race_id.is_empty() and option.is_recommended_for(race_id):
			result.append(option)
	return result


func _has_recommended_art(race_id: String, portraits: Array[CharacterAppearanceOptionView], icons: Array[CharacterAppearanceOptionView]) -> bool:
	for option: CharacterAppearanceOptionView in portraits + icons:
		if option.is_recommended_for(race_id):
			return true
	return false


func _active_imported_group_names() -> PackedStringArray:
	var names := PackedStringArray()
	for by_id: Dictionary in _imported_groups_by_kind.values():
		for group_list: PackedStringArray in by_id.values():
			for group_name: String in group_list:
				_append_group_name(names, group_name)
	return names


func _has_imported_group(option_id: String, group_name: String) -> bool:
	if group_name.is_empty() or _retained_only_ids.has(option_id):
		return false
	for by_id: Dictionary in _imported_groups_by_kind.values():
		if not by_id.has(option_id):
			continue
		for candidate: String in by_id[option_id]:
			if candidate.nocasecmp_to(group_name) == 0:
				return true
	return false


func _race_id_for_name(owner: PartySetupCharacterCreationController, group_name: String) -> String:
	if owner.view == null or group_name.is_empty():
		return ""
	for race: DefinitionOptionView in owner.view.race_options:
		if race.available_for_creation and race.name.nocasecmp_to(group_name) == 0:
			return race.id
	return ""


static func _append_group_name(names: PackedStringArray, group_name: String) -> void:
	if group_name.strip_edges().is_empty():
		return
	for existing: String in names:
		if existing.nocasecmp_to(group_name) == 0:
			return
	names.append(group_name)


static func _group_item_index(control: OptionButton, group_name: String) -> int:
	for index: int in control.item_count:
		if String(control.get_item_metadata(index)).nocasecmp_to(group_name) == 0:
			return index
	return -1


func _append_retained_rows(rows: Array[Dictionary], options: Array[CharacterAppearanceOptionView], assigned: Dictionary) -> void:
	var retained: Array[CharacterAppearanceOptionView] = []
	for option: CharacterAppearanceOptionView in options:
		if _retained_only_ids.has(option.id):
			retained.append(option)
			assigned[option.id] = true
	_append_rows(rows, "Current selection", retained)


func _select_art_group(index: int, control: OptionButton) -> void:
	_selected_art_group = String(control.get_item_metadata(index))
	_portrait_page = 0
	_combat_icon_page = 0
	_owner().render_creator_step()


func _artwork_library_dismissed() -> void:
	var owner := _owner()
	if owner != null and owner.setup_mode == &"creator" and owner.creator_step == 2 and owner.setup_overlay != null and owner.setup_overlay.visible:
		owner.render_creator_step()


func _prune_retained_options(owner: PartySetupCharacterCreationController) -> void:
	var selected_ids := [owner.draft_portrait_id, owner.draft_combat_icon_id]
	for option_id: String in _retained_imported_options.keys():
		if not selected_ids.has(option_id):
			_retained_imported_options.erase(option_id)


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
	var owner := _owner()
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


func _sorted_options(owner: PartySetupCharacterCreationController, source: Array[CharacterAppearanceOptionView]) -> Array[CharacterAppearanceOptionView]:
	var result := source.duplicate()
	result.sort_custom(func(left: CharacterAppearanceOptionView, right: CharacterAppearanceOptionView) -> bool:
		var left_recommended := left.is_recommended_for(owner.selected_race_id)
		var right_recommended := right.is_recommended_for(owner.selected_race_id)
		if left_recommended != right_recommended:
			return left_recommended
		return left.classic_resource_id < right.classic_resource_id
	)
	return result


static func _add_option(owner: PartySetupCharacterCreationController, control: OptionButton, option: CharacterAppearanceOptionView) -> void:
	var texture := owner.appearance_textures().get(option.id) as Texture2D
	if texture != null:
		control.add_icon_item(texture, option.label)
	else:
		control.add_item(option.label)
	var index := control.item_count - 1
	control.set_item_metadata(index, option.id)
	control.set_item_tooltip(index, option.label)


func _select_default(owner: PartySetupCharacterCreationController, control: OptionButton, selected_id: String, portrait: bool) -> void:
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


func _portrait_selected(owner: PartySetupCharacterCreationController) -> void:
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


func _combat_icon_selected(owner: PartySetupCharacterCreationController) -> void:
	owner.combat_icon_touched = true
	_refresh_preview(owner)


func _refresh_preview(owner: PartySetupCharacterCreationController) -> void:
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
	for option: CharacterAppearanceOptionView in _options(portrait):
		if option.id == option_id:
			return option
	return null


func _options(portrait: bool) -> Array[CharacterAppearanceOptionView]:
	var owner := _owner()
	var options: Array[CharacterAppearanceOptionView] = []
	if owner.view != null:
		options.assign(owner.view.portrait_options if portrait else owner.view.combat_icon_options)
	var kind := CharacterAppearanceDefinition.PORTRAIT if portrait else CharacterAppearanceDefinition.COMBAT_ICON
	var imported_groups: Dictionary = {}
	if owner.media != null:
		for option: CharacterAppearanceOptionView in owner.media.imported_appearance_options(kind):
			if not imported_groups.has(option.id):
				imported_groups[option.id] = PackedStringArray()
			var groups: PackedStringArray = imported_groups[option.id]
			_append_group_name(groups, option.art_group)
			imported_groups[option.id] = groups
			if not _contains_option(options, option.id):
				options.append(option)
			if option.id == _selected_id(owner, portrait):
				_retained_imported_options[option.id] = option
	_imported_groups_by_kind[String(kind)] = imported_groups
	var selected_id := _selected_id(owner, portrait)
	if CharacterArtIdentity.is_imported(selected_id) and not _contains_option(options, selected_id):
		var retained := _retained_imported_options.get(selected_id) as CharacterAppearanceOptionView
		if retained == null and owner.media != null:
			var asset: MediaAsset = owner.media.asset_by_id(selected_id)
			if asset != null:
				retained = CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new(asset.id, asset.label, StringName(kind), 0))
		if retained != null:
			options.append(retained)
			_retained_only_ids[selected_id] = true
	return options


func _selected_id(owner: PartySetupCharacterCreationController, portrait: bool) -> String:
	return owner.draft_portrait_id if portrait else owner.draft_combat_icon_id


static func _contains_option(options: Array[CharacterAppearanceOptionView], option_id: String) -> bool:
	return options.any(func(option: CharacterAppearanceOptionView) -> bool: return option.id == option_id)


func _open_character_art() -> void:
	var owner := _owner()
	var group_name := ""
	if owner.view != null:
		for race: DefinitionOptionView in owner.view.race_options:
			if not race.available_for_creation:
				continue
			if race.id == owner.selected_race_id:
				group_name = race.name
	owner.character_art_dialog.open_library(group_name, _select_imported_art)


func _select_imported_art(id: String, kind: String) -> void:
	var owner := _owner()
	if kind == "portrait":
		owner.draft_portrait_id = id
		_portrait_page = 0
	else:
		owner.draft_combat_icon_id = id
		owner.combat_icon_touched = true
		_combat_icon_page = 0
	owner.render_creator_step()
