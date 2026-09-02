class_name PartySummaryView
extends RefCounted

var character_ids: Array[String] = []
var ally_ids: Array[String] = []
var pooled_gold: int = 0
var banked_gold: int = 0
var fatigue: int = 0
var light_remaining: int = 0
var condition_values: Array[int] = []
var has_classic_torch: bool = false
var camping: bool = false
var searching: bool = false
var in_boat: bool = false
var acquired_map_ids: Array[String] = []
