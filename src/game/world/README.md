# World game model

Start with `MapTopology` when you need to understand where the party can move or what it can see. It is the one immutable spatial truth used by movement, pathfinding, line of sight, Search, Action Point lookup, and detached map views. Cells, directional edges, secrets, transitions, land profiles, and battle-terrain definitions live beside it because they describe authored world space.

Mutable playthrough truth sits beside the definitions whose meaning it preserves. `WorldState` gathers its topology, trigger, and exploration collaborators; together with `RandomRegionState` and `LocationNoteState`, they record opened doors, revealed secrets, altered tiles, effective random regions, walked and seen cells, acquired maps, and player notes without mutating the installed package.

`RealmzClock` owns the saveable minute count. `ClockRules` interprets elapsed time as Castle gameplay: fatigue, condition decay, spell-point recovery, aging, ration use, and half-day healing. World workflows decide when an action advances time and pass each source-ordered timeclick through those rules.

```text
authored MapTopology       saved RealmzClock
          |                       |
          v                       v
world state overlays       ClockRules
          |                       |
          +-----------+-----------+
                      v
          playthrough world workflows
                      |
                      v
              detached MapView/events
```

Topology work starts in `test_map_topology.gd`. Clock and fatigue rules start in `test_realmz_rules.gd`; public movement and Camp/Rest/Heal journeys live in `test_exploration_session.gd` and `test_scroll_camp_workflow.gd`. Spatial presentation changes additionally use the movement and dungeon-transition performance probes.
