class_name RealmzContent
extends RefCounted

var campaign_id: String
var package_hash: String
var content_id: String
var rules_version: String
var start_map_id: String
var start_coordinate: Vector2i
var world: WorldDefinition
var _messages: Dictionary = {}
var _triggers: Dictionary = {}


func _init(campaign: String, package_identity: String, content_identity: String, rules: String, start_map: String, start_position: Vector2i, world_definition: WorldDefinition, messages: Array[MessageDefinition], triggers: Array[TriggerDefinition]) -> void:
	campaign_id = campaign
	package_hash = package_identity
	content_id = content_identity
	rules_version = rules
	start_map_id = start_map
	start_coordinate = start_position
	world = world_definition
	for message: MessageDefinition in messages:
		_messages[message.id] = message
	for trigger: TriggerDefinition in triggers:
		_triggers[trigger.id] = trigger


func message_by_id(message_id: int) -> MessageDefinition:
	return _messages.get(message_id) as MessageDefinition


func trigger_by_id(trigger_id: String) -> TriggerDefinition:
	return _triggers.get(trigger_id) as TriggerDefinition
