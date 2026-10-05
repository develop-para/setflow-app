"""Exact-ID production specifications, separate from render/approval state.

Run once with --refresh-upstream to fetch the pinned public-domain TEXT dataset
and license. Subsequent runs reuse its media-free snapshot embedded in the output.
No exercise is selected by its name, and no animation is assigned by this tool.
python tool/exercise_visuals/production_specs.py --self-test
"""

import argparse
import ast
import copy
import hashlib
import json
import re
import unittest
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
REVISION = "a859101d633a01c4a1a920d6a8ce41dabba0705f"
DATA_SHA256 = "5bb747e3fc658f095a60dcbf6d53c96627acdcc6ffb6fffde86f7e26995d40bf"
LICENSE_SHA256 = "6b0382b16279f26ff69014300541967a356a666eb0b91b422f6862f6b7dad17e"
UPSTREAM = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/" + REVISION + "/"
ACE = "https://www.acefitness.org/resources/everyone/exercise-library/"
NSCA = "https://www.nsca.com/contentassets/24f7e187e9aa4a588439c9612231c7fd/tsac-module-3.0--3.3.pdf"
VERIFIED_DATE = "2026-10-05"
TEXT_FIELDS = ("id", "name", "force", "level", "mechanic", "equipment",
               "primaryMuscles", "secondaryMuscles", "instructions", "category")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def reference(suffix, title, scope="exact_selected_variant"):
    return {"url": ACE + suffix + "/", "publisher": "American Council on Exercise",
            "title": title, "checkedDate": VERIFIED_DATE, "scope": scope,
            "verifiedBy": "Coding-agent reading of official text; not expert approval"}


def spec(variant, family, equipment, grip, body, start, movement, end, lowering,
         reference_url, constraints=()):
    """Each call below is an explicitly reviewed exercise, not a family fallback."""
    return {"variant": variant, "productionFamily": family,
            "requiredEquipment": equipment, "requiredGrip": grip,
            "requiredBodyPosition": body,
            "rangeOfMotion": {"start": start, "movement": movement,
                              "end": end, "return": lowering},
            "constraints": list(constraints), "references": [reference_url],
            "anglePolicy": "Use anatomical landmarks and body-specific reach; no universal numeric joint angle implied"}


# Curated IDs only. A shared row with a similar name/source ID does not inherit
# any of these specs. Family labels organize production; they bind no animation.
EXACT_SPECS = {
    "row": spec(
        "Overhand bent-over barbell row toward abdomen", "horizontal_pull",
        ["barbell"], "Closed overhand grip; neutral wrist; hands about shoulder width",
        "Hip hinge; slight knee bend; neutral stationary torso and neck; feet planted",
        "Arms nearly fully extended; shaft hanging below shoulders",
        "Bend elbows and retract shoulder girdle while bringing shaft toward abdomen",
        "Shaft near abdominal surface; do not pull through torso or thighs",
        "Controlled arm extension, without standing up or shrugging",
        reference("12/bent-over-row", "Bent-over Row"),
        ["Validate actual skinned-surface shaft clearance throughout every frame",
         "Grip proxy alignment alone does not establish closed hand contact"]),
    "bench": spec(
        "Flat barbell bench press", "horizontal_push", ["barbell", "flat_bench", "barbell_rack"],
        "Closed overhand grip slightly wider than shoulders; wrists aligned with forearms",
        "Supine; head, shoulders and butt on bench; both feet supported",
        "Bar over chest with extended arms", "Lower bar toward chest by flexing elbows",
        "Controlled lower point near chest without bouncing", "Press upward to arm extension",
        reference("5/chest-press", "Chest Press - barbell"),
        ["Keep bench/foot supports and clear face during bar travel"]),
    "dumbbell_bench": spec(
        "Flat dumbbell bench press", "horizontal_push", ["two_dumbbells", "flat_bench"],
        "Closed pronated grip; neutral wrists", "Head, shoulders and butt on bench; feet supported",
        "Dumbbells above chest/eye line with elbows extended",
        "Lower symmetrically toward mid-chest, slightly toward armpits",
        "Controlled chest-side lower position, without bouncing", "Press both dumbbells to starting position",
        reference("19/chest-press", "Chest Press - dumbbells"),
        ["Choose and declare elbow flare; keep all support contacts"]),
    "incline": spec(
        "Incline dumbbell chest press", "incline_push", ["two_dumbbells", "incline_bench"],
        "Closed pronated grip; neutral wrists; elbows below wrists",
        "Supine on incline bench; head/shoulders/butt supported; feet planted",
        "Arms extended over upper chest", "Lower both dumbbells toward upper chest/armpits",
        "Chest-side position without bouncing", "Press to arm extension with back supported",
        reference("25/incline-chest-press", "Incline Chest Press"),
        ["ACE describes bench 45-60 degrees; declare chosen bench geometry, not a universal angle"]),
    "close_grip_bench": spec(
        "Shoulder-width close-grip barbell bench press", "horizontal_push",
        ["barbell", "flat_bench", "barbell_rack"],
        "Closed overhand grip with hands in shoulder line; do not force hands together",
        "Supine; hips on bench; feet planted", "Bar above chest",
        "Lower to chest with elbows tracking near ribs", "Controlled chest-side position",
        "Press away from chest while maintaining foot and hip support",
        reference("311/close-grip-bench-press", "Close-grip Bench Press")),
    "one_arm_dumbbell_row": spec(
        "Right-arm dumbbell row with left hand and knee supported on a flat bench", "horizontal_pull",
        ["one_dumbbell", "flat_bench", "floor"],
        "Closed neutral dumbbell grip; left palm supports beneath shoulder",
        "Left knee under hip on bench; right foot planted; braced flat back and aligned head; no torso rotation",
        "Right arm extended toward floor without dropping the right shoulder",
        "Bend right elbow and draw upper arm back close to torso",
        "Highest controlled position before any torso rotation", "Lower slowly with back and shoulder position maintained",
        {**reference("126/single-arm-row", "Single-arm Row"), "checkedDate": "2026-10-06"},
        ["This demonstration uses the right arm; the guide also instructs repeating on the opposite side"]),
    "arnold_press": spec(
        "Seated supported dumbbell Arnold press", "vertical_push",
        ["two_dumbbells", "upright_backrest_bench", "floor"],
        "Closed dumbbell grip; palms toward torso at start and forward overhead; rotate arms rather than twisting wrists alone",
        "Seated with backrest support and planted feet; braced torso without lumbar overextension",
        "Dumbbells at shoulder height with bent elbows and palms toward torso",
        "Rotate upper arms and forearms outward while pressing overhead",
        "Arms extended overhead with palms forward", "Reverse the press and arm rotation slowly to starting position",
        {"url": "https://www.acefitness.org/resources/pros/expert-articles/6467/fast-and-efficient-upper-body-training/",
         "publisher": "American Council on Exercise", "title": "Fast and Efficient Upper-body Training - Arnold Press",
         "checkedDate": "2026-10-06", "scope": "arm_rotation_and_press_sequence; seated_backrest_is_selected_Setflow_variant",
         "verifiedBy": "Official Arnold Press paragraph read; no trainer approval"},
        ["ACE article describes arm rotation and pressing, but does not prescribe this seated backrest setup"]),
    "curl": spec(
        "Standing supinated dumbbell curl", "elbow_flexion", ["two_dumbbells"],
        "Supinated closed grip; straight rigid wrists", "Standing upright; elbows close to sides; no torso sway",
        "Arms at sides with elbows extended", "Flex elbows while keeping upper arms still",
        "Comfortable elbow flexion without moving elbows forward", "Lower slowly to start",
        {"url": "https://www.mayoclinic.org/healthy-lifestyle/fitness/multimedia/biceps-curl/vid-20084675",
         "publisher": "Mayo Clinic", "title": "Biceps curl with dumbbell", "checkedDate": VERIFIED_DATE,
         "scope": "exact_selected_variant", "verifiedBy": "Official transcript read; media not downloaded"}),
    "barbell_curl": spec(
        "Standing supinated barbell curl", "elbow_flexion", ["barbell"],
        "Closed palms-up grip about shoulder width; neutral wrists",
        "Upright; chest stationary; elbows beside torso", "Bar at arm length",
        "Flex elbows to bring bar toward shoulders", "Arm flexion without shoulder/body swing",
        "Lower slowly to arm-length start", reference("70/bicep-curl", "Bicep Curl - barbell")),
    "hammer_curl": spec(
        "Standing neutral-grip dumbbell hammer curl", "elbow_flexion", ["two_dumbbells"],
        "Closed neutral grip throughout; palms toward body; straight wrists",
        "Stable standing stance; elbows by sides; torso erect", "Dumbbells beside thighs; elbows extended",
        "Flex elbows together while preserving neutral grip", "Dumbbells near front of shoulders",
        "Return slowly to extended arms, without rotating to palms-forward",
        reference("10/hammer-curl", "Hammer Curl")),
    "reverse_curl": spec(
        "Standing overhand barbell reverse curl", "elbow_flexion", ["barbell"],
        "Closed pronated grip about shoulder width; neutral wrists",
        "Upright; elbows close to sides", "Bar at arm length",
        "Flex elbows with palms-down grip", "Bar toward shoulders without lifting upper arms",
        "Lower to starting position", reference("310/reverse-bicep-curl", "Reverse Bicep Curl")),
    "dumbbell_shoulder_press": spec(
        "Seated supported dumbbell overhead press", "vertical_push",
        ["two_dumbbells", "upright_backrest_bench"],
        "Closed pronated grip; neutral wrists; elbows slightly in front",
        "Seated; head/shoulders/butt supported; feet planted; braced torso",
        "Dumbbells at shoulder level", "Press both dumbbells overhead",
        "Elbows extended without lumbar arch", "Controlled return to shoulder level",
        reference("45/seated-overhead-press", "Seated Overhead Press - dumbbells"),
        ["This selected variant is seated; standing demos do not satisfy it"]),
    "ohp": spec(
        "Strict standing barbell overhead press", "vertical_push",
        ["barbell", "barbell_rack", "floor"],
        "Closed overhand grip slightly wider than shoulders; neutral wrists",
        "Standing; feet planted; braced torso; no knee dip or leg drive; no backward lumbar lean",
        "Bar in front of shoulders after unracking", "Press bar in front of head to overhead",
        "Arms extended above shoulders with stationary torso", "Controlled return in front to shoulder height",
        {**reference("71/standing-shoulder-press", "Standing Shoulder Press",
                     "standing_barbell_setup_body_position_and_press_path"), "checkedDate": "2026-10-06"},
        ["The broad catalog name now selects the authored standing variant; do not label it seated",
         "Neutral wrists and no leg drive are explicit Setflow strict-press constraints; ACE 71 supplies standing setup and path, not every selected constraint"]),
    "lateral": spec(
        "Standing dumbbell lateral raise", "shoulder_abduction", ["two_dumbbells"],
        "Closed neutral starting grip; straight wrists; small upward rotation near shoulder level",
        "Stable standing stance; braced torso; head aligned", "Dumbbells beside thighs; slight elbow bend",
        "Raise upper arms and elbows together to sides", "Upper arms approximately shoulder level",
        "Controlled return, preserving slight bend", reference("26/lateral-raise", "Lateral Raise"),
        ["Do not use the source dataset's pouring-water cue as an approved shoulder rotation"]),
    "front_raise": spec(
        "Standing dumbbell front raise", "shoulder_flexion", ["two_dumbbells"],
        "Closed pronated starting grip; neutral wrists; small external rotation near shoulder level",
        "Standing braced torso; no backward lean", "Dumbbells in front of thighs; soft elbows",
        "Raise arms forward together", "Arms at shoulder height, approximately parallel to floor",
        "Lower slowly to thighs", reference("54/front-raise", "Front Raise")),
    "deadlift": spec(
        "Conventional barbell floor deadlift with double-overhand grip", "loaded_hip_hinge",
        ["barbell", "weight_plates", "floor"], "Closed pronated grip; extended arms; straight wrists",
        "Feet planted; hips and knees flexed; neutral spine; shoulders over bar",
        "Loaded plates on floor close to shins", "Extend hips and knees together while keeping bar close",
        "Tall standing position; no exaggerated backward lean", "Hip/knee flexion to return plates to floor",
        {"url": NSCA + "#page=18", "publisher": "NSCA", "title": "TSAC Module 3.2-5 - Deadlift",
         "checkedDate": VERIFIED_DATE, "scope": "exact_selected_variant",
         "verifiedBy": "Official technique text read; not expert approval"},
        ["Keep arms extended and evaluate plate-floor contact separately from wrist coordinates"]),
    "romanian_deadlift": spec(
        "Standing barbell Romanian deadlift", "loaded_hip_hinge", ["barbell"],
        "Closed overhand grip; arms long; wrists straight",
        "Standing braced neutral back with maintained slight knee bend", "Bar in front of thighs",
        "Send hips backward and lower bar close to legs", "Stop at controlled hamstring-limited hinge range",
        "Return by hip extension, not repeated squat knee flexion",
        reference("317/romanian-deadlift", "Romanian Deadlift"),
        ["Do not force bar to floor; show RDL separately from conventional deadlift"]),
    "squat": spec(
        "High-bar barbell back squat", "loaded_squat", ["barbell", "barbell_rack"],
        "Closed grip wider than shoulders; bar supported on upper trapezius, not neck or rear-deltoid low-bar shelf",
        "Feet slightly wider than shoulders; braced straight back; chest lifted",
        "Standing with bar on upper back", "Flex hips and knees together while staying balanced",
        "Controlled squat depth without losing support or spinal control",
        "Extend hips and knees to stand", reference("11/back-squat", "Back Squat"),
        ["Different equipment and bar placement from bodyweight_squat; no interchangeable binding"]),
    "front_squat": spec(
        "Barbell front squat with clean front rack", "loaded_squat", ["barbell", "barbell_rack", "floor"],
        "Hands grasp shaft outside shoulders on their own side; uncrossed forearms; wrist extension keeps fingers around shaft",
        "Bar supported on anterior deltoids and upper chest; elbows forward and high; upper arms parallel to floor; neutral head and spine",
        "Standing with front rack; feet shoulder width and slightly turned outward",
        "Send hips back and flex knees, keeping knees aligned with feet and feet flat",
        "Controlled approximately parallel-thigh depth while preserving front-rack support",
        "Extend hips and knees with chest and elbows up and feet flat",
        {"url": "https://www.nsca.com/globalassets/education/nsca-coach/nsca-coach-10.1.pdf#page=10",
         "publisher": "NSCA", "title": "NSCA Coach 10.1 - Front Squat Checklist, Table 2, printed page 10",
         "checkedDate": "2026-10-06", "scope": "clean_rack_front_squat_checklist",
         "verifiedBy": "Official checklist text read; no trainer approval"},
        ["Do not substitute the former crossed-arm proposal or a back squat",
         "Rendered wrist and elbow angles are body-specific choices, not universal mobility requirements",
         "Numeric hand or shaft alignment cannot prove grip pressure or load-bearing contact"]),
    "bodyweight_squat": spec(
        "Unloaded bilateral bodyweight squat", "unloaded_squat", ["floor"],
        "No implement; hands may balance in front", "Stable stance slightly wider than hips; braced torso",
        "Standing with feet planted", "Hips move back and down while knees follow toe direction",
        "Controlled near-parallel thigh depth, before heel lift or loss of torso control",
        "Hips and torso rise together to standing", reference("135/bodyweight-squat", "Bodyweight Squat")),
    "pushup": spec(
        "Bilateral floor push-up", "horizontal_push", ["floor_or_mat"],
        "Palms flat; fingers forward or slightly inward; hands around shoulder width",
        "Straight braced body; toes and palms support weight; head aligned",
        "Extended elbows in high plank", "Lower chest and hips together by bending elbows",
        "Chest near floor without body sag", "Press to extended elbows without moving supports",
        reference("41/push-up", "Push-up")),
    "plank": spec(
        "Static forearm front plank", "trunk_anti_extension", ["floor_or_mat"],
        "Forearms and palms supported; elbows directly under shoulders",
        "Stiff torso and extended legs; head aligned; toes support",
        "Lift into forearm-supported straight body", "Hold with natural breathing",
        "Maintain alignment; no sag, hip hike, or shrug", "Lower gently after the hold",
        reference("32/front-plank", "Front Plank")),
    "side_plank": spec(
        "Static straight-leg forearm side plank with staggered feet", "trunk_anti_lateral_flexion", ["floor_or_mat"],
        "Supporting forearm on floor; elbow under shoulder", "Side support; straight legs; staggered feet; head aligned; top arm vertical",
        "Side-lying setup", "Lift hips and knees clear of mat",
        "Straight side-supported body; stable hold", "Lower gently and repeat opposite side",
        {"url": "https://www.nasm.org/resource-center/exercise-library/side-plank", "publisher": "NASM",
         "title": "Side Plank", "checkedDate": "2026-10-06", "scope": "forearm_support_and_staggered_feet_variant",
         "verifiedBy": "Official setup and hold text read; not expert approval"},
        ["Top arm vertical is the selected Setflow arm position; NASM text specifies support and feet, not this arm placement"]),
    "crunch": spec(
        "Supine floor abdominal crunch", "trunk_flexion", ["floor_or_mat"],
        "Hands lightly behind head; no neck pulling", "Bent knees; feet, tailbone and low back stay on mat",
        "Supine upper back on mat", "Curl rib cage toward pelvis with relaxed neck",
        "Upper back lifted; lower back/pelvis remain supported", "Uncurl slowly to mat",
        reference("52/crunch", "Crunch")),
    "bird_dog": spec(
        "Alternating contralateral quadruped bird dog", "trunk_anti_rotation", ["floor_or_mat"],
        "Flat hands under shoulders; fingers forward", "Knees under hips; neutral spine; level shoulders and hips",
        "Four-point support", "Extend opposite arm and leg together",
        "Limbs near torso height while low back and pelvis stay fixed",
        "Return gently, then alternate sides", reference("14/bird-dog", "Bird-dog")),
    "chest_press": spec(
        "Generic seated machine chest press", "horizontal_push", ["generic_seated_chest_press_machine"],
        "Full closed handle grip; neutral wrists",
        "Seated; backrest support; feet planted; handles at mid-chest",
        "Handles no deeper than front of chest", "Extend elbows to press handles forward",
        "Arms extended without hard locking or rounding shoulders off backrest",
        "Controlled return to start", reference("188/seated-chest-press", "Seated Chest Press"),
        ["Generic machine only; no manufacturer-specific linkage or model claim"]),
    "leg_curl": spec(
        "Prone machine hamstring curl", "knee_flexion", ["generic_prone_leg_curl_machine"],
        "Light full grip on fixed handles", "Prone; knee joint aligned to lever axis; braced pelvis",
        "Long legs; lower-calf pads above heels", "Bend knees to bring pads toward buttocks",
        "Controlled knee flexion without lumbar arch", "Return slowly to long legs",
        reference("153/lying-hamstrings-curl", "Lying Hamstrings Curl"),
        ["Pad supports lower calf, not bare heels; actual model geometry requires separate spec"]),
    "triceps_pushdown": spec(
        "Standing high-pulley straight-bar triceps pushdown", "elbow_extension",
        ["cable_stack", "high_pulley", "straight_bar_attachment"],
        "Closed overhand grip; neutral wrists", "Standing vertical braced torso; upper arms fixed by sides",
        "Bent elbows with upper arms near torso midline", "Extend elbows to push bar down",
        "Elbows extended without hard locking or shoulder movement", "Return under tension without elbows drifting forward",
        reference("185/triceps-pushdowns", "Triceps Pushdowns")),
    "glute_bridge": spec(
        "Barbell floor glute bridge", "hip_extension", ["barbell", "floor_or_mat"],
        "Palms-down grip to stabilize bar over hips", "Supine on floor; feet hip width; no shoulder-elevated bench",
        "Hips and tailbone down with bar over hips", "Press feet down and lift hips",
        "Controlled raised hips without exaggerated lumbar extension", "Lower tailbone to floor",
        reference("318/hip-bridge", "Hip Bridge - barbell"),
        ["Current local guide explicitly uses barbell; generic name alone does not justify unloaded or hip-thrust substitution"]),
}


