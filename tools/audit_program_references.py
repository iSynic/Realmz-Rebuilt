"""Independent conservative Classic call inventory over native action records.

Branch modes follow realmz_orig/newland.c, not the compiler's dependency visitor.
The graph proves possible authored paths; predicates, player choices and map access
are not simulated. Loaded Simple and Complex records travel with each path.
"""
from collections import deque


def classic_range(low, high):
    """Castle randrange narrows width to signed short; QuickDraw excludes -32768."""
    width = ((high - low + 1 + 32768) % 65536) - 32768
    end = low + (width - 1 if width > 0 else width + 1 if width < 0 else 0)
    return range(min(low, end), max(low, end) + 1)


def action_edges(action, context):
    op, operand, e = action["opcode"], action["id"], action["extraCode"]
    edges = []

    def emit(kind, number):
        edges.append((kind, number))

    def branch(mode, number, first=0, inline=False):
        if inline:
            if mode == first:
                emit("xap", number)
            elif mode in (first + 1, first + 2):
                family = "simple" if mode == first + 1 else "complex"
                owner = context[0 if family == "simple" else 1]
                if owner is None and 0 <= number <= 3:
                    emit("retained-" + family + "-result", number)
                else:
                    emit("program" if owner is not None and 0 <= number <= 3 else "unsafe-inline",
                         f"{family}:{owner}:result:{number}")
        elif first <= mode <= first + 2:
            emit(("xap", "simple", "complex")[mode - first], number)

    if op in (4, 5, 39):
        emit({4: "simple", 5: "complex", 39: "xap"}[op], operand)
    if op == 8:
        emit("current-map-record", operand)
    if op == 89:
        emit("monster", operand)
    if op == 54 and e is not None:
        emit("timed", e[0])
    if op == 124 and e is not None:
        emit("monster", e[1])
    # 120/123/125 inspect or alter actors already present; they do not spawn a
    # monster record. Their possible death hooks are covered by actual spawns.
    if e is None:
        return edges
    if op in (2, 48, 56, 107):
        low, high = abs(e[0]), abs(e[1])
        for number in range(low, (high if high >= low and e[1] else low) + 1):
            emit("battle", number)
    if op == 2 and e[4] == 10:
        emit("xap", e[2])
    elif op == 3:
        branch(e[1], e[2], first=1, inline=True)
    elif op == 7:
        emit("xap", e[2])
    elif op in (21, 87):
        branch(e[1], e[3])
        if e[2] == 0:
            branch(e[1], e[4])
    elif op in (64, 81) or op == 31 and (e[2] == 0 or e[0] in (0, 1, 2, 3, 4, 6)):
        emit("xap", e[3])
        emit("xap", e[4])
    elif op in (33, 38, 42, 46) and e[1] in (0, 1, 2):
        branch(e[2], e[3], inline=True)
    elif op in (58, 59) and e[1] == 1:
        branch(e[2], e[3], inline=True)
    elif op == 40:
        branch(e[1], e[2], first=1)
    elif op == 55:
        emit("xap", e[3])
        if e[1] == 1:
            emit("xap", e[4])
    elif op == 56 and e[2] != -1:
        emit("xap", e[2])
    elif op == 67:
        if not (e[1] in (1, 2) and e[3] == -1):
            branch(e[1], e[3])
        branch(e[1], e[4])
    elif op in (72, 75):
        branch(e[3], e[4])
    elif op == 76 and e[3]:
        branch(e[2], e[4], first=1)
    elif op in (77, 78, 86):
        for number in e[3:5]:
            if number:
                branch(e[2], number)
    elif op == 85:
        for number in classic_range(e[1], e[2]):
            branch(e[0], number)
    elif op == 107:
        emit("xap", e[4])
    elif op == 126:
        if e[2] == 2 and e[4] < e[3]:
            emit("unresolved-range", f"{e[3]}..{e[4]}")
        else:
            for number in range(e[3], (e[4] if e[2] == 2 else e[3]) + 1):
                emit("xap", number)
    return edges


