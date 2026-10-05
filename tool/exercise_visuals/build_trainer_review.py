"""Build a local exact-file trainer review page; write no approval into the app.

python tool/exercise_visuals/build_trainer_review.py --evidence output/exercise_visuals/production/current-review-evidence.json
python tool/exercise_visuals/build_trainer_review.py --self-test
Rebuild after completed exports change. Browser downloads are standalone JSON
reviews tied to hashes shown in this page, never approval of future revisions.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, urlsplit

from build_preview import load_exports

ROOT = Path(__file__).resolve().parents[2]
VISUALS = ROOT / "output/exercise_visuals"
MEDIA_FILES = ("exercise.mp4", "exercise.gif", "pose-start.png", "pose-middle.png",
               "pose-peak.png", "contact-sheet.png")
QA_SUMMARIES = ("motion-validation.json", "technique-validation.json", "highlight-audit.json",
                "equipment-surface-validation.json")
QA_FILE_LINKS = QA_SUMMARIES + ("skin-floor-audit.json", "bar-surface-audit.json", "motion-audit.json",
                               "equipment-surface-audit.json", "technique-reference.json",
                               "metadata.json", "production-state.json")
# This is an explicit provenance link for the existing squat export pipeline.
# It does not reuse a different exercise's scene or choose anything by name.
LEGACY_NATIVE = {"bodyweight_squat": "bodyweight_squat/v5/squat.blend"}


def sha256(path: Path) -> str:
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(handle.read()).hexdigest()


def file_record(path: Path, visuals: Path) -> dict:
    return {"path": path.relative_to(visuals).as_posix(), "bytes": path.stat().st_size,
            "sha256": sha256(path)}


def read_object(path: Path) -> dict | None:
    if not path.is_file():
        return None
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"readError": "Invalid JSON; no successful QA implied"}
    return result if isinstance(result, dict) else {"readError": "Expected JSON object"}


def native_for(exercise_id: str, directory: Path, visuals: Path) -> tuple[dict | None, str | None, Path]:
    native = directory / "exercise.blend"
    method = "same_export_directory"
    if not native.is_file() and exercise_id in LEGACY_NATIVE:
        native = visuals / LEGACY_NATIVE[exercise_id]
        method = "explicit_existing_squat_pipeline_source"
    if not native.is_file():
        return None, "검수 대상 영상의 제작 원본이 연결되지 않았습니다.", directory
    record = {**file_record(native, visuals), "bindingMethod": method}
    state = read_object(directory / "production-state.json") or {}
    recorded = state.get("files", {})
    expected = recorded.get("exercise.blend") if isinstance(recorded, dict) else None
    if expected and expected != record["sha256"]:
        return record, "영상 내보내기 이후 제작 원본이 바뀌었습니다. 영상을 다시 내보내야 합니다.", native.parent
    record["exportStateNativeHashRecorded"] = bool(expected)
    return record, None, native.parent


def safe_http_url(value: object) -> str | None:
    if not isinstance(value, str) or any(ord(char) < 32 for char in value):
        return None
    try:
        parsed = urlsplit(value)
    except ValueError:
        return None
    return value if parsed.scheme in ("http", "https") and parsed.netloc else None


def reference_records(values: list) -> list[dict]:
    result, seen = [], set()
    for value in values:
        ref = {"url": value} if isinstance(value, str) else dict(value) if isinstance(value, dict) else {}
        url = safe_http_url(ref.get("url"))
        if url and url not in seen:
            result.append(ref)
            seen.add(url)
    return result


def attach_review_evidence(entries: list[dict], evidence: dict, visuals: Path,
                           workspace: Path, input_hashes: dict) -> None:
    """Bind coding-agent notes to the actual revision; never grant approval."""
    if evidence.get("trainerApproved") is not False or evidence.get("humanTrainerApproval") is not False:
        raise ValueError("Independent review evidence must remain trainer pending")
    if input_hashes.get("catalog") and evidence.get("catalogSha256") != input_hashes["catalog"]:
        raise ValueError("Review evidence catalog SHA is stale; collect current evidence again")
    records = evidence.get("exercises")
    if not isinstance(records, list):
        raise ValueError("Review evidence requires exercises[]")
    ids = [record.get("exerciseId") for record in records if isinstance(record, dict)]
    known = {row["exerciseId"] for row in entries}
    if len(ids) != len(records) or any(not isinstance(eid, str) or not eid for eid in ids) or len(set(ids)) != len(ids):
        raise ValueError("Review evidence requires unique exact exercise IDs")
    if set(ids) - known:
        raise ValueError("Review evidence contains an unknown catalog ID")
    rendered = {row["exerciseId"] for row in entries if row["media"]}
    if set(ids) != rendered or evidence.get("verifiedCount") != len(records):
        raise ValueError("Review evidence must cover exactly the current rendered IDs")
    by_id = {record["exerciseId"]: record for record in records}
    workspace = workspace.resolve()

    def checked_file(record: dict) -> Path:
        relative = Path(record.get("path", ""))
        expected = record.get("sha256")
        if relative.is_absolute() or not str(relative) or not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("Review evidence requires relative file paths and SHA-256")
        path = (workspace / relative).resolve()
        if not path.is_relative_to(workspace) or not path.is_file() or sha256(path) != expected:
            raise ValueError("Stale review evidence file missing or changed: " + str(relative))
        return path

    for row in entries:
        if not row["media"]:
            row["independentReview"] = None
            continue
        record = by_id[row["exerciseId"]]
        if record.get("trainerApproved") is not False or record.get("humanTrainerApproval") is not False:
            raise ValueError("Independent review entry must remain trainer pending: " + row["exerciseId"])
        pinned = record.get("mediaFilesAtReview")
        if not isinstance(pinned, dict) or any(not isinstance(value, dict) for value in pinned.values()):
            raise ValueError("Review evidence requires hash-bound media/native records")
        paths = {checked_file(value): value["sha256"] for value in pinned.values()}
        current = [*row["media"]["files"].values(), row["media"]["native"]]
        for current_file in current:
            if current_file is None or paths.get((visuals / current_file["path"]).resolve()) != current_file["sha256"]:
                raise ValueError("Stale review evidence does not bind current media/native: " + row["exerciseId"])
        qa_outside_report = []
        for name, current_file in row["qaFiles"].items():
            path = (visuals / current_file["path"]).resolve()
            if path not in paths:
                # The explicit legacy squat scene has older linked QA files.
                # A current-media inspection must not claim it inspected them.
                qa_outside_report.append(name)
            elif paths[path] != current_file["sha256"]:
                raise ValueError("Stale review evidence QA hash changed: " + row["exerciseId"])
        checked_file({"path": record.get("reviewReport", ""), "sha256": record.get("reviewReportSha256")})
        frames, poses = record.get("inspectedMP4Frames"), record.get("inspectedMainPoses")
        if type(frames) is not int or frames < 1 or poses != 3 or (row["media"].get("frameCount") and frames != row["media"]["frameCount"]):
            raise ValueError("Review evidence requires the full decoded frame count and three poses")
        findings, questions = record.get("findings", []), record.get("sourceReviewQuestions", [])
        if not isinstance(findings, list) or not isinstance(questions, list) or any(not isinstance(item, dict) for item in findings + questions):
            raise ValueError("Independent findings must be structured records")
        # Source-review questions are also findings; retain their original severity.
        merged = list(findings)
        for question in questions:
            if question not in merged:
                merged.append(question)
        row["independentReview"] = {
            "reviewReport": record["reviewReport"], "reviewReportSha256": record["reviewReportSha256"],
            "inspectedMP4Frames": frames, "inspectedMainPoses": poses,
            "findings": merged, "sourceReviewQuestions": questions,
            "qaFilesNotIncludedInIndependentReport": qa_outside_report,
            "mediaFilesAtReview": pinned, "trainerApproved": False, "humanTrainerApproval": False,
            "scope": evidence.get("scope"), "verifiedAt": evidence.get("verifiedAt")}


def build_data(catalog: dict, specifications: dict, visuals: Path, output: Path,
               input_hashes: dict | None = None, evidence: dict | None = None,
               evidence_root: Path = ROOT) -> dict:
    rows = catalog["exercises"]
    ids = [row["exerciseId"] for row in rows]
    if any(not isinstance(eid, str) or not eid for eid in ids) or len(ids) != len(set(ids)):
        raise ValueError("Catalog requires unique nonempty exact exercise IDs")
    specs = specifications["exercises"]
    spec_ids = [row["exerciseId"] for row in specs]
    if len(spec_ids) != len(set(spec_ids)) or set(spec_ids) != set(ids):
        raise ValueError("Specifications must cover exactly the catalog IDs, with no unknown/duplicate IDs")
    spec_by_id = {row["exerciseId"]: row for row in specs}
    media, invalid = load_exports(rows, visuals)
    entries = []
    for original in rows:
        eid = original["exerciseId"]
        production = spec_by_id[eid]
        selected = production.get("specification")
        item = media.get(eid)
        playback = None
        qa = {}
        qa_files = {}
        media_reference = None
        newer_draft = None
        if item:
            parts = Path(item["directory"]).parts
            if len(parts) != 2 or parts[0] != eid or not re.fullmatch(r"v[0-9]+", parts[1]):
                raise ValueError("Media directory does not match its exact exercise ID/version")
            directory = visuals / item["directory"]
            if not directory.resolve().is_relative_to(visuals.resolve()):
                raise ValueError("Media directory leaves the visuals workspace")
            native, native_issue, qa_directory = native_for(eid, directory, visuals)
            prefix = quote(os.path.relpath(directory, output.parent).replace(os.sep, "/"), safe="/.")
            files = {name: file_record(directory / name, visuals) for name in MEDIA_FILES}
            files["media.json"] = file_record(directory / "media.json", visuals)
            media_reference = read_object(directory / "technique-reference.json")
            for filename in QA_FILE_LINKS:
                # Export-directory files bind to the selected media revision.
                # Only the explicit legacy squat native link may supply QA.
                path = directory / filename
                if not path.is_file():
                    path = qa_directory / filename
                if path.is_file():
                    if filename in QA_SUMMARIES:
                        qa[filename] = read_object(path)
                    qa_files[filename] = {**file_record(path, visuals),
                                          "url": quote(os.path.relpath(path, output.parent).replace(os.sep, "/"), safe="/.")}
            for draft in directory.parent.glob("v*/exercise.blend"):
                match = re.fullmatch(r"v([0-9]+)", draft.parent.name)
                if match and int(match[1]) > int(parts[1][1:]):
                    newer_draft = max(newer_draft or 0, int(match[1]))
            playback = {"directory": item["directory"], "version": parts[1],
                        "urlPrefix": prefix, "files": files, "native": native,
                        "nativeIssue": native_issue, "reviewEligible": native is not None and native_issue is None,
                        "fps": item.get("fps"), "frameCount": item.get("frameCount"),
                        "durationSeconds": item.get("durationSeconds"), "newerNativeDraftVersion": newer_draft}
        declared_variant = (media_reference or {}).get("variant")
        variant = declared_variant or (selected or {}).get("variant")
        refs = list((selected or {}).get("references", []))
        refs.extend((production.get("localGuide") or {}).get("references", []))
        if media_reference:
            candidates = [media_reference.get(key) for key in ("url", "reference", "additional_url")]
            listed = media_reference.get("references")
            if isinstance(listed, list):
                candidates.extend(listed)
            for ref in reference_records(candidates):
                refs.append({"publisher": "Current motion reference", "scope": "current_media_variant", **ref})
        if safe_http_url(original.get("sourceUrl")):
            refs.append({"url": original["sourceUrl"], "publisher": original.get("brand") or "Catalog source", "scope": "manufacturer_or_catalog_source"})
        source = production.get("exactSourceText")
        if source and safe_http_url(source.get("provenance", {}).get("datasetUrl")):
            refs.append({"url": source["provenance"]["datasetUrl"], "publisher": "free-exercise-db text; expert unverified", "scope": "exact_source_id_text"})
        refs = reference_records(refs)
        entries.append({
            "exerciseId": eid, "name": original.get("name"), "nameEnglish": original.get("nameEnglish"),
            "muscle": original.get("muscle"), "category": original.get("category"),
            "equipment": original.get("equipmentName") or original.get("equipmentKey"),
            "brand": original.get("brand"), "model": original.get("model"),
            "status": "rendered" if playback else "queued", "reviewStatus": "trainer_pending",
            "trainerApproved": False, "media": playback, "selectedVariant": variant,
            "variantSource": "current_media_declaration" if declared_variant else "production_specification" if variant else "unresolved",
            "specificationStatus": production.get("status", "needs_reference"),
            "specification": selected, "localGuide": production.get("localGuide"),
            "exactSourceText": source, "catalogSource": production.get("catalogSource"),
            "guideReviewFlags": production.get("guideReviewFlags", []),
            "guideCorrections": production.get("guideCorrections", []),
            "referenceReviewNote": production.get("referenceReviewNote"),
            "mediaReference": media_reference, "references": refs, "numericalQA": qa, "qaFiles": qa_files,
            "independentReview": None,
        })
    if evidence is not None:
        attach_review_evidence(entries, evidence, visuals, evidence_root, input_hashes or {})
    rendered = sum(bool(row["media"]) for row in entries)
    recorded_guide_hash = next((value for key, value in specifications.get("inputSha256", {}).items()
                                if key.replace("\\", "/") == "lib/data/exercise_guides.dart"), None)
    guide_path = ROOT / "lib/data/exercise_guides.dart"
    guide_snapshot_current = (sha256(guide_path) == recorded_guide_hash
                              if recorded_guide_hash and guide_path.is_file() else None)
    return {"schemaVersion": 1, "builtAt": datetime.now(timezone.utc).isoformat(),
            "scope": "Local exact-file trainer review; browser downloads only, no app approval mutation",
            "inputSha256": input_hashes or {}, "exercises": entries,
            "counts": {"total": len(entries), "renderedDemos": rendered, "queued": len(entries) - rendered,
                       "reviewEligible": sum(bool(row["media"] and row["media"]["reviewEligible"]) for row in entries),
                       "independentlyReviewedDemos": sum(row["independentReview"] is not None for row in entries),
                       "sourceReviewQuestions": sum(len((row["independentReview"] or {}).get("sourceReviewQuestions", [])) for row in entries),
                       "trainerApproved": 0}, "invalidExports": invalid,
            "sourceGuideSnapshotCurrent": guide_snapshot_current}


def escaped_data(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False).replace("<", "\\u003c").replace("&", "\\u0026").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


def build(catalog_path: Path, specs_path: Path, output: Path, visuals: Path = VISUALS,
          evidence_path: Path | None = None) -> dict:
    if output.resolve() in (catalog_path.resolve(), specs_path.resolve(), evidence_path.resolve() if evidence_path else None):
        raise ValueError("Review output must not overwrite catalog/specifications")
    hashes = {"catalog": sha256(catalog_path), "specifications": sha256(specs_path),
              "builder": sha256(Path(__file__))}
    evidence = None
    if evidence_path:
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
        hashes["reviewEvidence"] = sha256(evidence_path)
    data = build_data(json.loads(catalog_path.read_text(encoding="utf-8")),
                      json.loads(specs_path.read_text(encoding="utf-8")), visuals, output,
                      hashes, evidence)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(TEMPLATE.replace("__REVIEW_DATA__", escaped_data(data)), encoding="utf-8")
    return {**data["counts"], "invalidExports": data["invalidExports"], "output": str(output)}


TEMPLATE = r'''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Setflow 트레이너 검수</title>
<style>
:root{color-scheme:light;--ink:#181818;--muted:#656565;--line:#ddd;--surface:#f5f5f5;--brand:#ccff00}
*{box-sizing:border-box}body{margin:0;color:var(--ink);background:#fff;font:15px/1.6 system-ui,"Malgun Gothic",sans-serif}main{max-width:1400px;margin:auto;padding:24px 18px}h1{font-size:28px;line-height:1.3;margin:8px 0}h2{font-size:22px;margin:0}h3{font-size:17px;margin:20px 0 8px}p{margin:8px 0}.muted{color:var(--muted)}.brand{font-weight:800;font-size:21px;letter-spacing:-1px}.stats{display:flex;flex-wrap:wrap;gap:24px;margin:16px 0}.stats strong{font-size:24px}.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin:16px 0}input,select,textarea,button{font:inherit;color:inherit;border:1px solid var(--line);border-radius:10px;padding:10px;background:#fff;min-height:44px}input[type=search]{flex:1;min-width:200px}input[type=checkbox],input[type=radio]{min-height:0;accent-color:var(--ink)}textarea{width:100%;min-height:100px;resize:vertical}button{cursor:pointer}button:hover{background:var(--surface)}button:disabled{cursor:default;color:var(--muted)}button:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible,a:focus-visible,summary:focus-visible{outline:3px solid var(--ink);outline-offset:3px}.workspace{display:grid;grid-template-columns:310px minmax(0,1fr);gap:24px;align-items:start}.list{border:1px solid var(--line);border-radius:14px;max-height:78vh;overflow:auto}.exercise{display:block;width:100%;text-align:left;border:0;border-radius:0;border-bottom:1px solid var(--line);padding:12px 16px}.exercise[aria-current=true]{background:var(--brand)}.exercise strong{display:block}.exercise small{display:block;font-size:12px}.id{font-family:ui-monospace,monospace;overflow-wrap:anywhere;font-size:12px}.detail{min-width:0;border:1px solid var(--line);border-radius:16px;padding:20px}.badge{display:inline-block;border:1px solid var(--line);background:var(--surface);padding:2px 8px;border-radius:6px;font-size:12px;margin:8px 0}.video-wrap{max-width:640px;margin:auto}video{display:block;width:100%;aspect-ratio:1;background:var(--surface);object-fit:contain}.play-controls{display:flex;gap:10px;margin:10px 0}.poses{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}figure{margin:0}img{display:block;width:100%;background:var(--surface);aspect-ratio:1;object-fit:contain}figcaption{font-size:12px;color:var(--muted)}a{color:var(--ink);overflow-wrap:anywhere}pre{margin:12px 0;padding:12px;background:var(--surface);font:12px/1.6 ui-monospace,monospace;white-space:pre-wrap;overflow-wrap:anywhere}dl{display:grid;grid-template-columns:110px minmax(0,1fr);gap:6px 12px}dt{color:var(--muted)}dd{margin:0;overflow-wrap:anywhere}ol{padding-left:24px}.notice{padding:12px;background:var(--surface);border-left:3px solid var(--line);margin:14px 0}.review-form{margin-top:24px;border-top:1px solid var(--line);padding-top:16px}.choice{display:flex;gap:18px;flex-wrap:wrap;margin:12px 0}.check{display:block;margin:10px 0}.download{background:var(--brand);color:var(--ink);border-color:var(--ink);font-weight:700}.download:hover{background:var(--brand)}label{cursor:pointer}details{margin:14px 0;border-top:1px solid var(--line);padding-top:10px}summary{cursor:pointer;font-weight:600}.result{font-size:13px}.empty{padding:18px}.reviewer{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.reviewer input{min-width:180px}footer{margin-top:24px;color:var(--muted);font-size:12px}@media(max-width:800px){.workspace{grid-template-columns:1fr}.list{max-height:300px}.detail{padding:16px}.poses{gap:6px}h1{font-size:24px}dl{grid-template-columns:90px 1fr}}
.notice{overflow-wrap:anywhere}
</style></head><body><main>
<header><div class="brand">Setflow</div><h1>트레이너 운동 검수</h1><p class="muted">종목별 전체 영상과 자세를 확인하고 검수 파일을 내려받으세요.</p><div class="stats"><span><strong id="total"></strong> 전체 종목</span><span><strong id="rendered"></strong> 영상 시안</span><span><strong id="queued"></strong> 제작 대기</span></div><p class="notice">모든 시안은 트레이너 검수 대기 상태입니다. 이 페이지는 검수 결과를 JSON 파일로 내려받으며 앱이나 서버에 승인 상태를 자동 반영하지 않습니다. 검수는 표시된 SHA-256 파일에만 적용됩니다.</p></header>
<div class="reviewer"><label for="reviewer">검수자 이름 <span aria-hidden="true">*</span></label><input id="reviewer" required autocomplete="name" placeholder="실제 검수자 이름"><span class="muted">승인 또는 수정 요청에 이름이 기록됩니다.</span></div>
<div class="toolbar"><input id="search" type="search" aria-label="운동 검색" placeholder="이름 · 정확한 ID · 기구 · 제조사 검색"><select id="state" aria-label="제작 상태"><option value="">전체 상태</option><option value="rendered">영상 시안</option><option value="queued">제작 대기</option></select><select id="category" aria-label="운동 부위"><option value="">모든 부위</option></select></div>
<p id="result" class="result" role="status" aria-live="polite"></p><div class="workspace"><nav id="list" class="list" aria-label="운동 목록"></nav><section id="detail" class="detail" aria-label="선택한 운동 검수"></section></div>
<footer>외부 업로드 없이 로컬 브라우저에서 사용합니다. 붉은색은 부위 안내이며 측정된 근육 활성도가 아닙니다. 새 영상으로 바뀌면 검수 페이지도 다시 생성해야 합니다. <span id="built"></span></footer>
</main><script type="application/json" id="review-data">__REVIEW_DATA__</script><script>
'use strict';
const data=JSON.parse(document.getElementById('review-data').textContent), rows=data.exercises, $=id=>document.getElementById(id);
let selectedId=(rows.find(row=>row.media)||rows[0]||{}).exerciseId;
const node=(tag,text,cls)=>{const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(cls)el.className=cls;return el};
const link=(text,href)=>{const el=node('a',text);el.href=href;return el};
function details(title,value){const el=node('details');el.append(node('summary',title),node('pre',JSON.stringify(value,null,2)));return el}
function inspectionNotes(row){
 const wrap=node('div'),review=row.independentReview;wrap.append(node('h3','제작 검토 메모'));
 if(!review){wrap.append(node('p','현재 파일에 연결한 독립 제작 검토 기록이 없습니다.','notice'));return wrap}
 wrap.append(node('p','제작자의 시각·파일 검사 기록입니다. 실제 트레이너의 자세 승인과 구분합니다.','muted'),info('검토 범위',{'보고서':review.reviewReport,'보고서 SHA-256':review.reviewReportSha256,'전체 영상 확인':review.inspectedMP4Frames+'개 디코딩 프레임','주요 자세 확인':review.inspectedMainPoses+'개','파일 확인 시각':review.verifiedAt}));
 if(review.sourceReviewQuestions.length)wrap.append(node('p','출처와 선택 변형 사이에 확인할 사항이 남아 있습니다. 아래 메모의 심각도를 유지했으며 트레이너가 해당 변형을 판단해야 합니다.','notice'));
 if(review.qaFilesNotIncludedInIndependentReport.length)wrap.append(node('p','별도로 연결된 이전 원본 QA 파일은 이번 독립 검토의 검사 범위에 포함되지 않았습니다: '+review.qaFilesNotIncludedInIndependentReport.join(', '),'muted'));
 const labels={high:'높음',medium:'중간',low:'낮음',info:'참고'},fields={text:'검토 내용',observation:'관찰',detail:'상세',requiredAction:'트레이너 확인',referenceScope:'출처 범위'};
 if(!review.findings.length)wrap.append(node('p','이 제작 검토 기록에 추가 지적 사항이 없습니다. 트레이너 검수는 대기 중입니다.','muted'));
 for(const finding of review.findings){const item=node('div',undefined,'notice');item.append(node('strong',(labels[finding.severity]||finding.severity||'참고')+' · '+(finding.code||'제작 검토')));for(const [key,value] of Object.entries(finding)){if(['severity','code'].includes(key)||value===null||value===undefined)continue;item.append(node('p',(fields[key]||key)+': '+(typeof value==='string'?value:JSON.stringify(value,null,2))))}wrap.append(item)}return wrap;
}
function steps(title,items){const wrap=node('div');wrap.append(node('h3',title));const list=node('ol');for(const text of items)list.append(node('li',text));wrap.append(list);return wrap}
function info(title,values){const wrap=node('div'),dl=node('dl');wrap.append(node('h3',title));for(const [label,value] of Object.entries(values)){dl.append(node('dt',label),node('dd',Array.isArray(value)?value.join(' / '):value||'미확정'))}wrap.append(dl);return wrap}
for(const key of ['total','queued'])$(key).textContent=data.counts[key].toLocaleString('ko-KR');$('rendered').textContent=data.counts.renderedDemos;$('built').textContent='생성: '+new Date(data.builtAt).toLocaleString('ko-KR');
if(data.sourceGuideSnapshotCurrent===false){const notice=node('p','한국어 설명은 저장된 사양 시점의 문장입니다. 현재 앱 설명이 이후 수정되어, 검수할 때 영상의 선택 변형과 원본 출처를 함께 확인해야 합니다.','notice');document.querySelector('header').append(notice)}
for(const value of [...new Set(rows.map(row=>row.muscle||row.category).filter(Boolean))].sort()){const option=node('option',value);option.value=value;$('category').append(option)}
function showList(){
 const term=$('search').value.trim().toLocaleLowerCase(),state=$('state').value,category=$('category').value;
 const matching=rows.filter(row=>(!state||row.status===state)&&(!category||(row.muscle||row.category)===category)&&(!term||[row.exerciseId,row.name,row.nameEnglish,row.equipment,row.brand,row.model,(row.catalogSource||{}).sourceId].join(' ').toLocaleLowerCase().includes(term)));
 $('list').replaceChildren();$('result').textContent=matching.length.toLocaleString('ko-KR')+'개 종목 · 전체 목록은 정확한 운동 ID로 구분합니다.';
 for(const row of matching){const button=node('button');button.type='button';button.className='exercise';button.setAttribute('aria-current',String(row.exerciseId===selectedId));button.append(node('strong',row.name||row.exerciseId),node('small',row.media?'영상 '+row.media.version+' · 검수 대기':'제작 대기'),node('small',row.exerciseId,'id'));button.addEventListener('click',()=>{selectedId=row.exerciseId;showList();showDetail()});$('list').append(button)}
 if(!matching.length)$('list').append(node('p','검색 결과가 없습니다.','empty'));
}
function reviewForm(row){
 const form=node('form',undefined,'review-form');form.append(node('h3','이 파일 검수 결과'),node('p','승인은 이 영상과 제작 원본의 SHA에만 연결됩니다. 다운로드한 JSON을 제작 담당자에게 전달해주세요.','muted'));
 const choices=node('div',undefined,'choice');
 for(const [value,label] of [['approved','승인'],['changes_requested','수정 요청']]){const wrap=node('label'),radio=node('input');radio.type='radio';radio.name='disposition';radio.value=value;radio.required=true;wrap.append(radio,document.createTextNode(' '+label));choices.append(wrap)}form.append(choices);
 const commentLabel=node('label','검수 코멘트'),comment=node('textarea');comment.id='review-comment';comment.name='comment';comment.placeholder='수정이 필요한 관절 · 기구 접촉 · 동작 구간을 적어주세요.';commentLabel.htmlFor=comment.id;form.append(commentLabel,comment);
 const poseLabel=node('label',undefined,'check'),poseCheck=node('input');poseCheck.type='checkbox';poseLabel.append(poseCheck,document.createTextNode(' 세 자세를 확인했습니다.'));
 const videoLabel=node('label',undefined,'check'),videoCheck=node('input');videoCheck.type='checkbox';videoLabel.append(videoCheck,document.createTextNode(' 전체 영상을 확인했습니다.'));form.append(poseLabel,videoLabel);
 const download=node('button','검수 JSON 다운로드','download');download.type='submit';const message=node('p','', 'result');message.setAttribute('role','status');message.setAttribute('aria-live','polite');form.append(download,message);
 form.addEventListener('change',()=>{comment.required=Boolean(form.querySelector('input[name=disposition]:checked')?.value==='changes_requested');comment.setCustomValidity('')});
 form.addEventListener('submit',event=>{
  event.preventDefault();message.textContent='';const reviewer=$('reviewer').value.trim(),status=form.querySelector('input[name=disposition]:checked')?.value;
  if(!reviewer){$('reviewer').setCustomValidity('실제 검수자 이름을 입력해주세요.');$('reviewer').reportValidity();$('reviewer').focus();return}$('reviewer').setCustomValidity('');
  if(!form.reportValidity())return;if(!status)return;
  if(status==='changes_requested'&&!comment.value.trim()){comment.setCustomValidity('수정 요청에는 코멘트를 입력해주세요.');comment.reportValidity();return}comment.setCustomValidity('');
  if(status==='approved'&&(!poseCheck.checked||!videoCheck.checked)){message.textContent='승인하려면 세 자세와 전체 영상 확인을 표시해주세요.';return}
  const result={schemaVersion:1,exerciseId:row.exerciseId,name:row.name,selectedVariant:row.selectedVariant,mediaVersion:row.media.version,mediaDirectory:row.media.directory,mediaFiles:row.media.files,nativeFile:row.media.native,qaFiles:row.qaFiles,independentReview:row.independentReview,inputSha256:data.inputSha256,reviewer:{name:reviewer},status,comment:comment.value.trim(),reviewedAt:new Date().toISOString(),reviewScope:{threePoses:poseCheck.checked,fullVideo:videoCheck.checked},approvalAppliesOnlyToListedHashes:true,automaticExpertApproval:false,transmission:'Local browser JSON download; no upload or application state mutation'};
  const blob=new Blob([JSON.stringify(result,null,2)+'\n'],{type:'application/json;charset=utf-8'}),href=URL.createObjectURL(blob),anchor=node('a');anchor.href=href;anchor.download='setflow-review-'+row.exerciseId+'-'+row.media.version+'-'+new Date().toISOString().replaceAll(':','-')+'.json';document.body.append(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(href),1000);message.textContent='검수 JSON 다운로드를 요청했습니다. 내려받은 파일을 제작 담당자에게 전달해주세요.';
 });comment.addEventListener('input',()=>comment.setCustomValidity(''));return form;
}
$('reviewer').addEventListener('input',()=>$('reviewer').setCustomValidity(''));
function showDetail(){
 document.querySelectorAll('video').forEach(video=>video.pause());const row=rows.find(item=>item.exerciseId===selectedId),pane=$('detail');pane.replaceChildren();if(!row){pane.append(node('p','운동을 선택해주세요.'));return}
 pane.append(node('h2',row.name||row.exerciseId),node('div',row.exerciseId,'id'),node('span',row.media?'영상 '+row.media.version+' · 트레이너 검수 대기':'제작 대기 · 검수할 영상 없음','badge'));
 pane.append(info('선택 종목',{'변형':row.selectedVariant,'기구':row.equipment,'제조사 / 모델':[row.brand,row.model].filter(Boolean),'원본 ID':(row.catalogSource||{}).sourceId,'사양 상태':row.specificationStatus==='specification_ready'?'제작 사양 있음 · 검수 대기':'추가 동작 근거 필요'}));
 if(row.media){
  const prefix=row.media.urlPrefix,wrap=node('div',undefined,'video-wrap'),video=node('video');video.controls=true;video.loop=true;video.muted=true;video.playsInline=true;video.preload='metadata';video.poster=prefix+'/pose-start.png';video.src=prefix+'/exercise.mp4';video.setAttribute('aria-label',(row.name||row.exerciseId)+' 전체 동작 영상');wrap.append(video);
  const controls=node('div',undefined,'play-controls'),slow=node('button','0.5배속'),normal=node('button','1배속');slow.type=normal.type='button';slow.setAttribute('aria-pressed','false');normal.setAttribute('aria-pressed','true');for(const [button,rate] of [[slow,.5],[normal,1]])button.addEventListener('click',()=>{video.playbackRate=rate;slow.setAttribute('aria-pressed',String(rate===.5));normal.setAttribute('aria-pressed',String(rate===1))});controls.append(slow,normal,link('전체 영상 파일',prefix+'/exercise.mp4'));wrap.append(controls);pane.append(wrap);
  const poses=node('div',undefined,'poses');for(const [phase,label] of [['start','시작'],['middle','중간'],['peak','주요 자세']]){const figure=node('figure'),image=node('img');image.src=prefix+'/pose-'+phase+'.png';image.alt=(row.name||row.exerciseId)+' '+label;image.loading='lazy';const anchor=link('',image.src);anchor.append(image);figure.append(anchor,node('figcaption',label));poses.append(figure)}pane.append(poses);
  if(row.media.newerNativeDraftVersion)pane.append(node('p','최신 v'+row.media.newerNativeDraftVersion+' 제작 원본은 영상 내보내기 대기입니다. 현재 검수 파일은 '+row.media.version+'입니다.','notice'));
  if(row.media.nativeIssue)pane.append(node('p',row.media.nativeIssue,'notice'));
  pane.append(details('검수할 파일 SHA-256',{media:row.media.files,native:row.media.native,qa:row.qaFiles}));
  pane.append(inspectionNotes(row));
 }else pane.append(node('p','이 종목의 완성 영상이 아직 없습니다. 다른 동작으로 대신 표시하지 않습니다.','notice'));
 if(row.guideReviewFlags.length)pane.append(steps('가이드에서 확인할 사항',row.guideReviewFlags));if(row.referenceReviewNote)pane.append(node('p',row.referenceReviewNote,'notice'));
 if(row.specification){const s=row.specification;pane.append(info('제작 사양',{'그립':s.requiredGrip,'몸통 / 지지':s.requiredBodyPosition,'기구':s.requiredEquipment}));const motion=s.rangeOfMotion||{};pane.append(info('동작 구간',{'시작':motion.start,'동작':motion.movement,'끝':motion.end,'복귀':motion.return}));}
 if(row.localGuide?.steps?.length)pane.append(steps('한국어 수행 설명 · 근거 재확인 필요',row.localGuide.steps));if(row.exactSourceText?.instructions?.length)pane.append(steps('정확한 원본 ID 지침 · 전문가 검증 전',row.exactSourceText.instructions));
 if(row.references.length){const refs=node('div');refs.append(node('h3','출처'));const list=node('ul');for(const ref of row.references){const item=node('li');item.append(link((ref.publisher||'출처')+' · '+ref.url,ref.url));list.append(item)}refs.append(list);pane.append(refs)}
 pane.append(details('원본과 선택 변형 근거',{catalogSource:row.catalogSource,variantSource:row.variantSource,mediaReference:row.mediaReference,specificationReferences:row.specification?.references||[],sourceProvenance:row.exactSourceText?.provenance||null,localGuideSource:row.localGuide?.source||null,guideCorrections:row.guideCorrections}));
 if(row.media){pane.append(node('p','숫자 QA는 관절·루프·기구의 제작 검사입니다. 수치 통과가 트레이너의 자세 승인을 뜻하지 않습니다.','notice'),details('숫자 QA',Object.keys(row.numericalQA).length?row.numericalQA:{status:'이 파일 버전의 별도 숫자 QA가 연결되지 않았습니다.'}));
  if(Object.keys(row.qaFiles).length){const audits=node('div'),list=node('ul');audits.append(node('h3','검사 원본 파일'),node('p','큰 프레임별 기록은 파일로 확인할 수 있습니다. 각 파일의 SHA는 검수 JSON에도 포함됩니다.','muted'));for(const [name,file] of Object.entries(row.qaFiles)){const item=node('li'),anchor=link(name,file.url);item.append(anchor,node('div','SHA-256 '+file.sha256,'id'));list.append(item)}audits.append(list);pane.append(audits)}
  if(row.media.reviewEligible)pane.append(reviewForm(row));}
}
for(const id of ['search','state','category'])$(id).addEventListener(id==='search'?'input':'change',showList);document.addEventListener('visibilitychange',()=>{if(document.hidden)document.querySelectorAll('video').forEach(video=>video.pause())});showList();showDetail();
</script></body></html>'''


class TrainerReviewTests(unittest.TestCase):
    def fixture(self, root: Path, exercise_id="curl") -> tuple[dict, dict]:
        directory = root / exercise_id / "v1"
        directory.mkdir(parents=True)
        files = {}
        for name in MEDIA_FILES:
            path = directory / name
            path.write_bytes((exercise_id + name).encode())
            files[name] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
        (directory / "exercise.blend").write_bytes(b"exact native scene")
        (directory / "media.json").write_text(json.dumps({"status": "rendered", "exerciseId": exercise_id, "files": files}))
        catalog = {"exercises": [{"exerciseId": exercise_id, "name": "same name", "status": "approved"}, {"exerciseId": "unmade", "name": "same name"}]}
        specs = {"exercises": [{"exerciseId": eid, "status": "needs_reference"} for eid in (exercise_id, "unmade")]}
        return catalog, specs

    def test_actual_hashes_are_pinned_and_similar_unmade_stays_queued(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            data = build_data(catalog, specs, root, root / "trainer-review.html")
            row, unmade = data["exercises"]
            self.assertEqual(row["media"]["files"]["exercise.mp4"]["sha256"], sha256(root / "curl/v1/exercise.mp4"))
            self.assertEqual(row["media"]["native"]["sha256"], sha256(root / "curl/v1/exercise.blend"))
            self.assertTrue(row["media"]["reviewEligible"])
            self.assertEqual(unmade["status"], "queued")
            self.assertIsNone(unmade["media"])
            self.assertFalse(row["trainerApproved"])

    def test_modified_or_incomplete_export_is_not_playable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            (root / "curl/v1/exercise.mp4").write_bytes(b"changed after export")
            self.assertIsNone(build_data(catalog, specs, root, root / "review.html")["exercises"][0]["media"])
            (root / "curl/v1/pose-peak.png").unlink()
            self.assertEqual(build_data(catalog, specs, root, root / "review.html")["counts"]["renderedDemos"], 0)

    def test_unknown_media_or_spec_ids_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            specs["exercises"].append({"exerciseId": "unknown"})
            with self.assertRaisesRegex(ValueError, "exactly the catalog"):
                build_data(catalog, specs, root, root / "review.html")
            specs["exercises"].pop()
            catalog["exercises"][0]["exerciseId"] = specs["exercises"][0]["exerciseId"] = "elsewhere"
            with self.assertRaisesRegex(ValueError, "absent from catalog"):
                build_data(catalog, specs, root, root / "review.html")

    def test_wrong_folder_identity_is_not_an_alias(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            (root / "curl").rename(root / "different")
            data = build_data(catalog, specs, root, root / "review.html")
            self.assertEqual(data["counts"]["renderedDemos"], 0)
            self.assertEqual(data["exercises"][0]["status"], "queued")
            self.assertIsNone(data["exercises"][0]["media"])
            self.assertEqual(data["invalidExports"], ["different/v1/media.json"])

    def test_duplicate_ids_and_unsafe_source_urls_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            catalog["exercises"].append(catalog["exercises"][0])
            with self.assertRaisesRegex(ValueError, "unique"):
                build_data(catalog, specs, root, root / "review.html")
        self.assertIsNone(safe_http_url("javascript:alert(1)"))
        self.assertIsNone(safe_http_url("https://example.com/\nunsafe"))

    def test_html_data_cannot_close_script_and_roundtrips_text(self):
        payload = {"name": "</script><img src=x onerror=alert(1)>& 한글\u2028"}
        safe = escaped_data(payload)
        self.assertNotIn("</script", safe)
        self.assertNotIn("<img", safe)
        self.assertEqual(json.loads(safe), payload)

    def test_native_change_after_export_blocks_review_not_video(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            (root / "curl/v1/production-state.json").write_text(json.dumps({"files": {"exercise.blend": "old-source-hash"}}))
            row = build_data(catalog, specs, root, root / "review.html")["exercises"][0]
            self.assertEqual(row["status"], "rendered")
            self.assertFalse(row["media"]["reviewEligible"])
            self.assertTrue(row["media"]["nativeIssue"])

    def test_current_reference_lists_are_safe_and_deduplicated(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            first, second, third = "https://example.com/first", "https://example.com/second", "https://example.com/third"
            (root / "curl/v1/technique-reference.json").write_text(json.dumps({
                "variant": "Current exact variant", "url": first, "reference": {"url": second},
                "additional_url": third, "references": [first, {"url": second, "title": "Duplicate"},
                                                        "javascript:alert(1)", {"url": "https://[invalid"}, 7]}))
            specs["exercises"][0]["specification"] = {"references": [{"url": first, "publisher": "Official source"}]}
            specs["exercises"][0]["localGuide"] = {"references": [{"url": third, "publisher": "Setflow authored guide reference"}]}
            row = build_data(catalog, specs, root, root / "review.html")["exercises"][0]
            self.assertEqual([ref["url"] for ref in row["references"]], [first, third, second])
            self.assertEqual(row["references"][0]["publisher"], "Official source")
            self.assertEqual(row["selectedVariant"], "Current exact variant")

    def test_frame_audits_are_hash_links_not_inline_arrays(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            for filename in QA_FILE_LINKS:
                value = [{"frame": index, "large_frame_value": "x" * 1000} for index in range(96)] if filename.endswith("-audit.json") else {"passed": True}
                (root / "curl/v1" / filename).write_text(json.dumps(value))
            row = build_data(catalog, specs, root, root / "pages/review.html")["exercises"][0]
            self.assertEqual(set(row["qaFiles"]), set(QA_FILE_LINKS))
            for filename, record in row["qaFiles"].items():
                self.assertEqual(record["sha256"], sha256(root / "curl/v1" / filename))
                self.assertEqual(record["url"], "../curl/v1/" + filename)
            self.assertNotIn("large_frame_value", escaped_data(row))
            self.assertEqual(set(row["numericalQA"]), set(QA_SUMMARIES))


    def test_actual_machine_surface_proof_and_export_metadata_are_linked(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            required = ("equipment-surface-audit.json", "equipment-surface-validation.json", "metadata.json")
            for filename in required:
                (root / "curl/v1" / filename).write_text('{"passed":true}')
            row = build_data(catalog, specs, root, root / "review.html")["exercises"][0]
            for filename in required:
                self.assertIn(filename, row["qaFiles"])
                self.assertEqual(row["qaFiles"][filename]["sha256"], sha256(root / "curl/v1" / filename))
            self.assertTrue(row["numericalQA"]["equipment-surface-validation.json"]["passed"])

    def evidence_fixture(self, root: Path, catalog: dict, specs: dict) -> dict:
        row = build_data(catalog, specs, root, root / "review.html")["exercises"][0]
        media = row["media"]
        report = root / "independent-review.json"
        report.write_text('{"trainerApproved":false}', encoding="utf-8")
        files = {name: {"path": record["path"], "sha256": record["sha256"]}
                 for name, record in media["files"].items()}
        files["exercise.blend"] = {"path": media["native"]["path"], "sha256": media["native"]["sha256"]}
        question = {"severity": "medium", "code": "reference_variant_scope", "detail": "Source variant differs; trainer must assess selected variant."}
        return {"catalogSha256": "catalog-sha", "verifiedCount": 1,
                "trainerApproved": False, "humanTrainerApproval": False,
                "exercises": [{"exerciseId": row["exerciseId"], "reviewReport": report.name,
                               "reviewReportSha256": sha256(report), "mediaFilesAtReview": files,
                               "inspectedMP4Frames": 96, "inspectedMainPoses": 3,
                               "findings": [question, {"severity": "low", "code": "model_scope", "text": "Support force unmeasured."}],
                               "sourceReviewQuestions": [question], "trainerApproved": False, "humanTrainerApproval": False}]}

    def test_current_evidence_keeps_all_findings_and_stale_files_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            evidence = self.evidence_fixture(root, catalog, specs)
            data = build_data(catalog, specs, root, root / "review.html", {"catalog": "catalog-sha"}, evidence, root)
            review = data["exercises"][0]["independentReview"]
            self.assertEqual(len(review["findings"]), 2)
            self.assertEqual(review["findings"][0]["severity"], "medium")
            self.assertEqual(review["inspectedMP4Frames"], 96)
            self.assertEqual(review["inspectedMainPoses"], 3)
            self.assertFalse(review["trainerApproved"])
            self.assertIsNone(data["exercises"][1]["independentReview"])
            self.assertEqual(data["counts"]["sourceReviewQuestions"], 1)
            # A later native edit still leaves a playable export, but the old
            # inspection cannot attach to its changed bytes.
            (root / "curl/v1/exercise.blend").write_bytes(b"later native revision")
            with self.assertRaisesRegex(ValueError, "Stale review evidence"):
                build_data(catalog, specs, root, root / "review.html", evidence=evidence, evidence_root=root)

    def test_evidence_exact_coverage_catalog_hash_and_approval_are_checked(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, specs = self.fixture(root)
            evidence = self.evidence_fixture(root, catalog, specs)
            with self.assertRaisesRegex(ValueError, "catalog SHA is stale"):
                build_data(catalog, specs, root, root / "review.html", {"catalog": "changed"}, evidence, root)
            evidence["exercises"][0]["exerciseId"] = "unknown"
            with self.assertRaisesRegex(ValueError, "unknown catalog ID"):
                build_data(catalog, specs, root, root / "review.html", evidence=evidence, evidence_root=root)
            evidence["exercises"][0]["exerciseId"] = "curl"
            evidence["exercises"][0]["trainerApproved"] = True
            with self.assertRaisesRegex(ValueError, "remain trainer pending"):
                build_data(catalog, specs, root, root / "review.html", evidence=evidence, evidence_root=root)
            evidence["exercises"] = []
            evidence["verifiedCount"] = 0
            with self.assertRaisesRegex(ValueError, "exactly the current rendered"):
                build_data(catalog, specs, root, root / "review.html", evidence=evidence, evidence_root=root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=VISUALS / "catalog.json")
    parser.add_argument("--specifications", type=Path, default=VISUALS / "production/specifications.json")
    parser.add_argument("--visuals", type=Path, default=VISUALS)
    parser.add_argument("--output", type=Path, default=VISUALS / "trainer-review.html")
    parser.add_argument("--evidence", type=Path, help="Show all independent findings only after current-file SHA verification")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(TrainerReviewTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    print(json.dumps(build(args.catalog, args.specifications, args.output, args.visuals, args.evidence), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
