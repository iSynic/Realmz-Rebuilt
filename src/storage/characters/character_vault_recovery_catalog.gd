## Resolves exact historical stock rules only for explicit Character Files repair.
class_name CharacterVaultRecoveryCatalog
extends RefCounted

const PATH := "res://src/storage/characters/character-rule-recovery.json"
const SHA256 := "912e79bf075cae103c89604af765b16654a0859a358b229326dbc15151c34b82"

var last_error := ""
var _profiles: Array = []


func load_catalog() -> bool:
	var bytes := FileAccess.get_file_as_bytes(PATH)
	if bytes.is_empty() or FileAccess.get_sha256(PATH) != SHA256:
		last_error = "The built-in character recovery definitions failed verification."
		return false
	var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or data.get("version") != 1 or not data.get("profiles") is Array:
		last_error = "The built-in character recovery catalog is invalid."
		return false
	_profiles = data.profiles
	return true


func resolve(record: CharacterVaultRecord) -> CharacterVaultRuleIdentity:
	for profile: Dictionary in _profiles:
		if profile.packageHash != record.source_package_hash or profile.rulesVersion != record.rules_version or not record.source_campaign_id in profile.sourceCampaignIds:
			continue
		if not profile.races.has(record.state.race_id) or not profile.castes.has(record.state.caste_id):
			return null
		return CharacterVaultRuleIdentity.from_data({"version": 1, "raceId": record.state.race_id, "casteId": record.state.caste_id, "raceFingerprint": profile.races[record.state.race_id], "casteFingerprint": profile.castes[record.state.caste_id], "raceCustom": false, "casteCustom": false})
	return null
