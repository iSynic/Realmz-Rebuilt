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
	caster_picker().fit_to_longest_item = not compact
	caster_picker().clip_text = compact
	(selected_spell_record().get_node("Content/TargetAndFacts/Facts") as GridContainer).columns = 2
	(selected_spell_record().get_node("Content/TargetAndFacts") as BoxContainer).vertical = compact
	(level_rail().get_node("LevelButtons") as GridContainer).columns = 2 if compact else 1
	(power_rail().get_node("PowerButtons") as GridContainer).columns = 2 if compact else 1
	(get_node("ClassicSpellbookWorkspace/Content/LevelStructuredSpellbook/LevelSpellRecords/KnownSpellList") as Control).custom_minimum_size.y = 90.0 if compact else 210.0
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


## Links visible controls only inside the supplied spellbook boundary. At each
## edge, focus stays on the nearest control instead of escaping into gameplay.
static func link_controller_focus(root: Control) -> void:
	if root == null or not is_instance_valid(root) or not root.is_inside_tree():
		return
	var tree := root.get_tree()
	if tree == null:
		return
	var retained_root: WeakRef = weakref(root)
	tree.process_frame.connect(func() -> void:
		var current := retained_root.get_ref() as Control
		if current != null and current.is_visible_in_tree():
			_link_controller_focus_now(current)
	, CONNECT_ONE_SHOT)


static func _link_controller_focus_now(root: Control) -> void:
	var controls: Array[Control] = []
	_collect_controller_controls(root, controls)
	for control: Control in controls:
		for direction: StringName in [&"top", &"bottom", &"left", &"right"]:
			var neighbor := _nearest_controller_neighbor(control, controls, direction)
			if neighbor == null:
				neighbor = control
			control.set("focus_neighbor_" + String(direction), control.get_path_to(neighbor))
	_link_spell_list_actions(root, controls)


static func _link_spell_list_actions(root: Control, controls: Array[Control]) -> void:
	var action: Control
	for control: Control in controls:
		if control.name in [&"CombatSpellAim", &"EncounterSpellChoose", &"SpellCastAction"]:
			action = control
			break
	for control: Control in controls:
		var parent := control.get_parent()
		if parent.name not in [&"CombatSpellList", &"Spells"]:
			continue
		var rows: Array[Node] = parent.get_children().filter(func(child: Node) -> bool: return controls.has(child))
		var index := rows.find(control)
		if index > 0:
			control.focus_neighbor_top = control.get_path_to(rows[index - 1])
		var next := rows[index + 1] as Control if index + 1 < rows.size() else action
		if next != null and root.is_ancestor_of(next):
			control.focus_neighbor_bottom = control.get_path_to(next)


## Reveals a focused control in each scroll container that owns it.
static func reveal_controller_focus(control: Control) -> void:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree():
		return
	var tree := control.get_tree()
	if tree == null:
		return
	var retained_control: WeakRef = weakref(control)
	tree.process_frame.connect(func() -> void:
		var current := retained_control.get_ref() as Control
		if current != null and current.is_visible_in_tree():
			_reveal_controller_focus_now(current)
	, CONNECT_ONE_SHOT)


static func _reveal_controller_focus_now(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(control)
		ancestor = ancestor.get_parent()


static func _collect_controller_controls(node: Node, output: Array[Control]) -> void:
	for child: Node in node.get_children():
		var control := child as Control
		var disabled := child is BaseButton and (child as BaseButton).disabled
		if control != null and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not disabled:
			output.append(control)
		_collect_controller_controls(child, output)


static func _nearest_controller_neighbor(origin: Control, controls: Array[Control], direction: StringName) -> Control:
	var origin_rect := origin.get_global_rect()
	var origin_center := origin_rect.get_center()
	var best: Control
	var best_score := INF
	for candidate: Control in controls:
		if candidate == origin:
			continue
		var candidate_rect := candidate.get_global_rect()
		var center := candidate_rect.get_center()
		var delta := center - origin_center
		var primary := delta.y if direction == &"top" or direction == &"bottom" else delta.x
		if (direction == &"top" or direction == &"left") and primary >= -0.5:
			continue
		if (direction == &"bottom" or direction == &"right") and primary <= 0.5:
			continue
		var secondary := absf(delta.x) if direction == &"top" or direction == &"bottom" else absf(delta.y)
		var vertical := direction == &"top" or direction == &"bottom"
		var aligned := candidate_rect.position.x < origin_rect.end.x and candidate_rect.end.x > origin_rect.position.x if vertical else candidate_rect.position.y < origin_rect.end.y and candidate_rect.end.y > origin_rect.position.y
		var score := absf(primary) + secondary * 2.0 + (0.0 if aligned else 100000.0)
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
