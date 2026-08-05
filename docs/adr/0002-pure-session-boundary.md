# ADR 0002: Pure session and explicit host boundary

Status: accepted

One pure `GameSession` owns gameplay state and commits typed intents synchronously. Godot consumes views/events and returns typed responses only for genuine interactions. The root scene constructs dependencies explicitly; gameplay autoloads, service locators, Nodes in simulation, and dynamic script dispatch are prohibited.
