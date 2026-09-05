## Coordinates the character-creation wizard and submits typed draft decisions.
class_name PartySetupCharacterCreationController
extends "res://src/ui/setup/party_setup_controller_component.gd"

const SpellSelectionChrome := preload("res://src/ui/magic/classic_spell_selection_chrome.gd")

var _assembly: RefCounted
var _starting_spell_level: int = 0
var _starting_spell_id: String = ""
var _appearance_editor: PartySetupAppearanceEditor
var _race_caste_binding: PartySetupRaceCasteBinding
var _step_scene_cache: Dictionary = {}


func _init(state: RefCounted, assembly: RefCounted) -> void:
	super(state)
	_assembly = assembly
	_appearance_editor = PartySetupAppearanceEditor.new(self)
	_race_caste_binding = PartySetupRaceCasteBinding.new(state, _appearance_editor)

func ensure_appearance_textures(requested_asset_ids: Array[String] = []) -> void:
	_ensure_appearance_textures(requested_asset_ids)

func appearance_textures() -> Dictionary:
	_ensure_appearance_textures()
	return _appearance_textures

func set_appearance_texture(asset_id: String, texture: Texture2D) -> void:
	_appearance_textures[asset_id] = texture

func set_presentation_settings(next_settings: PresentationSettings) -> void:
	if next_settings != null:
		settings = next_settings
	_campaign_library.set_presentation_settings(next_settings)

func set_standalone_character_creation_available(enabled: bool, reason: String = "") -> void:
	standalone_character_creation_available = enabled
	standalone_character_creation_reason = reason if not reason.is_empty() else "The Classic character library is unavailable."
	if setup_overlay != null and setup_overlay.visible and setup_mode == &"assembly":
		refresh_setup_options()

func begin_standalone_character_creation() -> void:
	standalone_character_creation_active = true
	setup_mode = &"creator"
	reset_creator(false)
	render_creator_step()

func finish_standalone_character_creation() -> void:
	standalone_character_creation_active = false
	reset_creator(true)

func refresh_setup_options() -> void:
	if view == null or not view.party_setup_available:
		_campaign_library.set_selected_campaign_summary(null)
		campaign_overlay.tooltip_text = "Select an installed scenario to assemble a party."
		_assembly.refresh_party_list()
		_assembly.refresh_party_setup_options()
		render_creator_step()
		return
	var summary := view.campaign_summary
	_campaign_library.set_selected_campaign_summary(summary)
	if summary != null:
		var title_parts: Array[String] = [summary.title]
		if not summary.version.is_empty():
			title_parts.append("v%s" % summary.version)
		if not summary.author.is_empty():
			title_parts.append("by %s" % summary.author)
		var restriction_text := summary.restriction_description.strip_edges()
		if restriction_text.is_empty():
			restriction_text = "No authored party restrictions."
		var limits := "Up to %d characters" % summary.maximum_party_size
		if summary.maximum_level > 0:
			limits += " • Maximum level %d" % summary.maximum_level
		campaign_overlay.tooltip_text = "%s\n%s\n%s" % [" • ".join(title_parts), restriction_text, limits]
	else:
		campaign_overlay.tooltip_text = "The selected scenario has no campaign summary metadata."
	_assembly.refresh_party_list()
	_assembly.refresh_party_setup_options()
	var setup_count := view.party_members.size()
	_apply_availability(begin_button, &"begin_adventure")
	begin_button.text = "Begin adventure (%d/%d)" % [setup_count, _assembly.maximum_party_size()]
	render_creator_step()

func render_creator_step() -> void:
	if creator_page == null:
		return
	_state.apply_setup_mode_layout()
	if setup_mode == &"assembly":
		_assembly.render_party_assembly()
		return
	create_character_button.visible = false
	begin_button.visible = false
	party_setup_options.visible = false
	creator_steps.visible = true
	creator_action_bar.visible = true
	setup_message.visible = false
	setup_message.tooltip_text = ""
	setup_message.modulate = MUTED
	setup_message.custom_minimum_size.y = 32.0
	setup_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_message.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	setup_message.text = ""
	_clear_creator_page()
	for index: int in creator_step_labels.size():
		creator_step_labels[index].modulate = GOLD if index == creator_step else Color("e0e2e5") if index < creator_step else MUTED
	match creator_step:
		0:
			_build_creator_identity()
		1:
			_race_caste_binding.build()
		2:
			_build_creator_appearance()
		3:
			_build_creator_review()
		4:
			_build_creator_spells()
	_update_creator_actions()

