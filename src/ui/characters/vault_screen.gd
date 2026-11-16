## Owns the stable, editor-visible Character Files library, detail and inspection layout.
class_name VaultScreen
extends ScreenFrame

@export var character_row_scene: PackedScene
@export var revision_row_scene: PackedScene
## Baseline widths per layout profile; UiSizing scales them with Interface Size.
@export var wide_list_width := 430.0
@export var compact_list_width := 300.0
@export var wide_search_width := 260.0
@export var compact_search_width := 170.0

@onready var archive_confirmation: VaultArchiveConfirmation = %ArchiveConfirmation
@onready var repair_dialog: VaultRepairDialog = %RepairDialog
@onready var library: VBoxContainer = %VaultLibrary
@onready var list_back_button: Button = %Back
@onready var context_label: Label = %Context
@onready var library_tools: MenuButton = %LibraryTools
@onready var toolbar: HBoxContainer = %Toolbar
@onready var active_tab: Button = %ActiveTab
@onready var archived_tab: Button = %ArchivedTab
@onready var search_field: LineEdit = %Search
@onready var notice_banner: PanelContainer = %NoticeBanner
@onready var notice_text: Label = %NoticeText
@onready var vault_body: HBoxContainer = %VaultBody
@onready var list_panel: PanelContainer = %ListPanel
@onready var list_scroll: ScrollContainer = %ListScroll
@onready var character_file_list: VBoxContainer = %CharacterFileList
@onready var list_empty: VBoxContainer = %ListEmpty
@onready var list_empty_title: Label = %ListEmptyTitle
@onready var list_empty_detail: Label = %ListEmptyDetail
@onready var clear_search_button: Button = %ClearSearch
@onready var detail_panel: PanelContainer = %DetailPanel
@onready var detail_scroll: ScrollContainer = %DetailScroll
@onready var detail_portrait: TextureRect = %DetailPortrait
@onready var detail_tactical_icon: TextureRect = %DetailTacticalIcon
@onready var detail_name: Label = %DetailName
@onready var detail_identity: Label = %DetailIdentity
@onready var stat_grid: GridContainer = %StatGrid
@onready var eligibility_accent: ColorRect = %EligibilityAccent
@onready var eligibility_heading: Label = %EligibilityHeading
@onready var eligibility_reasons: Label = %EligibilityReasons
@onready var add_group: VBoxContainer = %AddGroup
@onready var add_to_party_button: Button = %AddToParty
@onready var full_sheet_button: Button = %FullSheet
@onready var edit_button: Button = %EditCharacter
@onready var restore_archived_button: Button = %RestoreArchived
@onready var archive_button: Button = %Archive
@onready var setup_reason: Label = %SetupReason
@onready var revision_rows: VBoxContainer = %RevisionRows
@onready var manage_strip: VBoxContainer = %ManageStrip
@onready var delete_button: Button = %DeletePermanently
@onready var empty_state: PanelContainer = %EmptyState
@onready var empty_title: Label = %EmptyTitle
@onready var empty_detail: Label = %EmptyDetail
@onready var empty_restore_starters_button: Button = %EmptyRestoreStarters
@onready var footer: HBoxContainer = %Footer
@onready var status_notice: Label = %StatusNotice
@onready var prompts: HBoxContainer = %Prompts
@onready var inspection_area: VBoxContainer = %VaultInspectionArea
@onready var inspection_back_button: Button = $WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody/VaultInspectionArea/InspectionHeader/Back
@onready var inspection_heading: Label = %Heading
@onready var inspection_eligibility: Label = %InspectionEligibility
@onready var character_sheet: ClassicCharacterSheet = %VaultCharacterSheet
@onready var character_editor: CharacterEditor = %CharacterEditor


func apply_route_chrome() -> void:
	# The library authors its own header; the shared route heading stays hidden.
	($WorkspaceColumn/WorkspaceHeader as Control).visible = false
	($WorkspaceColumn/HeaderRule as Control).visible = false


## Dialogs close only when the layout changes; a refresh of the same layout keeps them open.
func prepare_list_layout() -> void:
	if not library.visible: _dismiss_dialogs()
	library.visible = true
	inspection_area.visible = false
	character_editor.visible = false


func prepare_inspection_layout() -> void:
	if not inspection_area.visible: _dismiss_dialogs()
	library.visible = false
	inspection_area.visible = true
	character_editor.visible = false


func prepare_editor_layout() -> void:
	_dismiss_dialogs()
	library.visible = false
	inspection_area.visible = false
	character_editor.visible = true


func _dismiss_dialogs() -> void:
	(%ArchiveConfirmation as Window).hide()
	if not repair_dialog.committing(): repair_dialog.hide()


func stat_value(tile_name: String) -> Label:
	return stat_grid.get_node("%s/Tile/Value" % tile_name) as Label


func prompt_glyph(prompt_name: String) -> Label:
	return prompts.get_node("%s/Glyph" % prompt_name) as Label


## Applies the profile's list and search widths and stat columns.
func apply_profile(compact: bool) -> void:
	UiSizing.minimum_size(list_panel, Vector2(compact_list_width if compact else wide_list_width, 0))
	UiSizing.minimum_size(search_field, Vector2(compact_search_width if compact else wide_search_width, 0))
	stat_grid.columns = 2 if compact else 4
