"""Integration verifier for the locally built Realmz music importer.

All fixtures and helper output stay under a caller-selected new directory in
the repository's ignored artifacts tree. The supplied ffmpeg is used only to
create additional synthetic sampled-audio containers and inspect Ogg output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys
import time
import wave

from synthetic_modules import fixtures as tracker_fixtures


REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS_ROOT = (REPO_ROOT / "artifacts").resolve()
MAX_HELPER_SECONDS = 120


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_tone(path: Path, seconds: float = 1.0, rate: int = 22050) -> None:
    frames = int(seconds * rate)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        block = bytearray()
        for frame in range(frames):
            sample = int(9000 * math.sin(2 * math.pi * 440 * frame / rate))
            block.extend(struct.pack("<h", sample))
            if len(block) >= 65536:
                output.writeframesraw(block)
                block.clear()
        if block:
            output.writeframesraw(block)


def encode_with_ffmpeg(ffmpeg: Path, source: Path, target: Path, codec: str) -> None:
    args = [str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", str(source), "-map_metadata", "-1"]
    if codec == "mp3":
        args += ["-c:a", "libmp3lame", "-q:a", "4", "-f", "mp3"]
    elif codec == "ogg":
        args += ["-c:a", "libvorbis", "-q:a", "4", "-f", "ogg"]
    elif codec == "flac":
        args += ["-c:a", "flac", "-f", "flac"]
    elif codec == "aiff":
        args += ["-c:a", "pcm_s16be", "-f", "aiff"]
    else:
        raise ValueError(f"Unsupported synthetic encoding request: {codec}")
    args.append(str(target))
    subprocess.run(args, check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def new_run(root: Path, name: str) -> tuple[Path, Path]:
    run_root = root / "runs" / name
    output = run_root / "stage"
    output.mkdir(parents=True)
    result = run_root / "result.json"
    return output, result


def invoke(helper: Path, source: Path, output: Path, result_path: Path, name: str, *, timeout: int = MAX_HELPER_SECONDS) -> tuple[int, dict]:
    args = [
        str(helper), "--input", str(source.resolve()), "--output", str(output.resolve()),
        "--name", name, "--result", str(result_path.resolve()),
    ]
    completed = subprocess.run(args, timeout=timeout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result_path.is_file(), f"helper did not write its result file (exit {completed.returncode})")
    result = json.loads(result_path.read_text(encoding="utf-8"))
    require(result.get("formatVersion") == 1, "helper result formatVersion is not 1")
    require(str(result.get("converter", "")).startswith("realmz-music-1:"), "helper result has no converter identity")
    return completed.returncode, result


def assert_success(result: dict, return_code: int, expected_format: str, expected_duration: float | None = None) -> dict:
    require(return_code == 0, f"helper failed for {expected_format}: exit {return_code}, result={result}")
    require(result.get("ok") is True, f"helper did not report success for {expected_format}: {result}")
    tracks = result.get("tracks")
    require(isinstance(tracks, list) and len(tracks) == 1, f"expected one track for {expected_format}: {result}")
    track = tracks[0]
    require(track.get("format") == expected_format, f"content detection mismatch: expected {expected_format}, got {track}")
    require(track.get("subsong") == 0, f"unexpected subsong identity: {track}")
    require(isinstance(track.get("duration"), (float, int)) and 0 < track["duration"] < 7200, f"invalid finite duration: {track}")
    if expected_duration is not None:
        require(abs(track["duration"] - expected_duration) <= 0.25, f"duration differs from source: {track}")
    converted = expected_format not in ("mp3", "ogg")
    require(track.get("playbackFormat") == ("ogg" if converted else expected_format), f"playback format mismatch: {track}")
    require(track.get("cacheFile") == ("track-0.ogg" if converted else ""), f"cache file mismatch: {track}")
    return track


def assert_ogg_decodes(ffmpeg: Path, path: Path) -> None:
    require(path.is_file() and path.stat().st_size > 0, f"expected generated Ogg file: {path}")
    with path.open("rb") as stream:
        require(stream.read(4) == b"OggS", f"converted cache is not an Ogg container: {path}")
    args = [
        str(ffmpeg), "-hide_banner", "-loglevel", "error", "-nostdin", "-i", str(path),
        "-f", "f32le", "-acodec", "pcm_f32le", "-",
    ]
    decoded = subprocess.run(args, check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(decoded.stdout and len(decoded.stdout) % 4 == 0, f"Ogg cache did not decode to float PCM: {path}")
    peak = max(abs(sample[0]) for sample in struct.iter_unpack("<f", decoded.stdout))
    require(math.isfinite(peak) and peak > 1e-5, f"Ogg cache decoded as silence: {path}")


def write_cancellation_wave(path: Path) -> None:
    # About 46 MiB at the helper's maximum accepted rate; the test terminates
    # as soon as the writer creates its cache file rather than waiting for it.
    block = random.Random(31873).randbytes(1024 * 1024)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(192000)
        for _ in range(46):
            output.writeframesraw(block)


def try_cancellation(helper: Path, root: Path) -> str:
    source = root / "fixtures" / "cancel-me.wav"
    write_cancellation_wave(source)
    before = sha256(source)
    output, result_path = new_run(root, "cancellation")
    args = [
        str(helper), "--input", str(source.resolve()), "--output", str(output.resolve()),
        "--name", "Cancellation probe", "--result", str(result_path.resolve()),
    ]
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 10
    terminated = False
    while time.monotonic() < deadline:
        if process.poll() is not None:
            break
        cache = output / "track-0.ogg"
        if cache.exists():
            process.terminate()
            terminated = True
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            break
        time.sleep(0.005)

    if process.poll() is None:
        process.terminate()
        terminated = True
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    if sha256(source) != before:
        raise AssertionError("cancellation changed its source file")
    if result_path.exists():
        result = json.loads(result_path.read_text(encoding="utf-8"))
        if result.get("ok") is True and not terminated:
            return "SKIP (helper completed before cancellation could be sent)"
        require(result.get("ok") is not True, "cancellation committed a successful result")
        return "PASS (helper recorded failure before termination)"
    if terminated and process.returncode not in (None, 0):
        return "PASS (helper terminated; no result was committed)"
    return "SKIP (helper finished before a cancellation window was observed)"


def run_suite(helper: Path, ffmpeg: Path, root: Path) -> list[str]:
    (root / ".gdignore").write_text("", encoding="utf-8")
    fixtures_dir = root / "fixtures"
    fixtures_dir.mkdir()
    runs_dir = root / "runs"
    runs_dir.mkdir()

    tone = fixtures_dir / "音楽 Δ Synthetic tone.wav"
    write_tone(tone)
    source_hashes = {tone: sha256(tone)}

    sampled: dict[str, Path] = {"wav": tone}
    for codec in ("mp3", "ogg", "flac", "aiff"):
        path = fixtures_dir / f"Synthetic-{codec}-with-misleading-ext.data"
        encode_with_ffmpeg(ffmpeg, tone, path, codec)
        sampled[codec] = path

    tracker_paths: dict[str, Path] = {}
    for kind, contents in tracker_fixtures().items():
        path = fixtures_dir / f"Generated-{kind}-module.not-{kind}"
        path.write_bytes(contents)
        tracker_paths[kind] = path

    all_cases = {**sampled, **tracker_paths}
    for path in all_cases.values():
        source_hashes[path] = sha256(path)

    reports: list[str] = []
    for index, (kind, path) in enumerate(all_cases.items()):
        expected_duration = 1.0 if kind in sampled else None
        output, result_path = new_run(root, f"supported-{index}-{kind}")
        run_name = f"♫ synthetic {kind} Δ"
        return_code, result = invoke(helper, path, output, result_path, run_name)
        track = assert_success(result, return_code, kind, expected_duration)
        require(track.get("title") == run_name, f"Unicode fallback title was not preserved for {kind}: {track}")
        if kind in ("mp3", "ogg"):
            require(not any(output.iterdir()), f"direct-playback {kind} unexpectedly created a cache file")
        else:
            assert_ogg_decodes(ffmpeg, output / "track-0.ogg")
        require(sha256(path) == source_hashes[path], f"helper modified original {kind} input")
        reports.append(f"PASS content detection, finite playback, and cache amplitude: {kind}")

    # Re-import the same bytes with the same visible name. The track record and
    # track metadata should remain stable across staging paths.
    duplicate = fixtures_dir / "duplicate-content.other"
    shutil.copyfile(sampled["wav"], duplicate)
    source_hashes[duplicate] = sha256(duplicate)
    prior_result = root / "runs" / "supported-0-wav" / "result.json"
    same_output, same_result_path = new_run(root, "duplicate-wav")
    name = "♫ synthetic wav Δ"
    duplicate_code, duplicate_result = invoke(helper, duplicate, same_output, same_result_path, name)
    duplicate_track = assert_success(duplicate_result, duplicate_code, "wav", 1.0)
    prior_track = json.loads(prior_result.read_text(encoding="utf-8"))["tracks"][0]
    require(duplicate_track == prior_track, "duplicate bytes with the same name changed stable track identity data")
    assert_ogg_decodes(ffmpeg, same_output / "track-0.ogg")
    require(sha256(duplicate) == source_hashes[duplicate], "duplicate import changed its original")
    reports.append("PASS duplicate-content track metadata")

    invalid: dict[str, bytes] = {
        "truncated-wav": tone.read_bytes()[: tone.stat().st_size // 2],
        "random-bytes": random.Random(881).randbytes(8192),
        "mad": b"MAD\0synthetic unsupported format" + bytes(64),
    }
    for kind, contents in invalid.items():
        path = fixtures_dir / f"{kind}.bin"
        path.write_bytes(contents)
        before = sha256(path)
        output, result_path = new_run(root, f"invalid-{kind}")
        return_code, result = invoke(helper, path, output, result_path, f"synthetic {kind}")
        require(return_code == 1, f"{kind} should fail with a result-bearing import error, got {return_code}: {result}")
        require(result.get("ok") is False and isinstance(result.get("error"), str) and result["error"], f"{kind} failure lacks an error result: {result}")
        require(sha256(path) == before, f"helper modified rejected {kind} input")
        reports.append(f"PASS rejection with structured error: {kind}")

    for path, expected_hash in source_hashes.items():
        require(sha256(path) == expected_hash, f"helper modified source material: {path.name}")
    reports.append("PASS all original source hashes unchanged")
    reports.append("CANCELLATION " + try_cancellation(helper, root))
    return reports


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", required=True, type=Path, help="absolute path to the built native importer")
    parser.add_argument("--ffmpeg", required=True, type=Path, help="absolute path to a development-only ffmpeg executable")
    parser.add_argument("--scratch", required=True, type=Path, help="new scratch directory beneath the repository artifacts directory")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    helper = args.helper.resolve(strict=True)
    ffmpeg = args.ffmpeg.resolve(strict=True)
    scratch = args.scratch.resolve()
    require(helper.is_file(), "--helper must name a file")
    require(ffmpeg.is_file(), "--ffmpeg must name a file")
    require(not scratch.exists(), "--scratch must be a new path; existing data is never reused")
    common_root = os.path.commonpath((str(ARTIFACTS_ROOT), str(scratch)))
    require(os.path.normcase(common_root) == os.path.normcase(str(ARTIFACTS_ROOT)), "--scratch must remain beneath this repository's artifacts directory")
    scratch.mkdir(parents=True, exist_ok=False)
    reports = run_suite(helper, ffmpeg, scratch)
    print("\n".join(reports))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"music importer verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