def inventory(programs, imported):
    queue, seen, references, roots = deque(), set(), [], []
    reference_keys = set()
    simple = {r["nativeId"]: r for r in imported["simpleEncounters"]}
    complex_rows = {r["nativeId"]: r for r in imported["complexEncounters"]}
    battles = {r["nativeId"]: r for r in imported["battles"]}
    monsters = {}
    for source in imported["monsterSets"]:
        for row in source["monsters"]:
            monsters.setdefault(row["nativeId"], []).append(row)
    timed = {r["nativeId"]: r for r in imported["timedEncounters"]}
    parent = {}

    def link(source, slot, kind, number, context=(None, None, None), root=False):
        if kind == "xap":
            kind, number = "program", f"xap:{number}"
        reference_key = (source, slot, kind, str(number), context)
        if reference_key in reference_keys:
            return
        reference_keys.add(reference_key)
        key = (kind, str(number), context)
        references.append(dict(source=source, slot=slot, targetKind=kind, target=number,
                               simpleContext=context[0], complexContext=context[1], mapContext=context[2]))
        if root:
            roots.append(references[-1])
        if kind in ("retained-simple-result", "retained-complex-result"):
            family = "simple" if kind == "retained-simple-result" else "complex"
            for owner in sorted(simple if family == "simple" else complex_rows):
                retained = (owner, context[1], context[2]) if family == "simple" else (context[0], owner, context[2])
                link(source, slot, family, owner, retained)
                link(source, slot, "program", f"{family}:{owner}:result:{number}", retained)
            return
        if key not in seen:
            seen.add(key)
            parent.setdefault(f"{kind}:{number}", source)
            queue.append((kind, number, context))

    for row in imported["world"]["actionPoints"]:
        door = row["classicDoorId"]
        if door > 0 and door // 10000 == row["levelIndex"] and door % 100 < 90 and door // 100 % 100 < 90:
            file = "Data DD" if row["levelType"] == "land" else "Data DDD"
            key = f"trigger:{file}:{row['levelIndex']}:{row['recordIndex']}"
            link("native-placement", None, "program", key, (None, None, f"{file}:{row['levelIndex']}"), root=True)
    for name, value in imported.get("scenarioApplication", {}).get("hooks", {}).items():
        if value is not None:
            if isinstance(value, str) and value.startswith("extra-action-point:"):
                link("application:" + name, None, "xap", int(value.split(":")[1]), root=True)
            else:
                link("application:" + name, None, "unresolved-hook", str(value), root=True)
    for number, row in timed.items():
        if row["day"] > 0:
            link(f"timed:{number}", None, "xap", row["door"], root=True)
    for world_map in imported["world"]["maps"]:
        for r in (world_map.get("runtime") or {}).get("randomRectangles", []):
            for slot, (target, chance) in enumerate(zip(r["randomDoors"], r["randomDoorPercent"])):
                if chance:
                    link(r["identity"], slot, "xap", target, root=True)
            low, high = r["battleRange"]
            if low:
                for target in classic_range(low, high):
                    link(r["identity"], None, "battle", abs(target), root=True)
    for row in imported["itemRules"] + imported["scenarioItemRules"]:
        item = row["definition"]
        if abs(item["itemType"]) == 23 or item["special"][0] == -23:
            link(row["id"] if "id" in row else item["id"], None, "xap", item["special"][4], root=True)
    native_maps = {r["identity"]: r for r in imported["world"]["maps"]}
    region_ranges, region_writes = {}, {}
    invalid_mutations = []

    def mutate(source, action, context):
        values = action["extraCode"]
        if values is None:
            return
        map_id = f"{'dungeon' if action['rawOpcode'] == -23 else 'land'}:{values[0]}"
        region_id = f"{map_id}:rect:{values[1]}"
        if map_id not in native_maps or not 0 <= values[1] < 20:
            invalid_mutations.append(dict(source=source, slot=action["slot"], rawOpcode=action["rawOpcode"],
                extraCode=values, classification="invalid-authored-reference", mapId=map_id, regionId=region_id))
            return
        rectangles = native_maps[map_id]["runtime"]["randomRectangles"]
        native = next((r["battleRange"] for r in rectangles if r["identity"] == region_id), [0, 0])
        ranges = region_ranges.setdefault(region_id, {tuple(native)})
        writes = region_writes.setdefault(region_id, set())
        writes.add((source, action["slot"], tuple(values), context))
        while True:
            changed = False
            for caller, slot, values, ctx in list(writes):
                for prior in list(ranges):
                    updated = tuple(value if value >= 0 else prior[i] for i, value in enumerate(values[3:5]))
                    if updated not in ranges:
                        ranges.add(updated)
                        changed = True
                    if updated[0]:
                        for target in classic_range(*updated):
                            link(caller, slot, "battle", abs(target))
            if not changed:
                break

    reachable = set()
    while queue:
        kind, number, context = queue.popleft()
        if kind == "program" and number in programs:
            reachable.add(number)
            for a in programs[number]["instructions"]:
                copy_context = context
                if a["opcode"] == 7 and a["extraCode"] is not None:
                    values = a["extraCode"]
                    copy_context = (None, None, None)
                    if values[0] in (-1, -2) and values[1] >= 0:
                        family = "simple" if values[0] == -1 else "complex"
                        copy_context = (values[1], None, None) if family == "simple" else (None, values[1], None)
                        link(number, a["slot"], family, values[1], copy_context)
                        context = (values[1], context[1], context[2]) if family == "simple" else (context[0], values[1], context[2])
                for target_kind, target in action_edges(a, context):
                    link(number, a["slot"], target_kind, target, copy_context if a["opcode"] == 7 else context)
                if a["rawOpcode"] in (23, -23):
                    mutate(number, a, context)
                if a["opcode"] == 54 and a["extraCode"] is not None:
                    row = timed.get(a["extraCode"][0])
                    if row:
                        link(number, a["slot"], "xap", row["door"])
        elif kind == "simple" and number in simple:
            row = simple[number]
            next_context = (number, context[1], context[2])
            if row["choiceResults"][0] == -4:
                link(f"simple:{number}", None, "program", f"simple:{number}:result:3", next_context)
            else:
                for text, result in zip(row["texts"], row["choiceResults"]):
                    if text.strip() and 1 <= result <= 4:
                        link(f"simple:{number}", None, "program", f"simple:{number}:result:{result - 1}", next_context)
        elif kind == "complex" and number in complex_rows:
            row = complex_rows[number]
            results = {row["actionResult"], row["wordResult"]}
            results.update(result for target, result in zip(row["spellIds"], row["spellResults"]) if target)
            results.update(result for target, result in zip(row["itemIds"], row["itemResults"]) if target)
            if row["actionResult"] or row["wordResult"] or any(row["spellIds"]) or any(row["itemIds"]):
                results.add(4)
            if row["thief"]:
                rogue = next((r for r in imported["rogueEncounters"] if r["nativeId"] == row["thiefSuccess"]), None)
                if rogue:
                    results.update(rogue["successCodes"] + rogue["failureCodes"])
            if 4 in results and row["maxTimes"] > 1:
                results.add(3)
            for result in sorted(results):
                if 1 <= result <= 4:
                    link(f"complex:{number}", None, "program", f"complex:{number}:result:{result - 1}", (context[0], number, context[2]))
        elif kind == "battle" and number in battles:
            row = battles[number]
            if row["battleMacro"] < 0:
                link(f"battle:{number}", None, "xap", abs(row["battleMacro"]), context)
            for monster in sorted(set(row["grid"]) - {0}):
                link(f"battle:{number}", None, "monster", abs(monster), context)
        elif kind == "monster" and number in monsters:
            for macro in sorted({r["deathMacro"] for r in monsters[number]} - {0}):
                link(f"monster:{number}", None, "xap", abs(macro), context)
        elif kind == "current-map-record" and 0 <= number < 100:
            # Opcode 8 uses the loaded map's slot even if that slot is not placed.
            # Non-spatial roots conservatively admit every native map context.
            maps = {context[2]} if context[2] is not None else {
                f"{'Data DD' if r['levelType'] == 'land' else 'Data DDD'}:{r['levelIndex']}"
                for r in imported["world"]["actionPoints"]}
            for owner in sorted(maps):
                identity = f"trigger:{owner}:{number}"
                link(f"same-map:{owner}:{number}", None, "program", identity, (context[0], context[1], owner))
    data_references = []
    for program in programs.values():
        for action in program["instructions"]:
            values = action["extraCode"]
            if values is None:
                continue
            op = action["rawOpcode"]
            row = dict(source=program["id"], slot=action["slot"], rawOpcode=op, extraCode=values,
                       sourceStaticallySelected=program["id"] in reachable)
            if op == 7:
                family = {-1: "simple", -2: "complex"}.get(values[0])
                if family:
                    owners = simple if family == "simple" else complex_rows
                    data_references.append(dict(row, relation="installs-encounter-result", ownerKind=family,
                        owner=values[1], result=values[4], available=values[1] in owners and 0 <= values[4] < 4,
                        sourceXap=values[2], sourceAvailable=f"xap:{values[2]}" in programs))
                else:
                    kinds = ["land"] if values[3] == 1 else ["dungeon"] if values[3] == 2 else ["land", "dungeon"]
                    targets = [f"{kind}:{values[0]}" for kind in kinds if f"{kind}:{values[0]}" in native_maps]
                    data_references.append(dict(row, relation="installs-map-action", possibleMaps=targets,
                        record=values[1], available=bool(targets) and 0 <= values[1] < 100,
                        sourceXap=values[2], sourceAvailable=f"xap:{values[2]}" in programs))
            elif op == 54:
                data_references.append(dict(row, relation="reschedules-timed-record", record=values[0],
                    available=values[0] in timed))
            elif op in (23, -23, 92):
                dungeon = values[2] != 0 if op == 92 else op == -23
                target = f"{'dungeon' if dungeon else 'land'}:{values[0]}"
                data_references.append(dict(row, relation="mutates-random-region", mapId=target,
                    region=values[1], available=target in native_maps and 0 <= values[1] < 20))
            elif op == 55 and values[1] == 1:
                data_references.append(dict(row, relation="failure-load-without-execution", target=f"xap:{values[4]}",
                    available=f"xap:{values[4]}" in programs))
    return dict(roots=roots, references=references, reachableProgramIds=sorted(reachable), parent=parent,
                nativeDataReferences=data_references,
                unresolved=[r for r in references if r["targetKind"].startswith(("unsafe", "unresolved")) or
                            r["targetKind"] == "current-map-record" and not 0 <= r["target"] < 100],
                invalidRandomMutations=invalid_mutations,
                dynamicRandomRanges={key: sorted(values) for key, values in region_ranges.items()},
                dynamicContexts=[r for r in references if r["targetKind"].startswith("retained-")],
                missingNativeRecords=[r for r in references if r["targetKind"] in
                    ("program", "simple", "complex", "battle", "monster", "timed") and r["target"] not in
                    {"program": programs, "simple": simple, "complex": complex_rows, "battle": battles, "monster": monsters, "timed": timed}[r["targetKind"]]],
                missingNativePrograms=[r for r in references if r["targetKind"] == "program" and r["target"] not in programs])