CERTIFIED_2009 = "https://contentcdn.eacefitness.com/cp/pdfs/CertifiedNews/AugSept09Cert.pdf"
INSIGNIA_MANUAL = "https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf"
REVERSE_FLY_PAPER = "https://bretcontreras.com/wp-content/uploads/Effect-of-hand-position-on-EMG-activity-of-the-posterior-shoulder-musculature-during-a-horizontal-abduction-exercise.pdf"
RACK_PULL_PAPER = "https://www.nsca.com/contentassets/b70b70c5cb96417bbc58d5b6756a689e/ptq-8.3.1-resistance-training-progressions-for-the-older-adult-deadlifts.pdf"
UPRIGHT_ROW_PAPER = "https://www.lookgreatnaked.com/articles/upright_row_implications_for_preventing_subacromial_impingement.pdf"
EXACT_SPECS.update({
    "rack_pull": spec("Knee-height double-overhand rack pull", "partial_deadlift", ["barbell", "power_rack_safety_catches"],
        "Closed overhand just outside shoulders", "Planted feet; hip hinge; softly bent knees; stable torso",
        "Bar resting on knee-height catches", "Bring hips forward and stand tall", "Upright without leaning backward",
        "Hinge back; unload on catches and pause",
        {"url": RACK_PULL_PAPER + "#page=3", "publisher": "NSCA", "title": "Rack Pulls — PTQ 8.3",
         "checkedDate": "2026-10-06", "scope": "rack_pull_technique; selected_knee_height_overhand_variant",
         "verifiedBy": "Printed page 6 instructions read; not trainer approval"}),
    "tbar_row": spec("Neutral Double-D handle landmine T-bar row", "horizontal_pull", ["landmine_barbell", "double_d_handle"],
        "Closed neutral handles", "Straddle shaft facing away from pivot; fixed hip hinge and softly bent knees",
        "Extended arms", "Row along rigid landmine arc with elbows drawing back", "Controlled abdomen-side endpoint",
        "Extend arms without rising or moving the fixed pivot",
        {"url": "https://doi.org/10.1519/SSC.0000000000000751", "publisher": "NSCA Strength and Conditioning Journal",
         "title": "Exercise Technique: The Landmine Row", "checkedDate": "2026-10-06",
         "scope": "bilateral_landmine_tbar_technique; double_d_is_selected_attachment",
         "verifiedBy": "Author-provided full paper pages 3-4 read; not trainer approval"},
        ["Maintain a rigid shaft and actual fixed pivot; measure whole-shaft skin clearance"]),
    "upright_row": spec("Standing straight-bar upright row below shoulder height", "shoulder_elevation", ["barbell", "floor"],
        "Closed overhand, comfortable shoulder-width-or-wider grip", "Upright stationary torso; planted feet",
        "Bar in front of thighs", "Lead elbows outward, slightly anterior to the coronal plane", "Upper arms below shoulder level",
        "Lower without trunk swing",
        {"url": UPRIGHT_ROW_PAPER, "publisher": "NSCA Strength and Conditioning Journal",
         "title": "The Upright Row: Implications for Preventing Subacromial Impingement", "checkedDate": "2026-10-06",
         "scope": "modified_technique; body_specific_comfortable_range",
         "verifiedBy": "Original author-provided paper's technique modifications read; not trainer approval"},
        ["Selected range is not a guarantee of suitability; do not force bar to chin or wrists to a proxy target"]),
    "rowing_machine": spec("Sliding-seat stationary rowing ergometer", "rowing_cycle",
        ["rowing_ergometer", "footstraps"], "Closed handle grip; flat wrists",
        "Seated; relaxed shoulders; hip hinge", "Arms straight; comfortable near-vertical shins",
        "Drive legs, body, then arms", "Legs extended; handle below ribs; small backward torso lean",
        "Recover arms, body, then legs",
        {"url": "https://www.concept2.com/training/rowing-technique", "publisher": "Concept2",
         "title": "Indoor Rowing Technique", "checkedDate": "2026-10-06",
         "scope": "stroke_sequence_and_landmarks; original_generic_apparatus",
         "verifiedBy": "Official catch/drive/finish/recovery text read; not trainer approval"},
        ["Hands clear knees before knee flexion on recovery; heels may lift at catch"]),
    "adductor_machine": spec("Seated supported machine hip adduction", "hip_adduction", ["hip_adductor_machine"],
        "Hold side handles", "Back supported; knees bent; feet on pegs", "Comfortable open-leg start",
        "Move medial pads inward", "Controlled closed-leg point", "Reopen slowly",
        {"url": INSIGNIA_MANUAL + "#page=26", "publisher": "Life Fitness", "title": "Hip Adduction",
         "checkedDate": "2026-10-06", "scope": "medial_pads_and_foot_supports; original_generic_apparatus",
         "verifiedBy": "Printed page 24 read; not trainer approval"}),
    "leg_extension": spec("Seated machine knee extension", "knee_extension", ["leg_extension_machine"],
        "Hold seat-side handles", "Back and hips supported; knees aligned with machine pivots",
        "Bent knees; anterior lower-shin pads above ankles", "Extend knees under control", "Near-full extension", "Return slowly",
        {"url": INSIGNIA_MANUAL + "#page=29", "publisher": "Life Fitness", "title": "Leg Extension",
         "checkedDate": "2026-10-06", "scope": "knee_pivot_shin_pad_and_supported_extension; original_generic_apparatus",
         "verifiedBy": "Printed page 27 read; not trainer approval"}),
    "assisted_pullup": spec("Overhand pull-up with moving knee assistance pad", "vertical_pull",
        ["assisted_pullup_machine"], "Closed overhand bar grip", "Knees on moving pad; upright torso",
        "Supported extended arms", "Pull upward without swinging", "Comfortable upper point without neck reach", "Lower slowly",
        {"url": INSIGNIA_MANUAL + "#page=13", "publisher": "Life Fitness", "title": "Assist Dip / Chin",
         "checkedDate": "2026-10-06", "scope": "knee_pad_assistance_and_controlled_pull; original_generic_apparatus",
         "verifiedBy": "Printed page 11 read; selected overhand grip is Setflow's variant; not trainer approval"}),
    "pec_deck": spec("Seated vertical-handle neutral-grip pectoral fly", "horizontal_adduction",
        ["pec_fly_machine"], "Neutral vertical handles", "Back supported; feet planted; elbows slightly below shoulders",
        "Open arms with slight elbow bend", "Bring handles together", "Controlled chest-front point", "Reopen under control",
        {"url": INSIGNIA_MANUAL + "#page=30", "publisher": "Life Fitness", "title": "Pectoral Fly / Rear Deltoid",
         "checkedDate": "2026-10-06", "scope": "vertical_handle_pectoral_fly_cues; original_generic_apparatus",
         "verifiedBy": "Printed page 28 read; machine dimensions not reused; not trainer approval"}),
    "reverse_pec_deck": spec("Chest-supported thumb-up reverse machine fly", "horizontal_abduction",
        ["reverse_fly_machine"], "Neutral vertical handles; thumbs up", "Chest against pad; shoulder-height handles; feet planted",
        "Arms in front", "Open arms laterally", "Upper arms in torso plane", "Return slowly",
        {"url": REVERSE_FLY_PAPER + "#page=4", "publisher": "Journal of Strength and Conditioning Research",
         "title": "Effect of hand position on posterior shoulder activity", "checkedDate": "2026-10-06",
         "scope": "neutral_grip_exercise_description; original_generic_apparatus",
         "verifiedBy": "Page 2647 Exercise Description read; no manufacturer's geometry or trainer approval"}),
    "ab_wheel": spec("Kneeling ab-wheel rollout", "anti_extension", ["ab_wheel", "floor"],
        "Closed wheel handles", "Kneeling; braced trunk", "Wheel beneath shoulders",
        "Roll forward", "Controlled reach without lumbar sag", "Roll back",
        {"url": "https://www.nsca.com/globalassets/education/tsac-report/tsac-report-55.pdf#page=17",
         "publisher": "NSCA", "title": "TSAC Report 55 — Ab Wheel Rollout", "checkedDate": "2026-10-06",
         "scope": "kneeling_wheel_variant", "verifiedBy": "Official text read; not trainer approval"},
        ["Reach is body-specific; full extension is not mandatory"]),
    "burpee": spec("Burpee with push-up and vertical jump", "integrated", ["floor"],
        "Floor palms", "Standing", "Hip-width feet", "Squat, plank, push-up, gather, jump",
        "Bent-knee landing", "Reset stance",
        {"url": "https://www.nasm.org/resource-center/exercise-library/squat-thrust-burpees",
         "publisher": "NASM", "title": "Squat Thrust Burpees", "checkedDate": "2026-10-06",
         "scope": "pushup_vertical_jump_variant", "verifiedBy": "Official text read; not trainer approval"}),
    "cable_crunch": spec("Facing-pulley kneeling rope crunch", "trunk_flexion", ["high_cable", "rope"],
        "Rope ends", "Kneel facing pulley", "Hands beside head", "Curl torso",
        "Controlled flexion", "Return slowly",
        {"url": CERTIFIED_2009 + "#page=10", "publisher": "ACE", "title": "Kneeling Crunches",
         "checkedDate": "2026-10-06", "scope": "facing_pulley_kneeling_rope",
         "verifiedBy": "Official printed page 10 read; not trainer approval"},
        ["Keep hands beside head; no arm-driven pull"]),
    "cable_lateral_raise": spec("Unilateral low-cable lateral raise", "shoulder_abduction", ["low_cable", "single_handle"],
        "Full handle grip", "Stand side-on", "Handle at opposite hip", "Raise laterally",
        "Shoulder height", "Lower slowly",
        {"url": CERTIFIED_2009 + "#page=9", "publisher": "ACE", "title": "Cable Lateral Raise",
         "checkedDate": "2026-10-06", "scope": "unilateral_low_handle",
         "verifiedBy": "Official printed page 9 read; not trainer approval"},
        ["Slight fixed elbow bend; weight evenly supported"]),
})

