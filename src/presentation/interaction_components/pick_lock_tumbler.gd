class_name PickLockTumbler
extends Control

const ClassicPickLockRulesScript := preload("res://src/core/rules/classic_pick_lock_rules.gd")

var marker_position: int = 10
var yellow_threshold: int = 100
var green_threshold: int = 150


func _init() -> void:
	custom_minimum_size = Vector2(360.0, 34.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(position_value: int, yellow: int, green: int) -> void:
	marker_position = position_value
	yellow_threshold = yellow
	green_threshold = green
	queue_redraw()


func _draw() -> void:
	var track := Rect2(2.0, 7.0, size.x - 4.0, size.y - 14.0)
	draw_rect(track, Color("6b2d2d"), true)
	var yellow_x := track.position.x + track.size.x * float(yellow_threshold) / float(ClassicPickLockRulesScript.TRACK_END)
	var green_x := track.position.x + track.size.x * float(green_threshold) / float(ClassicPickLockRulesScript.TRACK_END)
	draw_rect(Rect2(yellow_x, track.position.y, maxf(0.0, green_x - yellow_x), track.size.y), Color("80672d"), true)
	draw_rect(Rect2(green_x, track.position.y, maxf(0.0, track.end.x - green_x), track.size.y), Color("285b43"), true)
	var marker_x := track.position.x + track.size.x * float(marker_position) / float(ClassicPickLockRulesScript.TRACK_END)
	draw_line(Vector2(marker_x, 2.0), Vector2(marker_x, size.y - 2.0), Color("f2d36b"), 3.0)
	draw_rect(track, Color("626a70"), false, 1.0)
