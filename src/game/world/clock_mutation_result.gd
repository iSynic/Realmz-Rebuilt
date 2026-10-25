## Separates committed clock events from the ordered age and timer work they require.
class_name ClockMutationResult
extends RefCounted

var events: Array[DomainEvent] = []
var age_updates: Array[AgeUpdateRequestBody] = []
var scan_timers: bool = false
