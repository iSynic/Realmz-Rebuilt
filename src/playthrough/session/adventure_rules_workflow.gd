## Validates adventure rules at an idle setup or exploration boundary.
class_name AdventureRulesWorkflow
extends RefCounted


static func unavailable_reason(context: SessionWorkflowContext, pending: bool) -> String:
	if context == null or context.state == null:
		return "Select a campaign before changing Adventure Rules."
	if context.state.combat != null and not context.state.combat.completed:
		return "Adventure Rules cannot change during battle."
	if pending or context.scenario_vm != null and context.scenario_vm.is_active():
		return "Resolve the pending action or interaction before changing Adventure Rules."
	if context.state.character_draft != null:
		return "Finish or cancel character creation before changing Adventure Rules."
	return ""


static func apply(context: SessionWorkflowContext, pending: bool, selection: AdventureRulesIntents.Selection) -> SessionCoordinatorResult:
	var reason := unavailable_reason(context, pending)
	if not reason.is_empty():
		return SessionCoordinatorResult.rejected(&"adventure_rules_unavailable", reason)
	if selection == null or selection.rules == null:
		return SessionCoordinatorResult.rejected(&"invalid_adventure_rules", "A validated Adventure Rules selection is required.")
	context.state.adventure_rules = selection.rules.copy()
	return SessionCoordinatorResult.completed([DomainEvent.new(&"adventure_rules_changed", context.state.adventure_rules.to_data())])
