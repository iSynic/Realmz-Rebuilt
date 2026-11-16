## Nonserialized preparation for one source save and destination setup revision.
class_name PartyTransferReview
extends RefCounted

var candidates: Array[PartyTransferCandidate] = []
var left_behind: Array[String] = []
var source_package_hash: String
var source_campaign_id: String
var source_definitions: ContentTransferCatalog
var destination_package_hash: String
var destination_revision: int
var source_file_hash: String
var available_slots: int
## Whether same-named items take the destination version instead of staying behind.
var adopt_changed: bool
var changed_items: Array[String] = []
