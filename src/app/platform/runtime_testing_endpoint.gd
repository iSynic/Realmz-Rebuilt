## Publishes an explicitly enabled authenticated loopback testing endpoint.
class_name RuntimeTestingEndpoint
extends Node

var protocol: RuntimeTestingProtocol
var descriptor: Dictionary = {}
var _server := TCPServer.new()
var _connections: Array[RuntimeTestingConnection] = []
var _descriptor_path: String = ""
var _revision: Callable
var _dispatch: Callable
var _shutdown_requested := false


func open(root_path: String, access: String, revision: Callable, dispatch: Callable, fixture: RuntimeTestingFixtureRequest = null) -> Error:
	if not OS.is_debug_build() or not root_path.is_absolute_path() or access not in ["observe", "fixture"]:
		return ERR_UNAUTHORIZED
	var identity := Crypto.new().generate_random_bytes(16).hex_encode()
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	if identity.length() != 32 or secret.length() != 64:
		return ERR_CANT_CREATE
	var status := _server.listen(0, "127.0.0.1")
	if status != OK:
		return status
	_revision = revision
	_dispatch = dispatch
	protocol = RuntimeTestingProtocol.new(identity, secret, access)
	descriptor = {"protocol": RuntimeTestingProtocol.VERSION, "sessionId": identity, "engine": "rebuilt", "build": OS.get_environment("REALMZ_TESTING_BUILD") if OS.has_environment("REALMZ_TESTING_BUILD") else "unversioned-source", "pid": OS.get_process_id(), "port": _server.get_local_port(), "token": secret, "access": access, "capabilities": ["describe", "observe", "checkpoint"], "startedAt": Time.get_datetime_string_from_system(true) + "Z"}
	if fixture != null:
		descriptor["fixtureId"] = fixture.fixture_id
		descriptor["build"] = fixture.build
		descriptor["capabilities"] = RuntimeTestingProtocol.COMMANDS.duplicate()
	var directory := root_path.simplify_path().path_join("sessions")
	status = DirAccess.make_dir_recursive_absolute(directory)
	if status != OK:
		_server.stop()
		return status
	_descriptor_path = directory.path_join(identity + ".json")
	var file := FileAccess.open(_descriptor_path, FileAccess.WRITE)
	if file == null:
		_server.stop()
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(descriptor))
	file.close()
	set_process(true)
	return OK


func description() -> Dictionary:
	var public_descriptor := descriptor.duplicate(true)
	public_descriptor.erase("token")
	return public_descriptor


func request_shutdown() -> void:
	_shutdown_requested = true
	_server.stop()


func _process(_delta: float) -> void:
	if not _server.is_listening() and not _shutdown_requested:
		return
	if not _shutdown_requested and _server.is_connection_available():
		var connection := _server.take_connection()
		if _connections.size() < 8:
			_connections.append(RuntimeTestingConnection.new(connection))
		else:
			connection.disconnect_from_host()
	for connection: RuntimeTestingConnection in _connections:
		connection.poll(_handle)
	_connections = _connections.filter(func(connection: RuntimeTestingConnection) -> bool: return not connection.finished)
	if _shutdown_requested and _connections.is_empty():
		get_tree().quit()


func _handle(request: Variant) -> Dictionary:
	return protocol.execute(request, int(_revision.call()), _dispatch)


func _exit_tree() -> void:
	_server.stop()
	for connection: RuntimeTestingConnection in _connections:
		connection.close()
	_connections.clear()
	if not _descriptor_path.is_empty():
		DirAccess.remove_absolute(_descriptor_path)
	_revision = Callable()
	_dispatch = Callable()
