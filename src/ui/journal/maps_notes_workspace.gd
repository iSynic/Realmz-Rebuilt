## Owns the complete editor-authored Places, Maps, and Journal workspace.
class_name MapsNotesWorkspace
extends VBoxContainer

@export var location_note_row_scene: PackedScene
@export var player_map_row_scene: PackedScene
@export var journal_entry_row_scene: PackedScene

const SECTION_ORDER: Array[int] = [1, 0, 2]


func _ready() -> void:
	var tab_container := tabs()
	tab_container.tabs_visible = false
	get_node("MapsNotesSectionRail/Maps").pressed.connect(func() -> void: select_tab(1))
	get_node("MapsNotesSectionRail/Places").pressed.connect(func() -> void: select_tab(0))
	get_node("MapsNotesSectionRail/Journal").pressed.connect(func() -> void: select_tab(2))
	tab_container.tab_changed.connect(_sync_section_rail)
	_sync_section_rail(tab_container.current_tab)


func prepare(compact: bool) -> void:
	visible = true
	(get_node("MapsNotesTabs/Places/LocationNotesWorkspace") as BoxContainer).vertical = compact
	(get_node("MapsNotesTabs/Maps/AcquiredMapsWorkspace") as BoxContainer).vertical = compact
	(get_node("MapsNotesTabs/Journal/JournalWorkspace") as BoxContainer).vertical = compact
	for host: Node in [location_note_rows(), player_map_rows(), journal_entry_rows()]:
		_clear(host)
	for path: String in [
		"MapsNotesTabs/Places/LocationNotesWorkspace/SavedLocationNotes/Content/Empty",
		"MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNotePreview/Empty",
		"MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNoteEditor/Unavailable",
		"MapsNotesTabs/Maps/AcquiredMapsWorkspace/PlayerMapBrowser/Content/Empty",
		"MapsNotesTabs/Maps/AcquiredMapsWorkspace/PlayerMapDisplay/Empty",
		"MapsNotesTabs/Journal/JournalWorkspace/JournalEntryBrowser/Content/Empty",
		"MapsNotesTabs/Journal/JournalWorkspace/JournalEntryDetail/Content/JournalEntryDetailScroll/JournalEntryDetailBody/Empty",
	]:
		get_node(path).visible = false
	historical_map().visible = false
	location_preview_facts().visible = false
	location_editor().visible = false
	player_map_stage().visible = false
	player_map_empty().visible = false
	journal_detail_record().visible = false


func tabs() -> TabContainer:
	return get_node("MapsNotesTabs") as TabContainer


func select_tab(index: int) -> void:
	tabs().current_tab = clampi(index, 0, tabs().get_tab_count() - 1)
	_sync_section_rail(tabs().current_tab)


func cycle_tab(delta: int) -> void:
	var position := SECTION_ORDER.find(tabs().current_tab)
	select_tab(SECTION_ORDER[wrapi(maxi(0, position) + delta, 0, SECTION_ORDER.size())])


func _sync_section_rail(index: int) -> void:
	(get_node("MapsNotesSectionRail/Maps") as Button).button_pressed = index == 1
	(get_node("MapsNotesSectionRail/Places") as Button).button_pressed = index == 0
	(get_node("MapsNotesSectionRail/Journal") as Button).button_pressed = index == 2


func summary_label() -> Label:
	return get_node("MapsNotesSummary/MapsNotesHeader/Facts") as Label


func location_note_rows() -> VBoxContainer:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/SavedLocationNotes/Content/SavedLocationNoteScroll/SavedLocationNoteRows") as VBoxContainer


func location_notes_empty() -> PanelContainer:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/SavedLocationNotes/Content/Empty") as PanelContainer


func location_preview_facts() -> VBoxContainer:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNotePreview/Facts") as VBoxContainer


func location_preview_empty() -> PanelContainer:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNotePreview/Empty") as PanelContainer


func historical_map() -> ClassicMapPresenter:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNotePreview/HistoricalLocationMap") as ClassicMapPresenter


func location_editor() -> VBoxContainer:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNoteEditor/Editor") as VBoxContainer


func location_editor_unavailable() -> PanelContainer:
	return get_node("MapsNotesTabs/Places/LocationNotesWorkspace/CurrentLocationNotePane/Content/LocationNoteEditor/Unavailable") as PanelContainer


func player_map_rows() -> VBoxContainer:
	return get_node("MapsNotesTabs/Maps/AcquiredMapsWorkspace/PlayerMapBrowser/Content/AcquiredMapChooser") as VBoxContainer


func player_map_browser_empty() -> PanelContainer:
	return get_node("MapsNotesTabs/Maps/AcquiredMapsWorkspace/PlayerMapBrowser/Content/Empty") as PanelContainer


func player_map_empty() -> PanelContainer:
	return get_node("MapsNotesTabs/Maps/AcquiredMapsWorkspace/PlayerMapDisplay/Empty") as PanelContainer


func player_map_stage() -> PlayerMapCartographicStage:
	return get_node("MapsNotesTabs/Maps/AcquiredMapsWorkspace/PlayerMapDisplay/PlayerMapCartographicStage") as PlayerMapCartographicStage


func journal_entry_rows() -> VBoxContainer:
	return get_node("MapsNotesTabs/Journal/JournalWorkspace/JournalEntryBrowser/Content/JournalEntryScroll/JournalEntryRows") as VBoxContainer


func journal_browser_empty() -> PanelContainer:
	return get_node("MapsNotesTabs/Journal/JournalWorkspace/JournalEntryBrowser/Content/Empty") as PanelContainer


func journal_detail_body() -> VBoxContainer:
	return get_node("MapsNotesTabs/Journal/JournalWorkspace/JournalEntryDetail/Content/JournalEntryDetailScroll/JournalEntryDetailBody") as VBoxContainer


func journal_detail_record() -> VBoxContainer:
	return get_node("MapsNotesTabs/Journal/JournalWorkspace/JournalEntryDetail/Content/JournalEntryDetailScroll/JournalEntryDetailBody/Record") as VBoxContainer


func journal_detail_empty() -> PanelContainer:
	return get_node("MapsNotesTabs/Journal/JournalWorkspace/JournalEntryDetail/Content/JournalEntryDetailScroll/JournalEntryDetailBody/Empty") as PanelContainer


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
