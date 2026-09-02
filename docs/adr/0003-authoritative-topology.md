# ADR 0003: One authoritative map topology

Status: accepted

`MapTopology` plus `WorldState` overlays answers every gameplay map question. Rendering, collisions, navigation graphs, minimaps, battle terrain, and optional 3D are disposable derivatives. Providence normalizes imported land and dungeon data before runtime packaging.
