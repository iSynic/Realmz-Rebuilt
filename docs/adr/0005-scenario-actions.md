# ADR 0005: Scenario Actions are ordinary reusable calls

Status: accepted

APs, XAPs, Encounter Results, hooks, and lifecycle events invoke built-in or project Scenario Actions through one ordinary timeline. Safe Actions are bounded portable programs in the scenario VM. Private helpers are not chooser entries. Core `realmz.*` operations cannot be overridden, and raw Godot/GDScript access is not a fallback.
