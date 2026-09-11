## Frames one bounded nonblocking testing request without entering gameplay.
class_name RuntimeTestingConnection
extends RefCounted

const TRANSFER_BYTES := 64 * 1024
var peer: StreamPeerTCP
var input := PackedByteArray()
var output := PackedByteArray()
var sent: int = 0
var handled: bool = false
var finished: bool = false
var deadline_msec: int


func _init(connection: StreamPeerTCP) -> void:
	peer = connection
	deadline_msec = Time.get_ticks_msec() + 5000


func poll(handler: Callable) -> void:
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() > deadline_msec:
		close()
		return
	if handled:
		_send()
		return
	var available := mini(peer.get_available_bytes(), TRANSFER_BYTES)
	if available <= 0:
		return
	var received := peer.get_partial_data(available)
	if received[0] != OK:
		close()
		return
	input.append_array(received[1])
	if input.size() > RuntimeTestingProtocol.MAX_MESSAGE_BYTES:
		close()
		return
	var newline := input.find(10)
	if newline < 0:
		return
	var parser := JSON.new()
	var valid := newline == input.size() - 1 and parser.parse(input.slice(0, newline).get_string_from_utf8()) == OK
	var reply: Dictionary = handler.call(parser.data if valid else null)
	output = (JSON.stringify(reply, "", true, true) + "\n").to_utf8_buffer()
	input.clear()
	handled = true
	deadline_msec = Time.get_ticks_msec() + 30_000
	_send()


func _send() -> void:
	var result := peer.put_partial_data(output.slice(sent, mini(sent + TRANSFER_BYTES, output.size())))
	if result[0] != OK:
		close()
		return
	sent += int(result[1])
	if sent >= output.size():
		close()


func close() -> void:
	peer.disconnect_from_host()
	finished = true
