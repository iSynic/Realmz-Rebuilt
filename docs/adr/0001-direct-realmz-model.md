# ADR 0001: Model Realmz directly

Status: accepted

The runtime uses typed Realmz concepts matching Castle structs and control flow. It does not adapt campaign behavior to the prior Remake's generic resources. This keeps authored IDs, encounter routing, arithmetic, maps, and save meanings explicit and testable against the oracle.
