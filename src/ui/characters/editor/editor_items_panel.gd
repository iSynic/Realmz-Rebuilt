## Items tab: carried items with Equip, Identify and Remove, plus a searchable Classic
## library list. Disabled actions keep their reason visible in the tooltip and facts line.

class_name EditorItemsPanel
extends HBoxContainer

signal command(operation: Dictionary)
signal add_requested(definition_id: String)

@export var item_row_scene: PackedScene
@export var catalog_row_scene: PackedScene

const CATALOG_LIMIT := 80

var _session: CharacterEditorSession

@onready var _count: Label = %Count
@onready var _load: Label = %ItemLoad
@onready var _carried: VBoxContainer = %CarriedList
@onready var _empty: Label = %CarriedEmpty
@onready var _search: LineEdit = %Search
@onready var _catalog: VBoxContainer = %CatalogList
@onready var _note: Label = %AddNote
@onready var _more: Label = %MoreMatches


func _ready() -> void:
	_search.text_changed.connect(func(_text: String) -> void: _bind_catalog())


func bind(session: CharacterEditorSession) -> void:
	_session = session
	var rows := session.queries.items()
	_count.text = "%d / %d" % [rows.size(), InventoryRules.MAX_ITEMS]
	_load.text = session.queries.load_text()
	_empty.visible = rows.is_empty()
	_sync_children(_carried, rows.size(), item_row_scene)
	for index: int in rows.size():
		var row := _carried.get_child(index) as EditorItemRow
		row.bind(rows[index], session.queries.rules_reason())
		if not row.action_requested.is_connected(command.emit):
			row.action_requested.connect(command.emit)
	var reason := session.queries.rules_reason()
	_search.editable = reason.is_empty()
	_note.text = reason if not reason.is_empty() else "Added items arrive identified and unequipped. Removing an equipped item unequips it first, even a cursed one."
	_bind_catalog()


func _bind_catalog() -> void:
	if _session == null:
		return
	var rows := _session.queries.catalog(_search.text, CATALOG_LIMIT) if _session.queries.rules_reason().is_empty() else [] as Array[Dictionary]
	var more := rows.size() > CATALOG_LIMIT
	if more:
		rows.resize(CATALOG_LIMIT)
	_more.visible = more
	_sync_children(_catalog, rows.size(), catalog_row_scene)
	for index: int in rows.size():
		var row := _catalog.get_child(index) as EditorCatalogRow
		row.bind(rows[index])
		if not row.add_requested.is_connected(add_requested.emit):
			row.add_requested.connect(add_requested.emit)


## Keeps exactly `count` row instances, reusing existing ones.
static func _sync_children(parent: Container, count: int, scene: PackedScene) -> void:
	while parent.get_child_count() > count:
		var extra := parent.get_child(parent.get_child_count() - 1)
		parent.remove_child(extra)
		extra.queue_free()
	while parent.get_child_count() < count:
		parent.add_child(scene.instantiate())
