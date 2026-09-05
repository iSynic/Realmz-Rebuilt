## Explains whether shell navigation and application actions are currently legal.
class_name GameShellAvailability
extends RefCounted


static func route_change_reason(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return "Choose a campaign first."
	if game_view.party_setup_available:
		return "Begin the adventure first."
	if game_view.pending_interaction != null:
		return "Resolve the current interaction first."
	if game_view.combat_view != null and game_view.combat_view.outcome == &"active":
		return "Finish the current battle first."
	return ""


static func action_reason(game_view: GameView, action_id: StringName) -> String:
	if game_view == null or not game_view.session_started:
		return "Begin a campaign first."
	var availability := game_view.availability(action_id)
	return "" if availability.enabled else availability.reason


static func save_reason(game_view: GameView) -> String:
	var reason := session_reason(game_view)
	if not reason.is_empty():
		return reason
	if game_view.combat_view != null and game_view.combat_view.outcome == &"active":
		return "Saving is unavailable during battle."
	return ""


static func load_reason(game_view: GameView) -> String:
	var reason := session_reason(game_view)
	if not reason.is_empty():
		return reason
	if game_view.pending_interaction != null:
		return "Resolve the current interaction first."
	if game_view.combat_view != null and game_view.combat_view.outcome == &"active":
		return "Loading is unavailable during battle."
	return ""


static func campaign_library_reason(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return ""
	return "Return to the Main Menu before choosing another campaign."


static func allies_reason(game_view: GameView) -> String:
	var reason := route_change_reason(game_view)
	if not reason.is_empty():
		return reason
	if game_view.party_allies.is_empty():
		return "No allies are currently traveling with the party."
	return ""


static func end_adventure_reason(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return "Choose a campaign first."
	if game_view.pending_interaction != null and game_view.pending_interaction.kind != InteractionRequest.COMBAT:
		return "Resolve the current interaction first."
	return ""


static func session_reason(game_view: GameView) -> String:
	if game_view == null or not game_view.session_started:
		return "Choose a campaign first."
	if game_view.party_setup_available:
		return "Begin the adventure first."
	return ""
