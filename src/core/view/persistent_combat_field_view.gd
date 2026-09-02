class_name PersistentCombatFieldView
extends RefCounted

var slot: int
var spell_id: String
var spell_name: String
var caster_id: String
var center: Vector2i
var rotation: int
var shape: int
var queue_icon: int
var power_level: int
var remaining_duration: int
var affected_coordinates: Array[Vector2i] = []


func _init(field: PersistentCombatField, display_name: String, coordinates: Array[Vector2i]) -> void:
	slot = field.slot
	spell_id = field.spell_id
	spell_name = display_name
	caster_id = field.caster_id
	center = field.center
	rotation = field.rotation
	shape = field.shape
	queue_icon = field.queue_icon
	power_level = field.power_level
	remaining_duration = field.remaining_duration
	affected_coordinates = coordinates.duplicate()
