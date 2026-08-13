class_name CampaignDefinition
extends RefCounted

var id: String = ""
var title: String = ""
var version: String = ""
var author: String = ""
var contact: Dictionary = {}
var description: String = ""
var splash_asset_id: String = ""
var recommended_party_levels: int = 0
var maximum_party_levels: int = 0
var guidance_authored: bool = false
var restrictions: RestrictionDefinition = RestrictionDefinition.new()
