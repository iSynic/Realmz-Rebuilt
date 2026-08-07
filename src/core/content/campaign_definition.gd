class_name CampaignDefinition
extends RefCounted

var id: String = ""
var title: String = ""
var version: String = ""
var author: String = ""
var contact: Dictionary = {}
var description: String = ""
var splash_asset_id: String = ""
var restrictions: RestrictionDefinition = RestrictionDefinition.new()
