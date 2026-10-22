//! Reproduce Trouble's missing refusal program through the pinned Providence codec/projector.
use std::{collections::BTreeMap, env, fs, io::{Cursor, Read}};
use providence_core::{
    codecs::decode_extra_action_points,
    model::{ProjectSnapshot, StableId},
    rebuilt::{project_rebuilt_v3_trigger_programs, recompile_rebuilt_manifest,
        RebuiltV3CompilerIdentity, RebuiltV3FileInput, RebuiltV3Manifest},
};
use providence_rebuilt_package::write_rebuilt_v3_archive;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

const COMPILER: &str = "542f9a1d250a155ca6ecf52645cca83c808c3dad";
const OLD_ARCHIVE: &str = "c87a004438e05070d297cfa61f245c6eb637d9d4b5093bc8c7ef6b8ada758aaa";
const NATIVE: &str = "9a10703a149d804258fc0950ceb50e036dd2f4aeb7919cfb39b4e5c3ab1ca5e5";

fn hash(bytes: &[u8]) -> String { format!("{:x}", Sha256::digest(bytes)) }

fn archive(bytes: &[u8]) -> Result<BTreeMap<String, Vec<u8>>, Box<dyn std::error::Error>> {
    let mut zip = zip::ZipArchive::new(Cursor::new(bytes))?;
    let mut files = BTreeMap::new();
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i)?;
        let mut data = Vec::new();
        entry.read_to_end(&mut data)?;
        if files.insert(entry.name().to_owned(), data).is_some() { return Err("duplicate ZIP entry".into()); }
    }
    let manifest: RebuiltV3Manifest = serde_json::from_slice(&files["manifest.json"])?;
    if manifest.files.len() + 1 != files.len() { return Err("archive inventory mismatch".into()); }
    for (path, identity) in &manifest.files {
        let data = files.get(path).ok_or("missing manifest entry")?;
        if data.len() as u64 != identity.bytes || hash(data) != identity.sha256 { return Err("archive integrity mismatch".into()); }
    }
    Ok(files)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() != 4 { return Err("Expected: original.realmz2 native-Data-ED3 output.realmz2 receipt.json".into()); }
    if std::path::Path::new(&args[2]).exists() || std::path::Path::new(&args[3]).exists() { return Err("output already exists".into()); }
    let old_bytes = fs::read(&args[0])?;
    let native = fs::read(&args[1])?;
    if hash(&old_bytes) != OLD_ARCHIVE || hash(&native) != NATIVE { return Err("source pin mismatch".into()); }
    let mut files = archive(&old_bytes)?;
    let manifest: RebuiltV3Manifest = serde_json::from_slice(&files.remove("manifest.json").ok_or("manifest")?)?;
    if manifest.campaign_id.0 != "scenario-trouble-in-the-sword-lands" || manifest.compiler.commit != COMPILER { return Err("campaign/compiler pin mismatch".into()); }
    let mut snapshot = ProjectSnapshot::new_authored(StableId("trouble-payment-restoration".into()));
    snapshot.extra_action_points = decode_extra_action_points(&native).records.into_iter().filter(|row| row.native_id.0 == 330).collect();
    if snapshot.extra_action_points.len() != 1 { return Err("native XAP 330 missing".into()); }
    let projected = project_rebuilt_v3_trigger_programs(&snapshot)?;
    let additions = serde_json::to_value(projected.programs)?;
    let mut scenario: Value = serde_json::from_slice(&files["scenario.json"])?;
    let previous_scenario_sha256 = hash(&files["scenario.json"]);
    let programs = scenario["programs"].as_array_mut().ok_or("programs")?;
    if programs.iter().any(|program| program["id"] == "xap:330") { return Err("would replace existing program".into()); }
    programs.extend(additions.as_array().ok_or("additions")?.iter().cloned());
    files.insert("scenario.json".into(), serde_json::to_vec(&scenario)?);
    let inputs: Vec<_> = files.iter().map(|(path, bytes)| RebuiltV3FileInput { path, bytes }).collect();
    let output_manifest = recompile_rebuilt_manifest(&manifest, &RebuiltV3CompilerIdentity {
        version: env!("CARGO_PKG_VERSION").into(), commit: COMPILER.into(), minimum_engine_version: manifest.engine.minimum_version.clone(),
    }, &inputs)?;
    let output = write_rebuilt_v3_archive(Cursor::new(Vec::new()), &output_manifest, &inputs)?.into_inner();
    archive(&output)?;
    let receipt = json!({"kind": "realmz-rebuilt.trouble-payment-restoration", "formatVersion": 1,
        "campaignId": manifest.campaign_id, "file": "scenario-trouble-in-the-sword-lands.realmz2",
        "previousPackage": {"packageHash": manifest.package_hash, "contentId": manifest.content_id,
            "archiveSha256": hash(&old_bytes), "bytes": old_bytes.len(), "compilerRevision": COMPILER},
        "packageHash": output_manifest.manifest.package_hash, "contentId": output_manifest.manifest.content_id,
        "archiveSha256": hash(&output), "bytes": output.len(), "compilerRevision": COMPILER,
        "sourceRevision": "491816ad60037394f92c428e99c004494d3c28b3", "nativeFile": "Data ED3",
        "nativeSha256": hash(&native), "nativeRecordSha256": hash(&native[330*40..331*40]),
        "previousScenarioSha256": previous_scenario_sha256, "addedPrograms": additions});
    fs::write(&args[2], output)?;
    fs::write(&args[3], serde_json::to_vec_pretty(&receipt)?)?;
    println!("{}", receipt);
    Ok(())
}
