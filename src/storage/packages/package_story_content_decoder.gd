## Decodes campaign metadata, messages, and option labels.

class_name PackageStoryContentDecoder
extends PackageDecoderBase

func decode_campaign_definition(value: Variant) -> CampaignDefinition:
	if not value is Dictionary:
		_reject("Content campaign metadata must be an object.")
		return null
	var record: Dictionary = value
	var fields: Array[String] = ["id", "name", "version", "author", "contact", "description", "splashAssetId", "recommendedPartyLevels", "maximumPartyLevels", "guidanceAuthored", "restrictions"]
	if not _exact_fields(record, fields) or not record["id"] is String or record["id"].is_empty() or not record["name"] is String or record["name"].is_empty() or not record["version"] is String or not record["author"] is String or not record["contact"] is Dictionary or not record["description"] is String or not record["splashAssetId"] is String or _integer(record["recommendedPartyLevels"]) < 0 or _integer(record["maximumPartyLevels"]) < 0 or not record["guidanceAuthored"] is bool or not record["restrictions"] is Dictionary:
		_reject("Campaign display metadata is malformed.")
		return null
	var contact: Dictionary = record["contact"]
	if not _exact_fields(contact, ["email", "web", "date", "fee"]) or not contact["email"] is String or not contact["web"] is String or not contact["date"] is String or not contact["fee"] is String:
		_reject("Campaign contact metadata is malformed.")
		return null
	var restrictions: Dictionary = record["restrictions"]
	var restriction_fields: Array[String] = ["description", "maxPartySize", "maxLevel", "bannedRaces", "bannedCastes"]
	if not _exact_fields(restrictions, restriction_fields) or not restrictions["description"] is String or _integer(restrictions["maxPartySize"]) < 1 or _integer(restrictions["maxPartySize"]) > 6 or _integer(restrictions["maxLevel"]) < 0 or not restrictions["bannedRaces"] is Array or not restrictions["bannedCastes"] is Array:
		_reject("Campaign restriction metadata is malformed.")
		return null
	var result := CampaignDefinition.new()
	result.id = record["id"]
	result.title = record["name"]
	result.version = record["version"]
	result.author = record["author"]
	result.contact = record["contact"].duplicate(true)
	result.description = record["description"]
	result.splash_asset_id = record["splashAssetId"]
	result.recommended_party_levels = _integer(record["recommendedPartyLevels"])
	result.maximum_party_levels = _integer(record["maximumPartyLevels"])
	result.guidance_authored = record["guidanceAuthored"]
	result.restrictions.description = restrictions["description"]
	result.restrictions.maximum_party_size = _integer(restrictions["maxPartySize"])
	result.restrictions.maximum_level = _integer(restrictions["maxLevel"])
	for race_id: Variant in restrictions["bannedRaces"]:
		if not race_id is String:
			_reject("Campaign banned race IDs must be strings.")
			return null
		result.restrictions.banned_races.append(race_id)
	for caste_id: Variant in restrictions["bannedCastes"]:
		if not caste_id is String:
			_reject("Campaign banned caste IDs must be strings.")
			return null
		result.restrictions.banned_castes.append(caste_id)
	return result

func decode_messages(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content messages must be an array.")
		return null
	var messages: Array[MessageDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or _integer(record.get("id")) < 0 or not record.get("text") is String:
			_reject("Message record is malformed.")
			return null
		var id := _integer(record["id"])
		if ids.has(id):
			_reject("Message ID %d is duplicated." % id)
			return null
		ids[id] = true
		messages.append(MessageDefinition.new(id, record["text"]))
	return messages

func decode_option_labels(value: Variant) -> Variant:
	if not value is Array:
		_reject("Content option labels must be an array.")
		return null
	var option_labels: Array[OptionLabelDefinition] = []
	var ids: Dictionary = {}
	for record: Variant in value:
		if not record is Dictionary or not _exact_fields(record, ["id", "text"]) or _integer(record.get("id")) < 0 or not record.get("text") is String:
			_reject("Option-label record is malformed.")
			return null
		var id := _integer(record["id"])
		if ids.has(id):
			_reject("Option-label ID %d is duplicated." % id)
			return null
		ids[id] = true
		option_labels.append(OptionLabelDefinition.new(id, record["text"]))
	return option_labels
