## Binds the character creator's authored Race and Caste step.
class_name PartySetupRaceCasteBinding
extends "res://src/ui/setup/party_setup_controller_component.gd"

var _appearance_editor: PartySetupAppearanceEditor
var _step_scene: PackedScene


func _init(state: RefCounted, appearance_editor: PartySetupAppearanceEditor) -> void:
	super(state)
	_appearance_editor = appearance_editor


func build() -> void:
	if _step_scene == null:
		_step_scene = load(race_caste_step_scene_path) as PackedScene
	var step = _step_scene.instantiate()
	creator_page.add_child(step)
	race_caste_columns = step.get_node("%RaceCasteSelectors") as BoxContainer
	race_list = step.race_options()
	caste_list = step.caste_options()
	race_list.option_selected.connect(_race_selected)
	caste_list.option_selected.connect(_caste_selected)
	_populate_options()


func _populate_options() -> void:
	if view == null or race_list == null or caste_list == null:
		return
	for option: DefinitionOptionView in view.race_options:
		if _placeholder_definition_name(option.name, "Race"):
			continue
		var race_restricted := view.campaign_summary != null and view.campaign_summary.banned_races.has(option.id)
		race_list.add_option(option.id, option.name, "Unavailable in this scenario." if race_restricted else option.description, not race_restricted, option.id == selected_race_id)
	if selected_race_id.is_empty() or not race_list.is_enabled(selected_race_id):
		selected_race_id = race_list.first_enabled_id()
	race_list.select_id(selected_race_id)
	_rebuild_caste_options()
	if selected_caste_id.is_empty() or not caste_list.is_enabled(selected_caste_id):
		selected_caste_id = caste_list.first_enabled_id()
	caste_list.select_id(selected_caste_id)
	_refresh_details()


func _refresh_details() -> void:
	var race_detail_name := creator_page.find_child("RaceDetailName", true, false) as Label
	var race_detail := creator_page.find_child("RaceDescription", true, false) as Label
	var race_facts := creator_page.find_child("RaceFacts", true, false) as Label
	var race_relations := creator_page.find_child("RaceRelations", true, false) as Label
	var caste_detail_name := creator_page.find_child("CasteDetailName", true, false) as Label
	var caste_detail := creator_page.find_child("CasteDescription", true, false) as Label
	var caste_facts := creator_page.find_child("CasteFacts", true, false) as Label
	var caste_relations := creator_page.find_child("CasteRelations", true, false) as Label
	var race_option := _definition_option(view.race_options if view != null else [], selected_race_id)
	var caste_option := _definition_option(view.caste_options if view != null else [], selected_caste_id)
	if race_detail_name != null:
		race_detail_name.text = race_option.name if race_option != null else "No race selected"
	if race_detail != null:
		race_detail.text = race_option.description if race_option != null else ""
		race_detail.visible = not race_detail.text.is_empty()
	if race_facts != null:
		race_facts.text = "\n".join(race_option.facts) if race_option != null else ""
		race_facts.visible = not race_facts.text.is_empty()
	if race_relations != null:
		race_relations.text = _related_definition_text("Compatible Castes", view.caste_options if view != null else [], race_option.related_ids if race_option != null else [])
	if caste_detail_name != null:
		caste_detail_name.text = caste_option.name if caste_option != null else "No caste selected"
	if caste_detail != null:
		caste_detail.text = caste_option.description if caste_option != null else ""
		caste_detail.visible = not caste_detail.text.is_empty()
	if caste_facts != null:
		caste_facts.text = "\n".join(caste_option.facts) if caste_option != null else ""
		caste_facts.visible = not caste_facts.text.is_empty()
	if caste_relations != null:
		caste_relations.text = _related_definition_text("Compatible Races", view.race_options if view != null else [], caste_option.related_ids if caste_option != null else [])


static func _related_definition_text(heading: String, options: Array[DefinitionOptionView], related_ids: Array[String]) -> String:
	var names: Array[String] = []
	for option: DefinitionOptionView in options:
		if related_ids.has(option.id) and not _placeholder_definition_name(option.name, "Race") and not _placeholder_definition_name(option.name, "Caste"):
			names.append(option.name)
	names.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	return "%s\n%s" % [heading, ", ".join(names)] if not names.is_empty() else ""


static func _placeholder_definition_name(display_name: String, prefix: String) -> bool:
	if not display_name.begins_with(prefix + " "):
		return false
	return display_name.trim_prefix(prefix + " ").is_valid_int()


static func _definition_option(options: Array[DefinitionOptionView], option_id: String) -> DefinitionOptionView:
	for option: DefinitionOptionView in options:
		if option.id == option_id:
			return option
	return null


func _race_selected(selected_id: String) -> void:
	if not race_list.is_enabled(selected_id):
		return
	if selected_id != selected_race_id:
		draft_portrait_id = ""
		draft_combat_icon_id = ""
		combat_icon_touched = false
		_appearance_editor.reset_pages()
	selected_race_id = selected_id
	race_list.select_id(selected_race_id)
	_rebuild_caste_options()
	_refresh_details()


func _caste_selected(selected_id: String) -> void:
	if not caste_list.is_enabled(selected_id):
		return
	selected_caste_id = selected_id
	caste_list.select_id(selected_caste_id)
	_refresh_details()


func _rebuild_caste_options() -> void:
	if view == null or caste_list == null:
		return
	var allowed_castes: Array[String] = []
	for option: DefinitionOptionView in view.race_options:
		if option.id == selected_race_id:
			allowed_castes = option.related_ids.duplicate()
			break
	var ordered: Array[DefinitionOptionView] = []
	for option: DefinitionOptionView in view.caste_options:
		if not _placeholder_definition_name(option.name, "Caste"):
			ordered.append(option)
	ordered.sort_custom(func(left: DefinitionOptionView, right: DefinitionOptionView) -> bool:
		var left_compatible := allowed_castes.is_empty() or allowed_castes.has(left.id)
		var right_compatible := allowed_castes.is_empty() or allowed_castes.has(right.id)
		if left_compatible != right_compatible:
			return left_compatible
		return left.name.naturalnocasecmp_to(right.name) < 0
	)
	caste_list.clear_options()
	for definition: DefinitionOptionView in ordered:
		var restricted := view.campaign_summary != null and view.campaign_summary.banned_castes.has(definition.id)
		var compatible := allowed_castes.is_empty() or allowed_castes.has(definition.id)
		var tooltip := definition.description
		if restricted:
			tooltip = "Unavailable in this scenario."
		elif not compatible:
			tooltip = "Unavailable to the selected race."
		caste_list.add_option(definition.id, definition.name, tooltip, not restricted and compatible, definition.id == selected_caste_id)
	if not selected_caste_id.is_empty() and not caste_list.is_enabled(selected_caste_id):
		selected_caste_id = ""
		selected_caste_id = caste_list.first_enabled_id()
	caste_list.select_id(selected_caste_id)
