//! Compile as an example in the pinned Providence application-library crate.
//! Its native codec, shop projector, manifest compiler and ZIP writer own output.
use std::{collections::{BTreeMap, BTreeSet}, env, fs, io::{Cursor, Read}};
use providence_core::{
    codecs::decode_shops,
    model::{ProjectSnapshot, StableId},
    rebuilt::{project_rebuilt_v3_shops, recompile_rebuilt_v3_manifest,
        RebuiltV3CompilerIdentity, RebuiltV3FileInput, RebuiltV3Manifest},
};
use providence_rebuilt_package::write_rebuilt_v3_archive;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

const COMPILER: &str = "a779ad4de3d247b045c54e7ef4633a89a7ec9660";

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
    if args.len() != 6 { return Err("Expected: input-plan.json old.realmz2 native-Data-SD application.realmz2 output.realmz2 receipt.json".into()); }
    if std::path::Path::new(&args[4]).exists() || std::path::Path::new(&args[5]).exists() { return Err("output already exists".into()); }
    let plan: Value = serde_json::from_slice(&fs::read(&args[0])?)?;
    let old_bytes = fs::read(&args[1])?;
    let native = fs::read(&args[2])?;
    if plan["oldArchiveSha256"] != hash(&old_bytes) || plan["nativeShopSha256"] != hash(&native) { return Err("source pin mismatch".into()); }
    let mut files = archive(&old_bytes)?;
    let manifest: RebuiltV3Manifest = serde_json::from_slice(&files.remove("manifest.json").ok_or("manifest")?)?;
    if plan["oldPackageHash"] != manifest.package_hash || plan["campaignId"] != manifest.campaign_id.0 { return Err("campaign pin mismatch".into()); }
    let app = archive(&fs::read(&args[3])?)?;
    let app_manifest: Value = serde_json::from_slice(&app["manifest.json"])?;
    if app_manifest["packageHash"] != plan["applicationPackageHash"] { return Err("application pin mismatch".into()); }
    let app_content: Value = serde_json::from_slice(&app["content.json"])?;
    let mut content: Value = serde_json::from_slice(&files["content.json"])?;
    let items: BTreeSet<StableId> = [&content, &app_content].iter().flat_map(|c| c["items"].as_array().unwrap()).map(|i| StableId(i["id"].as_str().unwrap().into())).collect();
    let wanted: BTreeSet<u32> = plan["shopIds"].as_array().ok_or("shop IDs")?.iter().map(|id| id.as_u64().unwrap() as u32).collect();
    let shops = content["shops"].as_array_mut().ok_or("shops")?;
    if shops.iter().any(|s| wanted.contains(&(s["classicId"].as_u64().unwrap() as u32))) { return Err("repair would replace an existing shop".into()); }
    let mut snapshot = ProjectSnapshot::new_authored(StableId("shop-restoration".into()));
    snapshot.shops = decode_shops(&native).records.into_iter().filter(|s| wanted.contains(&s.native_id.0)).collect();
    if snapshot.shops.len() != wanted.len() { return Err("native shop missing".into()); }
    let additions = project_rebuilt_v3_shops(&snapshot, &items)?;
    for shop in &additions { shops.push(serde_json::to_value(shop)?); }
    shops.sort_by_key(|s| s["classicId"].as_u64().unwrap());
    files.insert("content.json".into(), serde_json::to_vec(&content)?);
    let inputs: Vec<_> = files.iter().map(|(path, bytes)| RebuiltV3FileInput { path, bytes }).collect();
    let output_manifest = recompile_rebuilt_v3_manifest(&manifest, &RebuiltV3CompilerIdentity {
        version: env!("CARGO_PKG_VERSION").into(), commit: COMPILER.into(), minimum_engine_version: manifest.engine.minimum_version.clone(),
    }, &inputs)?;
    let output = write_rebuilt_v3_archive(Cursor::new(Vec::new()), &output_manifest, &inputs)?.into_inner();
    archive(&output)?;
    let receipt = json!({"campaignId": manifest.campaign_id, "oldPackageHash": manifest.package_hash,
        "oldArchiveSha256": hash(&old_bytes), "newPackageHash": output_manifest.manifest.package_hash,
        "newContentId": output_manifest.manifest.content_id, "newArchiveSha256": hash(&output), "bytes": output.len(),
        "nativeShopSha256": hash(&native), "shopIds": wanted, "compilerRevision": COMPILER,
        "addedShopsSha256": hash(&serde_json::to_vec(&serde_json::to_value(&additions)?)?)});
    fs::write(&args[4], output)?;
    fs::write(&args[5], serde_json::to_vec_pretty(&receipt)?)?;
    println!("{}", receipt);
    Ok(())
}
