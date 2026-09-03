## Owns the complete editor-authored Places, Maps, and Journal workspace.
class_name MapsNotesWorkspace
extends VBoxContainer

@export var location_note_row_scene: PackedScene
@export var player_map_row_scene: PackedScene
@export var journal_entry_row_scene: PackedScene


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
