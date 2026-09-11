## Defines the strict, developer-only Providence preview request contract.

class_name DevelopmentPreviewRequest
extends RefCounted

const KIND := "realmz2.preview-request"
const FORMAT_VERSION := 1
const PARTY_FIXTURE := "classic-six"
const ACTION_POINT := &"action-point"
const SIMPLE_ENCOUNTER := &"simple-encounter"
const COMPLEX_ENCOUNTER := &"complex-encounter"
const THIEF_ENCOUNTER := &"thief-encounter"
const EXTRA_ACTION_POINT_PROGRAM := &"extra-action-point-program"
const MAP_LOCATION := &"map-location"
const SCROLLING_TEXT := &"scrolling-text"
const BATTLE := &"battle"
const TREASURE := &"treasure"
const SHOP := &"shop"

var package_path: String
var package_sha256: String
var target_kind: StringName
var target_id: Variant
var target_complex_encounter_id: int = -1
var target_map_id: String = ""
var target_coordinate: Variant
var party_fixture: String
var rng_seed: int
var result_path: String


static func decode(data: Variant) -> DevelopmentPreviewRequest:
	if not data is Dictionary or not _has_exact_fields(data, ["kind", "formatVersion", "packagePath", "packageSha256", "target", "partyFixture", "rngSeed", "isolatedSession", "resultPath"]):
		return null
	if data["kind"] != KIND or not _is_integer(data["formatVersion"]) or int(data["formatVersion"]) != FORMAT_VERSION or data["isolatedSession"] != true:
		return null
	if not data["packagePath"] is String or not String(data["packagePath"]).is_absolute_path() or not data["resultPath"] is String or not String(data["resultPath"]).is_absolute_path():
		return null
	if not data["packageSha256"] is String or not _is_sha256(data["packageSha256"]):
		return null
	if data["partyFixture"] != PARTY_FIXTURE or not _is_integer(data["rngSeed"]):
		return null
	var target := _decode_target(data["target"])
	if target.is_empty():
		return null
	var request := DevelopmentPreviewRequest.new()
	request.package_path = data["packagePath"]
	request.package_sha256 = data["packageSha256"].to_lower()
	request.target_kind = target["kind"]
	request.target_id = target["id"]
	request.target_complex_encounter_id = target.get("complexEncounterId", -1)
	request.target_map_id = target.get("mapId", "")
	request.target_coordinate = target.get("coordinate")
	request.party_fixture = data["partyFixture"]
	request.rng_seed = int(data["rngSeed"])
	request.result_path = data["resultPath"]
	return request


static func _decode_target(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("kind") is String:
		return {}
	var kind := StringName(value["kind"])
	if kind in [SIMPLE_ENCOUNTER, COMPLEX_ENCOUNTER, EXTRA_ACTION_POINT_PROGRAM, BATTLE, TREASURE, SHOP]:
		if not _has_exact_fields(value, ["kind", "id"]) or not _is_integer(value["id"]) or int(value["id"]) < 0:
			return {}
		if kind == EXTRA_ACTION_POINT_PROGRAM and int(value["id"]) > 4_294_967_295:
			return {}
		return {"kind": kind, "id": int(value["id"])}
	if kind == THIEF_ENCOUNTER:
		if not _has_exact_fields(value, ["kind", "id", "complexEncounterId"]) or not _is_integer(value["id"]) or int(value["id"]) < 0 or not _is_integer(value["complexEncounterId"]) or int(value["complexEncounterId"]) < 0:
			return {}
		return {"kind": kind, "id": int(value["id"]), "complexEncounterId": int(value["complexEncounterId"])}
	if kind == SCROLLING_TEXT:
		if not _has_exact_fields(value, ["kind", "id"]) or not _is_integer(value["id"]) or int(value["id"]) == 0:
			return {}
		return {"kind": kind, "id": int(value["id"])}
	if kind not in [ACTION_POINT, MAP_LOCATION] or not _has_exact_fields(value, ["kind", "id", "mapId", "x", "y"]):
		return {}
	if not value["id"] is String or value["id"].is_empty() or not value["mapId"] is String or value["mapId"].is_empty() or not _is_integer(value["x"]) or not _is_integer(value["y"]):
		return {}
	if kind == MAP_LOCATION and value["id"] != value["mapId"]:
		return {}
	return {"kind": kind, "id": value["id"], "mapId": value["mapId"], "coordinate": Vector2i(int(value["x"]), int(value["y"]))}


static func _has_exact_fields(data: Dictionary, fields: Array[String]) -> bool:
	if data.size() != fields.size():
		return false
	for field: String in fields:
		if not data.has(field):
			return false
	return true


static func _is_integer(value: Variant) -> bool:
	return value is int or value is float and is_equal_approx(value, roundf(value))


static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if character not in "0123456789abcdefABCDEF":
			return false
	return true
