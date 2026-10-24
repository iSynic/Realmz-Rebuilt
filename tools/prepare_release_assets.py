"""Package the exact native artifacts from a successful release preparation run."""

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import stat
import subprocess
import tarfile
import zipfile


PLATFORMS = ("Windows x86_64", "Linux x86_64", "macOS universal")
ARTIFACTS = (
    "realmz-rebuilt-windows-x86_64",
    "realmz-rebuilt-linux-x86_64",
    "realmz-rebuilt-macos-universal",
)


def api(repository, endpoint):
    return json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{repository}/{endpoint}"], encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def validate_run(repository, run, commit, workflow_id):
    require(run["head_sha"] == commit and run["workflow_id"] == workflow_id
            and run["event"] == "push" and run["head_branch"].startswith("release/")
            and run["head_repository"]["full_name"].lower() == repository.lower()
            and run["status"] == "completed" and run["conclusion"] == "success",
            "Preparation must be a successful same-repository release branch run at the exact tag commit.")
    jobs = api(repository, f"actions/runs/{run['id']}/jobs?per_page=100")
    expected = {f"{kind} ({platform})" for kind in ("Verify", "Export") for platform in PLATFORMS}
    expected.add("Runtime testing tools")
    require(jobs["total_count"] == len(expected)
            and {job["name"] for job in jobs["jobs"]} == expected
            and all(job["conclusion"] == "success" for job in jobs["jobs"]),
            "Every required preparation job must have passed.")


def checked_members(archive):
    members = archive.infolist()
    names = set()
    for member in members:
        path = pathlib.PurePosixPath(member.filename)
        require(member.filename and not path.is_absolute() and ".." not in path.parts
                and "\\" not in member.filename and ":" not in member.filename
                and member.filename not in names
                and not stat.S_ISLNK(member.external_attr >> 16), "Unsafe artifact member.")
        names.add(member.filename)
    return members


def package_artifact(name, source, output, commit):
    with zipfile.ZipFile(source) as archive:
        members = checked_members(archive)
        require("smoke.log" in archive.namelist(), "Native startup log is missing.")
        smoke = archive.read("smoke.log").decode("utf-8-sig")
        require(not re.search(r"(?m)^(?:ERROR|SCRIPT ERROR):", smoke), "Native startup failed.")
        if name.endswith("macos-universal"):
            # The nested archive retains the native app's Unix permissions and metadata.
            target = output / (name + ".zip")
            with archive.open("Realmz Rebuilt.zip") as src, target.open("xb") as dest:
                shutil.copyfileobj(src, dest)
        else:
            manifest = json.loads(archive.read("release-manifest.json"))
            require(manifest["commit"] == commit and not manifest["localTestBuild"],
                    "Export manifest does not match the tag's clean source.")
            for key in ("artifact", "pck"):
                row = manifest[key]
                data = archive.read(row["file"])
                require(len(data) == row["bytes"] and hashlib.sha256(data).hexdigest() == row["sha256"],
                        "Exported executable or PCK differs from its verified manifest.")
            if name.endswith("windows-x86_64"):
                target = output / (name + ".zip")
                shutil.copyfile(source, target)
            else:
                target = output / (name + ".tar.gz")
                executables = {"Realmz Rebuilt.x86_64", "importer/providence-native-adapter",
                               "music-importer/realmz-music-importer"}
                require(executables <= set(archive.namelist()), "Linux executables are missing.")
                with tarfile.open(target, "x:gz") as tar:
                    for member in members:
                        info = tarfile.TarInfo(member.filename)
                        info.mode = 0o755 if member.is_dir() or member.filename in executables else 0o644
                        if member.is_dir():
                            info.type = tarfile.DIRTYPE
                            tar.addfile(info)
                        else:
                            info.size = member.file_size
                            with archive.open(member) as stream:
                                tar.addfile(info, stream)
    return {"name": target.name, "bytes": target.stat().st_size, "sha256": sha256(target)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--run-id", type=int)
    args = parser.parse_args()
    require(re.fullmatch(r"[0-9a-f]{40}", args.commit), "A full commit SHA is required.")
    require(api(args.repository, f"commits/{args.tag}")["sha"] == args.commit, "Tag identity differs.")
    workflow = api(args.repository, "actions/workflows/ci.yml")
    if args.run_id:
        run = api(args.repository, f"actions/runs/{args.run_id}")
    else:
        runs = api(args.repository, f"actions/workflows/{workflow['id']}/runs?head_sha={args.commit}&event=push&status=success&per_page=100")
        candidates = [r for r in runs["workflow_runs"] if r["head_branch"].startswith("release/")]
        require(candidates, "No successful preparation run exists for this tag; prepare it first.")
        run = candidates[0]
    validate_run(args.repository, run, args.commit, workflow["id"])
    listing = api(args.repository, f"actions/runs/{run['id']}/artifacts?per_page=100")
    artifacts = listing["artifacts"]
    require(listing["total_count"] == 3 and {a["name"] for a in artifacts} == set(ARTIFACTS),
            "Preparation must contain exactly the three native artifacts.")
    require(not args.output.exists(), "Use a new output directory; existing artifacts are never replaced.")
    args.output.mkdir(parents=True)
    downloads = args.output / "preparation"
    downloads.mkdir()
    rows = []
    for artifact in artifacts:
        require(not artifact["expired"] and artifact["workflow_run"]["head_sha"] == args.commit
                and artifact["workflow_run"]["id"] == run["id"]
                and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"] or ""), "Artifact identity or digest is missing.")
        path = downloads / (artifact["name"] + ".zip")
        print(f"Downloading verified {artifact['name']} from run {run['id']}", flush=True)
        with path.open("xb") as stream:
            subprocess.run(["gh", "api", f"repos/{args.repository}/actions/artifacts/{artifact['id']}/zip"],
                           stdout=stream, check=True)
        require("sha256:" + sha256(path) == artifact["digest"], "Downloaded preparation digest differs.")
        row = package_artifact(artifact["name"], path, args.output, args.commit)
        rows.append({**row, "artifactId": artifact["id"], "artifactDigest": artifact["digest"]})
    sums = "".join(f"{r['sha256']}  {r['name']}\n" for r in sorted(rows, key=lambda r: r["name"]))
    (args.output / "SHA256SUMS").write_text(sums, encoding="utf-8", newline="\n")
    receipt = {"commit": args.commit, "tag": args.tag, "runId": run["id"], "runUrl": run["html_url"], "assets": rows}
    (args.output / "promotion.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
