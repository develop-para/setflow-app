"""Record only complete exports and explicitly checked demos in the inventory.

--checked-demos records visual/geometry review, not professional trainer approval.
--install copies checked demo GIFs to local Flutter assets; update the exact ID
registry separately. No network writes, deployment or guessed aliases occur.
"""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from build_preview import build, load_exports

PROJECT = Path(__file__).resolve().parents[2]
VISUALS = PROJECT / "output/exercise_visuals"


def sync(catalog_path: Path, checked_ids: list[str], install: bool = False) -> dict:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    rows = {row["exerciseId"]: row for row in catalog["exercises"]}
    unknown = set(checked_ids) - rows.keys()
    if unknown:
        raise ValueError(f"Unknown checked IDs: {sorted(unknown)}")
    # Share the gallery's export validation without trusting file existence or
    # parsing a generated HTML presentation as production data.
    media_by_id, invalid = load_exports(catalog["exercises"], VISUALS)
    missing = set(checked_ids) - media_by_id.keys()
    if missing:
        raise ValueError(f"Incomplete or unverified media for checked IDs: {sorted(missing)}")
    timestamp = datetime.now(timezone.utc).isoformat()
    for exercise_id, row in rows.items():
        media = media_by_id.get(exercise_id)
        if media is None:
            if row.get("status") == "rendered":
                row["status"] = "queued"
                row["reviewStatus"] = "export_missing_or_changed"
                row["visualAssets"] = {}
            continue
        row["status"] = "rendered"
        row["motionKey"] = exercise_id
        row["visualAssets"] = {
            "gif": media["directory"] + "/exercise.gif",
            "mp4": media["directory"] + "/exercise.mp4",
            "poster": media["directory"] + "/pose-start.png",
            "export": media["directory"] + "/media.json",
        }
        previous_review = row.get("reviewedExportHashes")
        current_hashes = {name: record["sha256"] for name, record in media["files"].items()}
        if exercise_id in checked_ids:
            row["reviewStatus"] = "visual_checked_trainer_pending"
            row["reviewedAt"] = timestamp
            row["reviewedExportHashes"] = current_hashes
        elif previous_review != current_hashes:
            row["reviewStatus"] = "visual_review_pending"
            row.pop("reviewedAt", None)
            row.pop("reviewedExportHashes", None)
        if install and exercise_id in checked_ids:
            target = PROJECT / "assets/exercise_visuals"
            target.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(VISUALS / row["visualAssets"]["gif"], target / (exercise_id + ".gif"))
    counts = catalog["counts"]
    counts["rendered"] = sum(row.get("status") == "rendered" for row in rows.values())
    counts["queued"] = sum(row.get("status") == "queued" for row in rows.values())
    counts["visuallyCheckedDemos"] = sum(row.get("reviewStatus") == "visual_checked_trainer_pending" for row in rows.values())
    counts["approved"] = sum(row.get("status") == "approved" for row in rows.values())
    temporary = catalog_path.with_suffix(".json.writing")
    temporary.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(catalog_path)
    build(catalog_path, VISUALS / "index.html")
    return counts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=VISUALS / "catalog.json")
    parser.add_argument("--checked-demos", nargs="*", default=[])
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    if args.install and not args.checked_demos:
        parser.error("--install requires explicitly checked demo IDs")
    print(json.dumps(sync(args.catalog, args.checked_demos, args.install)))
