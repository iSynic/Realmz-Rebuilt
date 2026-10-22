//! Apply reviewed additive selections from a pinned native Providence projection.
use std::{collections::BTreeMap, env, fs, io::{Cursor, Read}, path::Path};
use providence_core::rebuilt::{recompile_rebuilt_manifest, RebuiltV3CompilerIdentity,
    RebuiltV3FileInput, RebuiltV3Manifest};
use providence_rebuilt_package::write_rebuilt_v3_archive;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

const COMPILER: &str = "0d2fc1f0bea6c33bd28d58ba715f2eb67920446e";
type Error = Box<dyn std::error::Error>;
fn hash(bytes: &[u8]) -> String { format!("{:x}", Sha256::digest(bytes)) }
fn check(condition: bool, message: &str) -> Result<(), Error> {
    if condition { Ok(()) } else { Err(message.into()) }
}
fn archive(bytes: &[u8]) -> Result<BTreeMap<String, Vec<u8>>, Error> {
    let mut zip = zip::ZipArchive::new(Cursor::new(bytes))?;
    let mut files = BTreeMap::new();
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i)?;
        let mut data = Vec::new();
        entry.read_to_end(&mut data)?;
        check(files.insert(entry.name().to_owned(), data).is_none(), "duplicate ZIP entry")?;
    }
    let manifest: RebuiltV3Manifest = serde_json::from_slice(&files["manifest.json"])?;
    check(files.len() == manifest.files.len() + 1, "archive inventory mismatch")?;
    for (name, record) in manifest.files {
        let data = files.get(&name).ok_or("missing payload")?;
        check(hash(data) == record.sha256 && data.len() as u64 == record.bytes, "payload integrity failure")?;
    }
    Ok(files)
}
fn append(target: &mut Value, rows: &Value, source: &Value) -> Result<(), Error> {
    let target = target.as_array_mut().ok_or("target array")?;
    let source = source.as_array().ok_or("source array")?;
    for row in rows.as_array().ok_or("additions array")? {
        check(source.iter().filter(|r| r["id"] == row["id"]).collect::<Vec<_>>() == vec![row], "addition differs from native projection")?;
        check(!target.iter().any(|r| r["id"] == row["id"]), "addition replaces an existing record")?;
        target.push(row.clone());
    }
    Ok(())
}
fn main() -> Result<(), Error> {
    let args: Vec<_> = env::args().skip(1).collect();
    check(args.len() == 6, "Expected original.realmz2 projection.json recipe.json output.realmz2 receipt.json application.realmz2")?;
    check(!Path::new(&args[3]).exists() && !Path::new(&args[4]).exists(), "output already exists")?;
    let original = fs::read(&args[0])?;
    let projection_bytes = fs::read(&args[1])?;
    let recipe_bytes = fs::read(&args[2])?;
    let projection: Value = serde_json::from_slice(&projection_bytes)?;
    let recipe: Value = serde_json::from_slice(&recipe_bytes)?;
    check(recipe["kind"] == "realmz-rebuilt.program-restoration-input" && recipe["formatVersion"] == 1, "recipe version")?;
    check(recipe["originalArchiveSha256"] == hash(&original) && recipe["projectionSha256"] == hash(&projection_bytes), "input pin differs")?;
    check(recipe["compilerRevision"] == COMPILER && projection["compilerRevision"] == COMPILER, "compiler pin differs")?;
    let application_bytes = fs::read(&args[5])?;
    check(recipe["applicationArchiveSha256"] == hash(&application_bytes), "application archive pin differs")?;
    archive(&application_bytes)?;
    let mut files = archive(&original)?;
    let old_manifest: RebuiltV3Manifest = serde_json::from_slice(&files.remove("manifest.json").ok_or("manifest")?)?;
    check(recipe["campaignId"] == old_manifest.campaign_id.0, "campaign differs")?;
    let mut documents = BTreeMap::<String, Value>::new();
    for name in ["scenario.json", "content.json", "world.json"] {
        let doc: Value = serde_json::from_slice(&files[name])?;
        check(recipe["previousDocuments"][name] == hash(&serde_json::to_vec(&doc)?), "previous document differs")?;
        documents.insert(name.to_owned(), doc);
    }
    for (name, groups) in recipe["additions"].as_object().ok_or("additions")? {
        let doc = documents.get_mut(name).ok_or("unapproved document")?;
        for (field, rows) in groups.as_object().ok_or("addition groups")? {
            let source = match (name.as_str(), field.as_str()) {
                ("scenario.json", "programs") => &projection["runtime"]["scenario"]["programs"],
                ("world.json", "triggers") => &projection["triggers"],
                ("world.json", "timedEncounters") => &projection["runtime"]["timedEncounters"],
                ("content.json", "simpleEncounters" | "complexEncounters" | "thiefEncounters" | "treasures" | "shops" | "battles" | "timedEncounters" | "monsters" | "monsterDescriptions" | "items" | "spells" | "messages") => &projection["content"][field],
                _ => return Err("unapproved additive field".into()),
            };
            append(&mut doc[field], rows, source)?;
        }
    }
    for set in recipe["monsterSetIntroductions"].as_array().ok_or("introduced monster sets")? {
        let source = projection["content"]["monsterSets"].as_array().ok_or("projected sets")?;
        check(source.iter().filter(|row| row["setId"] == set["setId"]).collect::<Vec<_>>() == vec![set], "new monster set differs from native projection")?;
        let target = documents.get_mut("content.json").ok_or("content")?["monsterSets"].as_array_mut().ok_or("sets")?;
        check(!target.iter().any(|row| row["setId"] == set["setId"]), "monster set already exists")?;
        target.push(set.clone());
    }
    for group in recipe["monsterSetAdditions"].as_array().ok_or("monster sets")? {
        let id = &group["setId"];
        let source = projection["content"]["monsterSets"].as_array().ok_or("projected sets")?.iter().find(|s| &s["setId"] == id).ok_or("source set")?;
        let target = documents.get_mut("content.json").ok_or("content")?["monsterSets"].as_array_mut().ok_or("sets")?.iter_mut().find(|s| &s["setId"] == id).ok_or("target set")?;
        append(&mut target["monsters"], &group["monsters"], &source["monsters"])?;
    }
    for change in recipe["cellChanges"].as_array().ok_or("cell changes")? {
        let map = documents.get_mut("world.json").ok_or("world")?["maps"].as_array_mut().ok_or("maps")?.iter_mut().find(|m| m["id"] == change["mapId"]).ok_or("map")?;
        let index = change["index"].as_u64().ok_or("cell index")? as usize;
        check(map["cells"][index][4] == change["before"], "cell refs differ")?;
        let before = change["before"].as_array().ok_or("old refs")?;
        let after = change["after"].as_array().ok_or("new refs")?;
        check(after.len() == before.len() + 1 && before.iter().all(|r| after.contains(r)), "cell change is not additive")?;
        let added = after.iter().find(|r| !before.contains(r)).ok_or("missing added reference")?;
        let trigger = projection["triggers"].as_array().ok_or("native triggers")?.iter().find(|t| &t["id"] == added).ok_or("unknown added trigger")?;
        check(trigger["mapId"] == map["id"] &&
            trigger["coordinate"]["y"].as_u64().ok_or("trigger y")? * map["width"].as_u64().ok_or("map width")? +
            trigger["coordinate"]["x"].as_u64().ok_or("trigger x")? == index as u64, "trigger placement differs from native projection")?;
        map["cells"][index][4] = change["after"].clone();
    }
    for change in recipe["randomRectangleAdditions"].as_array().ok_or("random rectangles")? {
        let source = projection["mapRandomRectangles"].as_array().ok_or("native maps")?.iter().find(|m| m["id"] == change["mapId"]).ok_or("native map")?;
        let row = &change["record"];
        check(source["randomRectangles"].as_array().ok_or("source rectangles")?.iter().filter(|r| r["id"] == row["id"]).collect::<Vec<_>>() == vec![row], "rectangle differs from native projection")?;
        let target = documents.get_mut("world.json").ok_or("world")?["maps"].as_array_mut().ok_or("maps")?.iter_mut().find(|m| m["id"] == change["mapId"]).ok_or("target map")?;
        let rows = target["randomRectangles"].as_array_mut().ok_or("rectangles")?;
        check(!rows.iter().any(|r| r["id"] == row["id"]), "rectangle already present")?;
        rows.push(row.clone());
    }
    for change in recipe["randomRectangleLayouts"].as_array().ok_or("rectangle layouts")? {
        let source = projection["mapRandomRectangles"].as_array().ok_or("native maps")?.iter().find(|m| m["id"] == change["mapId"]).ok_or("native map")?;
        let target = documents.get_mut("world.json").ok_or("world")?["maps"].as_array_mut().ok_or("maps")?.iter_mut().find(|m| m["id"] == change["mapId"]).ok_or("target map")?;
        check(target["randomRectangles"] == change["before"], "rectangle layout precondition differs")?;
        let slot = |row: &Value| -> Result<u32, Error> { Ok(row["id"].as_str().ok_or("rectangle identity")?.rsplit(":rect:").next().ok_or("rectangle slot")?.parse()?) };
        let before = change["before"].as_array().ok_or("old rectangle layout")?;
        let mut native = source["randomRectangles"].as_array().ok_or("native rectangles")?.clone();
        native.sort_by_key(|row| slot(row).unwrap_or(u32::MAX));
        let mut expected = Vec::new();
        for mut row in native {
            let index = slot(&row)?;
            check(index < 20 && !expected.iter().any(|other| slot(other).ok() == Some(index)), "duplicate or out-of-range native rectangle slot")?;
            if let Some(previous) = before.iter().find(|other| slot(other).ok() == Some(index)) {
                row["id"] = previous["id"].clone();
            }
            expected.push(row);
        }
        check(change["after"] == serde_json::to_value(&expected)? && before.iter().all(|row| expected.iter().any(|candidate| candidate["id"] == row["id"])), "rectangle layout differs from native slots or removes an existing identity")?;
        target["randomRectangles"] = serde_json::to_value(expected)?;
    }
    for change in recipe["programReplacements"].as_array().ok_or("replacements")? {
        let source = projection["runtime"]["scenario"]["programs"].as_array().ok_or("programs")?.iter().find(|p| p["id"] == change["after"]["id"]).ok_or("native replacement")?;
        check(source == &change["after"], "replacement differs from native projection")?;
        let target = documents.get_mut("scenario.json").ok_or("scenario")?["programs"].as_array_mut().ok_or("programs")?.iter_mut().find(|p| p["id"] == change["before"]["id"]).ok_or("old program")?;
        check(target == &change["before"] && target["id"] == change["after"]["id"], "replacement precondition differs")?;
        *target = change["after"].clone();
    }
    for change in recipe["textReplacements"].as_array().ok_or("text replacements")? {
        let family = change["family"].as_str().ok_or("text family")?;
        let allowed: &[&str] = match family {
            "items" => &["name", "unidentifiedName", "description"],
            _ => return Err("unapproved text replacement family".into()),
        };
        let before = &change["before"];
        let after = &change["after"];
        check(before["id"] == after["id"], "text replacement changes identity")?;
        let source = projection["content"][family].as_array().ok_or("projected text")?.iter().find(|row| row["id"] == after["id"]).ok_or("native text row")?;
        let mut expected = before.clone();
        for field in allowed { expected[*field] = source[*field].clone(); }
        check(after == &expected, "text replacement differs from native text or changes gameplay")?;
        let target = documents.get_mut("content.json").ok_or("content")?[family].as_array_mut().ok_or("text rows")?.iter_mut().find(|row| row["id"] == before["id"]).ok_or("prior text row")?;
        check(target == before, "text replacement before differs")?;
        *target = after.clone();
    }
    for (name, doc) in &documents { files.insert(name.clone(), serde_json::to_vec(doc)?); }
    let mut asset_index: Value = serde_json::from_slice(&files["assets/index.json"])?;
    check(recipe["previousAssetIndexSha256"] == hash(&serde_json::to_vec(&asset_index)?), "previous asset index differs")?;
    for change in recipe["assetMetadataChanges"].as_array().ok_or("asset metadata changes")? {
        let before = &change["before"];
        let bytes = files.get(before["path"].as_str().ok_or("PNG path")?).ok_or("PNG payload")?;
        check(bytes.len() >= 24 && &bytes[..16] == b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR" && before["sha256"] == hash(bytes), "PNG source differs")?;
        check(before["width"].is_null() && before["height"].is_null(), "metadata correction replaces known dimensions")?;
        let mut expected = before.clone();
        expected["width"] = u32::from_be_bytes(bytes[16..20].try_into()?).into();
        expected["height"] = u32::from_be_bytes(bytes[20..24].try_into()?).into();
        check(change["after"] == expected, "metadata correction differs from PNG dimensions")?;
        let target = asset_index["assets"].as_array_mut().ok_or("asset index")?.iter_mut().find(|row| row["id"] == before["id"]).ok_or("metadata asset")?;
        check(target == before, "metadata correction before differs")?;
        *target = expected;
    }
    check(recipe["assetIndexAdditions"] == projection["sourceAssets"] && recipe["payloadAdditions"] == projection["sourcePayloads"], "source retention differs from native projection")?;
    append(&mut asset_index["assets"], &recipe["assetIndexAdditions"], &projection["sourceAssets"])?;
    files.insert("assets/index.json".into(), serde_json::to_vec(&asset_index)?);
    let payload_root = Path::new(&args[1]).with_extension("sources");
    for record in recipe["payloadAdditions"].as_array().ok_or("source payload inventory")? {
        let path = record["path"].as_str().ok_or("source payload path")?;
        let leaf = path.strip_prefix("assets/media/").ok_or("source payload prefix")?;
        check(!leaf.contains('/') && !leaf.contains('\\'), "source payload leaf is unsafe")?;
        let bytes = fs::read(payload_root.join(leaf))?;
        check(record["sha256"] == hash(&bytes) && record["bytes"] == bytes.len() as u64, "source payload integrity differs")?;
        check(files.insert(path.into(), bytes).is_none(), "source payload replaces an existing archive entry")?;
    }
    let inputs: Vec<_> = files.iter().map(|(path, bytes)| RebuiltV3FileInput { path, bytes }).collect();
    let mut compilation_manifest = old_manifest.clone();
    for capability in recipe["addedCapabilities"].as_array().ok_or("capabilities")? {
        check(capability == "realmz.scenario.deferred-references-v1", "unexpected capability")?;
        if !compilation_manifest.capabilities.iter().any(|c| c == capability.as_str().unwrap()) {
            compilation_manifest.capabilities.push(capability.as_str().unwrap().to_owned());
        }
    }
    let manifest = recompile_rebuilt_manifest(&compilation_manifest, &RebuiltV3CompilerIdentity {
        version: env!("CARGO_PKG_VERSION").into(), commit: COMPILER.into(), minimum_engine_version: old_manifest.engine.minimum_version.clone(),
    }, &inputs)?;
    let output = write_rebuilt_v3_archive(Cursor::new(Vec::new()), &manifest, &inputs)?.into_inner();
    archive(&output)?;
    let receipt = json!({"kind":"realmz-rebuilt.program-restoration", "formatVersion":1,
        "campaignId":old_manifest.campaign_id, "file":Path::new(&args[3]).file_name().ok_or("filename")?.to_str(),
        "previousPackage":{"packageHash":old_manifest.package_hash, "contentId":old_manifest.content_id,
            "archiveSha256":hash(&original), "bytes":original.len(), "compilerRevision":old_manifest.compiler.commit},
        "packageHash":manifest.manifest.package_hash, "contentId":manifest.manifest.content_id,
        "archiveSha256":hash(&output), "bytes":output.len(), "compilerRevision":COMPILER,
        "recipeSha256":hash(&recipe_bytes), "recipe":recipe,
        "outputDocuments":documents.iter().map(|(k,v)| (k.clone(),hash(&serde_json::to_vec(v).unwrap()))).collect::<BTreeMap<_,_>>()});
    fs::write(&args[3], output)?;
    fs::write(&args[4], serde_json::to_vec_pretty(&receipt)?)?;
    println!("{} {}", receipt["campaignId"], receipt["packageHash"]);
    Ok(())
}
