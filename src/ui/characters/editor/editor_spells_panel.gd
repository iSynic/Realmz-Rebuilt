## Spells tab: the shared Spell Level rail and level-colored filters, then this caster's
## spells at the selected level. Toggling learns or forgets a spell with no point cost.

class_name EditorSpellsPanel
extends VBoxContainer

signal command(operation: Dictionary)

@export var choice_scene: PackedScene

var _session: CharacterEditorSession
var _level := 1

@onready var _summary: Label = %Summary
@onready var _list: GridContainer = %SpellList
@onready var _detail: Label = %SpellDetail


func bind(session: CharacterEditorSession) -> void:
	_session = session
	var summary := session.queries.spell_summary()
	var levels: Array[int] = []
	levels.assign(summary.levels)
	if not levels.is_empty() and not levels.has(_level):
		_level = levels[0]
	for level: int in range(1, 8):
		var button := get_node("%%LevelRail/SpellLevel%d" % level) as Button
		ClassicSpellSelectionChrome.bind_level_button(button, level, level == _level, levels.has(level), _select_level.bind(level), "This caster has no level %d spells." % level)
	var reason := session.queries.rules_reason()
	if not reason.is_empty():
		_summary.text = reason
	elif not bool(summary.caster):
		_summary.text = "%s doesn't cast spells." % session.queries.identity().name
	else:
		_summary.text = "%d known · own caster type only · learning or forgetting here costs no points." % int(summary.known)
	_bind_list(reason.is_empty())


func _bind_list(editable: bool) -> void:
	var rows := _session.queries.spells(_level)
	while _list.get_child_count() > rows.size():
		var extra := _list.get_child(_list.get_child_count() - 1)
		_list.remove_child(extra)
		extra.queue_free()
	for index: int in rows.size():
		if index >= _list.get_child_count():
			var created := choice_scene.instantiate() as EditorSpellChoice
			created.name = "Spell%d" % (index + 1)
			_list.add_child(created)
			# Focus or hover shows the spell's description without learning or forgetting it.
			created.previewed.connect(_show_description)
			created.toggled.connect(_toggle.bind(created))
		(_list.get_child(index) as EditorSpellChoice).bind(rows[index], editable)


func _show_description(choice: EditorSpellChoice) -> void:
	_detail.text = String(choice.spell.get("description", ""))


func _select_level(level: int) -> void:
	_level = level
	_detail.text = ""
	bind(_session)


func _toggle(known: bool, choice: EditorSpellChoice) -> void:
	_show_description(choice)
	command.emit({"kind": &"spell", "spell_id": String(choice.spell.id), "known": known})
