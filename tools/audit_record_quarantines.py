"""Account for exact reviewed foreign record ranges without pruning programs."""
import json
from pathlib import Path
from audit_native_programs import sha


def ranges_for(campaign_id):
    path = Path(__file__).with_name("fixtures") / "classic-record-quarantines.json"
    data = path.read_bytes()
    assert sha(data) == "fe61d74f4b783c58b10377138a686ed6d0c90775941f2e63af25497132f47de4", "quarantine evidence drift"
    catalog = json.loads(data)
    assert catalog["formatVersion"] == 1 and len(catalog["campaigns"]) == 13
    return [row for row in catalog["ranges"] if row["campaignId"] == campaign_id]


def account(campaign_id, native_sources, imported, baseline):
    dispositions = []
    for span in ranges_for(campaign_id):
        data = native_sources[span["nativePath"]]
        assert len(data) == span["sourceBytes"] and sha(data) == span["sourceSha256"], "quarantined source drift"
        assert sha(data[span["startOffset"]:span["endOffsetExclusive"]]) == span["retainedRangeSha256"]
        if span["family"] == "battle":
            imported_rows = imported["battles"]
            previous = baseline["content"]["battles"]
        else:
            imported_rows = next(s for s in imported["monsterSets"] if s["setId"] == span["setId"])["monsters"]
            previous = baseline["content"]["monsters"] if span["setId"] == 0 else next(
                (s["monsters"] for s in baseline["content"]["monsterSets"] if s["setId"] == span["setId"]), [])
        for row in span["rows"]:
            index, offset, size = row["record"], row["offset"], row["bytes"]
            assert offset == index * span["recordBytes"] and size == span["recordBytes"]
            assert sha(data[offset:offset + size]) == row["sha256"], "quarantined record drift"
            assert not any(r["classicId"] == index for r in previous), "quarantine would remove a baseline record"
            matches = [r for r in imported_rows if r["nativeId"] == index]
            assert len(matches) == 1, "retained intake quarantine identity differs"
            imported_rows.remove(matches[0])
            dispositions.append(dict(path=span["nativePath"], nativeIndex=index, offset=offset,
                bytes=size, sha256=row["sha256"], sourceSha256=span["sourceSha256"],
                classification="retained-raw-certified-foreign-range-not-runtime-definition",
                nativeFields=row["nativeFields"], sourceReason=span["reason"]))
    return dispositions


def verify_projection(dispositions, projected, candidate):
    key = lambda row: (row["path"], row["nativeIndex"])
    expected = {key(row): row for row in dispositions}
    actual = {key(row): row for row in projected["nativeRecordDispositions"]}
    assert len(actual) == len(projected["nativeRecordDispositions"]) and actual.keys() == expected.keys(), "quarantine accounting differs"
    for identity, row in actual.items():
        assert row["disposition"] == "quarantined-unchanged-certified-tail-row", "modified intake row needs separate review"
        assert all(row[field] == expected[identity][field] for field in ("offset", "bytes", "sha256", "sourceSha256"))
        path, index = identity
        if path == "Data BD":
            records = candidate["content"]["battles"]
        elif path == "Data MD":
            records = candidate["content"]["monsters"]
        else:
            set_id = int(path.removeprefix("Data MD"))
            records = next(s for s in candidate["content"]["monsterSets"] if s["setId"] == set_id)["monsters"]
        assert not any(r["classicId"] == index for r in records), "quarantined row became executable"


def verify_retained(campaign_id, dispositions, archive):
    expected = {}
    for span in ranges_for(campaign_id):
        raw = archive.read("assets/media/" + span["sourceSha256"] + ".bin")
        assert sha(raw) == span["sourceSha256"] and len(raw) == span["sourceBytes"]
        assert sha(raw[span["startOffset"]:span["endOffsetExclusive"]]) == span["retainedRangeSha256"]
        for row in span["rows"]:
            expected[(span["nativePath"], row["record"])] = dict(path=span["nativePath"],
                nativeIndex=row["record"], offset=row["offset"], bytes=row["bytes"], sha256=row["sha256"],
                sourceSha256=span["sourceSha256"], classification="retained-raw-certified-foreign-range-not-runtime-definition",
                nativeFields=row["nativeFields"], sourceReason=span["reason"])
    actual = {(row["path"], row["nativeIndex"]): row for row in dispositions}
    assert actual == expected and len(actual) == len(dispositions), "reviewed quarantine dispositions differ"
    candidate = {"content": json.loads(archive.read("content.json"))}
    projected = {"nativeRecordDispositions": [{**row, "disposition": "quarantined-unchanged-certified-tail-row"}
                                             for row in dispositions]}
    verify_projection(dispositions, projected, candidate)