FORTIS_MANUAL = "https://assets.kogan.com/files/usermanuals/FSLEGHCKSQA_UG_V1.1.pdf"
CALF_MANUAL = "https://kb.cybexintl.com/Owners_Manuals/Strength/16212-999-4.pdf"
BACK_EXTENSION_PAPER = "https://bretcontreras.com/wp-content/uploads/Are-All-Hip-Extension-Exercises-Created-Equal.pdf"
MUSCLE_STRENGTH = "https://www.muscleandstrength.com/"


def publisher_reference(url, title, scope="exact_selected_variant", publisher="Muscle & Strength"):
    return {"url": url, "title": title, "publisher": publisher, "checkedDate": "2026-10-06",
            "scope": scope, "verifiedBy": "Primary instructions read; no media reused or trainer approval"}


EXACT_SPECS.update({
    "brisk_walk": spec("Forward ground brisk walking with heel-to-toe roll", "cyclic_cardio",
        ["training_shoes"], "Relaxed hands; opposite bent-arm swing",
        "Upright torso and head; neutral pelvis; at least one foot on ground", "Heel contact",
        "Roll heel to forefoot while advancing", "Supported toe-off and opposite heel landing",
        "Alternate sides with actual forward progress",
        publisher_reference("https://contentcdn.eacefitness.com/assets/about-ace/advocacy/Walking_Toolkit_Community.pdf#page=16",
                            "Walk This Way — Walking Form", "printed_pages9_and16; original_stride_and_cadence", "ACE")),
    "run": spec("Level moving-belt treadmill running with emergency-stop clip", "cyclic_cardio",
        ["treadmill", "training_shoes", "emergency_stop_cord"], "Relaxed hands; rails not held",
        "Forward-looking head; relaxed shoulders; small ankle-based lean", "Soft near-hip footstrike",
        "Alternating belt-relative stance and flight with opposite arm swing", "Airborne stride",
        "Soft next contact under hips",
        [publisher_reference("https://www.acefitness.org/resources/pros/expert-articles/5415/5-tips-for-optimizing-running-form/",
                             "5 Tips for Optimizing Running Form", "common_running_cues; selected_treadmill_geometry", "ACE"),
         publisher_reference("https://support.lifefitness.com/hc/en-us/articles/42814055083031-Life-Fitness-Atmos-Treadmill-How-to-Use-the-Emergency-Stop-and-Prevent-Child-Use",
                             "Atmos Treadmill — Emergency Stop", "clothing_clip_only; no_brand_model_replication", "Life Fitness")],
        ["Established running cycle only; start and stop procedure is in the local guide; footstrike is individual"]),
    "stair_climber": spec("Forward alternating climbing on rotating stepmill", "cyclic_cardio",
        ["rotating_stepmill", "training_shoes"], "Light closed handrail grip",
        "Upright and forward-facing; sole supported on actual stair", "One supporting step",
        "Alternate feet as steps descend through a closed continuous path", "Opposite step placement",
        "Repeat without leaning bodyweight onto hands",
        publisher_reference("https://fitnessengros.dk/media/c8/82/f7/1670237019/Owners%20Manual%20G8.pdf?ts=1727943233",
                            "8G Owner Manual 620-8297F", "manufacturer_text_via_distributor_mirror; printed_pages3_6_7; original_generic_geometry", "Core Health & Fitness"),
        ["Local selected rotating stairs differ from upstream Stairmaster pedal instructions; trainer must assess this declared variant"]),
    "jump_rope": spec("Two-foot basic bounce with wrist-driven forward rope rotation", "cyclic_cardio",
        ["jump_rope", "training_shoes"], "Closed handle grips; elbows close to sides",
        "Feet comfortably close; erect head and relaxed torso", "Supported forefeet",
        "Small wrist circles and low bilateral hops", "Only enough flight to clear rope",
        "Land softly on forefeet with comfortable ankle and knee motion",
        publisher_reference("https://jumpropeinstitute.com/howto-htm/", "How to Jump Rope — Basic Bounce Step",
                            "basic_bounce_cues; original_model_hop_and_rope_geometry", "Jump Rope Institute")),
    "stationary_bike": spec("Seated upright stationary bike with forward cranks", "cyclic_cardio",
        ["upright_stationary_bike", "training_shoes", "pedal_straps"], "Fixed front handlebars",
        "Stable saddle; forefeet on strapped pedals; comfortable slight knee bend at fullest reach",
        "Supported seated stance", "Pedal forward without rocking hips", "Opposite crank phase",
        "Continue smooth controlled rotations",
        publisher_reference("https://support.lifefitness.com/hc/en-us/articles/42862231037335-How-to-Adjust-the-Seat-on-Your-Life-Fitness-Atmos-Upright-Bike",
                            "Atmos Upright Bike — Seat Adjustment", "setup_and_nonlocking_knee_cues; original_generic_geometry", "Life Fitness"),
        ["Original slow demonstration cadence and dimensions are model-fit choices; pedal strap setup source is recorded separately"]),
    "elliptical": spec("Forward elliptical pedaling with coupled moving arms", "cyclic_cardio",
        ["elliptical_cross_trainer", "training_shoes"], "Closed moving-arm grips",
        "Face forward; supported whole soles; stable relaxed torso", "Opposite pedal phase",
        "Pedal through an ellipse while pushing and pulling coupled handles", "Opposite coupled phase",
        "Continue controlled rotations; stop before dismounting",
        publisher_reference("https://kb.cybexintl.com/Owners_Manuals/Cross_Trainer/OM_CSX_Club_Series_Cross_Trainer.pdf#page=5",
                            "Club Series CSX Cross-Trainer — Operation", "printed_pages4_5_6_25; original_rigid_linkage_not_manufacturer_geometry", "Life Fitness")),
    "rowing_machine": spec("Sliding-seat ergometer with sequenced drive and recovery", "cyclic_cardio",
        ["rowing_ergometer", "training_shoes", "foot_straps"], "Relaxed closed overhand grip; flat wrists",
        "Supported strapped feet; neutral neck and shoulders; hip hinge", "Arms straight and shins near vertical at catch",
        "Drive through legs, then hip swing, then arm pull", "Extended legs; small backward lean; handle below ribs",
        "Extend arms, hinge forward, then bend knees; controlled slower recovery",
        publisher_reference("https://www.concept2.com/training/rowing-technique", "Indoor Rowing Technique",
                            "catch_drive_finish_recovery_text; original_generic_ergometer", "Concept2")),
    "preacher_curl": spec("Seated close-inner-grip EZ-bar preacher curl", "elbow_flexion",
        ["ez_curl_bar", "preacher_bench"], "Closed palms-up inner EZ handles",
        "Seated with upper arms and chest supported; stationary torso", "Elbows extended without forced locking",
        "Flex elbows with upper arms on padding", "Controlled raised forearms", "Lower without bouncing or torso motion",
        publisher_reference(MUSCLE_STRENGTH + "exercises/ez-bar-preacher-curl.html", "EZ Bar Preacher Curl",
                            "publisher_allows_narrow_grip; original_split_arm_padding_for_model")),
    "skull_crusher": spec("Flat-bench EZ-bar skull crusher with above-forehead stop", "elbow_extension",
        ["ez_curl_bar", "flat_bench"], "Closed inner EZ handles", "Supine; head and torso supported; feet planted",
        "Arms over chest", "Bend elbows with fixed upper arms", "Bar above forehead without head contact",
        "Extend elbows under control",
        publisher_reference(MUSCLE_STRENGTH + "exercises/ez-bar-skullcrusher.html", "EZ Bar Skullcrusher",
                            "ez_bar_above_forehead_variant; fixed_upper_arms_selected")),
    "chest_supported_row": spec("Prone 45-degree neutral-grip bilateral dumbbell row", "horizontal_pull",
        ["two_dumbbells", "incline_bench"], "Closed neutral grips", "Chest supported; feet planted; aligned neck",
        "Arms below shoulders", "Draw elbows behind torso with scapular movement", "Controlled torso-side dumbbells",
        "Lower without lifting chest off pad",
        publisher_reference(MUSCLE_STRENGTH + "node/48713", "Neutral Grip Chest Supported Dumbbell Row")),
    "back_extension": spec("Neutral-spine 45-degree Roman-chair hip extension", "hip_extension",
        ["roman_chair"], "Arms crossed on chest", "Upper thighs supported; anchored feet; nearly straight knees",
        "Torso in leg line", "Lower through hip flexion with aligned spine", "Comfortable controlled hip flexion",
        "Extend hips to body line without lumbar overextension",
        publisher_reference(BACK_EXTENSION_PAPER + "#page=1", "Are All Hip Extension Exercises Created Equal?",
                            "45_degree_neutral_spine_analysis; pad_setup_from_exact_upstream_text",
                            "NSCA Strength and Conditioning Journal")),
    "decline_bench": spec("15-degree decline straight-bar bench press", "horizontal_push",
        ["barbell", "decline_bench", "foot_anchor_pads"], "Closed overhand just outside shoulder width",
        "Head, back and hips supported; feet secured", "Bar above chest", "Lower in straight path toward low sternum",
        "Chest-side endpoint", "Press without bouncing; arms almost extended",
        publisher_reference(MUSCLE_STRENGTH + "exercises/decline-bench-press.html", "Decline Bench Press"),
        ["15 degrees is original apparatus fit, not universal prescription; skin clearance does not simulate tissue pressure"]),
    "overhead_triceps_extension": spec("Standing right-arm dumbbell overhead extension", "elbow_extension",
        ["one_dumbbell"], "Palm forward; closed grip", "Braced standing torso; fixed overhead upper arm",
        "Slightly bent elbow", "Flex elbow to lower dumbbell behind neck", "Controlled comfortable elbow flexion",
        "Extend without hard locking",
        publisher_reference(MUSCLE_STRENGTH + "exercises/one-arm-dumbbell-extension.html",
                            "One-Arm Standing Dumbbell Extension", "right_arm_mirror_of_publisher_left_arm")),
    "seated_calf_raise": spec("Bent-knee seated calf raise with fixed seat-side handles", "ankle_plantarflexion",
        ["seated_calf_machine"], "Fixed seat-side handles", "Seated with distal thigh pads and forefeet supported; heels free",
        "Heels in comfortable lowered position", "Press through forefeet to raise heels", "Comfortable heel elevation",
        "Lower under control",
        publisher_reference(CALF_MANUAL + "#page=10", "Cybex 16212 Seated Calf — Movement",
                            "thigh_pad_forefoot_support; fixed_handles_original_variant", "Cybex"),
        ["Pinned source uses hands on moving lever; selected original fixed handles are explicit"]),
    "legpress": spec("Inclined moving-footplate leg press with fixed reclined seat", "compound_leg_press",
        ["leg_press_machine"], "Fixed seat-side handles", "Back and hips supported; whole feet on moving platform",
        "Comfortably bent knees", "Extend hips and knees to move footplate along rails", "Slightly bent knees",
        "Lower plate with back and feet supported",
        publisher_reference(FORTIS_MANUAL + "#page=25", "Leg Press — Operation",
                            "support_and_control_cues; original_generic_rails_and_body_specific_range", "Fortis")),
    "hack_squat": spec("Back-and-shoulder-supported translating hack-squat sled", "supported_squat",
        ["hack_squat_machine"], "Sled-side handles", "Back and shoulders against pads; feet on fixed platform",
        "Nearly extended knees", "Bend knees and hips with pad support", "Comfortable supported depth",
        "Extend without knee hard lock",
        publisher_reference(FORTIS_MANUAL + "#page=25", "Hack Squat — Operation",
                            "pad_support_and_control_cues; original_generic_apparatus", "Fortis"),
        ["Do not require a universal knees-behind-toes rule or depth"]),
})

# Resolve two earlier source-scope questions by explicitly selecting the actual
# authored variant. Keep the upstream incline/V-handle texts as distinct source
# records; they are not instructions for these clips.
EXACT_SPECS.update({
    "reverse_fly": spec("Standing hip-hinged neutral-grip dumbbell reverse fly", "horizontal_abduction",
        ["two_dumbbells", "floor"], "Closed neutral grip; slightly flexed elbows held at a fixed angle",
        "Standing with soft knees and fixed hip hinge; braced neutral spine and aligned neck",
        "Dumbbells hanging below shoulders", "Open upper arms to the sides without torso swing or repeated elbow flexion",
        "Controlled arm position near torso level", "Lower slowly beneath shoulders with stationary torso",
        publisher_reference("https://www.muscleandstrength.com/exercises/bent-over-dumbbell-reverse-fly.html",
                            "Bent Over Dumbbell Reverse Fly", "standing_neutral_grip_variant; body_specific_hinge_and_range"),
        ["Mayo seated reverse fly and upstream incline-bench Reverse_Flyes are separate variants",
         "No manufacturer media reused or trainer approval implied"]),
    "seated_cable_row": spec("Seated low-pulley shoulder-width pronated straight-bar row", "horizontal_pull",
        ["low_pulley", "straight_bar_attachment", "seat", "foot_supports"],
        "Closed overhand grip about shoulder width; wrists aligned with forearms",
        "Seated with feet supported and knees slightly bent; stable upright torso",
        "Arms extended in front", "Draw elbows back close to torso and bring bar toward abdomen without torso swing",
        "Controlled abdomen-side endpoint", "Extend arms slowly with torso and foot support unchanged",
        publisher_reference(CERTIFIED_2009 + "#page=9", "ACE Certified News August/September 2009 — Seated Row",
                            "printed_page10_straight_bar_and_bench_options; pronated_grip_and_footrests_are_explicit_Setflow_selection", "ACE"),
        ["ACE 48 narrow handle and upstream Seated_Cable_Rows V-handle are distinct variants",
         "ACE 2009 lists straight bar but does not specify the pronated grip; that grip is a declared selected variant"]),
})

# Manually identified conflicts. These are evidence-review flags; string regexes
# are used only to parse Dart source, never to pick a motion or fix a variant.
GUIDE_FLAGS = {
    "lateral": ["exact 원본의 물 따르는 내회전 cue와 ACE의 약한 외회전 cue가 다릅니다. 공식 사양을 우선합니다."],
}


def correction(issue, change, basis, guide_sha, references=(), scope="local_guide", equipment=None):
    return {"recordedDate": "2026-10-06", "previousIssue": issue,
            "implementedChange": change, "correctionBasis": basis,
            "scope": scope, "referenceUrls": list(references),
            "verifiedGuideStepsSha256": guide_sha, "expectedCatalogEquipmentKey": equipment,
            "verificationScope": "Coding-agent source comparison; no animation or trainer approval",
            "trainerApproved": False}


