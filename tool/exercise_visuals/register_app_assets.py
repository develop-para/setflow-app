"""Write the app's exact-ID demo registry from explicitly checked exports.

Run sync_catalog.py --checked-demos ... --install first. This command verifies
the reviewed media hashes and installed GIF, and never approves an exercise.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from build_preview import load_exports
from export_media import sha256

ROOT = Path(__file__).resolve().parents[2]
VISUALS = ROOT / "output/exercise_visuals"
LABELS = {"quadriceps": "대퇴사두근", "glutes": "둔근", "hamstrings": "햄스트링",
          "erectors": "척추기립근", "chest": "대흉근", "triceps": "삼두근", "triceps_r": "오른쪽 삼두근", "adductors": "내전근", "traps": "승모근",
          "deltoids": "삼각근", "rear_deltoids": "후면 삼각근", "forearms": "전완근",
          "lats": "광배근", "upper_back": "상부 등", "biceps": "이두근",
          "calves": "종아리", "abs": "복근", "gluteus maximus": "둔근"}
VARIANTS = {
    "bodyweight_squat": "양발을 지지하는 맨몸 스쿼트",
    "pushup": "손바닥과 발끝으로 지지하는 바닥 푸시업",
    "bench": "플랫 벤치 바벨 프레스",
    "dumbbell_bench": "플랫 벤치 덤벨 프레스",
    "deadlift": "바닥에서 시작하는 오버핸드 바벨 데드리프트",
    "romanian_deadlift": "선 자세에서 시작하는 바벨 루마니안 데드리프트",
    "row": "오버핸드 그립으로 복부 방향에 당기는 벤트오버 바벨 로우",
    "curl": "선 자세에서 손바닥이 앞을 향하는 덤벨 컬",
    "dumbbell_shoulder_press": "등받이에 지지하고 앉아서 하는 덤벨 숄더 프레스",
    "lateral": "선 자세에서 양팔을 옆으로 드는 덤벨 레터럴 레이즈",
    "calf_raise": "어깨 패드 머신에서 하는 스탠딩 카프 레이즈",
    "plank": "팔꿈치를 어깨 아래에 둔 전완 플랭크",
    "crunch": "발을 바닥에 두고 손을 머리 옆에 둔 바닥 크런치",
    "squat": "바벨을 등 위쪽에 지지하는 하이바 백 스쿼트",
    "front_squat": "어깨 바깥 그립과 높은 팔꿈치로 바벨을 앞어깨에 지지하는 프런트 스쿼트",
    "goblet_squat": "케틀벨 손잡이를 가슴 앞에 잡는 고블릿 스쿼트",
    "barbell_curl": "선 자세에서 손바닥이 앞을 향하는 바벨 컬",
    "ohp": "스탠딩 바벨 프레스 · 다리 반동 없이",
    "incline": "45도 인클라인 덤벨 프레스",
    "incline_barbell": "45도 인클라인 바벨 프레스",
    "hip_thrust": "등 위쪽을 벤치에 지지하는 바벨 힙 쓰러스트",
    "glute_bridge": "바닥에서 하는 바벨 글루트 브리지",
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb": "발을 넓게 벌리고 무릎 안쪽에서 바를 잡는 스모 데드리프트",
    "58acf002-4e6d-5e95-b252-cae16252cef8": "무릎 굽힘을 작게 유지하는 바벨 스티프레그 데드리프트",
    "bulgarian_split_squat": "양손 덤벨을 들고 뒷발을 벤치에 지지하는 스플릿 스쿼트",
    "0f177240-029b-543a-be27-2e8ed0526bca": "원본 설명에 따른 뒷발 벤치 지지 덤벨 스플릿 스쿼트",
    "pullup": "오버핸드 그립 · 반동 없이 하는 풀업",
    "3c358477-aeb3-5d78-a6aa-91c9fb6c81db": "손바닥이 얼굴을 향하는 그립 · 반동 없이 하는 친업",
    "dips": "상체를 앞으로 기울이는 평행봉 딥스",
    "dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe": "상체를 세우고 팔꿈치를 가까이 둔 평행봉 딥스",
    "bench_dip": "무릎을 굽히고 손을 벤치 가장자리에 둔 벤치 딥스",
    "hanging_leg_raise": "반동 없이 편 다리를 수평까지 드는 행잉 레그 레이즈",
    "leg_raise": "등을 플랫 벤치에 지지하고 편 다리를 드는 레그 레이즈",
    "bird_dog": "네발 자세에서 반대쪽 팔과 다리 뻗기",
    "dead_bug": "누운 자세에서 반대쪽 팔과 다리 뻗기",
    "side_plank": "발을 앞뒤로 놓고 전완으로 지지하는 사이드 플랭크",
    "bff7dff4-2b99-5357-b365-f10e1187cbb3": "덤벨을 들고 앞으로 내디딘 뒤 제자리로 돌아오는 런지",
    "d1ecb818-0235-5e2f-9113-39be506aa98a": "덤벨을 들고 뒤로 내디딘 뒤 제자리로 돌아오는 런지",
    "823846f5-2414-58b7-911e-2d9397a28f49": "앞발을 플랫폼에 둔 자세에서 시작하는 덤벨 스텝업",
    "hammer_curl": "손바닥이 서로 마주보는 그립을 유지하는 덤벨 해머 컬",
    "reverse_curl": "오버핸드 그립으로 하는 바벨 리버스 컬",
    "front_raise": "양손 덤벨을 어깨 높이까지 앞으로 드는 프런트 레이즈",
    "rear_delt_raise": "상체를 숙여 양손 덤벨을 옆으로 드는 후면 레이즈",
    "reverse_fly": "상체를 숙여 양손 덤벨을 옆으로 벌리는 리버스 플라이",
    "cable_curl": "낮은 풀리 · 직선 바 · 언더핸드 그립 케이블 컬",
    "triceps_pushdown": "높은 풀리 · 직선 바 · 오버핸드 그립 푸시다운",
    "seated_cable_row": "낮은 풀리 · 직선 바 · 오버핸드 그립 시티드 로우",
    "latpull": "바를 머리 앞에서 가슴 쪽으로 당기는 오버핸드 랫 풀다운",
    "wall_sit": "양발을 바닥에 두고 등과 엉덩이를 벽에 지지하는 월싯",
    "russian_twist": "발을 들고 양손을 모아 좌우로 회전하는 맨몸 러시안 트위스트",
    "mountain_climber": "양손을 바닥에 고정하고 앞뒤 다리를 교체하는 마운틴 클라이머",
    "face_pull": "눈높이 풀리 · 로프 양끝을 얼굴 방향으로 당기는 페이스 풀",
    "arnold_press": "등받이에 지지하고 팔을 돌리며 밀어 올리는 덤벨 아놀드 프레스",
    "one_arm_dumbbell_row": "왼손과 왼쪽 무릎을 벤치에 지지하는 원암 덤벨 로우",
    "close_grip_bench": "손을 어깨선에 두는 플랫 바벨 클로즈그립 벤치 프레스",
    "chest_press": "등과 양발을 지지하고 가슴 중간 손잡이를 미는 머신 체스트 프레스",
    "leg_curl": "골반과 허벅지를 패드에 지지하는 엎드린 머신 레그 컬",
    "leg_extension": "등과 허벅지를 지지하고 정강이 패드를 드는 머신 레그 익스텐션",
    "adductor_machine": "안쪽 무릎 패드를 모으는 시티드 내전근 머신",
    "rack_pull": "무릎 높이 안전 받침에서 시작하는 오버핸드 바벨 랙 풀",
    "tbar_row": "한쪽이 고정된 바벨과 중립 그립 손잡이로 하는 랜드마인 T바 로우",
    "cable_crunch": "높은 풀리를 바라보며 무릎을 꿇고 하는 로프 케이블 크런치",
    "cable_fly": "가슴 높이 풀리 · 중립 그립 · 손을 가슴 앞에서 모으는 스탠딩 케이블 플라이",
    "cable_lateral_raise": "낮은 풀리에서 반대 골반 앞을 지나 옆으로 드는 편측 케이블 레이즈",
    "straight_arm_pulldown": "높은 풀리 · 직선 바 · 팔꿈치 굽힘을 작게 유지하는 스트레이트암 풀다운",
    "ab_wheel": "무릎을 바닥에 두고 허리 처짐 없이 제어하는 AB 휠 롤아웃",
    "burpee": "푸시업과 수직 점프를 포함한 버피",
    "walking_lunge": "양손 덤벨을 들고 한 발씩 앞으로 이동하는 워킹 런지",
    "pec_deck": "세로 손잡이 · 중립 그립으로 하는 시티드 펙덱 플라이",
    "reverse_pec_deck": "가슴 패드 지지 · 엄지가 위인 중립 그립 리버스 펙덱 플라이",
    "assisted_pullup": "양 무릎을 움직이는 보조 패드에 지지하는 오버핸드 어시스트 풀업",
    "seated_calf_raise": "허벅지 패드 · 앞발 발판 지지 · 고정 옆 손잡이 시티드 카프 레이즈",
    "legpress": "고정 시트 · 움직이는 발판 · 양발을 지지하는 레그 프레스",
    "hack_squat": "등과 양어깨 패드 · 고정 발판 지지 슬래드 핵 스쿼트",
    "preacher_curl": "팔 패드 지지 · 좁은 안쪽 EZ바 그립으로 하는 프리처 컬",
    "skull_crusher": "플랫 벤치 · EZ바 · 위팔을 고정하고 이마 위에서 멈추는 스컬 크러셔",
    "chest_supported_row": "45도 벤치 가슴 지지 · 양손 중립 그립 덤벨 로우",
    "back_extension": "45도 로만 체어 · 팔 교차 · 엉덩이 관절 중심 백 익스텐션",
    "decline_bench": "15도 디클라인 벤치 · 발 고정 · 낮은 흉골 쪽 바벨 프레스",
    "overhead_triceps_extension": "선 자세 · 한 손 덤벨 · 손바닥이 앞을 향하는 오버헤드 익스텐션",
    "upright_row": "넓은 오버핸드 그립 · 팔꿈치를 옆으로 이끌고 어깨 아래에서 멈추는 업라이트 로우",
    "brisk_walk": "지면을 앞으로 이동하며 발뒤꿈치부터 굴려 딛는 빠른 걷기",
    "run": "움직이는 수평 트레드밀 벨트 · 안전 정지 줄 연결 · 편안한 달리기",
    "jump_rope": "발을 가까이 두고 손목으로 줄을 돌리는 낮은 두 발 기본 바운스",
    "stair_climber": "회전하는 계단 · 발판 전체 지지 · 가볍게 손잡이를 잡는 스텝밀",
    "stationary_bike": "안장 지지 · 페달 스트랩 · 앞쪽 고정 손잡이 · 전방 페달링",
    "elliptical": "페달과 움직이는 양팔 손잡이가 연결된 전방 일립티컬 페달링",
    "rowing_machine": "발 스트랩과 이동 시트 · 다리·몸통·팔 순서로 당기는 로잉 머신",
}
SIDES = {
    "bulgarian_split_squat": "왼다리가 앞인",
    "0f177240-029b-543a-be27-2e8ed0526bca": "왼다리가 앞인",
    "bff7dff4-2b99-5357-b365-f10e1187cbb3": "왼다리를 앞으로 내딛는",
    "d1ecb818-0235-5e2f-9113-39be506aa98a": "오른다리를 뒤로 내딛는",
    "823846f5-2414-58b7-911e-2d9397a28f49": "왼다리로 올라서는",
    "bird_dog": "왼팔과 오른다리를 뻗는",
    "dead_bug": "오른팔과 왼다리를 뻗는",
    "side_plank": "오른쪽 전완으로 지지하는",
    "one_arm_dumbbell_row": "오른팔로 당기는",
    "cable_lateral_raise": "왼팔로 드는",
    "overhead_triceps_extension": "오른팔로 드는",
}
STATIC = {"plank", "side_plank", "wall_sit"}


def literal(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def render(catalog, media, target, visuals=VISUALS, root=ROOT):
    preamble = target.read_text(encoding="utf-8").split("const exerciseVisuals = ", 1)[0]
    if "class ExerciseVisual" not in preamble:
        raise ValueError("Missing ExerciseVisual class declaration")
    lines = [preamble + "const exerciseVisuals = <String, ExerciseVisual>{"]
    ids = []
    for row in catalog["exercises"]:
        if row.get("reviewStatus") != "visual_checked_trainer_pending":
            continue
        eid = row["exerciseId"]
        item = media.get(eid)
        if not item or row.get("reviewedExportHashes") != {name: r["sha256"] for name, r in item["files"].items()}:
            raise ValueError("Reviewed export changed: " + eid)
        if eid not in VARIANTS:
            raise ValueError("Exact variant description not written: " + eid)
        asset = root / "assets/exercise_visuals" / (eid + ".gif")
        if not asset.is_file() or sha256(asset) != item["files"]["exercise.gif"]["sha256"]:
            raise ValueError("Installed GIF does not match reviewed export: " + eid)
        audit_dir = visuals / ("bodyweight_squat/v5" if eid == "bodyweight_squat" else item["directory"])
        regions = json.loads((audit_dir / "highlight-audit.json").read_text(encoding="utf-8"))["regions"]
        labels = " · ".join(LABELS[region] for region in regions)
        lines.extend(["  " + literal(eid) + ": ExerciseVisual(",
                      "    assetPath: " + literal(asset.relative_to(root).as_posix()) + ",",
                      "    highlightedMuscles: " + literal(labels) + ",",
                      "    variantDescription: " + literal(VARIANTS[eid]) + ","])
        if eid in SIDES:
            lines.append("    demonstratedSide: " + literal(SIDES[eid]) + ",")
        if eid in STATIC:
            lines.append("    isStaticPose: true,")
        lines.append("  ),")
        ids.append(eid)
    if not ids:
        raise ValueError("No explicitly reviewed, installed exercise demos")
    return "\n".join([*lines, "};", ""]), ids


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=VISUALS / "catalog.json")
    parser.add_argument("--output", type=Path, default=ROOT / "lib/data/exercise_visuals.dart")
    args = parser.parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
    media, _ = load_exports(catalog["exercises"], VISUALS)
    content, ids = render(catalog, media, args.output)
    args.output.write_text(content, encoding="utf-8")
    print(json.dumps({"registeredDemos": len(ids), "trainerApproved": 0}))


if __name__ == "__main__":
    main()
