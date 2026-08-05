# ADR 0004: Providence compiles immutable runtime packages

Status: accepted

Providence remains canonical and emits deterministic `.realmz2` packages. The game neither interprets editor state nor loads Realmz native binary files. Providence validates before export; the runtime independently validates untrusted package bytes before typed construction.