# Explicit source-edit history, never a name/variant inference. Matching the
# observed guide hash prevents a later edit from silently inheriting resolution.
# Metadata-only corrections retain the original imported guide authorship.
GUIDE_CORRECTIONS = {
    "squat": correction("후삼각근 로우바 선택지·뒤꿈치만 체중·허리를 굽힌다는 문장이 현재 하이바 시안과 충돌했습니다.",
        "등 위쪽 승모근 하이바 지지, 발바닥 전체 지지, 고관절과 무릎의 동시 굽힘·펴기를 명시했습니다.",
        "ACE 11의 등 위쪽 바 지지·곧은 등·바닥을 미는 복귀와 현재 하이바 선택 변형을 대조했습니다. 깊이는 통제 가능한 자체 범위입니다.",
        "f94456e3a3f2737ebdf22bdeeb372d94b4435ac9a619055ed75d271657d1a2de", [ACE + "11/back-squat/"]),
    "romanian_deadlift": correction("허리에서 굽히라는 표현과 시작 위치로 다시 내린다는 문장이 고관절 힌지와 선 자세 복귀를 혼동했습니다.",
        "무릎의 작은 굽힘을 유지한 hip hinge와 바벨의 다리 가까운 경로, 서 있는 시작 자세 복귀를 명시했습니다.",
        "ACE 317의 허벅지 앞 시작·엉덩이 뒤로 이동·곧은 등·서 있는 자세 복귀 본문을 직접 대조했습니다.",
        "3f375c72401ef8ecbbd63fa01b080ecbac11a23a08f8baf7ab42fe3587346cdb", [ACE + "317/romanian-deadlift/"]),
    "dips": correction("직립 표현과 어깨가 팔꿈치 아래로 반드시 내려가는 설명이 현재 가슴 딥스 변형과 충돌했습니다.",
        "가슴을 앞으로 조금 기울이는 평행봉 변형과 조절 가능한 내려가기·밀어 올라오기를 명시했습니다.",
        "Exact Dips_-_Chest_Version 원본 텍스트와 현재 시안의 선택 변형을 대조했습니다. 원본의 고정 각도·잠금·과한 깊이는 필수 조건으로 옮기지 않았습니다.",
        "65584a20ccc498ab611b1ee0d61dcfa9031879649c1131288f12f30d57568dc2", [UPSTREAM + "exercises/Dips_-_Chest_Version.json"]),
    "glute_bridge": correction("허리에 바를 놓고 허리를 올리고 내린다는 표현이 골반 바벨 지지와 고관절 신전을 혼동했습니다.",
        "보호 패드를 댄 바벨의 골반 앞 지지와 등 위쪽·발 지지, 골반 올리기·내리기를 명시했습니다.",
        "ACE 318의 골반 바벨 위치·발바닥 지지·골반 신전과 exact Barbell_Glute_Bridge의 보호 패드 설명을 대조했습니다.",
        "55a95e4d5b2d0f6390737cd83a027f05ebd80e0500b1adc089220988ef43c863", [ACE + "318/hip-bridge/", UPSTREAM + "exercises/Barbell_Glute_Bridge.json"]),
    "reverse_fly": correction("검토 자료의 Mayo 앉은 변형과 upstream 인클라인 벤치 변형이 현재 서서 하는 시안과 달랐습니다.",
        "서서 엉덩이 힌지를 유지하는 중립 그립 덤벨 리버스 플라이를 선택하고 한국어 단계를 직접 작성했습니다.",
        "Muscle & Strength의 직접 작성된 standing Bent Over Dumbbell Reverse Fly 본문을 읽어 선택 변형을 대조했습니다. 과거 시각 검토 메모는 삭제하지 않습니다.",
        "f8a76908b820b1ff38183267e850c1b416d438da8f54eb10b4d3ae2ad3ce4032", ["https://www.muscleandstrength.com/exercises/bent-over-dumbbell-reverse-fly.html"]),
    "seated_cable_row": correction("기존 guide의 오버핸드 핸들이 중립 V핸들 upstream 원본·ACE 48 narrow handle과 혼동되었습니다.",
        "현재 시안과 같은 낮은 풀리·어깨너비 회내 직바·발판 지지 변형을 명시해 한국어 단계를 다시 작성했습니다.",
        "ACE Certified News 2009 인쇄10쪽의 straight bar와 bench 옵션을 직접 읽었습니다. 회내 그립과 발판은 Setflow가 명시적으로 선택한 세부 변형이며 ACE가 그립을 지정한 것으로 주장하지 않습니다.",
        "5d3b363d1942660653fb2627f3e6eb442fb606c9e81a517236ecd98db6ba937e", [CERTIFIED_2009 + "#page=9"]),
    "straight_arm_pulldown": correction("팔을 완전히 곧게 두라는 표현이 현재 작고 고정된 팔꿈치 굽힘과 어깨에서 당기는 경로를 누락했습니다.",
        "직바 오버핸드 그립, 작은 팔꿈치 굽힘 유지, 어깨 관절에서 허벅지 앞까지 보내는 경로를 명시했습니다.",
        "ACE 5565의 어깨너비 케이블 바와 허벅지까지 내리는 본문을 대조했습니다. 작은 고정 팔꿈치 굽힘은 Setflow 선택이며 library 334의 혼합 rope/bar 표현으로 직바를 증명하지 않습니다.",
        "89478fde4bf91c49f583524446c84df93e87c6400d76cfe041bce740016c1d18", ["https://www.acefitness.org/resources/pros/expert-articles/5565/4-moves-to-help-you-master-the-pull-up/"]),
    "stationary_bike": correction("안장 위치와 스트랩 고정의 구체적인 기준이 없었습니다.",
        "내려서 안장을 조절하고 가장 먼 페달 위치에서 무릎이 조금 굽혀지는지 확인하며 운동화·발 앞부분·스트랩 지지를 명시했습니다.",
        "Life Fitness 공식 안장과 페달 스트랩 안내를 직접 읽었습니다. 안장과 페달 수치는 체형에 맞춘 자체 선택입니다.",
        "ee6669a78e90a8cdebf1f8db4d43f7d795eb389183cbe2b3697f0f1a0df4abf8",
        ["https://support.lifefitness.com/hc/en-us/articles/42862231037335-How-to-Adjust-the-Seat-on-Your-Life-Fitness-Atmos-Upright-Bike",
         "https://support.lifefitness.com/hc/en-us/articles/42862246498199-How-to-Adjust-the-Pedal-Straps-on-Your-Atmos-Cardio-Series-Bike"]),
    "elliptical": correction("움직이는 손잡이와 승하차용 고정 손잡이를 구분하지 않았습니다.",
        "앞을 향한 운동화·페달 지지, 움직이는 양팔 손잡이의 밀고 당김, 고정 손잡이로 승하차와 완전 정지를 명시했습니다.",
        "Life Fitness CSX 공식 매뉴얼 인쇄4–6·25쪽과 Atmos 공식 승하차 안내를 직접 읽었습니다. 링크 기구 형상은 자체 설계입니다.",
        "3b788d10522da60c746138d5606fddc4b2d0d3e8d79ae10df972619d5827c91a",
        ["https://kb.cybexintl.com/Owners_Manuals/Cross_Trainer/OM_CSX_Club_Series_Cross_Trainer.pdf",
         "https://support.lifefitness.com/hc/en-us/articles/42861901438359-How-to-Mount-and-Dismount-Your-Atmos-Elliptical-Safely"]),
    "stair_climber": correction("스텝밀 설명에서 손잡이에 체중을 매달거나 계단이 움직이는 동안 내리는 것으로 읽힐 수 있었습니다.",
        "앞을 향해 교대로 발판을 딛고 가벼운 손잡이 지지와 완전히 멈춘 뒤 하차를 명시했습니다.",
        "Core Health & Fitness 8G 제조사 매뉴얼 인쇄3·6–7쪽을 유통사 미러의 동일 원문으로 직접 읽었습니다. 회전 계단은 upstream 두 페달 변형과 구분한 자체 기구입니다.",
        "d4ca0622519ad40a02fd58840c1f381ab47d46412516bd1c338232206ecaa272",
        ["https://fitnessengros.dk/media/c8/82/f7/1670237019/Owners%20Manual%20G8.pdf?ts=1727943233"]),
    "jump_rope": correction("기본 바운스인데 어깨너비와 발가락 끝 착지를 설명했습니다.",
        "두 발을 가까이 두고 손목으로 줄을 돌리며 낮게 뛰고 발 앞부분으로 부드럽게 착지하도록 수정했습니다.",
        "Jump Rope Institute 코치 원문의 Basic Bounce와 손목·팔꿈치·앞꿈치 착지 cue를 직접 대조했습니다. 모델의 수치와 운동화 형상은 자체 제작입니다.",
        "ae1bff74387b1ec5a45a1706ed134ae717f74927e9f01d640ed0967b305bae8e",
        ["https://jumpropeinstitute.com/howto-htm/"]),
    "preacher_curl": correction("기존 넓은 직선 바 그립 설명이 선택한 좁은 EZ바 그립과 달랐습니다.",
        "패드에 위팔을 지지하고 EZ바의 안쪽 손잡이를 손바닥 위로 잡도록 수정했습니다.",
        "M&S의 직접 EZ바 프리처 컬 설명은 좁은 그립을 허용합니다. 패드 형상은 체형에 맞춘 자체 기구입니다.",
        "764d7f567d616ce5168c0f5fd12b0753768c618f37ae4d16bef8c081549d4246",
        [MUSCLE_STRENGTH + "exercises/ez-bar-preacher-curl.html"], equipment="ez_curl_bar"),
    "skull_crusher": correction("직선 바·머리가 벤치 끝인 설명이 선택한 머리 지지 EZ바 변형과 달랐습니다.",
        "머리와 몸통 지지, 닫힌 안쪽 EZ바 그립과 이마 위 정지점을 명시했습니다.",
        "M&S EZ Bar Skullcrusher의 이마 또는 그 위 끝점과 대조했습니다. ACE 직선 바 동작을 동일 EZ 변형으로 주장하지 않습니다.",
        "a1f5bdc211dc2183f9066c2f16c40b8e671a5bc9887908bf962ed6d3b6b2e289",
        [MUSCLE_STRENGTH + "exercises/ez-bar-skullcrusher.html"], equipment="ez_curl_bar"),
    "chest_supported_row": correction("벤치에 앉으라는 설명이 엎드려 가슴을 지지하는 선택과 달랐습니다.",
        "45도 벤치에 엎드려 가슴과 발을 지지하고 중립 덤벨 그립으로 당기도록 수정했습니다.",
        "M&S 원문에서 벤치 각도·중립 그립·견갑 움직임·발바닥 지지 선택을 대조했습니다.",
        "ad06f21aeeb4679c77ad8839742ba623dc2ac5eb448a6b0dd188474c7ddaa531",
        [MUSCLE_STRENGTH + "node/48713"], equipment="dumbbell"),
    "back_extension": correction("여러 팔 위치를 함께 안내하고 엉덩이 관절 중심 움직임을 명시하지 않았습니다.",
        "45도 로만 체어·팔 교차·허벅지와 발 지지·엉덩이 관절 굴곡과 몸 일직선 끝점으로 고정했습니다.",
        "NSCA SCJ 원논문 인쇄 17–18쪽의 중립 척추 힙 익스텐션 분석과 exact 원본의 패드 접촉을 대조했습니다.",
        "7fb0aa33039fd1b347f3b58b2aaca2d4a998fad66b942f4182a6e41f538a87a5",
        [BACK_EXTENSION_PAPER], equipment="machine"),
    "decline_bench": correction("손 방향과 거치대에서 내려놓는 표현이 모호하고 실제 지지점을 누락했습니다.",
        "등·머리·엉덩이·발 지지와 닫힌 바벨 그립, 낮은 흉골 쪽 하강을 명시했습니다.",
        "M&S Decline Bench Press의 원문 수행 설명과 대조했습니다. 15도는 자체 기구 선택값입니다.",
        "832f38ee6fb03abd160c503d8cb863dfafa2b18893ca86417f918e6a59187919",
        [MUSCLE_STRENGTH + "exercises/decline-bench-press.html"], equipment="barbell"),
    "overhead_triceps_extension": correction("한 손 덤벨의 손바닥 방향이 빠지고 팔 완전 잠금으로 읽힐 수 있었습니다.",
        "선 자세·손바닥 전방·고정 위팔·목 뒤 하강·끝 비잠금과 반대쪽 반복을 명시했습니다.",
        "M&S의 직접 한 팔 스탠딩 덤벨 익스텐션 원문을 대조했습니다. 오른팔 시범은 원문 왼팔의 대칭입니다.",
        "dfc4019fb7aecdac19616e5a4837c1d57a5cfe2b3fb14e18ddc92716c32cdb9f",
        [MUSCLE_STRENGTH + "exercises/one-arm-dumbbell-extension.html"], equipment="dumbbell"),
    "hack_squat": correction("등과 어깨 패드 지지가 빠지고 일정 깊이까지 하강하도록 강제했습니다.",
        "등·양어깨 패드 지지와 편안한 깊이, 발바닥 전체 지지를 명시했습니다.",
        "Fortis 공식 매뉴얼 PDF 25쪽의 패드와 슬래드 수행 설명을 대조했습니다. 브랜드 형상과 보편적 깊이는 복제하지 않습니다.",
        "9e33935d38006520055fddecb2ef2afe0913ee193a45c91947bb9829d6833319",
        [FORTIS_MANUAL + "#page=25"], equipment="machine"),
    "rack_pull": correction("안전 받침에 하중을 내려놓는 멈춤이 없고 끝에서 뒤로 젖히는 동작으로 읽힐 수 있었습니다.",
        "무릎 높이 받침·오버핸드·똑바로 서기·받침에 내려놓고 멈춤으로 정정했습니다.",
        "NSCA PTQ 8.3 인쇄 6쪽의 랙 풀 설명과 선택한 오버핸드 변형을 대조했습니다.",
        "78b5986b66f54be4512b8de1c41260bcf09906a7f722391a4f9339f7194397a1", [RACK_PULL_PAPER + "#page=3"]),
    "upright_row": correction("팔꿈치를 앞으로 향하게 하고 턱까지 당기도록 설명했습니다.",
        "팔꿈치를 옆으로 보내며 몸 가까이 당기고, 위팔이 어깨 높이를 넘기 전에 멈추는 변형으로 정정했습니다.",
        "Schoenfeld 등의 원논문 technique modifications를 읽었습니다. 선택한 가동 범위는 개인별 검수를 대신하지 않습니다.",
        "b82d67d4b99fc0c5f900c007d1689b5b6f52975ceeebae450921b0ca20bbab6d", [UPRIGHT_ROW_PAPER]),
    "assisted_pullup": correction("무릎 보조 패드가 없어 일반 매달리기와 구분되지 않았습니다.",
        "움직이는 무릎 패드 지지와 보조 무게의 의미를 명시하고 기구를 machine으로 교정했습니다.",
        "Life Fitness 매뉴얼 인쇄 11쪽의 보조 패드와 수행 경로를 대조했습니다. 오버핸드 그립은 선택 변형입니다.",
        "a7465ffbec907297a5fccf30ce75a7e3b375db9a8a47339aa67c08da5b10e349", [INSIGNIA_MANUAL + "#page=13"], equipment="machine"),
    "pec_deck": correction("손바닥이 아래라는 설명이 선택한 세로 손잡이와 달랐습니다.",
        "세로 손잡이 중립 그립과 어깨보다 약간 낮은 팔꿈치를 명시했습니다.",
        "Life Fitness 매뉴얼 인쇄 28쪽의 펙덱 설정을 대조했습니다. 기구 형상은 자체 제작입니다.",
        "f131094ca39873b1dd0318061b746b16e988a09a13a9dbd642d7e77c9ef2b705", [INSIGNIA_MANUAL + "#page=30"], equipment="machine"),
    "reverse_pec_deck": correction("손바닥을 위로 돌리는 설명이 원본 중립 그립과 달랐습니다.",
        "엄지가 위인 세로 손잡이와 가슴 지지·몸통 옆 끝점을 명시했습니다.",
        "Schoenfeld 등의 원논문 2647쪽 중립 그립 동작 설명을 읽었습니다. 제조사 형상을 복제하지 않았습니다.",
        "091d33441ee25832469a98e9beabc04fdab006f0734485db56c65e257a2eb050", [REVERSE_FLY_PAPER + "#page=4"], equipment="machine"),
    "ab_wheel": correction("완전한 몸통 신전을 모두에게 강제하는 설명이었습니다.",
        "허리 처짐 없이 제어 가능한 가동 범위를 선택하도록 수정했습니다.",
        "NSCA의 무릎 지지 휠 롤아웃과 몸통 안정화 기준을 읽고, 편안한 범위는 자체 제작 제약으로 명시했습니다.",
        "546465e372bbf3197dd462bd22d26e18fa94121c43becf5b80faa115e3271419", [EXACT_SPECS["ab_wheel"]["references"][0]["url"]]),
    "cable_crunch": correction("머신을 등지고 머리 뒤 로프를 당기는 설명이 선택한 무릎 크런치와 달랐습니다.",
        "머신을 바라보는 무릎 지지·머리 양옆 손목·몸통 굽힘으로 수정했습니다.",
        "ACE Certified News 2009년 8/9월 인쇄 10쪽의 Kneeling Crunches 수행 설명과 대조했습니다.",
        "610b5b93d70d00281e6b4813c7ef35985db7f1f66c41b3329607fa0ebd94aa31", [CERTIFIED_2009 + "#page=10"]),
    "cable_fly": correction("오버핸드이면서 손바닥은 앞을 향한다는 설명이 플라이의 선택 중립 그립과 달랐습니다.",
        "손바닥이 서로 마주보는 중립 그립과 중립 손목으로 수정했습니다.",
        "NASM Cable Crossover의 중립 그립 공통 cue를 읽었습니다. 가슴 높이에서 손이 만나는 자체 플라이는 교차 경로와 별개이며 exact 전체 사양을 승인한 것은 아닙니다.",
        "ece7a942ed0a10bd825af254e0830e38e37e0629a3e43afa35a71a70ff91b390", ["https://www.nasm.org/resource-center/exercise-library/cable-crossover"]),
    "cable_lateral_raise": correction("풀리 위치가 없고 팔꿈치를 완전히 펴도록 강제했습니다.",
        "낮은 풀리·반대 골반 시작·약간 굽힌 팔꿈치 유지·어깨 높이 끝점을 명시했습니다.",
        "ACE Certified News 2009년 8/9월 인쇄 9쪽의 편측 케이블 레이즈 수행 설명과 대조했습니다.",
        "40e258ce5f34de4a9500288e727b798db1004cfce13ddd1b123c71aacc7413a6", [CERTIFIED_2009 + "#page=9"]),
    "chest_press": correction("시작 팔꿈치 90도와 끝 잠금으로 읽힐 수 있는 표현을 강제했습니다.",
        "가슴 중간 손잡이·등과 발 지지·중립 손목·팔꿈치 비잠금과 편안한 시작점을 명시했습니다.",
        "ACE 188의 머신 체스트 프레스 설정과 수행 설명을 직접 대조했습니다.",
        "4a113346ef2e910507225ef8aeadb2be34ee20548876aec8302cc7d028fb58a1", [ACE + "188/seated-chest-press/"]),
    "row": correction("손 방향과 아래 가슴 목표가 선택한 오버핸드 복부 로우와 맞지 않았습니다.",
        "오버핸드·중립 손목·고정 힙 힌지·배꼽 방향 당기기의 5단계를 다시 작성했습니다.",
        "ACE Bent-over Row의 수행 설명과 선택 변형을 대조했습니다.",
        "a24ae4c911ad840249678b8012c77b13eef1ae16d43dfaac4b57b740c13f09b8", [ACE + "12/bent-over-row/"]),
    "plank": correction("기존 설명은 팔을 들고 회전하는 하이 플랭크 변형이었습니다.",
        "팔꿈치 지지·몸통 정렬·정적 유지와 호흡의 3단계를 다시 작성했습니다.",
        "ACE Front Plank와 앱의 정적 유지 변형을 대조했습니다.",
        "c8250f8565e52c33d601f1afe68851d1916a154186842798155a74e523f23b2b", [ACE + "32/front-plank/"]),
    "walking_lunge": correction("뒤로 물러나 제자리로 돌아오는 런지를 설명했습니다.",
        "양손 덤벨을 들고 한 발씩 앞으로 내디디며 전진하는 설명으로 교체했습니다.",
        "워킹 런지로 선택한 전진 경로와 현재 5단계 텍스트를 확인했습니다. exact 원본 sourceId는 없습니다.",
        "0b80b5febda870e6eb800136a5fb169d6e42a3e51f2ed66063aa258dc895f243"),
    "brisk_walk": correction("평지 빠른 걷기가 아니라 스텝밀 머신 사용을 설명했습니다.",
        "평평한 길에서 편한 보폭으로 빠르게 걷는 4단계로 교체했습니다.",
        "평지 빠른 걷기라는 현재 선택과 텍스트를 확인했습니다. exact 원본이나 공식 동작 사양이 추가된 것은 아닙니다.",
        "eef5b9e48836b3d39ddf6de893d4216969fa1dc3339c9f3d879b9c0f5c4ff754"),
    "rear_delt_raise": correction("한 바벨을 양옆으로 벌리는 불가능한 경로를 설명했습니다.",
        "양손 덤벨·고정 힙 힌지·약간 굽힌 팔꿈치로 양옆을 여는 변형으로 교체했습니다.",
        "독립된 덤벨의 경로와 현재 텍스트를 대조했습니다. 선택 변형의 트레이너 검수는 남아 있습니다.",
        "bf6f2802bf444af047a9d7cf11bc0ea2a412ef7fdb18efb42a27198ff563be6b"),
    "hammer_curl": correction("손바닥을 정면으로 회전하는 설명이 중립 그립과 달랐습니다.",
        "손바닥이 서로 마주보는 그립과 손목·전완 정렬을 유지하도록 수정했습니다.",
        "ACE Hammer Curl의 중립 그립 유지 설명과 대조했습니다.",
        "efdee77f8b5c47e49967e2a3b1a1247b0b4bad71c4ede6df19d20869375fc63c", [ACE + "10/hammer-curl/"]),
    "tbar_row": correction("시티드 가슴 패드 머신 설명이 exact sourceId의 랜드마인 변형과 달랐습니다.",
        "바벨 한쪽을 고정하고 다리 사이의 T바 손잡이를 복부로 당기는 설명으로 교체했습니다.",
        "정확한 T-Bar_Row_with_Handle 원본 텍스트와 catalog 바벨 기구를 대조했습니다.",
        "106b26672645d3663d5526ea8c48cca5c0f67a98fb6115f08e5c87c1ea246dc1", [UPSTREAM + "exercises/T-Bar_Row_with_Handle.json"]),
    "run": correction("트레드밀 대신 제자리 무릎 높이 들기를 설명했습니다.",
        "비상 정지 클립·벨트 위 러닝·감속 후 하차의 4단계로 교체했습니다.",
        "Running_Treadmill이라는 exact 원본과 기구를 대조했습니다. 세부 안내는 Setflow가 수정했습니다.",
        "8ff3e8b194f18133cf3c7938db8798752c6b6f4e6c3271f177d2affd0f5b3603", [UPSTREAM + "exercises/Running_Treadmill.json"]),
    "goblet_squat": correction("덤벨 설명이 catalog와 exact 원본의 케틀벨과 달랐습니다.",
        "케틀벨 손잡이 양옆을 가슴 앞에서 잡도록 수정했고 catalog 기구를 일치시켰습니다.",
        "Goblet_Squat 원본의 케틀벨 선택과 대조했습니다.",
        "9b08e7668275596ebc3583f7ac1d3da07b2b7a75569f75479c8abb06959837d4", [UPSTREAM + "exercises/Goblet_Squat.json"], equipment="kettlebell"),
    "bulgarian_split_squat": correction("앞무릎이 지면과 평행이라는 표현이 관절과 허벅지를 혼동했습니다.",
        "앞 허벅지가 수평에 가까워지는 편한 깊이와 앞발 전체 지지로 수정했습니다.",
        "현재 양손 덤벨·뒤발 벤치 지지 변형의 해부학적 표현을 바로잡았습니다. ACE의 한 덤벨 변형으로 대체하지 않았습니다.",
        "22065f6bdea534fb8c92b4c5c1b38095067a80ca1cd7cb88fb70c0c0e15ea0f2"),
    "bench_dip": correction("catalog dip_bars는 bench로 이미 정정했지만 단계가 현재 굽힌 무릎·양발 바닥·가까운 엉덩이 지지를 누락했습니다.",
        "벤치 기구 교정을 유지하고, 양발 바닥·굽힌 무릎·벤치 가까운 엉덩이 및 뒤로 굽히는 팔꿈치를 명시했습니다.",
        "NASM Bench Dips 본문과 굽힌 무릎 FAQ를 읽었습니다. 가까운 엉덩이는 시안의 고정 지지 선택이며 몸통을 안정시킨 채 조절 가능한 깊이를 사용합니다.",
        "d43e34eef62c32e605d6a95b558f9d2a18a828ce69465cb775ad111ece3a0662", ["https://www.nasm.org/resource-center/exercise-library/bench-dips"], equipment="bench"),
    "hanging_leg_raise": correction("catalog body_only가 매달릴 바의 필요를 누락했습니다.",
        "catalog equipmentKey를 pullup_bar로 교정했습니다. 단계 텍스트는 재작성하지 않았습니다.",
        "Hanging_Leg_Raise 원본과 매달리기 가이드의 지지 기구를 대조했습니다.",
        "05c49ac35b82fbe78a5228d134a596b6e70fa0a5d89925fede3de95b6e46b147", [UPSTREAM + "exercises/Hanging_Leg_Raise.json"], scope="catalog_metadata", equipment="pullup_bar"),
    "leg_raise": correction("catalog body_only가 플랫 벤치 지지 변형과 달랐습니다.",
        "catalog equipmentKey를 bench로 교정했습니다. 단계 텍스트는 재작성하지 않았습니다.",
        "Flat_Bench_Lying_Leg_Raise exact 원본과 가이드의 벤치 지지를 대조했습니다.",
        "941dcb908153a53f7995ced487436f12c8c3caf3e039a218e9ae9a87920dd61b", [UPSTREAM + "exercises/Flat_Bench_Lying_Leg_Raise.json"], scope="catalog_metadata", equipment="bench"),
    "leg_curl": correction("뒤꿈치 패드와 발을 들어올리지 말라는 문구가 실제 하단 종아리 패드 경로와 달랐습니다.",
        "무릎 회전축·발목 위 종아리 패드·골반 지지·무릎 굽힘으로 수정했습니다.",
        "Lying_Leg_Curls 원본과 ACE Lying Hamstrings Curl의 접촉·골반 제어 설명을 대조했습니다.",
        "02b5d24018e5eba01ebb2352bc71774b23556e3d5507320841970199cec18a6d", [UPSTREAM + "exercises/Lying_Leg_Curls.json", ACE + "153/lying-hamstrings-curl/"]),
    "leg_extension": correction("발을 풋패드 위에 놓는 설명이 하단 정강이 롤러 접촉과 달랐습니다.",
        "무릎 회전축·발목 바로 위 정강이 패드·등과 엉덩이 지지로 수정했습니다.",
        "Leg_Extensions exact 원본 텍스트의 접촉 위치와 대조했습니다. 본문이 비었던 ACE 183을 수행 근거로 주장하지 않습니다.",
        "a254891854d8e4abf536e93a284f73000acea349e4e68856bae0b059140e925b", [UPSTREAM + "exercises/Leg_Extensions.json"]),
    "seated_calf_raise": correction("약간 굽힌 무릎·평평한 발 설명이 앉은 허벅지 패드와 앞발 지지를 누락했습니다.",
        "앉은 무릎·무릎 위 허벅지 패드·앞발 지지와 뒤꿈치 자유 공간을 명시했습니다.",
        "Seated_Calf_Raise exact 원본의 패드와 발판 접촉을 대조했습니다.",
        "9b18edb9ba79f97cb8ae631c4a8259bbadea8947c22c995df220209cb8b37e38", [UPSTREAM + "exercises/Seated_Calf_Raise.json"]),
    "ohp": correction("이전 사양과 설명은 앉은 바벨 프레스였지만 이번 제작 동작은 서서 하는 프레스입니다.",
        "넓은 종목명 ohp의 선택을 strict standing barbell overhead press로 고정하고 앉은 설명을 대체했습니다.",
        "ACE 71의 서서 하는 바벨 설정·몸통·경로를 확인했습니다. 중립 손목과 다리 반동 없음은 Setflow의 선택 제약입니다.",
        "690964cf92fb26c4726694e15774c767e2f1ac364c624321714b52f3b34722ae", [ACE + "71/standing-shoulder-press/"]),
    "one_arm_dumbbell_row": correction("기존 가이드는 벤치 없는 선 자세로, 제작한 벤치 지지 변형과 달랐습니다.",
        "왼손·왼무릎 벤치 지지와 오른발 바닥 지지, 오른팔 당기기·몸통 회전 금지로 다시 작성했습니다.",
        "ACE 126 Single-arm Row의 지지점·몸통 정렬·팔 경로와 대조했습니다. 영상은 오른팔 시범이며 반대쪽 반복은 텍스트에 안내합니다.",
        "37634aae8caa637063fef091a83309ff9c64046d8eb55a475f667e89a3c9348e", [ACE + "126/single-arm-row/"]),
    "close_grip_bench": correction("기존 설명은 어깨보다 좁은 그립을 강제해 선택한 어깨선 그립과 달랐습니다.",
        "손을 어깨선에 놓고, 팔꿈치를 몸 가까이 두며 발바닥과 엉덩이 지지를 유지하도록 수정했습니다.",
        "ACE 311 Close-grip Bench Press의 손 위치·팔꿈치 경로·발과 엉덩이 지지를 대조했습니다.",
        "ba8e0795b0ad1acc1a4b680a54cf11a4000887d2e0e336fdb7424efd025c4c55", [ACE + "311/close-grip-bench-press/"]),
    "arnold_press": correction("손목만 돌리라는 표현은 위팔과 전완이 함께 회전하는 아놀드 프레스 경로를 누락했습니다.",
        "위팔·전완의 바깥 회전과 프레스를 함께 설명하고 기존 앉은 등받이 변형을 유지했습니다.",
        "ACE 6467의 Arnold Press 문단에서 팔 회전과 프레스 순서를 확인했습니다. 해당 문단이 앉은 등받이 설정까지 승인하는 것은 아닙니다.",
        "967121827ba436f1d7279408e059655a6384e014bfae4b68bca6349cbcc1bdbb", ["https://www.acefitness.org/resources/pros/expert-articles/6467/fast-and-efficient-upper-body-training/"]),
    "front_squat": correction("이전 단계는 앞어깨 지지와 팔꿈치 높이를 누락했고 초기 제작 제안은 교차 팔 랙이었습니다.",
        "어깨 바깥 그립·앞으로 높은 팔꿈치·수평 위팔·앞어깨 바벨 지지의 클린 프런트 랙을 명시하고, 뒤꿈치에만 힘을 싣는 표현을 발바닥 전체 지지로 교체했습니다.",
        "NSCA Coach 10.1 Table 2, 인쇄 10쪽의 클린 그립·전면 지지·평평한 발바닥 및 발 중앙 힘선 기준과 대조했습니다. 특정 손목 각도를 모두에게 강제하지 않습니다.",
        "a06d1f055ff13033a0547f2200dd6e089d2ce744840736125937b9a60b1ab89b", ["https://www.nsca.com/globalassets/education/nsca-coach/nsca-coach-10.1.pdf#page=10"]),
}

