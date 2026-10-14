## Carries the immutable character rules needed before a scenario world is ready.
class_name ScenarioSetupCatalog
extends RefCounted

var content: RealmzContent
var application_package_hash: String


func _init(setup_content: RealmzContent, application_hash: String) -> void:
	content = setup_content
	application_package_hash = application_hash


func matches(full_content: RealmzContent) -> bool:
	return full_content != null and content != null and not content.setup_rules_identity.is_empty() and full_content.setup_rules_identity == content.setup_rules_identity and full_content.application_package_hash == application_package_hash and full_content.campaign_id == content.campaign_id and full_content.package_hash == content.package_hash and full_content.content_id == content.content_id and full_content.rules_version == content.rules_version
