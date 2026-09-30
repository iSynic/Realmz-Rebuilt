## Nonserialized preparation for one source save and destination setup revision.
class_name PartyTransferReview
extends RefCounted

var candidates: Array[PartyTransferCandidate] = []
var left_behind: Array[String] = []
var source_package_hash: String
var destination_package_hash: String
var destination_revision: int
var source_file_hash: String
var available_slots: int