func _build_creator_identity() -> void:
	var step = _step_scene(identity_step_scene_path).instantiate()
	creator_page.add_child(step)
	var allowed_levels: Array[int] = []
	var maximum_level := view.campaign_summary.maximum_level if view != null and view.campaign_summary != null else 0
	for level: int in CharacterRules.STARTING_LEVELS:
		if maximum_level > 0 and level > maximum_level:
			continue
		allowed_levels.append(level)
	if not allowed_levels.has(draft_starting_level):
		draft_starting_level = allowed_levels[0]
	step.bind_identity(draft_name, draft_gender, draft_starting_level, allowed_levels, _creation_context())
	step.identity_changed.connect(func(next_name: String, next_gender: int, next_level: int) -> void:
		draft_name = next_name
		draft_gender = next_gender
		draft_starting_level = next_level
	)
	name_edit = step.character_name_control()
	gender_option = step.gender_control()
	starting_level_option = step.starting_level_control()
	_focus_first(creator_page)

func _creation_context() -> String:
	if view == null or view.campaign_summary == null:
		return "Classic Character Files"
	var summary := view.campaign_summary
	var facts: Array[String] = [summary.title]
	if summary.maximum_level > 0:
		facts.append("Maximum level %d" % summary.maximum_level)
	if not summary.restriction_description.strip_edges().is_empty():
		facts.append(summary.restriction_description.strip_edges())
	return " • ".join(facts)

func _build_creator_appearance() -> void:
	_appearance_editor.build()


func _selected_appearance(control: OptionButton, portrait: bool) -> CharacterAppearanceOptionView:
	return _appearance_editor.selected(control, portrait)


func _build_creator_review() -> void:
	var step = _step_scene(review_step_scene_path).instantiate()
	creator_page.add_child(step)
	review_label = step.status_label()
	_update_creator_review()
	if view == null or view.character_draft == null:
		return
	var character := view.character_draft
	var review_asset_ids: Array[String] = [character.portrait_id, character.combat_icon_id]
	_ensure_appearance_textures(review_asset_ids)
	var sheet := _state.character_sheet_scene.instantiate() as ClassicCharacterSheet
	sheet.name = "CreatorReviewSheet"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var characters: Array[CharacterView] = [character]
	sheet.present(
		characters,
		character.id,
		_appearance_textures,
		settings.text_scale if settings != null else 1.0,
		&"overview",
		view.portrait_options,
		view.combat_icon_options,
		ActionAvailabilityView.new(&"change_character_appearance", false, "Appearance is selected in the previous creator stage."),
		media,
		layout_profile,
		false
	)
	step.sheet_host().add_child(sheet)

func _build_creator_spells() -> void:
	var step := _step_scene(spells_step_scene_path).instantiate() as CharacterCreationSpellsStep
	creator_page.add_child(step)
	if view == null or view.character_draft == null:
		spell_label = step.show_unavailable("Generate and review the character before choosing spells.")
		return
	if view.character_draft.spellcaster_type < 1 or view.character_draft_spell_points_total < 1:
		spell_label = step.show_not_applicable("%s receives no Classic starting-spell choices." % view.character_draft.name)
		return
	if view.character_draft_spell_options.is_empty():
		spell_label = step.show_missing("This caster has selection points, but the package exposes no matching Classic spell records. Finalization is blocked.")
		return
	step.show_workspace()
	_prepare_starting_spell_selection()
	_bind_starting_spell_levels(step)
	_populate_starting_spell_rows(step)
	_present_starting_spell_detail(step)
	(step.get_node("%StartingSpellAllowanceValue") as Label).text = "%d of %d points remain" % [view.character_draft_spell_points_remaining, view.character_draft_spell_points_total]


func _bind_starting_spell_levels(step: CharacterCreationSpellsStep) -> void:
	for level: int in range(1, 8):
		var level_button := step.level_button(level) as Button
		SpellSelectionChrome.bind_level_button(
			level_button,
			level,
			level == _starting_spell_level,
			_starting_spell_level_available(level),
			_select_starting_spell_level.bind(level),
			"No starting spells are available at this level."
		)
		level_button.name = "StartingSpellLevel%d" % level


func _populate_starting_spell_rows(step: CharacterCreationSpellsStep) -> void:
	spell_list = step.spell_rows()
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.level != _starting_spell_level:
			continue
		var enabled := option.selected or option.selection_cost <= view.character_draft_spell_points_remaining
		var tooltip := option.description if enabled else "This spell costs %d points; %d remain." % [option.selection_cost, view.character_draft_spell_points_remaining]
		var button := step.spell_button_scene.instantiate() as Button
		SpellSelectionChrome.bind_spell_button(
			button,
			"StartingSpell_%s" % option.id,
			"%s   %d point%s" % [option.name, option.selection_cost, "" if option.selection_cost == 1 else "s"],
			option.selected,
			enabled,
			tooltip,
			_draft_spell_toggled.bind(option.id, not option.selected),
			ClassicUiAssetCatalog.texture(&"spells.button.available" if option.selected else &"spells.button.unavailable")
		)
		spell_list.add_child(button)


