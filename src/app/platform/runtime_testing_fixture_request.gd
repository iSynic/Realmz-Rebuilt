## Validates the private launch contract before fixture persistence is constructed.
class_name RuntimeTestingFixtureRequest
extends RefCounted

var fixture_id: String
var scratch_root: String
var discovery_root: String
var build: String
var package_path: String
var package_sha256: String
var source: Dictionary


static func decode(value: Variant) -> RuntimeTestingFixtureRequest:
	var fields := ["protocol", "kind", "fixtureId", "scratchRoot", "discoveryRoot", "build", "packagePath", "packageSha256", "source"]
	if not OS.is_debug_build() or not exact_fields(value, fields):
		return null
	if value["protocol"] != RuntimeTestingProtocol.VERSION or value["kind"] != "fixture":
		return null
	for field: String in fields.slice(2, 8):
		if not value[field] is String or value[field].is_empty() or value[field].length() > 4096:
			return null
	if not hex_identity(value["fixtureId"], 32) or not hex_identity(value["packageSha256"], 64):
		return null
	var root: String = value["discoveryRoot"]
	if not root.is_absolute_path() or normalized(root) != normalized(OS.get_environment("REALMZ_TESTING_HOME")):
		return null
	if normalized(value["scratchRoot"]) != normalized(root.path_join("fixtures").path_join(value["fixtureId"])):
		return null
	if not value["packagePath"].is_absolute_path() or value["packagePath"].get_extension().to_lower() != "realmz2":
		return null
	if not _valid_source(value["source"], value["scratchRoot"]):
		return null
	var request := RuntimeTestingFixtureRequest.new()
	request.fixture_id = value["fixtureId"]
	request.scratch_root = value["scratchRoot"]
	request.discovery_root = root
	request.build = value["build"]
	request.package_path = value["packagePath"]
	request.package_sha256 = value["packageSha256"]
	request.source = value["source"].duplicate(true)
	return request


static func exact_fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


static func hex_identity(value: String, size: int) -> bool:
	return value.length() == size and value.to_lower() == value and value.is_valid_hex_number(false)


static func normalized(path: String) -> String:
	var result := path.replace("\\", "/").simplify_path().trim_suffix("/")
	return result.to_lower() if OS.get_name() == "Windows" else result


static func _valid_source(value: Variant, scratch_root: String) -> bool:
	if not value is Dictionary:
		return false
	if value.get("kind") == "checkpoint":
		if not exact_fields(value, ["kind", "checkpointPath", "checkpointSha256"]):
			return false
		return value["checkpointPath"] is String and value["checkpointPath"].is_absolute_path() and normalized(value["checkpointPath"]).begins_with(normalized(scratch_root) + "/") and value["checkpointSha256"] is String and hex_identity(value["checkpointSha256"], 64)
	if value.get("kind") != "classic-starters" or not exact_fields(value, ["kind", "seed", "location"]):
		return false
	if not integer(value["seed"], 1, 2_147_483_646) or not exact_fields(value["location"], ["mapId", "x", "y"]):
		return false
	var location: Dictionary = value["location"]
	return location["mapId"] is String and location["mapId"].length() in range(1, 129) and integer(location["x"], 0, 32767) and integer(location["y"], 0, 32767)
