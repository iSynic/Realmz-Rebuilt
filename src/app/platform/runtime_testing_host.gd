## Connects opt-in testing transport to explicit application-owned collaborators.
class_name RuntimeTestingHost
extends Node

var _endpoint: RuntimeTestingEndpoint
var _observer: RuntimeTestingObserver


static func live_requested() -> bool:
	return OS.is_debug_build() and OS.get_cmdline_user_args().has("--realmz-testing-observe")


func bind(session: GameSessionController, content: Callable, readiness: Callable) -> Error:
	if not live_requested():
		return ERR_UNAUTHORIZED
	_observer = RuntimeTestingObserver.new(session, content, readiness)
	_endpoint = RuntimeTestingEndpoint.new()
	add_child(_endpoint)
	return _endpoint.open(OS.get_environment("REALMZ_TESTING_HOME"), "observe", func() -> int: return session.view().revision, _dispatch)


func _dispatch(command: String, params: Dictionary) -> Dictionary:
	match command:
		"describe":
			return _observer.accepted(_endpoint.description()) if params.is_empty() else _observer.rejected("invalid_params", "Describe accepts an empty parameter object.")
		"observe":
			return _observer.observe(params)
		"checkpoint":
			return _observer.checkpoint(params)
	return _observer.rejected("unsupported_command", "This adapter does not support the requested command.")
