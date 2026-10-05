"""Package the actual review page, its exact media/native files and provenance.

No uploads or approval changes. Open trainer-review.html after extracting ZIP.
The ZIP preserves the page's relative paths and rejects changed/missing files.
"""
import argparse
import json
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from export_media import sha256
from motion_registry import registrations

ROOT = Path(__file__).resolve().parents[2]
VISUALS = ROOT / "output/exercise_visuals"
README = """셋플로우 운동 영상 트레이너 검수 자료

1. ZIP 파일을 먼저 모두 압축 해제하세요.
2. trainer-review.html을 Chrome 또는 Edge에서 여세요.
3. 검수자 이름을 적고 운동을 선택해 시작·중간·정점과 전체 영상을 확인하세요.
4. 승인 또는 수정 요청을 선택하고 검수 JSON 파일을 내려받으세요.
5. 내려받은 JSON 파일을 제작 담당자에게 전달하세요.

검수는 표시된 정확한 운동 ID와 파일 SHA-256에만 적용됩니다.
붉은색은 운동 부위 안내이며 실제로 측정한 근육 활성도가 아닙니다.
모든 시안은 트레이너 승인 대기이며 앱과 서버의 승인 상태는 자동 변경되지 않습니다.
제작 대기 종목에는 영상이 없습니다. 다른 운동의 영상으로 대체하지 않았습니다.
제작 원본 .blend에는 인체와 애니메이션이 포함됩니다. Blender 4.4로 확인할 수 있습니다.
검수 페이지는 인터넷 연결 없이 작동합니다. 공식 설명의 출처 링크는 인터넷이 필요합니다.
bundle-manifest.json은 포함한 파일의 SHA-256과 제작 대기 수를 기록합니다.
source 안의 current-review-evidence.json은 현재 파일에 적용되는 제작 검사 기록입니다.
이전 검사 보고서도 수정 이력으로 포함되며 해당 보고서가 기록한 파일 해시에만 적용됩니다.
"""