# Newly written guides have no imported MIT wording to attribute. References
# distinguish common support cues from the selected loaded/arm-position variant.
SETFLOW_AUTHORED_GUIDES = {
    "bodyweight_squat": {"source": "Setflow-authored Korean steps from ACE Bodyweight Squat for the exact unloaded bilateral clip; not substituted back-squat wording",
                         "references": copy.deepcopy(EXACT_SPECS["bodyweight_squat"]["references"])},
    "reverse_fly": {"source": "Setflow-authored Korean steps for the selected standing neutral-grip bent-over dumbbell fly from the publisher's primary exercise instructions; not Mayo seated or upstream incline-bench wording",
                    "references": copy.deepcopy(EXACT_SPECS["reverse_fly"]["references"])},
    "seated_cable_row": {"source": "Setflow-authored Korean steps selecting the ACE 2009 straight-bar and bench options; pronated shoulder-width grip and footrests explicitly selected by Setflow, not specified by ACE or copied from the upstream V-bar guide",
                         "references": copy.deepcopy(EXACT_SPECS["seated_cable_row"]["references"])},
    "rowing_machine": {"source": "Setflow-authored Korean steps from Concept2's rowing stroke sequence; not imported dataset wording",
                       "references": copy.deepcopy(EXACT_SPECS["rowing_machine"]["references"])},
    "burpee": {"source": "Setflow-authored Korean steps for the NASM push-up and vertical-jump burpee; not imported dataset wording",
               "references": copy.deepcopy(EXACT_SPECS["burpee"]["references"])},
    "bird_dog": {"source": "Setflow-authored Korean text based on ACE Bird-dog; not imported dataset wording",
                 "references": [reference("14/bird-dog", "Bird-dog")]},
    "hip_thrust": {"source": "Setflow-authored Korean text for the selected barbell bench-supported hip thrust; ACE support cues and NSCA background are distinct from exact barbell certification",
                   "references": [reference("367/elevated-glute-bridge", "Elevated Glute Bridge", "upper_back_bench_and_foot_support_common_cues; ACE uses dumbbells"),
                                  {"url": "https://www.nsca.com/education/articles/ptq/program-design-strength-hypertrophy-glute/",
                                   "publisher": "NSCA", "title": "Glute strength and hypertrophy program design",
                                   "checkedDate": "2026-10-06", "scope": "background_article; exact barbell instructions not available in public summary",
                                   "verifiedBy": "Public article summary checked; no full-text or trainer approval implied"}]},
    "side_plank": {"source": "Setflow-authored Korean text based on NASM Side Plank, selecting staggered feet and an elevated top arm; not imported dataset wording",
                   "references": [copy.deepcopy(EXACT_SPECS["side_plank"]["references"][0])]},
    "face_pull": {"source": "Setflow-authored Korean text based on NASM Face Pull for standing eye-level cable rope pulls; not imported dataset wording",
                  "references": [{"url": "https://www.nasm.org/resource-center/exercise-library/face-pull",
                                  "publisher": "NASM", "title": "Face Pull", "checkedDate": "2026-10-06",
                                  "scope": "standing_eye_level_rope_setup_and_pull_path",
                                  "verifiedBy": "Official exercise text read; not trainer approval"}]},
    "wall_sit": {"source": "Setflow-authored Korean text based on NASM Wall Sits for a bilateral wall-supported static hold; not imported dataset wording",
                 "references": [{"url": "https://www.nasm.org/resource-center/blog/training/wall-sits",
                                 "publisher": "NASM", "title": "Wall Sits", "checkedDate": "2026-10-06",
                                 "scope": "bilateral_wall_supported_static_hold; depth_selected_for_control",
                                 "verifiedBy": "Official article text read; not trainer approval"}]},
    "mountain_climber": {"source": "Setflow-authored Korean text based on ACE Mountain Climbers for fixed-hand alternating leg switches; not imported dataset wording",
                         "references": [{**reference("258/mountain-climbers", "Mountain Climbers"),
                                         "checkedDate": "2026-10-06"}]},
}


