## Binds the editor-authored identity step and emits presentation-local draft edits.

extends VBoxContainer

signal identity_changed(name_text: String, gender_id: int, starting_level: int)


func _ready() -> void:
	(%CharacterName as LineEdit).text_changed.connect(_identity_edited.unbind(1))
	(%CharacterGender as OptionButton).item_selected.connect(_identity_edited.unbind(1))
	(%StartingLevel as OptionButton).item_selected.connect(_identity_edited.unbind(1))


func bind_identity(name_text: String, gender_id: int, starting_level: int, allowed_levels: Array[int], context: String) -> void:
	var name_edit := %CharacterName as LineEdit
	var gender_option := %CharacterGender as OptionButton
	var level_option := %StartingLevel as OptionButton
	name_edit.text = name_text
	gender_option.clear()
	gender_option.add_item("Male", 1)
	gender_option.add_item("Female", 2)
	gender_option.select(maxi(0, gender_option.get_item_index(gender_id)))
	level_option.clear()
	for level: int in allowed_levels:
		level_option.add_item("Starting level %d" % level, level)
	var level_index := level_option.get_item_index(starting_level)
	level_option.select(maxi(0, level_index))
	(%IdentityCampaignContext as Label).text = context
	_refresh_preview()


func character_name_control() -> LineEdit:
	return %CharacterName as LineEdit


func gender_control() -> OptionButton:
	return %CharacterGender as OptionButton


func starting_level_control() -> OptionButton:
	return %StartingLevel as OptionButton


func _identity_edited() -> void:
	_refresh_preview()
	identity_changed.emit(
		(%CharacterName as LineEdit).text,
		(%CharacterGender as OptionButton).get_selected_id(),
		(%StartingLevel as OptionButton).get_selected_id()
	)


func _refresh_preview() -> void:
	var name_text := (%CharacterName as LineEdit).text.strip_edges()
	var gender_id := (%CharacterGender as OptionButton).get_selected_id()
	var starting_level := (%StartingLevel as OptionButton).get_selected_id()
	(%IdentityPreviewName as Label).text = name_text if not name_text.is_empty() else "Unnamed adventurer"
	(%IdentityPreviewGender as Label).text = "Male" if gender_id == 1 else "Female"
	(%IdentityPreviewLevel as Label).text = "Starting level %d" % starting_level