func _present_starting_spell_detail(step: CharacterCreationSpellsStep) -> void:
	var selected := _starting_spell_option(_starting_spell_id)
	var prompt := step.get_node("%StartingSpellPrompt") as Label
	var detail := step.get_node("%StartingSpellDetail") as VBoxContainer
	if selected == null:
		prompt.text = "Choose a spell from level %d." % _starting_spell_level
		prompt.visible = true
		detail.visible = false
		spell_label = prompt
	else:
		prompt.visible = false
		detail.visible = true
		spell_label = step.get_node("%StartingSpellName") as Label
		spell_label.text = selected.name
		(step.get_node("%StartingSpellFacts") as Label).text = "Level %d  •  %d selection point%s" % [selected.level, selected.selection_cost, "" if selected.selection_cost == 1 else "s"]
		var preview := step.effect_preview_scene.instantiate() as ClassicSpellEffectPreview
		if preview.present(media, selected.animation_resource_type, selected.animation_resource_ids):
			step.effect_host().add_child(preview)
		else:
			preview.free()
		var description := selected.description.strip_edges()
		var description_label := step.get_node("%StartingSpellDescription") as Label
		description_label.text = description if not description.is_empty() else "Description unavailable."
		description_label.add_theme_color_override("font_color", Color("e0e2e5") if not description.is_empty() else MUTED)
		var selection_state := step.get_node("%StartingSpellSelectionState") as Label
		selection_state.text = "Selected" if selected.selected else "Available"
		selection_state.add_theme_color_override("font_color", GOLD if selected.selected else MUTED)


func _step_scene(path: String) -> PackedScene:
	if not _step_scene_cache.has(path):
		_step_scene_cache[path] = load(path) as PackedScene
	return _step_scene_cache[path] as PackedScene

func _prepare_starting_spell_selection() -> void:
	if not _starting_spell_level_available(_starting_spell_level):
		_starting_spell_level = view.character_draft_spell_options[0].level
	var selected := _starting_spell_option(_starting_spell_id)
	if selected == null or selected.level != _starting_spell_level:
		_starting_spell_id = ""
		for option: CharacterSpellOptionView in view.character_draft_spell_options:
			if option.level == _starting_spell_level:
				_starting_spell_id = option.id
				break

func _starting_spell_level_available(level: int) -> bool:
	if view == null:
		return false
	return view.character_draft_spell_options.any(func(option: CharacterSpellOptionView) -> bool: return option.level == level)

func _starting_spell_option(option_id: String) -> CharacterSpellOptionView:
	if view == null:
		return null
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.id == option_id:
			return option
	return null

func _select_starting_spell_level(level: int) -> void:
	if not _starting_spell_level_available(level):
		return
	_starting_spell_level = level
	_starting_spell_id = ""
	render_creator_step()

func creator_next() -> void:
	match creator_step:
		0:
			draft_name = name_edit.text.strip_edges()
			draft_gender = gender_option.get_selected_id()
			draft_starting_level = starting_level_option.get_selected_id()
			if draft_name.is_empty():
				_show_creator_error("Enter a character name before continuing.")
				return
			creator_step = 1
		1:
			if selected_race_id.is_empty() or selected_caste_id.is_empty():
				_show_creator_error("Choose both a race and a compatible caste.")
				return
			creator_step = 2
		2:
			if view != null and view.party_members.size() >= _assembly.maximum_party_size():
				_show_creator_error("This campaign allows no more than %d characters." % _assembly.maximum_party_size())
				return
			var portrait_value := _selected_appearance(portrait_option, true)
			var combat_icon_value := _selected_appearance(combat_icon_option, false)
			if portrait_value == null or combat_icon_value == null:
				_show_creator_error("Choose a portrait and combat icon before continuing.")
				return
			draft_portrait_id = portrait_value.id
			draft_combat_icon_id = combat_icon_value.id
			creator_step = 3
			awaiting_draft_generation = true
			_state.intent_submitted.emit(PartyIntents.generate_character_draft(_character_creation_spec()))
			return
		3:
			if view == null or view.character_draft == null:
				_show_creator_error("The Classic character roll did not complete. Review the action error before continuing.")
				return
			creator_step = 4
		4:
			if view == null or view.character_draft == null:
				return
			if view.character_draft.spellcaster_type > 0 and view.character_draft_spell_points_total > 0 and view.character_draft_spell_options.is_empty():
				_show_creator_error("Starting spells are unavailable in this package, so this caster cannot be finalized safely.")
				return
			awaiting_draft_finalization = true
			_state.intent_submitted.emit(PartyIntents.finalize_character())
			return
	setup_message.text = _creator_step_message()
	render_creator_step()