def package(page, destination, evidence_paths=()):
    match = re.search(r'<script type="application/json" id="review-data">(.*?)</script>', page.read_text(encoding="utf-8"), re.S)
    if not match:
        raise ValueError("Missing generated trainer review data")
    data = json.loads(match.group(1))
    for key, path in {"catalog": VISUALS / "catalog.json", "specifications": VISUALS / "production/specifications.json",
                      "builder": ROOT / "tool/exercise_visuals/build_trainer_review.py"}.items():
        if data.get("inputSha256", {}).get(key) != sha256(path):
            raise ValueError("Review page inputs changed; rebuild the page first: " + key)
    if data.get("sourceGuideSnapshotCurrent") is not True or data.get("invalidExports"):
        raise ValueError("Review page requires current guide specifications and valid exports")
    files = {"trainer-review.html": page}
    evidence_hash = data.get("inputSha256", {}).get("reviewEvidence")
    if evidence_hash:
        evidence = VISUALS / "production/current-review-evidence.json"
        if not evidence.is_file() or sha256(evidence) != evidence_hash:
            raise ValueError("Review evidence changed; rebuild the page first")
        files[evidence.relative_to(VISUALS).as_posix()] = evidence
    selected = []
    for row in data["exercises"]:
        media = row.get("media")
        if not media:
            continue
        if row.get("trainerApproved") or not media.get("reviewEligible"):
            raise ValueError("Review page requires a valid pending native/media pair: " + row["exerciseId"])
        records = [*media["files"].values(), media["native"], *row["qaFiles"].values()]
        for record in records:
            source = (VISUALS / record["path"]).resolve()
            if not source.is_relative_to(VISUALS.resolve()) or not source.is_file() or sha256(source) != record["sha256"]:
                raise ValueError("Review file missing or changed: " + record["path"])
            files[record["path"]] = source
        review = row.get("independentReview")
        if review:
            report = (ROOT / review["reviewReport"]).resolve()
            if not report.is_relative_to(ROOT.resolve()) or not report.is_file() or sha256(report) != review["reviewReportSha256"]:
                raise ValueError("Independent review report missing or changed: " + review["reviewReport"])
            files["source/" + report.relative_to(ROOT).as_posix()] = report
            # The independent inspector may have pinned additional actual guard
            # files beyond the page's compact QA summaries. Keep those exact
            # revisions too; never substitute a newer similarly named report.
            for record in review["mediaFilesAtReview"].values():
                source = (ROOT / record["path"]).resolve()
                if not source.is_relative_to(VISUALS.resolve()) or not source.is_file() or sha256(source) != record["sha256"]:
                    raise ValueError("Independent review guard file missing or changed: " + record["path"])
                files[source.relative_to(VISUALS).as_posix()] = source
        selected.append(row["exerciseId"])
        state_path = VISUALS / media["directory"] / "production-state.json"
        if state_path.is_file():
            signature = json.loads(state_path.read_text(encoding="utf-8")).get("fingerprint")
            snapshot = VISUALS / "production/source-snapshots" / str(signature) / "source-manifest.json"
            if snapshot.is_file():
                frozen = json.loads(snapshot.read_text(encoding="utf-8"))
                if frozen.get("exerciseId") != row["exerciseId"] or frozen.get("renderSourceFingerprint") != signature:
                    raise ValueError("Authoring snapshot does not match the selected export")
                files[snapshot.relative_to(VISUALS).as_posix()] = snapshot
                for record in frozen["sourceFiles"].values():
                    source = (ROOT / record["snapshotPath"]).resolve()
                    if not source.is_relative_to(VISUALS.resolve()) or not source.is_file() or sha256(source) != record["sha256"]:
                        raise ValueError("Frozen authoring source changed or missing")
                    files[source.relative_to(VISUALS).as_posix()] = source
                for relative, expected in frozen["sharedBodyInputs"].items():
                    source = (ROOT / relative).resolve()
                    if not source.is_relative_to(VISUALS.resolve()) or not source.is_file() or sha256(source) != expected:
                        raise ValueError("Frozen shared body input changed or missing")
                    files[source.relative_to(VISUALS).as_posix()] = source
    if not selected:
        raise ValueError("No completed reviewable videos")
    for path in (VISUALS / "catalog.json", VISUALS / "production/specifications.json",
                 VISUALS / "bodyweight_squat/v5/source-manifest.json", VISUALS / "bodyweight_squat/v5/README.md"):
        files[path.relative_to(VISUALS).as_posix()] = path
    owners = set(registrations().values())
    registered_sources = owners | {name.replace("_motions", "_equipment") for name in owners}
    pipeline_sources = [path for path in sorted((ROOT / "tool/exercise_visuals").glob("*.py"))
                        if not path.stem.endswith(("_motions", "_equipment"))
                        or path.stem in registered_sources]
    for path in [*pipeline_sources,
                 ROOT / "lib/data/exercise_guides.dart", ROOT / "lib/data/exercise_visuals.dart",
                 ROOT / "docs/exercise-guides.md", ROOT / "docs/exercise-visual-production.md"]:
        files["source/" + path.relative_to(ROOT).as_posix()] = path
    for path in evidence_paths:
        path = path.resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError("Review evidence must be an existing workspace file: " + str(path))
        files["source/" + path.relative_to(ROOT).as_posix()] = path
    manifest = {"schemaVersion": 1, "createdAt": datetime.now(timezone.utc).isoformat(),
                "exerciseIds": selected, "counts": data["counts"], "trainerApproved": False,
                "files": {name: {"sha256": sha256(path), "bytes": path.stat().st_size} for name, path in files.items()}}
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".zip.writing")
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.writestr("README.txt", README)
        archive.writestr("bundle-manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        for index, (name, path) in enumerate(files.items(), 1):
            archive.write(path, name)
            if index % 100 == 0:
                print(f"Package files: {index}/{len(files)}", flush=True)
    with zipfile.ZipFile(temporary) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError("ZIP integrity failed: " + bad)
    temporary.replace(destination)
    return {"renderedDemos": len(selected), "trainerApproved": 0,
            "fileCount": len(files) + 2, "bytes": destination.stat().st_size,
            "sha256": sha256(destination), "output": str(destination)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page", type=Path, default=VISUALS / "trainer-review.html")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/exercise_visuals/trainer-review-package.zip")
    parser.add_argument("--evidence", type=Path, nargs="*", default=[],
                        help="Include pinned local QA reports without changing approval state")
    args = parser.parse_args()
    print(json.dumps(package(args.page, args.output, args.evidence), ensure_ascii=False, indent=2))