def upstream_guide_reference(source_id, title):
    """A first-party text record, never an expert verification or media license."""
    return {"url": UPSTREAM + "exercises/" + source_id + ".json", "title": title,
            "publisher": "yuhonas/free-exercise-db", "sourceId": source_id, "commit": REVISION,
            "checkedDate": "2026-10-06", "scope": "exact_upstream_text_only; not_official_expert_instructions",
            "verifiedBy": "Pinned original text read and selected variant compared; not trainer approval"}


# Eight reviewed literal UUIDs only. A similar name/source ID never inherits a
# guide or motion. The source/selection difference is retained in every record.
SHARED_AUTHORED_GUIDES = {
    "bff7dff4-2b99-5357-b365-f10e1187cbb3": {
        "source": "Setflow-authored Korean forward-lunge-to-standing steps from exact Dumbbell_Lunges text and ACE 94 movement cues; not walking-lunge substitution or imported MIT translation",
        "references": [upstream_guide_reference("Dumbbell_Lunges", "Dumbbell Lunges"),
                       {**reference("94/forward-lunge", "Forward Lunge", "forward_step_and_return_to_standing; ACE unloaded, Setflow exact dumbbell selection"), "checkedDate": "2026-10-06"}]},
    "d1ecb818-0235-5e2f-9113-39be506aa98a": {
        "source": "Setflow-authored Korean steps for exact Dumbbell_Rear_Lunge returning to standing; pinned upstream text is not an official expert verification. Arbitrary fixed stride, knees-behind-toes and heel-only claims are not adopted",
        "references": [upstream_guide_reference("Dumbbell_Rear_Lunge", "Dumbbell Rear Lunge")]},
    "823846f5-2414-58b7-911e-2d9397a28f49": {
        "source": "Setflow-authored Korean lead-foot-supported step-up steps from exact Dumbbell_Step_Ups and NSCA support cues; clip starts with leading foot on platform. ACE trailing-leg push-off is not adopted as this clip's propulsion cue",
        "references": [upstream_guide_reference("Dumbbell_Step_Ups", "Dumbbell Step Ups"),
                       publisher_reference(NSCA + "#page=18", "TSAC Module 3.2-5 — Step-Up", "printed_module_page18_leading_foot_support_and_trailing_leg_first_descent; model_platform_height_not_universal", "NSCA"),
                       {**reference("28/step-up", "Step-up", "foot_alignment_and_downward_order_only; trailing_leg_push_off_not_selected"), "checkedDate": "2026-10-06"}]},
    "0f177240-029b-543a-be27-2e8ed0526bca": {
        "source": "Setflow-authored Korean steps for the exact rear-foot-elevated Split_Squat_with_Dumbbells source and NASM bilateral dumbbell option; not inferred from the broad split-squat name",
        "references": [upstream_guide_reference("Split_Squat_with_Dumbbells", "Split Squat with Dumbbells"),
                       publisher_reference("https://www.nasm.org/resource-center/exercise-library/bulgarian-split-squat", "Bulgarian Split Squat", "rear_foot_bench_and_two_dumbbell_option", "NASM")]},
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb": {
        "source": "Setflow-authored Korean steps for exact wide-stance Sumo_Deadlift with double-overhand hands inside legs; no exaggerated lean-back or mixed-grip substitution",
        "references": [upstream_guide_reference("Sumo_Deadlift", "Sumo Deadlift"),
                       publisher_reference("https://www.nsca.com/education/articles/tsac-report/the-deadlift-and-its-application-to-overall-performance/", "The Deadlift and Its Application to Overall Performance", "sumo_knee_tracking_and_close_bar_cues; other_setup_from_exact_source_and_selected_native", "NSCA")]},
    "58acf002-4e6d-5e95-b252-cae16252cef8": {
        "source": "Setflow-authored Korean steps for exact Stiff-Legged_Barbell_Deadlift and NSCA slight fixed knee flexion; not knee hard lock or an interchangeable Romanian-deadlift binding",
        "references": [upstream_guide_reference("Stiff-Legged_Barbell_Deadlift", "Stiff-Legged Barbell Deadlift"),
                       publisher_reference(NSCA + "#page=18", "TSAC Module 3.2-5 — Deadlift/Stiff-Leg Deadlift", "printed_module_page18_slight_knee_flexion_neutral_spine_closed_grip", "NSCA")]},
    "3c358477-aeb3-5d78-a6aa-91c9fb6c81db": {
        "source": "Setflow-authored Korean steps from ACE Chin-ups for the exact supinated non-kipping clip; not pronated pull-up wording",
        "references": [{**reference("190/chin-ups", "Chin-ups"), "checkedDate": "2026-10-06"}]},
    "dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe": {
        "source": "Setflow-authored Korean upright triceps-dip steps from exact Dips_-_Triceps_Version original text; this first-party text record is not official expert verification. Comfortable depth and no hard locking are explicit selected constraints",
        "references": [upstream_guide_reference("Dips_-_Triceps_Version", "Dips - Triceps Version")]},
}
SETFLOW_AUTHORED_GUIDES.update(SHARED_AUTHORED_GUIDES)

GUIDE_CORRECTIONS.update({
    "bodyweight_squat": correction("정확한 맨몸 영상이 있어도 한국어 단계는 과거 미확인 상태에서 비워 두었습니다.",
        "ACE 135 원문을 직접 확인하고 맨몸 양발 지지·힙과 무릎 굽힘·안정된 범위·함께 올라오기를 직접 작성했습니다.",
        "기존 barbell squat 가이드를 이름으로 대체 연결하지 않았습니다. ACE 135 본문과 exact unloaded 제작 사양을 대조했습니다.",
        "332ee7fa7fbec4d7a686cfcd64d60c38d126dd5316ba18f2f4ced1c7a9408365", [ACE + "135/bodyweight-squat/"]),
    "bff7dff4-2b99-5357-b365-f10e1187cbb3": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "앞으로 내딛고 서 있는 제자리로 돌아오는 양손 덤벨 런지를 직접 작성했습니다.",
        "Exact Dumbbell_Lunges의 기구·제자리 복귀와 ACE 94 전진 런지 본문을 대조했습니다. 원본의 무조건 무릎-발끝 제한은 채택하지 않았습니다.",
        "c7cac598e06d40d87c08a6a3b22be47178972aa4e043d7177210d0255cd42da7", [UPSTREAM + "exercises/Dumbbell_Lunges.json", ACE + "94/forward-lunge/"]),
    "d1ecb818-0235-5e2f-9113-39be506aa98a": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "뒤로 내딛고 앞발 지지로 일어나 제자리로 돌아오는 덤벨 런지를 직접 작성했습니다.",
        "Exact Dumbbell_Rear_Lunge 본문과 현재 후진 시안을 대조했습니다. 공식 전문가 검수로 표시하지 않습니다.",
        "9c35f549aa128aca1b283ff20753e39ea88c8d970a1f4746a4afad550dca6dd7", [UPSTREAM + "exercises/Dumbbell_Rear_Lunge.json"]),
    "823846f5-2414-58b7-911e-2d9397a28f49": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "앞발 전체를 플랫폼에 두고 시작하여 앞다리로 올라서고 반대 발부터 내려오는 덤벨 스텝업을 작성했습니다.",
        "Exact Dumbbell_Step_Ups와 NSCA module Step-Up의 앞발 지지·뒷다리 반동 오류를 대조했습니다. ACE 28의 뒷발 밀기는 현재 선택 경로로 채택하지 않았습니다.",
        "4198becc7fe98def96ecccb223dd118126c503c35367bd3cbf6f145bfe9a9428", [UPSTREAM + "exercises/Dumbbell_Step_Ups.json", NSCA + "#page=18", ACE + "28/step-up/"]),
    "0f177240-029b-543a-be27-2e8ed0526bca": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "양손 덤벨·뒷발 벤치 지지·앞발 바닥 지지 스플릿 스쿼트를 직접 작성했습니다.",
        "Exact Split_Squat_with_Dumbbells가 뒷발을 높이는 원본임을 직접 확인하고 NASM의 벤치·양손 덤벨 선택지를 대조했습니다.",
        "378e50566b89520b86bf583a5d3c67353bc5d5e8f0a75f2afd748e83dbdec121", [UPSTREAM + "exercises/Split_Squat_with_Dumbbells.json", "https://www.nasm.org/resource-center/exercise-library/bulgarian-split-squat"]),
    "896189fc-30d9-51df-aa19-fd5ea7fa76eb": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "넓은 발·발끝과 같은 무릎 방향·무릎 안쪽 양손 오버핸드 그립 스모 데드리프트를 직접 작성했습니다.",
        "Exact Sumo_Deadlift와 NSCA의 바 가까운 경로·무릎 바깥 추적 본문을 대조했습니다. 원본의 과장된 뒤로 젖히기는 채택하지 않았습니다.",
        "c0bd2d9065648519c203764e9943cbfb4a33d5c6e072fd73d0d606301750691c", [UPSTREAM + "exercises/Sumo_Deadlift.json", "https://www.nsca.com/education/articles/tsac-report/the-deadlift-and-its-application-to-overall-performance/"]),
    "58acf002-4e6d-5e95-b252-cae16252cef8": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "무릎을 작게 굽힌 채 유지하는 스티프레그 바벨 힌지를 작성하고 억지 무릎 잠금을 금지했습니다.",
        "Exact Stiff-Legged_Barbell_Deadlift와 NSCA module의 slight knee flexion·neutral spine을 대조했습니다. RDL과 같은 종목으로 대신 연결하지 않았습니다.",
        "70bf5bc6aa36b0dbeb489ed17d51f92da73336984c621390e9160a045ce15998", [UPSTREAM + "exercises/Stiff-Legged_Barbell_Deadlift.json", NSCA + "#page=18"]),
    "3c358477-aeb3-5d78-a6aa-91c9fb6c81db": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "얼굴을 향하는 언더핸드 친업·반동 없는 당김·조절된 내려오기를 직접 작성했습니다.",
        "ACE 190의 supinated grip·neutral wrist·elbows down·bar-height chin 원문을 대조했습니다.",
        "3af9193dfbccb36eb8db807415997ca352d693f698451e041092c745297b4ab9", [ACE + "190/chin-ups/"]),
    "dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe": correction("공유 UUID에 한국어 수행 단계가 없었습니다.",
        "직립 상체·가까운 팔꿈치의 트라이셉스 평행봉 딥스를 직접 작성했습니다.",
        "Exact Dips_-_Triceps_Version의 torso upright·elbows close·약 직각 범위와 현재 시안을 대조했습니다. 공식 전문가 검수로 표시하지 않습니다.",
        "f8a3a7e8f55e43f828c2d5ce91dfcc1b151bc47105e235043b4b73e4a7511214", [UPSTREAM + "exercises/Dips_-_Triceps_Version.json"]),
})


