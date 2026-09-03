## Owns the reusable, editor-authored spellbook, Fast Spell, and Scroll Case layout.
class_name SpellsWorkspace
extends VBoxContainer

@export var known_spell_button_scene: PackedScene
@export var action_dock_scene: PackedScene
@export var fast_spell_row_scene: PackedScene
@export var scroll_slot_row_scene: PackedScene


func prepare(compact: bool) -> void:
	visible = true
	get_node("Caster").visible = true
	get_node("Sections").visible = true
	get_node("Sections/WideSections").visible = not compact
	get_node("Sections/SpellSectionSelector").visible = compact
	get_node("SpellcastingBlockedNotice").visible = false
	get_node("EmptyState").visible = false
	for section: Control in [known_section(), fast_section(), scroll_section()]:
		section.visible = false
	_clear(known_spell_list())
	_clear(known_action_host())
	_clear(fast_spell_rows())
	_clear(scroll_rows())
	get_node("FastSection/Empty").visible = false
	get_node("ScrollSection/Empty").visible = false


func show_empty(title: String, detail: String) -> void:
	for section: Control in [known_section(), fast_section(), scroll_section()]:
		section.visible = false
	var empty := get_node("EmptyState") as PanelContainer
	empty.visible = true
	(empty.get_node("Content/Title") as Label).text = title
	(empty.get_node("Content/Detail") as Label).text = detail


func show_section(section_id: StringName) -> void:
	known_section().visible = section_id == &"known"
	fast_section().visible = section_id == &"fast"
	scroll_section().visible = section_id == &"scrolls"


func caster_picker() -> OptionButton:
	return get_node("Caster/Content/SpellCharacterSelector") as OptionButton


func wide_sections() -> HBoxContainer:
	return get_node("Sections/WideSections") as HBoxContainer


func compact_section_picker() -> OptionButton:
	return get_node("Sections/SpellSectionSelector") as OptionButton


func blocked_notice() -> PanelContainer:
	return get_node("SpellcastingBlockedNotice") as PanelContainer


func known_section() -> PanelContainer:
	return get_node("ClassicSpellbookWorkspace") as PanelContainer


func level_rail() -> VBoxContainer:
	return get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/SpellLevelRail/Content") as VBoxContainer


func power_rail() -> VBoxContainer:
	return get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/SpellLevelRail/Content/SpellPowerRail") as VBoxContainer


func known_spell_list() -> VBoxContainer:
	return get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/LevelSpellRecords/KnownSpellList/Content/SpellScroll/Spells") as VBoxContainer


func selected_spell_record() -> PanelContainer:
	return get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/LevelSpellRecords/SelectedSpellRecord") as PanelContainer


func known_action_host() -> HBoxContainer:
	return get_node("ClassicSpellbookWorkspace/Content/SpellActionHost") as HBoxContainer


func fast_section() -> VBoxContainer:
	return get_node("FastSection") as VBoxContainer


func fast_spell_rows() -> GridContainer:
	return get_node("FastSection/FastSpellGrid/Rows") as GridContainer


func scroll_section() -> VBoxContainer:
	return get_node("ScrollSection") as VBoxContainer


func scroll_rows() -> VBoxContainer:
	return get_node("ScrollSection/SpellScrollCase/Rows") as VBoxContainer


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
