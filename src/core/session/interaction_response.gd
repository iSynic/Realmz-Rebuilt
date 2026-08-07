class_name InteractionResponse
extends RefCounted

var request_id: String
var kind: StringName
var payload: Dictionary


func _init(id: String, response_kind: StringName, response_payload: Dictionary = {}) -> void:
	request_id = id
	kind = response_kind
	payload = response_payload.duplicate(true)


func is_supported_kind() -> bool:
	return InteractionRequest.kind_is_supported(kind)


static func acknowledge(request: InteractionRequest) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, InteractionRequest.ACKNOWLEDGE, {})


static func yes_no(request: InteractionRequest, accepted: bool) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, InteractionRequest.YES_NO, {"accepted": accepted})


static func indexed_choice(request: InteractionRequest, index: int) -> InteractionResponse:
	return InteractionResponse.new(request.request_id, request.kind, {"index": index})
