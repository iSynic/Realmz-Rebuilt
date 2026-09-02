class_name CampaignSummaryView
extends RefCounted

var campaign_id: String = ""
var title: String = ""
var version: String = ""
var author: String = ""
var contact: Dictionary = {}
var description: String = ""
var splash_asset_id: String = ""
var restriction_description: String = ""
var maximum_party_size: int = 6
var maximum_level: int = 0
var recommended_party_levels: int = 0
var maximum_party_levels: int = 0
var guidance_authored: bool = false
var banned_races: Array[String] = []
var banned_castes: Array[String] = []
var package_hash: String = ""
