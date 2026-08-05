# ADR 0006: Centralize persistence and randomness

Status: accepted

The session snapshot is the sole save aggregate. It includes every mutable domain, VM continuation, pending interaction, clock value, Scenario Action state, and RNG state/draw count. All gameplay draws pass through `RealmzRng`; presentation randomness is isolated and cannot affect replay or saves.