func creator_back() -> void:
	if creator_step <= 0:
		return
	if creator_step == 3 and view != null and view.character_draft != null:
		creator_step = 2
		_state.intent_submitted.emit(PartyIntents.cancel_character_draft())
		return
	creator_step -= 1
	setup_message.text = _creator_step_message()
	render_creator_step()

func cancel_creator() -> void:
	var had_generated_draft := view != null and view.character_draft != null
	reset_creator(true)
	if had_generated_draft:
		_state.intent_submitted.emit(PartyIntents.cancel_character_draft())
	if standalone_character_creation_active:
		_state.standalone_character_creation_cancelled.emit()
	elif not had_generated_draft:
		render_creator_step()

func reset_creator(return_to_assembly: bool = false) -> void:
	if return_to_assembly:
		setup_mode = &"assembly"
	creator_step = 0
	draft_name = ""
	draft_gender = 1
	draft_starting_level = 1
	draft_portrait_id = ""
	draft_combat_icon_id = ""
	combat_icon_touched = false
	selected_race_id = ""
	selected_caste_id = ""
	awaiting_draft_generation = false
	awaiting_draft_finalization = false
	if setup_message != null:
		setup_message.text = "Choose stored characters or create a new one." if setup_mode == &"assembly" else "Enter a name to begin creating another character."

func reroll_character() -> void:
	if creator_step != 3 or view == null or view.character_draft == null:
		return
	awaiting_draft_generation = true
	_state.intent_submitted.emit(PartyIntents.generate_character_draft(_character_creation_spec()))

func _draft_spell_toggled(option_id: String, selected: bool) -> void:
	_starting_spell_id = option_id
	var selected_ids: Array[String] = []
	for option: CharacterSpellOptionView in view.character_draft_spell_options:
		if option.id == option_id:
			if selected:
				selected_ids.append(option.id)
		elif option.selected:
			selected_ids.append(option.id)
	_state.intent_submitted.emit(PartyIntents.set_character_draft_spells(selected_ids))

func _character_creation_spec() -> CharacterCreationSpec:
	return CharacterCreationSpec.new(draft_name, selected_race_id, selected_caste_id, draft_gender, draft_portrait_id, draft_combat_icon_id, draft_starting_level)

func _creator_step_message() -> String:
	var final_step := "Choose starting spells, then create the Character File." if standalone_character_creation_active else "Choose starting spells, then add the character to the party."
	return ["Enter the character's identity.", "Choose a race and caste.", "Choose the character's appearance.", "Review the generated Classic character.", final_step][creator_step]

func _show_creator_error(message: String) -> void:
	setup_message.text = message
	setup_message.modulate = ERROR
	setup_message.visible = true

func _update_creator_actions() -> void:
	if creator_back_button == null:
		return
	creator_back_button.disabled = creator_step == 0
	add_character_button.visible = creator_step == 3
	_apply_availability(add_character_button, &"generate_character_draft")
	if creator_step == 4:
		creator_next_button.text = "Create Character File" if standalone_character_creation_active else "Add to party"
	elif creator_step == 3 and view != null and view.character_draft != null and view.character_draft.spellcaster_type > 0 and view.character_draft_spell_points_total > 0:
		creator_next_button.text = "Choose spells"
	else:
		creator_next_button.text = "Continue"
	if creator_step == 4:
		_apply_availability(creator_next_button, &"finalize_character")
	else:
		creator_next_button.disabled = false
		creator_next_button.tooltip_text = ""
	creator_cancel_button.disabled = false

func start_creator() -> void:
	if view == null or not view.party_setup_available:
		if standalone_character_creation_available:
			_state.standalone_character_creation_requested.emit()
			return
		setup_message.text = standalone_character_creation_reason
		return
	setup_mode = &"creator"
	reset_creator(false)
	render_creator_step()

func _update_creator_review() -> void:
	if review_label == null:
		return
	if view == null or view.character_draft == null:
		review_label.text = "The Classic character roll has not completed."
		review_label.visible = true
		return
	review_label.text = ""
	review_label.visible = false

func apply_creator_layout(profile_id: StringName) -> void:
	if creator != null:
		creator.vertical = profile_id == UiLayoutProfile.COMPACT
	_state.apply_setup_mode_layout()
