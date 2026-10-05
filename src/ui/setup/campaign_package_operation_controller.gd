## Presents package progress, terminal failures, and detached import diagnostics.
class_name CampaignPackageOperationController
extends RefCounted

signal cancel_requested
signal retry_requested(operation: StringName, path: String, native_menu_selection: int)
signal dismiss_requested

var _host: PanelContainer
var _status: PackageOperationView
var _operation_phase: Label
var _operation_percentage: Label
var _operation_progress: ProgressBar
var cancel_button: Button
var _operation_status: Label
var _failure_details: Label
var _failure_actions: HBoxContainer
var retry_button: Button
var _failure_dismiss: Button
var _operation_warning_toggle: Button
var _operation_warning_viewport: ScrollContainer
var _operation_warning_details: RichTextLabel

func bind(panel: CampaignSelectionPanel) -> void:
	_host = panel.get_node("%PackageOperationHost") as PanelContainer
	_operation_phase = panel.get_node("%PackageOperationPhase") as Label
	_operation_percentage = panel.get_node("%PackageOperationPercentage") as Label
	_operation_progress = panel.get_node("%PackageOperationProgress") as ProgressBar
	cancel_button = panel.get_node("%CancelPackageOperation") as Button
	_operation_status = panel.get_node("%PackageOperationStatus") as Label
	_failure_details = panel.get_node("%PackageFailureDetails") as Label
	_failure_actions = panel.get_node("%PackageFailureActions") as HBoxContainer
	retry_button = panel.get_node("%RetryPackageOperation") as Button
	_failure_dismiss = panel.get_node("%DismissPackageFailure") as Button
	_operation_warning_toggle = panel.get_node("%PackageWarningDetailsToggle") as Button
	_operation_warning_viewport = panel.get_node("%PackageWarningDetailsViewport") as ScrollContainer
	_operation_warning_details = panel.get_node("%PackageWarningDetails") as RichTextLabel
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	retry_button.pressed.connect(_retry)
	_failure_dismiss.pressed.connect(func() -> void: dismiss_requested.emit())
	_operation_warning_toggle.pressed.connect(func() -> void: _operation_warning_viewport.visible = not _operation_warning_viewport.visible)

func present(status: PackageOperationView, needs_startup_selection: bool) -> void:
	_status = status
	var running: bool = status.is_running()
	var failed: bool = status.state == PackageOperationView.FAILED
	var succeeded: bool = status.state == PackageOperationView.SUCCEEDED
	_host.visible = running or failed or succeeded
	_operation_progress.visible = running
	_operation_percentage.visible = running
	cancel_button.visible = running
	_failure_actions.visible = failed
	_failure_details.visible = failed
	_operation_warning_viewport.visible = false
	_operation_warning_toggle.visible = false
	if not running and not failed and not succeeded:
		return
	var phase_text := String(status.phase).replace("_", " ").capitalize()
	_operation_phase.text = "Could not open scenario" if failed else "Import complete" if succeeded else phase_text if not phase_text.is_empty() else "Installing"
	_operation_percentage.text = "%d%%" % int(round(status.progress_ratio() * 100.0)) if running and status.total > 0 else "Complete" if succeeded else "Working"
	_operation_progress.indeterminate = status.total <= 0
	_operation_progress.max_value = maxf(1.0, float(status.total))
	_operation_progress.value = clampf(float(status.completed), 0.0, _operation_progress.max_value)
	_operation_status.text = status.message
	_operation_status.tooltip_text = status.message
	var diagnostics: Array[String] = status.diagnostic_details
	if not diagnostics.is_empty():
		_operation_warning_toggle.visible = true
		_operation_warning_toggle.text = "Show import diagnostics" if succeeded else "Show diagnostics"
		_operation_warning_details.text = "\n".join(diagnostics)
		_operation_warning_details.scroll_to_line(0)
	if failed:
		var operation := String(status.operation_name).replace("_", " ").capitalize()
		var details: Array[String] = []
		if not operation.is_empty():
			details.append("Operation: %s" % operation)
		if not status.package_path.is_empty():
			details.append("Package: %s" % status.package_path)
		if not status.error_code.is_empty():
			details.append("Error: %s" % status.error_code)
		var requirement: ClassicRuleSelectionView = status.required_rule_selection
		if requirement != null:
			details.append("%s: %d–%d (%s)" % [requirement.field, requirement.minimum, requirement.maximum, requirement.origin])
		_failure_details.text = "\n".join(details)
		_failure_details.tooltip_text = _failure_details.text
		retry_button.disabled = status.package_path.is_empty() or needs_startup_selection
		retry_button.tooltip_text = "Choose a startup file to retry this import." if needs_startup_selection else "Retry the same operation." if not retry_button.disabled else "The failed operation did not retain a path."
		_failure_dismiss.tooltip_text = "Return to the scenario list without changing current files."


func _retry() -> void:
	if not retry_button.disabled and _status.state == PackageOperationView.FAILED and not _status.package_path.is_empty():
		retry_requested.emit(_status.operation_name, _status.package_path, _status.native_menu_selection)
