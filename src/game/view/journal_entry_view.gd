class_name JournalEntryView
extends RefCounted

var message_id: int
var text: String


func _init(source_message_id: int, source_text: String) -> void:
	message_id = source_message_id
	text = source_text
