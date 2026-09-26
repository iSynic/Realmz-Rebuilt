## Exposes the campaign selector's variable record scene to its controller.

class_name CampaignSelectionPanel
extends PanelContainer

@export var campaign_row_scene: PackedScene

signal revision_selected(campaign_id: String, package_hash: String)
signal removal_requested(campaign_id: String, display_name: String)
signal back_requested

var _origin := "main"
var _campaign: CampaignPackageView
var _running := false

func _ready() -> void:
	%MainFilter.pressed.connect(_filter_origin.bind("main"))
	%ImportedFilter.pressed.connect(_filter_origin.bind("imported"))
	%CampaignSearch.text_changed.connect(func(_text: String) -> void: _filter_rows())
	%CampaignRevision.item_selected.connect(_choose_revision)
	%RemoveCampaign.pressed.connect(func() -> void:
		if _campaign != null and not _running: removal_requested.emit(_campaign.campaign_id, _campaign.display_name))
	%ShowScenarioDetails.pressed.connect(_open_details)
	%CloseScenarioDetails.pressed.connect(close_details)
	%ScenarioBack.pressed.connect(func() -> void: back_requested.emit())
	get_viewport().gui_focus_changed.connect(_keep_details_focus)

func present_campaign(campaign: CampaignPackageView, running: bool, selected: bool, pending_revision: String = "") -> void:
	_campaign = campaign
	_running = running
	%CampaignDockTitle.text = campaign.display_name if campaign != null else "Choose a scenario"
	%CampaignDockTitle.tooltip_text = %CampaignDockTitle.text
	%CampaignDockStatus.text = "Preparing scenario..." if running else "Ready to add characters" if selected else campaign.error_message if campaign != null and not campaign.ready else "Select a scenario to add characters."
	%CampaignDockStatus.tooltip_text = %CampaignDockStatus.text
	%CampaignRevision.clear()
	%CampaignRevision.visible = campaign != null and campaign.origin == "imported" and campaign.revisions.size() > 1
	%CampaignRevision.disabled = running
	%CampaignRevision.tooltip_text = "Version for %s" % campaign.display_name if campaign != null else ""
	if campaign != null:
		for revision: Dictionary in campaign.revisions:
			var label := String(revision.get("version_label", ""))
			if label.is_empty(): label = String(revision.get("imported_at", ""))
			if label.is_empty(): label = "Imported version %d" % (%CampaignRevision.item_count + 1)
			elif campaign.revisions.filter(func(other: Dictionary) -> bool: return String(other.get("version_label", "")) == label).size() > 1:
				label += " • revision %d" % (%CampaignRevision.item_count + 1)
			%CampaignRevision.add_item(label)
			var index: int = %CampaignRevision.item_count - 1
			%CampaignRevision.set_item_metadata(index, revision.get("package_hash", ""))
			if revision.get("package_hash", "") == (pending_revision if running and not pending_revision.is_empty() else campaign.package_hash): %CampaignRevision.select(index)
		if running and not pending_revision.is_empty(): %CampaignDockStatus.text = "Preparing %s..." % %CampaignRevision.get_item_text(%CampaignRevision.selected)
	%RemoveCampaign.visible = campaign != null and campaign.origin == "imported"
	%RemoveCampaign.disabled = running
	%ShowScenarioDetails.disabled = campaign == null or running
	if campaign != null and not selected:
		%SelectedScenarioSummary.show()
		%SelectedScenarioTitle.text = campaign.display_name
		%SelectedScenarioByline.text = "Unavailable" if not campaign.ready else "Not prepared"
		%SelectedScenarioRestrictions.text = campaign.error_message if not campaign.ready else "Select this scenario to load its full details."
		%SelectedScenarioRestrictions.show()
		%SelectedScenarioLimits.text = ""
		%SelectedScenarioGuidance.text = ""
		%SelectedScenarioSplash.hide()
		%SelectedScenarioSplashUnavailable.hide()
	%MainFilter.disabled = running
	%ImportedFilter.disabled = running
	%CampaignSearch.editable = not running
	_filter_rows()

func reveal_campaign(campaign: CampaignPackageView) -> void:
	if campaign == null: return
	%CampaignSearch.text = ""
	_filter_origin(campaign.origin)
	call_deferred("_reveal_path", campaign.path)

func _reveal_path(path: String) -> void:
	await get_tree().process_frame
	for rows: VBoxContainer in [%MainCampaignRows, %ImportedCampaignRows]:
		for row: Node in rows.get_children():
			if row.has_method("package_path") and row.package_path() == path and row.is_visible_in_tree():
				%CampaignScroll.ensure_control_visible(row)

func _filter_origin(origin: String) -> void:
	_origin = origin
	_filter_rows()

func _filter_rows() -> void:
	%MainFilter.set_pressed_no_signal(_origin == "main")
	%ImportedFilter.set_pressed_no_signal(_origin == "imported")
	%MainScenarioHeading.hide()
	%ImportedScenarioHeading.hide()
	%MainCampaignRows.visible = _origin == "main"
	%ImportedCampaignRows.visible = _origin == "imported"
	%MainFilter.text = "Main %d" % %MainCampaignRows.get_child_count()
	%ImportedFilter.text = "Imported %d" % %ImportedCampaignRows.get_child_count()
	var count := 0
	var query: String = %CampaignSearch.text.strip_edges().to_lower()
	for rows: VBoxContainer in [%MainCampaignRows, %ImportedCampaignRows]:
		for row: Node in rows.get_children():
			var label: String = row.get_node("%LaunchCampaign").text
			row.visible = query.is_empty() or label.to_lower().contains(query)
			if rows.visible and row.visible: count += 1
	%NoCampaignsState.visible = count == 0
	%NoCampaignsState.text = "No matching scenarios." if not %CampaignSearch.text.is_empty() else "No imported scenarios yet. Import a folder or install a package below." if _origin == "imported" else "No main scenarios available."

func _choose_revision(index: int) -> void:
	if _campaign != null and not _running and index >= 0:
		revision_selected.emit(_campaign.campaign_id, String(%CampaignRevision.get_item_metadata(index)))

func _open_details() -> void:
	%ScenarioDetails.position = Vector2.ZERO
	%ScenarioDetails.size = get_viewport_rect().size
	%Panel.custom_minimum_size = Vector2(minf(560, get_viewport_rect().size.x - 32), minf(440, get_viewport_rect().size.y - 32))
	%ScenarioDetails.show()
	%CloseScenarioDetails.grab_focus()

func close_details() -> void:
	%ScenarioDetails.hide()
	%ShowScenarioDetails.grab_focus()

func _keep_details_focus(control: Control) -> void:
	if %ScenarioDetails.is_visible_in_tree() and not %ScenarioDetails.is_ancestor_of(control):
		%CloseScenarioDetails.grab_focus()

func _input(event: InputEvent) -> void:
	if %ScenarioDetails.visible and event.is_action_pressed("ui_cancel"):
		close_details()
		get_viewport().set_input_as_handled()