def guide_steps_sha256(steps):
    return sha256(json.dumps(steps, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


def guide_corrections(exercise_id, steps, original):
    record = GUIDE_CORRECTIONS.get(exercise_id)
    if record is None:
        return [], []
    record = copy.deepcopy(record)
    guide_matches = guide_steps_sha256(steps) == record["verifiedGuideStepsSha256"]
    expected_equipment = record["expectedCatalogEquipmentKey"]
    equipment_matches = expected_equipment is None or original.get("equipmentKey") == expected_equipment
    record["inputGuideMatchesRecordedCorrection"] = guide_matches
    record["inputEquipmentMatchesRecordedCorrection"] = equipment_matches
    record["status"] = "implemented_in_current_inputs" if guide_matches and equipment_matches else "needs_recheck"
    flags = [] if record["status"] == "implemented_in_current_inputs" else [
        "교정 이력 이후 현재 가이드 또는 기구가 변경되었습니다. 이력의 입력 해시·기구와 다시 대조해야 합니다."]
    return [record], flags
REFERENCE_NOTES = {
    "calf_raise": "ACE 294 Calf Raise는 앉아서 다리를 편 머신 변형이므로 어깨 패드 스탠딩 머신에 대체 적용하지 않았습니다.",
    "leg_extension": "ACE 183 Seated Leg Extension 페이지는 확인 시 단계 본문이 비어 있어 수행 근거로 승인하지 않았습니다.",
    "skull_crusher": "ACE 36은 일반 바벨이고 catalog exact 원본은 EZ바입니다. 손목/그립 차이를 확인해야 합니다.",
    "seated_cable_row": "현재 선택은 회내 직바입니다. ACE 2009의 straight bar·bench 옵션을 근거로 삼고, ACE 48 narrow handle 및 upstream V핸들 텍스트는 별도 변형으로 보존합니다. 회내 그립·발판은 Setflow 선택이며 ACE가 그립을 지정한 것으로 주장하지 않습니다.",
    "reverse_fly": "현재 선택은 서서 하는 중립 그립 덤벨 변형이며 Muscle & Strength의 1차 수행 설명과 대조했습니다. Mayo의 앉은 변형·upstream 인클라인 벤치 텍스트와 과거 검토 보고서는 별도로 보존합니다.",
    "bulgarian_split_squat": "ACE 366은 한 덤벨을 가슴 앞에 드는 변형으로 현재 양손 덤벨 guide에 자동 대체하지 않았습니다.",
    "glute_bridge": "일반 이름에서 임의로 맨몸/힙쓰러스트를 추론하지 않고 현 가이드의 바벨 바닥 브리지 변형을 명시했습니다.",
    "overhead_triceps_extension": "현 가이드는 서서 한 손 덤벨입니다. 양손 1덤벨 Standing_Dumbbell_Triceps_Extension이나 앉은 양손 Seated_Triceps_Press로 자동 대체하지 않았습니다.",
}


def parse_guides(text):
    guides = {}
    pattern = r"^  '([^']+)': \[(.*?)^  \],"
    for match in re.finditer(pattern, text, re.MULTILINE | re.DOTALL):
        # Ignore comments before reading string literals, so quoted comments
        # cannot silently become movement steps.
        block = re.sub(r"^\s*//.*$", "", match[2], flags=re.MULTILINE)
        guides[match[1]] = [ast.literal_eval(item[0]) for item in
                            re.finditer(r"'(?:\\.|[^'\\])*'", block)]
    return guides


def text_snapshot(raw, license_raw):
    if sha256(raw) != DATA_SHA256 or sha256(license_raw) != LICENSE_SHA256:
        raise ValueError("Pinned source/license SHA256 mismatch; refuse unreviewed source drift")
    rows = json.loads(raw)
    ids = [row["id"] for row in rows]
    if len(rows) != 876 or len(ids) != len(set(ids)):
        raise ValueError("Expected 876 unique pinned text-source IDs")
    return {"repository": "https://github.com/yuhonas/free-exercise-db",
            "commit": REVISION,
            "commitUrl": "https://github.com/yuhonas/free-exercise-db/commit/" + REVISION,
            "datasetUrl": UPSTREAM + "dist/exercises.json", "rawDatasetSha256": DATA_SHA256,
            "licenseUrl": UPSTREAM + "LICENSE.md", "licenseSha256": LICENSE_SHA256,
            "license": "Unlicense / public domain", "licenseText": license_raw.decode("utf-8"),
            "rowCount": len(rows), "mediaFetched": False, "mediaFieldsIncluded": False,
            "rows": [{key: row.get(key) for key in TEXT_FIELDS} for row in rows]}


def fetch_snapshot():
    def read(path):
        request = Request(UPSTREAM + path, headers={"User-Agent": "Setflow-production-specs/1.0"})
        with urlopen(request, timeout=30) as response:
            return response.read()
    return text_snapshot(read("dist/exercises.json"), read("LICENSE.md"))


def checked_snapshot(snapshot):
    if snapshot.get("commit") != REVISION or snapshot.get("rawDatasetSha256") != DATA_SHA256:
        raise ValueError("Embedded snapshot is not the pinned app catalog source")
    if snapshot.get("licenseSha256") != LICENSE_SHA256:
        raise ValueError("Embedded license provenance mismatch")
    rows = snapshot.get("rows", [])
    if len(rows) != 876 or len({r["id"] for r in rows}) != 876:
        raise ValueError("Embedded text snapshot must contain 876 unique IDs")
    if any(set(row) - set(TEXT_FIELDS) for row in rows):
        raise ValueError("Embedded snapshot contains unexpected/media fields")
    return snapshot


def group_for(origins):
    if "curated" in origins:
        return "curated"
    if "bodyweight-offline" in origins:
        return "bodyweight-offline"
    if "manufacturer" in origins:
        return "manufacturer"
    return "shared-only"


def build_specs(catalog, guides, snapshot, input_hashes):
    source_by_id = {row["id"]: row for row in checked_snapshot(snapshot)["rows"]}
    exercise_ids = [row["exerciseId"] for row in catalog["exercises"]]
    if len(set(exercise_ids)) != len(exercise_ids):
        raise ValueError("Catalog contains duplicate exact exercise IDs")
    rows = []
    for original in catalog["exercises"]:
        exercise_id = original["exerciseId"]
        source = source_by_id.get(original.get("sourceId")) if original.get("sourceName") == "free-exercise-db" else None
        selected = copy.deepcopy(EXACT_SPECS.get(exercise_id))
        origins = original.get("metadata", {}).get("catalogOrigins", [])
        guide_steps = guides.get(exercise_id, [])
        original_steps = source.get("instructions", []) if source else []
        corrections, correction_flags = guide_corrections(exercise_id, guide_steps, original)
        flags = list(GUIDE_FLAGS.get(exercise_id, [])) + correction_flags
        requests = []
        if not selected:
            requests.append("official_exact_variant_reference_needed")
        if not original_steps and not guide_steps and not selected:
            requests.append("exact_execution_instructions_missing")
        if flags and not selected:
            requests.append("existing_guide_variant_conflict_needs_resolution")
        if "manufacturer" in origins:
            requests += ["manufacturer_model_setup_and_linkage_reference_needed",
                         "model_specific_contact_and_range_limits_needed"]
        if original.get("equipmentKey") in (None, "unspecified", "other") and not selected:
            requests.append("required_equipment_not_resolved")
        if (source or {}).get("category") in ("olympic weightlifting", "plyometrics", "stretching") and not selected:
            requests.append("specialized_motion_reference_and_review_needed")
        authored_guide = SETFLOW_AUTHORED_GUIDES.get(exercise_id)
        modified_guide = any(record["scope"] == "local_guide" for record in corrections)
        guide_source = ("Setflow-authored or corrected Korean text; original imported text from "
                        "hasaneyldrm/exercises-dataset (MIT); see guideCorrections for changed wording and basis"
                        if modified_guide else
                        "Local Korean text imported from hasaneyldrm/exercises-dataset; MIT text only")
        if authored_guide:
            guide_source = authored_guide["source"]
        rows.append({
            "exerciseId": exercise_id, "name": original.get("name"),
            "storedName": original.get("storedName"), "nameEnglish": original.get("nameEnglish"),
            "originGroup": group_for(origins), "catalogOrigins": origins,
            "category": original.get("category"), "measurement": original.get("measurement"),
            "primaryMuscles": original.get("primaryMuscles", []),
            "secondaryMuscles": original.get("secondaryMuscles", []),
            "catalogEquipmentKey": original.get("equipmentKey"),
            "catalogEquipmentName": original.get("equipmentName"),
            "manufacturer": {key: original.get(key) for key in ("brand", "line", "model", "focus", "sourceUrl")}
                if "manufacturer" in origins else None,
            "catalogSource": {key: original.get(key) for key in ("sourceName", "sourceId", "databaseId", "sourceUrl")},
            "exactSourceText": {"sourceId": source["id"], "sourceName": source["name"],
                                "instructions": original_steps, "equipment": source.get("equipment"),
                                "mechanic": source.get("mechanic"), "force": source.get("force"),
                                "category": source.get("category"),
                                "provenance": {"commit": REVISION, "datasetUrl": snapshot["datasetUrl"],
                                               "license": snapshot["license"], "expertVerified": False}}
                if source else None,
            "localGuide": {"path": "lib/data/exercise_guides.dart", "exactKey": exercise_id,
                           "steps": guide_steps, "source": guide_source,
                           "authorship": "setflow_authored" if authored_guide else "setflow_modified" if modified_guide else "imported_translation",
                           "originalTextSource": {"repository": "https://github.com/hasaneyldrm/exercises-dataset",
                                                  "license": "MIT text only; media rights excluded"} if not authored_guide else None,
                           "references": copy.deepcopy(authored_guide["references"]) if authored_guide else [],
                           "stepsSha256": guide_steps_sha256(guide_steps),
                           "expertVerified": False} if guide_steps else None,
            "guideReviewFlags": flags, "guideCorrections": corrections,
            "referenceReviewNote": REFERENCE_NOTES.get(exercise_id),
            "specification": selected,
            "status": "specification_ready" if selected else "needs_reference",
            "sourceTextReadiness": "exact_source_text_available" if original_steps else
                                 "local_guide_available" if guide_steps else
                                 "official_specification_available" if selected else "missing",
            "referenceNeeds": requests,
            "publicationPrerequisites": (["Apply reviewed specification to conflicting local guide"] if selected and flags else []) +
                                       ["Author exact motion/equipment", "Validate animated contacts and ROM",
                                        "Independent full-motion review", "Trainer review remains pending"],
            "animationBinding": None, "animationReuseAllowed": False,
            "reviewStatus": "trainer_pending", "trainerApproved": False, "expertVerified": False,
        })
    statuses = Counter(row["status"] for row in rows)
    groups = Counter(row["originGroup"] for row in rows)
    categories = Counter((row["exactSourceText"] or {}).get("category") or row["category"] or "unspecified" for row in rows)
    reasons = Counter(reason for row in rows for reason in row["referenceNeeds"])
    counts = {"total": len(rows), "originGroups": dict(groups), "statuses": dict(statuses),
              "categories": dict(categories), "referenceNeeds": dict(reasons),
              "exactUpstreamMatches": sum(row["exactSourceText"] is not None for row in rows),
              "exactUpstreamInstructionsAvailable": sum(bool((row["exactSourceText"] or {}).get("instructions")) for row in rows),
              "localGuidesAvailable": sum(row["localGuide"] is not None for row in rows),
              "anyInstructionsOrOfficialSpecAvailable": sum(row["sourceTextReadiness"] != "missing" for row in rows),
              "noInstructionsAndNoOfficialSpec": sum(row["sourceTextReadiness"] == "missing" for row in rows),
              "guideConflictIds": sum(bool(row["guideReviewFlags"]) for row in rows),
              "guideCorrectionHistoryIds": sum(bool(row["guideCorrections"]) for row in rows),
              "guideCorrectionsMatchingCurrentInputs": sum(any(record["status"] == "implemented_in_current_inputs"
                                                               for record in row["guideCorrections"]) for row in rows),
              "setflowModifiedLocalGuides": sum((row["localGuide"] or {}).get("authorship") == "setflow_modified" for row in rows),
              "setflowAuthoredLocalGuides": sum((row["localGuide"] or {}).get("authorship") == "setflow_authored" for row in rows),
              "renderedByThisTool": 0, "trainerApproved": 0}
    return {"schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(),
            "scope": "Exact-ID production specifications; not produced or trainer-approved media",
            "policy": {"nameMatchingUsedForMotion": False, "sourceIdMatchingCreatesAnimationBinding": False,
                       "manufacturerIdsPreserved": True, "externalMediaDownloaded": False,
                       "privateRemoteDataRead": False,
                       "guideCorrectionHistoryIsTrainerApproval": False,
                       "specificationReadyMeaning": "Explicit reference-backed selected variant available for authoring; no motion/trainer approval implied",
                       "needsReferenceMeaning": "Source text may be present; exact production mechanics still require review"},
            "inputSha256": input_hashes, "counts": counts,
            "upstreamTextSnapshot": snapshot, "exercises": rows}


def validate_report(report, catalog):
    expected = [row["exerciseId"] for row in catalog["exercises"]]
    actual = [row["exerciseId"] for row in report["exercises"]]
    if expected != actual or len(set(actual)) != len(actual):
        raise ValueError("Specification output lost/reordered/duplicated original exact IDs")
    for row in report["exercises"]:
        if row["trainerApproved"] or row["expertVerified"] or row["animationBinding"] is not None:
            raise ValueError("Specifications must not claim approval or animation binding")
        if row["status"] not in ("specification_ready", "needs_reference"):
            raise ValueError("Specification tool cannot emit rendered/approved states")
        if row["status"] == "specification_ready":
            specification = row["specification"]
            if not specification or not all(specification.get(key) for key in
                    ("variant", "requiredEquipment", "requiredGrip", "requiredBodyPosition", "rangeOfMotion", "references")):
                raise ValueError("Incomplete specification marked ready")


class ProductionSpecTests(unittest.TestCase):
    def setUp(self):
        self.catalog = {"exercises": [self.row("row"), self.row("shared-looking-row"), self.row("machine_example", ["manufacturer"])]}
        self.snapshot = {"commit": REVISION, "rawDatasetSha256": DATA_SHA256,
                         "licenseSha256": LICENSE_SHA256, "datasetUrl": UPSTREAM + "dist/exercises.json",
                         "license": "Unlicense", "rows": [{"id": str(i), "name": "Source " + str(i)} for i in range(876)]}

    def row(self, exercise_id, origins=None):
        return {"exerciseId": exercise_id, "name": "바벨 로우", "status": "approved",
                "motionKey": "row", "visualAssets": {"fake": True},
                "metadata": {"catalogOrigins": origins or ["curated"]}}

    def build(self):
        return build_specs(self.catalog, {}, self.snapshot, {})

    def test_similar_name_does_not_assign_spec(self):
        rows = self.build()["exercises"]
        self.assertEqual(rows[0]["status"], "specification_ready")
        self.assertEqual(rows[1]["status"], "needs_reference")
        self.assertIsNone(rows[1]["specification"])

    def test_input_approved_state_and_assets_are_not_copied(self):
        report = self.build()
        validate_report(report, self.catalog)
        self.assertTrue(all(not r["trainerApproved"] and r["animationBinding"] is None for r in report["exercises"]))
        self.assertTrue(all("visualAssets" not in r and r["status"] != "approved" for r in report["exercises"]))

    def test_duplicate_exact_ids_rejected(self):
        self.catalog["exercises"].append(self.row("row"))
        with self.assertRaisesRegex(ValueError, "duplicate exact"):
            self.build()

    def test_original_order_and_manufacturer_identity_preserved(self):
        self.catalog["exercises"][2].update({"brand": "Example", "model": "A01", "sourceUrl": "https://example.com/A01"})
        rows = self.build()["exercises"]
        self.assertEqual([r["exerciseId"] for r in rows], ["row", "shared-looking-row", "machine_example"])
        self.assertEqual(rows[2]["manufacturer"]["model"], "A01")
        self.assertIsNone(rows[2]["specification"])

    def test_source_id_is_exact_and_does_not_create_motion(self):
        self.catalog["exercises"][1].update({"sourceName": "free-exercise-db", "sourceId": "1"})
        self.snapshot["rows"][1].update({"instructions": ["Exact original instructions"]})
        row = self.build()["exercises"][1]
        self.assertEqual(row["exactSourceText"]["instructions"], ["Exact original instructions"])
        self.assertIsNone(row["specification"])
        self.assertIsNone(row["animationBinding"])

    def test_media_snapshot_and_wrong_provenance_rejected(self):
        self.snapshot["rows"][0]["images"] = ["unlicensed.gif"]
        with self.assertRaisesRegex(ValueError, "media"):
            self.build()
        del self.snapshot["rows"][0]["images"]
        self.snapshot["commit"] = "unknown"
        with self.assertRaisesRegex(ValueError, "pinned"):
            self.build()

    def test_dart_comments_do_not_become_steps(self):
        text = "  'x': [\n    // 'not a step'\n    '실제 단계',\n  ],\n"
        self.assertEqual(parse_guides(text), {"x": ["실제 단계"]})

    def test_ready_without_required_grip_is_rejected(self):
        report = self.build()
        report["exercises"][0]["specification"]["requiredGrip"] = None
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            validate_report(report, self.catalog)

    def test_correction_history_is_separate_from_current_flags(self):
        steps = ["Keep neutral grip throughout"]
        record = correction("Previous rotation error", "Keep neutral grip", "ACE text compared",
                            guide_steps_sha256(steps), [ACE + "10/hammer-curl/"])
        self.catalog = {"exercises": [self.row("hammer_curl")]}
        with patch.dict(GUIDE_CORRECTIONS, {"hammer_curl": record}):
            row = build_specs(self.catalog, {"hammer_curl": steps}, self.snapshot, {})["exercises"][0]
        self.assertEqual(row["guideReviewFlags"], [])
        self.assertEqual(row["guideCorrections"][0]["previousIssue"], "Previous rotation error")
        self.assertEqual(row["guideCorrections"][0]["status"], "implemented_in_current_inputs")
        self.assertEqual(row["localGuide"]["authorship"], "setflow_modified")
        self.assertFalse(row["trainerApproved"])

    def test_changed_corrected_text_requires_recheck(self):
        record = correction("Previous error", "Fixed", "Observed text", guide_steps_sha256(["Fixed text"]))
        self.catalog = {"exercises": [self.row("hammer_curl")]}
        with patch.dict(GUIDE_CORRECTIONS, {"hammer_curl": record}):
            row = build_specs(self.catalog, {"hammer_curl": ["Later changed text"]}, self.snapshot, {})["exercises"][0]
        self.assertEqual(row["guideCorrections"][0]["status"], "needs_recheck")
        self.assertTrue(row["guideReviewFlags"])
        self.assertIn("conflicting local guide", " ".join(row["publicationPrerequisites"]))

    def test_metadata_correction_does_not_relabel_imported_text(self):
        steps = ["Hands on bench edge"]
        record = correction("Wrong equipment", "Bench metadata fixed", "Exact source compared",
                            guide_steps_sha256(steps), scope="catalog_metadata", equipment="bench")
        original = self.row("bench_dip")
        original["equipmentKey"] = "bench"
        self.catalog = {"exercises": [original]}
        with patch.dict(GUIDE_CORRECTIONS, {"bench_dip": record}):
            row = build_specs(self.catalog, {"bench_dip": steps}, self.snapshot, {})["exercises"][0]
            original["equipmentKey"] = "dip_bars"
            drifted = build_specs(self.catalog, {"bench_dip": steps}, self.snapshot, {})["exercises"][0]
        self.assertEqual(row["guideReviewFlags"], [])
        self.assertEqual(row["localGuide"]["authorship"], "imported_translation")
        self.assertEqual(drifted["guideCorrections"][0]["status"], "needs_recheck")
        self.assertTrue(drifted["guideReviewFlags"])

    def test_selected_standing_press_and_crunch_variants_are_explicit(self):
        selected = EXACT_SPECS["ohp"]
        self.assertIn("standing", selected["variant"])
        self.assertNotIn("shoulder_press_bench", selected["requiredEquipment"])
        self.assertIn("no knee dip or leg drive", selected["requiredBodyPosition"])
        self.assertEqual(selected["references"][0]["url"], ACE + "71/standing-shoulder-press/")
        self.assertIn("behind head", EXACT_SPECS["crunch"]["requiredGrip"])
        self.assertNotIn("crunch", GUIDE_FLAGS)
        self.assertEqual(set(GUIDE_FLAGS), {"lateral"})
        self.assertIn("clean front rack", EXACT_SPECS["front_squat"]["variant"])
        self.assertIn("uncrossed", EXACT_SPECS["front_squat"]["requiredGrip"])

    def test_new_authored_guide_has_its_own_sources_not_imported_mit_wording(self):
        ids = ("bird_dog", "hip_thrust", "side_plank", "face_pull", "wall_sit", "mountain_climber", "burpee", "rowing_machine")
        self.catalog = {"exercises": [self.row(eid) for eid in ids]}
        guides = {eid: ["Setflow authored guide"] for eid in ids}
        rows = build_specs(self.catalog, guides, self.snapshot, {})["exercises"]
        for row in rows:
            self.assertEqual(row["localGuide"]["authorship"], "setflow_authored")
            self.assertIsNone(row["localGuide"]["originalTextSource"])
            self.assertTrue(row["localGuide"]["references"])
            self.assertFalse(row["trainerApproved"])
        self.assertIn("staggered", rows[2]["specification"]["requiredBodyPosition"])
        self.assertEqual(rows[1]["status"], "needs_reference")

    def test_final_corrected_variants_pin_current_steps_without_approval(self):
        guides = parse_guides((ROOT / "lib/data/exercise_guides.dart").read_text(encoding="utf-8"))
        ids = ("one_arm_dumbbell_row", "close_grip_bench", "arnold_press", "front_squat",
               "ab_wheel", "cable_crunch", "cable_fly", "cable_lateral_raise", "chest_press",
               "assisted_pullup", "pec_deck", "reverse_pec_deck", "rack_pull", "upright_row",
               "preacher_curl", "skull_crusher", "chest_supported_row", "back_extension",
               "decline_bench", "overhead_triceps_extension", "hack_squat", "jump_rope")
        for eid in ids:
            with self.subTest(exercise_id=eid):
                original = self.row(eid)
                if GUIDE_CORRECTIONS[eid].get("expectedCatalogEquipmentKey"):
                    original["equipmentKey"] = GUIDE_CORRECTIONS[eid]["expectedCatalogEquipmentKey"]
                records, flags = guide_corrections(eid, guides[eid], original)
                self.assertEqual(flags, [])
                self.assertEqual(records[0]["status"], "implemented_in_current_inputs")
                self.assertFalse(records[0]["trainerApproved"])
                self.assertTrue(records[0]["referenceUrls"])
                self.assertNotIn(eid, GUIDE_FLAGS)
        self.assertIn("rotate arms", EXACT_SPECS["arnold_press"]["requiredGrip"])
        self.assertIn("Left knee", EXACT_SPECS["one_arm_dumbbell_row"]["requiredBodyPosition"])

    def test_unrelated_guide_addition_does_not_invalidate_exact_correction(self):
        steps = ["Keep neutral grip throughout"]
        record = correction("Previous rotation error", "Keep neutral grip", "ACE text compared", guide_steps_sha256(steps))
        self.catalog = {"exercises": [self.row("hammer_curl")]}
        with patch.dict(GUIDE_CORRECTIONS, {"hammer_curl": record}):
            before = build_specs(self.catalog, {"hammer_curl": steps}, self.snapshot, {"guides": "file-v1"})
            after = build_specs(self.catalog, {"hammer_curl": steps, "other": ["New guide"]}, self.snapshot, {"guides": "file-v2"})
        self.assertEqual(before["exercises"][0]["guideCorrections"], after["exercises"][0]["guideCorrections"])
        self.assertEqual(after["exercises"][0]["guideReviewFlags"], [])

    def test_shared_guide_provenance_and_corrections_use_only_eight_literal_ids(self):
        fixture = json.loads((ROOT / "test/fixtures/exercise_visual_shared_rows.json").read_text(encoding="utf-8"))
        exact_ids = {row["id"] for row in fixture["rows"]}
        self.assertEqual(set(SHARED_AUTHORED_GUIDES), exact_ids)
        guides = parse_guides((ROOT / "lib/data/exercise_guides.dart").read_text(encoding="utf-8"))
        self.catalog = {"exercises": [self.row(eid) for eid in sorted(exact_ids)] + [self.row("name-only-chin-up")]}
        rows = build_specs(self.catalog, guides, self.snapshot, {})["exercises"]
        for row in rows[:-1]:
            self.assertEqual(row["localGuide"]["authorship"], "setflow_authored")
            self.assertIsNone(row["localGuide"]["originalTextSource"])
            self.assertTrue(row["localGuide"]["references"])
            self.assertEqual(row["guideCorrections"][0]["status"], "implemented_in_current_inputs")
            self.assertFalse(row["trainerApproved"])
            self.assertIsNone(row["animationBinding"])
        self.assertIsNone(rows[-1]["localGuide"])
        self.assertEqual(rows[-1]["guideCorrections"], [])
        rear = SHARED_AUTHORED_GUIDES["d1ecb818-0235-5e2f-9113-39be506aa98a"]["references"][0]
        self.assertIn("not_official_expert", rear["scope"])
        self.assertEqual(rear["commit"], REVISION)

    def test_current_guide_alignment_corrections_are_hash_bound_without_trainer_approval(self):
        guides = parse_guides((ROOT / "lib/data/exercise_guides.dart").read_text(encoding="utf-8"))
        ids = ("squat", "romanian_deadlift", "dips", "glute_bridge", "bench_dip",
               "straight_arm_pulldown", "seated_cable_row", "reverse_fly", "bodyweight_squat")
        for eid in ids:
            original = self.row(eid)
            original["equipmentKey"] = GUIDE_CORRECTIONS[eid].get("expectedCatalogEquipmentKey")
            records, flags = guide_corrections(eid, guides[eid], original)
            self.assertEqual(flags, [], msg=eid)
            self.assertEqual(records[0]["status"], "implemented_in_current_inputs")
            self.assertFalse(records[0]["trainerApproved"])
            self.assertTrue(records[0]["referenceUrls"])
            _, changed_flags = guide_corrections(eid, guides[eid] + ["Unreviewed variant change"], original)
            self.assertTrue(changed_flags, msg=eid)

    def test_resolved_reference_scope_keeps_other_variants_distinct(self):
        standing = EXACT_SPECS["reverse_fly"]
        self.assertIn("Standing", standing["variant"])
        self.assertNotIn("bench", standing["requiredEquipment"])
        self.assertIn("bent-over-dumbbell-reverse-fly", standing["references"][0]["url"])
        seated = EXACT_SPECS["seated_cable_row"]
        self.assertIn("pronated straight-bar", seated["variant"])
        self.assertIn("straight_bar_attachment", seated["requiredEquipment"])
        self.assertIn("explicit_Setflow_selection", seated["references"][0]["scope"])
        self.assertNotIn("seated_cable_row", GUIDE_FLAGS)
        self.assertIn("V핸들", REFERENCE_NOTES["seated_cable_row"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=ROOT / "output/exercise_visuals/catalog.json")
    parser.add_argument("--guides", type=Path, default=ROOT / "lib/data/exercise_guides.dart")
    parser.add_argument("--output", type=Path, default=ROOT / "output/exercise_visuals/production/specifications.json")
    parser.add_argument("--refresh-upstream", action="store_true", help="Download only pinned public text JSON and license")
    parser.add_argument("--self-test", action="store_true", help="Run exact-ID/provenance/state regression tests; write nothing")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ProductionSpecTests))
        raise SystemExit(0 if result.wasSuccessful() else 1)
    if args.output.resolve() == args.catalog.resolve():
        parser.error("Output must be separate from the existing render catalog")
    if args.refresh_upstream:
        snapshot = fetch_snapshot()
    elif args.output.exists():
        snapshot = checked_snapshot(json.loads(args.output.read_text(encoding="utf-8"))["upstreamTextSnapshot"])
    else:
        parser.error("First run needs --refresh-upstream; later runs reuse the embedded pinned text snapshot")
    catalog_bytes = args.catalog.read_bytes()
    guide_bytes = args.guides.read_bytes()
    catalog = json.loads(catalog_bytes)
    report = build_specs(catalog, parse_guides(guide_bytes.decode("utf-8")), snapshot,
                         {str(args.catalog.relative_to(ROOT)): sha256(catalog_bytes),
                          str(args.guides.relative_to(ROOT)): sha256(guide_bytes),
                          "tool/exercise_visuals/production_specs.py": sha256(Path(__file__).read_bytes())})
    validate_report(report, catalog)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["counts"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
