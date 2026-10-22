//! Compile a hash-verified imported snapshot with the accepted Providence library.
use std::{collections::BTreeMap, env, fs, path::Path};
use providence_core::{codecs::{decode_simple_encounters, decode_complex_encounters,
    decode_extra_action_points, decode_land_action_points, decode_dungeon_action_points,
    decode_land_random_levels, decode_dungeon_random_levels,
    normalize_certified_battle_rows, normalize_certified_monster_rows},
    model::ProjectSnapshot, rebuilt::{derive_rebuilt_v3_reachability,
    project_rebuilt_v3_runtime, compile_rebuilt_v3_reachable_content,
    compile_rebuilt_v3_reachable_world, project_rebuilt_v3_native_source_assets}};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().skip(1).collect();
    if args.len() != 3 { return Err("Expected: project.providence.json new-output.json pinned-native-input.json".into()); }
    let source = Path::new(&args[0]);
    if Path::new(&args[1]).exists() { return Err("output already exists".into()); }
    let manifest_bytes = fs::read(source)?;
    let manifest: Value = serde_json::from_slice(&manifest_bytes)?;
    let input_bytes = fs::read(&args[2])?;
    let input: Value = serde_json::from_slice(&input_bytes)?;
    if input["kind"] != "realmz-rebuilt.pinned-native-input" || input["formatVersion"] != 1 { return Err("native input version".into()); }
    let native_root = fs::canonicalize(input["sourceDirectory"].as_str().ok_or("native directory")?)?;
    let mut document = serde_json::Map::new();
    for (name, identity) in manifest["segments"].as_object().ok_or("segments")? {
        let hash = identity.as_str().ok_or("blob identity")?.strip_prefix("sha256:").ok_or("blob prefix")?;
        if hash.len() != 64 || !hash.bytes().all(|c| c.is_ascii_hexdigit()) { return Err("invalid blob hash".into()); }
        let bytes = fs::read(source.parent().ok_or("project directory")?.join("blobs/sha256").join(hash))?;
        if format!("{:x}", Sha256::digest(&bytes)) != hash { return Err("blob hash differs".into()); }
        document.insert(name.clone(), serde_json::from_slice(&bytes)?);
    }
    // Re-decode native action records: retained projects may predate signed-byte fixes.
    let sources = document["classicSources"].as_array().ok_or("native sources")?.clone();
    let mut placed = Vec::new();
    let mut random_levels = Vec::new();
    let mut captured = BTreeMap::new();
    for record in sources {
        let identity = record["blob"].as_str().ok_or("native blob")?;
        let bytes = fs::read(source.parent().ok_or("project directory")?.join("blobs/sha256").join(&identity[7..]))?;
        if format!("sha256:{:x}", Sha256::digest(&bytes)) != identity { return Err("native blob hash differs".into()); }
        let native_path = record["nativePath"].as_str().ok_or("native path")?;
        if captured.insert(native_path.to_owned(), bytes.clone()).is_some() { return Err("duplicate native source path".into()); }
        match record["nativePath"].as_str().unwrap_or("") {
            "Data ED" => { document.insert("simpleEncounters".into(), serde_json::to_value(decode_simple_encounters(&bytes).records)?); }
            "Data ED2" => { document.insert("complexEncounters".into(), serde_json::to_value(decode_complex_encounters(&bytes).records)?); }
            "Data ED3" => { document.insert("extraActionPoints".into(), serde_json::to_value(decode_extra_action_points(&bytes).records)?); }
            "Data DD" => placed.extend(decode_land_action_points(&bytes).records),
            "Data DDD" => placed.extend(decode_dungeon_action_points(&bytes).records),
            "Data RD" => random_levels.extend(decode_land_random_levels(&bytes).records),
            "Data RDD" => random_levels.extend(decode_dungeon_random_levels(&bytes).records),
            _ => {}
        }
    }
    for record in input["files"].as_array().ok_or("native file inventory")? {
        let name = record["path"].as_str().ok_or("native relative path")?;
        if name.contains('\\') || name.contains(':') || name.split('/').any(|part| part.is_empty() || part == "." || part == "..") { return Err("unsafe native relative path".into()); }
        let path = fs::canonicalize(native_root.join(name))?;
        if !path.starts_with(&native_root) { return Err("native source escapes its pinned directory".into()); }
        let bytes = fs::read(path)?;
        let digest = format!("{:x}", Sha256::digest(&bytes));
        if record["sha256"] != digest || record["bytes"] != bytes.len() as u64 { return Err("pinned native source drift".into()); }
        if let Some(previous) = captured.get(name) {
            if previous != &bytes { return Err("project/native captured source differs".into()); }
        } else {
            captured.insert(name.to_owned(), bytes);
            document["classicSources"].as_array_mut().ok_or("classic sources")?.push(json!({
                "nativePath":name,"blob":format!("sha256:{digest}"),"byteLength":record["bytes"]}));
        }
    }
    if captured.len() != input["files"].as_array().ok_or("native files")?.len() { return Err("native input inventory differs from captured sources".into()); }
    document.get_mut("world").ok_or("world")?["actionPoints"] = serde_json::to_value(placed)?;
    for map in document["world"]["maps"].as_array_mut().ok_or("maps")? {
        if let Some(native) = random_levels.iter().find(|row|
            serde_json::to_value(row.level_type).ok().as_ref() == Some(&map["levelType"])
                && map["nativeIndex"].as_u64() == Some(u64::from(row.native_index))) {
            // Refresh only the fixed native slots; retain reviewed art and metadata corrections.
            map["runtime"]["randomRectangles"] = serde_json::to_value(&native.runtime.random_rectangles)?;
        }
    }
    let mut snapshot: ProjectSnapshot = serde_json::from_value(Value::Object(document))?;
    let mut record_dispositions = Vec::new();
    if let Some(bytes) = captured.get("Data BD") {
        let normalized = normalize_certified_battle_rows(bytes, snapshot.battles);
        snapshot.battles = normalized.records;
        for row in normalized.dispositions {
            record_dispositions.push(json!({"path":"Data BD", "nativeIndex":row.native_id,
                "offset":row.offset,"bytes":row.byte_length,"sha256":row.sha256,"sourceSha256":row.source_sha256,
                "disposition":row.disposition,"reason":row.reason}));
        }
    }
    for set in &mut snapshot.monster_sets {
        if let Some(bytes) = captured.get(&set.native_path) {
            let normalized = normalize_certified_monster_rows(bytes, &set.native_path,
                set.set_id, std::mem::take(&mut set.monsters));
            set.monsters = normalized.records;
            for row in normalized.dispositions {
                record_dispositions.push(json!({"path":set.native_path,"nativeIndex":row.native_id,
                    "offset":row.offset,"bytes":row.byte_length,"sha256":row.sha256,"sourceSha256":row.source_sha256,
                    "disposition":row.disposition,"reason":row.reason}));
            }
        }
    }
    let reachability = derive_rebuilt_v3_reachability(&snapshot)?;
    let runtime = project_rebuilt_v3_runtime(&snapshot)?;
    let content = compile_rebuilt_v3_reachable_content(&snapshot, &runtime)?;
    let world = compile_rebuilt_v3_reachable_world(&snapshot, &runtime)?;
    let sources = project_rebuilt_v3_native_source_assets(&snapshot.classic_sources, &captured)?;
    let payload_root = Path::new(&args[1]).with_extension("sources");
    fs::create_dir(&payload_root)?;
    let mut source_payloads = Vec::new();
    for (path, bytes) in &sources.payloads {
        let leaf = path.strip_prefix("assets/media/").ok_or("source payload prefix")?;
        if leaf.contains('/') || leaf.contains('\\') { return Err("invalid source payload leaf".into()); }
        fs::write(payload_root.join(leaf), bytes)?;
        source_payloads.push(json!({"path":path,"bytes":bytes.len(),"sha256":format!("{:x}",Sha256::digest(bytes))}));
    }
    let report = json!({"kind": "realmz-rebuilt.program-projection", "formatVersion": 1,
        "compilerRevision": "0d2fc1f0bea6c33bd28d58ba715f2eb67920446e",
        "projectManifestSha256": format!("{:x}", Sha256::digest(&manifest_bytes)),
        "nativeInputSha256":format!("{:x}",Sha256::digest(&input_bytes)),
        "reachability": reachability, "runtime": runtime, "content": content.document,
        "nativeRecordDispositions":record_dispositions,
        "sourceAssets":sources.descriptors,"sourcePayloads":source_payloads,
        "triggers": world.document.triggers,
        "mapRandomRectangles": world.document.maps.iter().map(|map|
            json!({"id":map.id,"randomRectangles":map.random_rectangles})).collect::<Vec<_>>()});
    fs::write(&args[1], serde_json::to_vec(&report)?)?;
    println!("Projected {} programs", report["runtime"]["scenario"]["programs"].as_array().ok_or("programs")?.len());
    Ok(())
}
