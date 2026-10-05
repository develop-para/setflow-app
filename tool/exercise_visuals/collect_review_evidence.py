"""Bind the current exports to actually reviewed, hash-pinned evidence.

Later reports replace earlier findings only for the same exact exercise ID.
This records coding-agent inspection and never grants trainer approval.
"""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from build_preview import load_exports
from export_media import sha256

ROOT = Path(__file__).resolve().parents[2]
VISUALS = ROOT / "output/exercise_visuals"
# These retain medium severity and require the trainer's explicit decision.
# They describe reference/variant scope, not permission to ignore a bad pose.
SOURCE_REVIEW_CODES = frozenset(("reference_variant_scope", "guide_variant_conflict"))


def verified_entry(row, report_path, root=ROOT):
    eid = row["exerciseId"]
    if row.get("trainerApproved") is not False or row.get("humanTrainerApproval") is not False:
        raise ValueError("Inspection evidence must explicitly remain trainer pending: " + eid)
    scope, visual = row.get("reviewScope", {}), row.get("visualReview", {})
    frames = row.get("decodedFrameCount", scope.get("decodedAndVisuallyInspectedMP4Frames", visual.get("framesViewed")))
    if row.get("reviewComplete") is False or ("visuallyInspectedDecodedFrames" in row and
                                             row["visuallyInspectedDecodedFrames"] != list(range(1, 97))):
        raise ValueError("Prepared frames have not all been visually inspected: " + eid)
    poses = row.get("mainPoseImagesActuallyOpened", row.get("mainPoseImagesInspectedInComposite"))
    pose_count = len(poses) if poses is not None else scope.get("mainPoseImagesInspectedInOpenedComposite", visual.get("openedPoses"))
    if frames != 96 or pose_count != 3:
        raise ValueError("Evidence does not establish 96 inspected frames and three poses: " + eid)
    findings = row.get("findings", visual.get("findings", []))
    if any(item.get("severity") in ("high", "major", "critical")
           or (item.get("severity") == "medium" and item.get("code") not in SOURCE_REVIEW_CODES)
           for item in findings):
        raise ValueError("Unresolved geometric finding in current evidence: " + eid)
    records = row.get("mediaFilesAtReview", row.get("mediaFiles", {}))
    required = {"exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png", "pose-peak.png"}
    if not required.issubset(records) or not any(record["path"].endswith(".blend") for record in records.values()):
        raise ValueError("Inspection evidence is missing media, poses or native source: " + eid)
    for name, record in records.items():
        path = (root / record["path"]).resolve()
        if not path.is_relative_to(root.resolve()) or not path.is_file() or sha256(path) != record["sha256"]:
            raise ValueError("Reviewed file changed or missing: " + eid + " / " + name)
    return {"exerciseId": eid, "reviewReport": report_path.relative_to(root).as_posix(),
            "reviewReportSha256": sha256(report_path), "mediaFilesAtReview": records,
            "inspectedMP4Frames": frames, "inspectedMainPoses": pose_count,
            "findings": findings,
            "sourceReviewQuestions": [item for item in findings if item.get("code") in SOURCE_REVIEW_CODES],
            "trainerApproved": False, "humanTrainerApproval": False}


def collect(catalog_path, reports, output, root=ROOT):
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    media, invalid = load_exports(catalog["exercises"], root / "output/exercise_visuals")
    if invalid:
        raise ValueError("Invalid export directories: " + str(invalid))
    latest, superseded = {}, []
    for path in reports:
        path = path.resolve()
        report = json.loads(path.read_text(encoding="utf-8"))
        rows = report.get("exercises", [report] if "exerciseId" in report else [])
        if not rows:
            raise ValueError("No exercise evidence: " + str(path))
        for row in rows:
            eid = row["exerciseId"]
            if eid in latest:
                superseded.append({"exerciseId": eid, "previousReport": latest[eid][1].relative_to(root).as_posix(),
                                   "replacementReport": path.relative_to(root).as_posix()})
            latest[eid] = (row, path)
    missing = set(media) - set(latest)
    if missing:
        raise ValueError("Completed videos without current inspection evidence: " + str(sorted(missing)))
    entries = []
    for eid, export in media.items():
        row, path = latest[eid]
        entry = verified_entry(row, path, root)
        for filename in ("exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png", "pose-peak.png"):
            if entry["mediaFilesAtReview"][filename]["sha256"] != export["files"][filename]["sha256"]:
                raise ValueError("Inspection belongs to another media revision: " + eid)
        entries.append(entry)
    report = {"schemaVersion": 1, "verifiedAt": datetime.now(timezone.utc).isoformat(),
              "scope": "Coding-agent inspection of the listed current files; no expert technique certification",
              "catalogSha256": sha256(catalog_path), "verifiedCount": len(entries),
              "trainerApproved": False, "humanTrainerApproval": False,
              "supersededEvidence": superseded, "exercises": entries}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=VISUALS / "catalog.json")
    parser.add_argument("--reports", type=Path, nargs="+", required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/exercise_visuals/current-review-evidence.json")
    args = parser.parse_args()
    result = collect(args.catalog, args.reports, args.output)
    print(json.dumps({"verifiedCount": result["verifiedCount"], "trainerApproved": 0}))
