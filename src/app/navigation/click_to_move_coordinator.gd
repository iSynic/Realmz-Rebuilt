## Executes disposable routes through acknowledged ordinary session commands.
class_name ClickToMoveCoordinator
extends RefCounted

const STOP_EVENTS: Array[StringName] = [&"trigger_fired", &"map_transitioned", &"timed_encounter_triggered", &"random_door_triggered", &"random_encounter_triggered", &"contextual_encounter_triggered"]

var _session: GameSessionController
var _presentation: PresentationCoordinator
var _shell: GameShell
var _map: ClassicMapPresenter
var _battlefield: ClassicBattlefieldPresenter
var _held: HeldMovementController
var _allows_exploration: Callable
var _is_first_person: Callable
var _submit_intent: Callable
var _submit_response: Callable
var combat_input_available: Callable
var _path: Array[Vector2i] = []
var _reachability: BattlefieldReachability
var _cached_revision := -1
var _cached_session := 0
var _expected_revision := -1
var _route_session := 0
var _battle_id := ""
var _actor_id := ""
var _round := -1
var _map_id := ""
var _remaining := 0.0
var _submitting := false
var _preview: MovementRoutePreview

func _init(session: GameSessionController, presentation: PresentationCoordinator, shell: GameShell, map: ClassicMapPresenter, battlefield: ClassicBattlefieldPresenter, held: HeldMovementController, allows_exploration: Callable, is_first_person: Callable, submit_intent: Callable, submit_response: Callable) -> void:
	_session = session
	_presentation = presentation
	_shell = shell
	_map = map
	_battlefield = battlefield
	_held = held
	_allows_exploration = allows_exploration
	_is_first_person = is_first_person
	_submit_intent = submit_intent
	_submit_response = submit_response
	_shell.exploration_move_to_available = func() -> bool: return _allows_exploration.call() and not _is_first_person.call()
	_shell.exploration_move_to_requested.connect(func() -> void: _map.movement_preview.toggle())
	for preview: MovementRoutePreview in [_map.movement_preview, _battlefield.movement_preview]:
		preview.destination_hovered.connect(func(coordinate: Vector2i) -> void: _hover(preview, coordinate))
		preview.destination_selected.connect(func(coordinate: Vector2i) -> void: _choose(preview, coordinate))
		preview.mode_changed.connect(func(enabled: bool) -> void:
			if not enabled: cancel()
			else: _held.stop()
		)
	_session.intent_submitted.connect(func(_intent: PlayerIntent) -> void:
		if not _submitting: cancel()
	)
	_session.response_submitted.connect(func(_response: InteractionResponse) -> void:
		if not _submitting: cancel()
	)
	_shell.route_changed.connect(func(_route: StringName) -> void: cancel())

func poll(delta: float) -> void:
	var view := _session.view()
	# Playback temporarily removes the command surface; it is not a new task.
	var awaiting_combat_draw := _presentation.is_combat_playback_active() or _presentation.drawn_revision != view.revision
	if not _path.is_empty() and not _battle_id.is_empty() and awaiting_combat_draw:
		if not _shell.navigation_overlay_active and _shell.navigator.current_screen() == &"combat" and _route_is_current(view, view.combat_view != null, false):
			return
	var combat := not _shell.navigation_overlay_active and _combat_available(view)
	var exploring: bool = not _shell.navigation_overlay_active and _allows_exploration.call() and not _is_first_person.call()
	_map.movement_preview.set_available(exploring, Input.is_physical_key_pressed(KEY_SHIFT), _shell.click_to_move_enabled)
	_battlefield.movement_preview.set_available(combat, Input.is_physical_key_pressed(KEY_SHIFT), _shell.click_to_move_enabled)
	_refresh_reachability(view, combat and _battlefield.movement_preview.enabled)
	if _path.is_empty(): return
	if not _route_is_current(view, combat, exploring):
		cancel("Move To stopped • the active task or route changed.")
		return
	if _presentation.is_combat_playback_active() or _presentation.drawn_revision != view.revision: return
	_remaining -= delta
	if _remaining > 0.0: return
	_step(view, combat)

func cancel(message: String = "") -> void:
	var was_active := not _path.is_empty()
	_path.clear()
	_preview = null
	_map.movement_preview.clear()
	_battlefield.movement_preview.clear()
	_cached_revision = -1
	if was_active and not message.is_empty(): _shell.status.set_status(message)

func is_selecting_destination() -> bool:
	return _map.movement_preview.enabled or _battlefield.movement_preview.enabled

func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"realmz_back") and (not _path.is_empty() or _map.movement_preview.latched or _battlefield.movement_preview.latched):
		cancel("Move To cancelled.")
		return true
	if UiInputActions.movement_direction(event) != Vector2i.ZERO:
		cancel("Move To cancelled • manual movement.")
	return false

func handle_controller(action: StringName, direction: Vector2i) -> bool:
	var view := _session.view()
	var combat := _combat_available(view)
	var preview := _battlefield.movement_preview if combat else _map.movement_preview
	if not preview.enabled or not combat and (not _allows_exploration.call() or _is_first_person.call()): return false
	if direction != Vector2i.ZERO:
		preview.move_focus(direction, BattlefieldPresentationGeometry.actor_position(view.combat_view, view.party_members, view.combat_view.active_actor_id) if combat else view.party_coordinate)
	elif action == &"realmz_controller_confirm":
		_choose(preview, preview.destination)
	elif action == &"realmz_controller_back":
		cancel("Move To cancelled.")
	else:
		return false
	return true

func _combat_available(view: GameView) -> bool:
	if view == null or view.combat_view == null or view.combat_view.outcome != &"active": return false
	if combat_input_available.is_valid() and not combat_input_available.call(): return false
	var request := view.active_interaction_request()
	return _shell.navigator.current_screen() == &"combat" and request != null and request.kind == InteractionRequest.COMBAT and _battlefield.interaction.targeting == null

func _refresh_reachability(view: GameView, combat: bool) -> void:
	if not combat:
		_cached_revision = -1
		_reachability = null
		return
	var session_id := _session.session().get_instance_id()
	if _cached_revision == view.revision and _cached_session == session_id: return
	_cached_revision = view.revision
	_cached_session = session_id
	_reachability = _session.session().navigation.combat_reachability() if combat else null
	if combat and _path.is_empty(): _hover(_battlefield.movement_preview, _battlefield.movement_preview.destination)

func _hover(preview: MovementRoutePreview, coordinate: Vector2i) -> void:
	if not _path.is_empty(): return
	var path: Array[Vector2i] = []
	var affordable: Array[Vector2i] = []
	var message := "Choose a revealed destination • Escape cancels"
	if preview == _battlefield.movement_preview and _reachability != null:
		affordable.assign(_reachability.costs.keys())
		path = _reachability.route_to(coordinate)
		message = "%d movement • reactions may interrupt" % _reachability.costs[coordinate] if _reachability.costs.has(coordinate) else "Unreachable, occupied, or beyond remaining movement"
	elif coordinate.x >= 0:
		path = _session.session().navigation.exploration_route(coordinate)
		message = "%d steps • stops at encounters and action points" % path.size() if not path.is_empty() else "Destination is unreachable through revealed terrain"
	preview.show_preview(path, message, affordable)

func _choose(preview: MovementRoutePreview, coordinate: Vector2i) -> void:
	if coordinate.x < 0 or _shell.navigation_overlay_active: return
	var view := _session.view()
	var combat := preview == _battlefield.movement_preview
	if combat and not _combat_available(view): return
	if not combat and (not _allows_exploration.call() or _is_first_person.call()): return
	var path: Array[Vector2i] = _session.session().navigation.combat_reachability().route_to(coordinate) if combat else _session.session().navigation.exploration_route(coordinate)
	if path.is_empty():
		_shell.status.set_status("Move To • destination is unreachable, occupied, or beyond the movement budget.", true)
		return
	_held.stop()
	_path = path
	_preview = preview
	_route_session = _session.session().get_instance_id()
	_expected_revision = view.revision
	_map_id = view.party_map_id
	_battle_id = view.combat_view.battle_id if combat else ""
	_actor_id = view.combat_view.active_actor_id if combat else ""
	_round = view.combat_view.round_number if combat else -1
	_remaining = 0.0
	preview.show_preview(_path, "Following route • Escape cancels")

func _route_is_current(view: GameView, combat: bool, exploring: bool) -> bool:
	if _route_session != _session.session().get_instance_id() or view.revision != _expected_revision: return false
	if _battle_id.is_empty(): return exploring and view.party_map_id == _map_id and view.combat_view == null
	return combat and view.combat_view.battle_id == _battle_id and view.combat_view.active_actor_id == _actor_id and view.combat_view.round_number == _round

func _step(view: GameView, combat: bool) -> void:
	var destination := _path[0]
	var step: SessionStep
	_submitting = true
	if combat:
		var legal := view.combat_view.movement_options.any(func(option: CombatMoveOptionView) -> bool: return option.destination == destination and option.enabled and option.attack_target_id.is_empty() and not option.retreats_from_battle)
		var fresh := _session.session().navigation.combat_reachability()
		if not legal or fresh.route_to(destination).size() != 1:
			_submitting = false
			cancel("Move To stopped • the next space is no longer reachable.")
			return
		var body := InteractionResponse.CombatBody.new(&"move", _actor_id)
		body.destination = destination
		body.has_destination = true
		step = _submit_response.call(InteractionResponse.new(view.active_interaction_request().request_id, InteractionRequest.COMBAT, body))
	else:
		var fresh := _session.session().navigation.exploration_route(destination)
		if fresh.size() != 1:
			_submitting = false
			cancel("Move To stopped • the next space is obstructed.")
			return
		var direction := destination - view.party_coordinate
		step = _submit_intent.call(ExplorationIntents.overhead_dungeon_move(direction) if view.map_view.level_type == &"dungeon" else ExplorationIntents.move(direction))
	_submitting = false
	_acknowledge(step, destination, combat)

func _acknowledge(step: SessionStep, destination: Vector2i, combat: bool) -> void:
	if _path.is_empty() or _preview == null: return
	var view := _session.view()
	if step == null or step.state == SessionStep.State.FAILED:
		cancel("Move To stopped • " + (step.error_message if step != null else "the movement did not complete."))
		return
	var position := BattlefieldPresentationGeometry.actor_position(view.combat_view, view.party_members, _actor_id) if combat and view.combat_view != null else view.party_coordinate
	if position != destination or step.events.any(func(event: DomainEvent) -> bool: return event.kind in STOP_EVENTS):
		cancel("Move To stopped • an interaction or reaction interrupted the route.")
		return
	_path.pop_front()
	_expected_revision = view.revision
	_remaining = _held.interval_seconds()
	if _path.is_empty():
		cancel()
		_shell.status.set_status("Destination reached.")
	else:
		_preview.show_preview(_path, "Following route • Escape cancels")
