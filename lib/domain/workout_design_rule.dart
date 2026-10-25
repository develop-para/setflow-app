/// 운동 기록·추천의 판단 근거. 논문의 원칙과 앱에서 선택한 수치를 구분한다.
/// 수치나 동작을 바꾸면 이 설명과 연결 논문, 회귀 사례도 함께 검토한다.
enum WorkoutRuleBasis {
  researchAndAppRule('연구 참고 · 앱 적용'),
  recordIntegrity('기록 보존'),
  userControl('사용자 선택'),
  planningEstimate('시간·입력 기본값');

  const WorkoutRuleBasis(this.label);
  final String label;
}

enum WorkoutDesignRule {
  goalPrescription(
    title: '목표별 세트·반복·휴식',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '근력에는 상대적으로 높은 부하, 근비대에는 주간 운동량·실패 근접도·충분한 휴식, 점진적 훈련을 참고합니다.',
    implementation:
        '종목당 2–3세트에서 시작합니다. 근력 복합 4–6회, 근비대 복합 8–12회·보조 10–15회, 근지구력 15–20회를 기본으로 둡니다. 휴식은 근력 복합 180초·그 외 복합 120초·보조 90초입니다.',
    rationale:
        '목표별로 기록하기 쉬운 시작 계획을 제공하고, 여러 관절을 쓰는 운동에는 더 긴 휴식 시간을 배정합니다. 무게·횟수·세트·휴식은 사용자가 수정할 수 있습니다.',
    limitations:
        '정확히 이 반복·휴식 조합이 개인에게 최적이라는 연구는 아닙니다. 다른 반복 범위에서도 효과를 얻을 수 있습니다. 근비대 휴식 연구는 숙련자·몸통 근육 자료가 부족하며 90초 초과의 추가 이점도 불명확합니다. 실패 근접도 연구는 추정 RIR의 탐색 분석으로 개인의 최적 RIR을 확정하지 않습니다. 개인 중량을 논문의 집단 평균으로 만들지 않습니다.',
    evidenceIds: {
      'acsm_currier_2026_resistance',
      'acsm-2009',
      'grgic-2018',
      'singer_2024_rest_hypertrophy',
      'robinson_2024_proximity_failure',
    },
  ),
  volumePlan(
    title: '자동 추천의 시작 계획',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '주간 운동량과 운동 빈도를 함께 보고, 운동량 증가의 효과가 점차 줄어들 수 있음을 참고합니다.',
    implementation:
        '기록이 부족할 때 부위별 하루 4/6/8세트, 근비대 주간 8/12/16세트, 그 외 주간 6/10/10세트, 하루 전체 12/18/24세트를 입문/기본/숙련의 자동 계획값으로 사용합니다.',
    rationale:
        '정보가 부족한 상태에서 세트 완료 때마다 끝없이 새 운동을 자동 제안하지 않도록 정한 시작 계획입니다. 숙련도에 따라 시작량을 나누지만, 4·6·8이라는 간격 자체는 연구가 정한 수치가 아닙니다. 사용자가 운동 추천을 직접 요청하면 이 계획값을 넘어 제안받을 수 있습니다.',
    limitations:
        '개인별 최적량·안전 상한·운동 종료 지시가 아닙니다. 8세트를 넘으면 효과가 없거나 위험하다는 뜻이 아닙니다. 시간·장비·선택 부위·제외 조건은 별도로 적용합니다.',
    evidenceIds: {
      'pelland_2026_dose_response',
      'acsm_currier_2026_resistance',
      'schoenfeld_2017_weekly_volume',
    },
  ),
  volumeAccounting(
    title: '주동근·보조근 운동량 집계',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '직접 세트와 간접 세트를 구분한 연구의 0.5 환산 모델을 참고합니다.',
    implementation:
        '주동근 1·검토된 복합 운동의 보조근 0.5로 집계합니다. 주간은 월요일부터 오늘까지이며 과거에는 완료 세트만, 오늘은 미완료 계획도 예약량으로 포함합니다. 웜업·예시·미래 기록은 제외합니다.',
    rationale:
        '보조근에 걸리는 운동량을 전부 무시하거나 직접 운동과 똑같이 세는 것을 피하고, 이미 추가한 계획을 추천이 중복해서 채우지 않게 합니다. 월요일 경계는 앱의 다른 주간 통계와 맞춥니다.',
    limitations:
        '개별 운동의 실제 근활성이 정확히 절반이라는 측정값은 아닙니다. 가슴·등·하체 같은 앱 대분류는 연구의 개별 근육과 동일하지 않습니다. 미완료 계획은 실제 완료량과 구분합니다.',
    evidenceIds: {'pelland_2026_dose_response'},
  ),
  loadProgression(
    title: '같은 종목의 중량·반복 조정',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle:
        '수행 향상에 맞춰 부하를 점진적으로 늘리는 원칙을 참고합니다. 매 세트 실패까지 해야 한다고 강제하지 않으며, RIR의 주관적 추정에는 오차가 있음을 반영합니다.',
    implementation:
        '같은 종목의 실제 작업세트 중량을 우선합니다. 28일 이내 두 날짜에서 목표 세트의 반복 상단을 모두 달성하면 기구 단위로 증량을 제안하고 증가폭은 10% 이내로 둡니다. RIR이 있으면 2회 이상 여유를 확인합니다.',
    rationale:
        '다른 기구의 kg이나 추정 1RM을 옮기지 않고, 한 번의 좋은 수행만으로 중량을 올리지 않기 위해 반복 관측합니다. 같은 중량의 세트별 +1회는 무게를 유지하며 작은 수행 목표를 제시하려는 선택입니다.',
    limitations:
        '두 날짜·28일·RIR 2·기구 증분·세트별 +1회는 앱의 판단 규칙입니다. 논문이 이 조합의 우월성이나 개인의 적정 중량을 검증하지 않았습니다. RIR은 실제 남은 반복수의 정확한 측정값이 아니며 연구의 평균 오차를 개인 기록에 자동 보정하지 않습니다. 설정한 휴식은 실제 휴식 측정값이 아닙니다.',
    evidenceIds: {
      'acsm-2009',
      'refalo_2023_proximity_failure',
      'larsen_2021_autoregulation',
      'halperin_2022_rir_accuracy',
    },
  ),
  recoveryAdjustment(
    title: '피로·오래된 기록·수행 하락',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '수면 부족 등에 따른 수행 저하 가능성과 개인 수행을 참고하는 자율조절 원칙을 봅니다.',
    implementation:
        '오늘 피로 응답이나 동일 종목의 28일 초과 공백에는 약 10% 기준 중량 조정과 1세트 감소를 제안합니다. 두 날짜 연속 최소 반복 미달에는 약 5% 기준으로 조정합니다. 42일 안 네 날짜의 비교 가능한 반복 하락에는 중량을 유지하고 1세트를 줄입니다.',
    rationale:
        '오래된 기록을 현재 능력으로 단정하거나 한 세트의 우연한 실패를 과해석하지 않도록 같은 종목·중량·세트 수를 맞춰 비교합니다. 감량 기준과 반올림 후 실제 중량을 함께 설명합니다.',
    limitations:
        '28일·42일·네 날짜·5/10%·1세트는 검증된 생리적 경계나 치료 처방이 아닙니다. 동일 종목 공백이 운동 전체 중단을 뜻하지 않습니다. 이 조정이 부상을 줄인다는 직접 근거도 없습니다.',
    evidenceIds: {'craven_2022_sleep_loss', 'larsen_2021_autoregulation'},
  ),
  personalCoaching(
    title: '개인 기록으로 계획 조정',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '고정된 계획과 함께 실제 수행·주관적 여유를 참고해 조정하는 접근을 참고합니다.',
    implementation:
        '직전 세 개 완료 주 중 최소 두 주·네 날짜 기록이 있어야 개인 운동량을 계산합니다. 비교 가능한 수행 개선과 실제 RIR 여유에는 주간 +2세트, 여러 종목의 반복 하락에는 −2세트를 제안합니다. 부위별 주간 계획은 최소 4·최대 12/20/24, 하루 계획은 최소 2·최대 입문 6/그 외 10세트로 배분합니다.',
    rationale:
        '단 한 주나 한 종목의 변화로 계획을 크게 바꾸지 않고 최근 수행량 가까이에서 작은 변경을 제안합니다. 종목별 세트는 최근 기록을 참고하되 2–5세트로 시작 계획을 한정합니다.',
    limitations:
        '이 표본 기준·증감 폭·계획 범위는 앱 선택입니다. 과거에 했던 운동량이 최적량이라는 뜻이 아니며, 향상 중인 사람에게 세트를 늘리는 것이 유지보다 우월하다고 검증된 알고리즘이 아닙니다. 자동 조절 부하와 고정 부하의 근력 효과 차이는 확정되지 않았으며 속도손실로 세트량을 조절한 연구를 앱의 주간 ±2세트 규칙과 같게 보지 않습니다.',
    evidenceIds: {
      'larsen_2021_autoregulation',
      'pelland_2026_dose_response',
      'halperin_2022_rir_accuracy',
      'hickmott_2022_autoregulation',
    },
  ),
  digitalGuidance(
    title: '모바일 운동 안내와 사용자 선택',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle:
        '모바일로 저항운동을 안내하는 중재는 일부 신경근 체력 개선 가능성을 보였으며, 처방 내용과 진행 방법을 명확히 설명하는 접근을 참고합니다.',
    implementation:
        '운동별 세트·반복·휴식과 추천 이유·연결 출처를 보여주고 사용자가 목표와 조건을 수정하거나 운동을 직접 선택할 수 있게 합니다. 설명을 읽어야만 다음 세트를 기록할 수 있게 막지 않습니다.',
    rationale:
        '어떤 계획을 제안했는지 확인하고 현재 기록에 맞춰 조정할 수 있도록 안내와 기록을 연결합니다. 운동 중 반복 입력과 강제 확인을 줄이는 구체적인 조작은 앱의 사용성 선택입니다.',
    limitations:
        '대부분 임상 대상을 포함한 여러 모바일 중재의 결과이며 이 앱의 효과를 검증한 연구가 아닙니다. 짧은 연구 기간·처방 보고 부족·방법론적 우려가 있고, 특정 UI나 숫자의 최적성·개인화 추천의 우월성·지속 참여 향상을 보장하지 않습니다.',
    evidenceIds: {'cox_2026_mhealth_resistance'},
  ),
  estimatedStrength(
    title: '추정 1RM과 기록 비교',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '중량과 반복으로 1RM을 추정하는 Epley·Brzycki 방식과 그 오차 연구를 참고합니다.',
    implementation:
        '완료 기록 1–15회에서 추정합니다. 11회 이상은 참고값이며 e1RM PR과 추천 중량 계산에서 제외합니다. 최근 다섯 운동 날짜의 대표값 중앙값을 쓰고, 공식 평균은 선택 가능한 산술평균입니다.',
    rationale:
        '한 번의 큰 값이 현재 추정치를 좌우하지 않도록 중앙값을 사용하고, 고반복 추정의 불확실성을 기록 비교에 반영합니다. 1회 기록에는 수행한 중량을 그대로 사용하며 실측 최대 중량으로 확정하지 않습니다.',
    limitations:
        '실패까지 수행했는지, RIR·동작 품질 등을 모두 통제하지 못합니다. 낮은/중간 반복 구간은 앱 분류이며 검증된 정확도 등급이 아닙니다. 두 공식 평균이나 다섯 날짜가 더 정확하다는 직접 근거는 없습니다.',
    evidenceIds: {
      'brzycki-1993',
      'lesuer_1997_e1rm',
      'reynolds_2006_rm_prediction',
    },
  ),
  cardioPlan(
    title: '유산소 시간·강도',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle:
        '성인의 주간 중강도 150분 또는 고강도 75분에 해당하는 활동량 지침과 점진적 증가를 참고합니다. 근력·유산소 병행은 목표에 따라 배치합니다.',
    implementation:
        '일반 연속 운동은 30분, 감량 목표는 40분을 시작값으로 제안하며 남은 시간과 기록을 반영합니다. 완료한 각 구간을 기록된 강도로 환산하고, 거리 목표는 최근 같은 종목의 날짜별 페이스를 참고합니다.',
    rationale:
        '주간 목표를 여러 번의 기록 가능한 세션으로 나누기 위한 기본값입니다. 40분은 감량 효과를 보장하는 시간 공식이 아닙니다. 서로 다른 길이·강도의 구간을 하나의 단순 평균으로 환산하지 않습니다.',
    limitations:
        '목표 RPE가 미리 입력된 경우 완료는 화면의 값을 확인한 기록으로 취급합니다. RPE는 심박 측정값이 아니며 중강도/고강도 환산에도 오차가 있습니다. 미기록 활동은 포함하지 않습니다. 병행 운동의 시간 분리 안내는 폭발력 등 우선 목표에 따라 해석해야 합니다.',
    evidenceIds: {
      'who_bull_2020_pa_guideline',
      'acsm_garber_2011_prescription',
      'acsm_jakicic_2024_adiposity',
      'schumann_2022_concurrent',
    },
  ),
  cardioIntervals(
    title: '고강도 인터벌 제안 조건',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '건강한 훈련자를 대상으로 한 4분 운동·3분 회복의 4회 인터벌 연구를 참고합니다.',
    implementation:
        '고강도 운동 가능 여부를 명시하고 숙련도·최근 28일 내 서로 다른 여섯 날짜의 20분 이상 운동 기록을 확인한 경우에만 자동 제안 후보가 됩니다. 심박 목표는 알고 있는 최대 심박 등이 제공된 경우에만 계산합니다.',
    rationale:
        '좁은 연구 대상과 강도 조건을 아무 사용자에게나 확대하지 않고, 나이만으로 개인 최대 심박을 만들어 넣지 않기 위한 제안 조건입니다.',
    limitations:
        '28일·여섯 날짜·RPE 범위는 앱 조건으로 개인의 안전성을 검증하지 않습니다. 연구의 4×4 프로토콜을 모든 유산소·모든 건강 상태에 일반화할 수 없습니다.',
    evidenceIds: {'helgerud_2007_4x4', 'acsm_garber_2011_prescription'},
  ),
  exerciseSelection(
    title: '운동 순서·장비·선택 부위',
    basis: WorkoutRuleBasis.researchAndAppRule,
    principle: '우선할 운동을 앞에 배치하는 원칙과 주간 운동량을 맞춘 분할·전신 방식 비교를 참고합니다.',
    implementation:
        '직접 선택한 장비·부위·제외 동작을 적용하고, 이미 기록한 종목은 새 후보에서 뺍니다. 대체 운동은 같은 동작으로 연결된 종목만, 중량은 그 종목 자체의 기록만 씁니다. 최근 90일에 두 날짜 이상 직접 고른 운동은 선호로 참고합니다.',
    rationale:
        '사용할 수 없는 운동과 원하지 않는 운동을 반복하지 않고, 다른 동작·다른 기구를 같은 운동으로 취급하지 않기 위한 선택입니다.',
    limitations:
        '논문이 다음 운동 하나나 앱의 분할 조합을 개인 최적으로 확정하지 않았습니다. 90일·두 날짜의 선호 판단은 사용 편의를 위한 규칙입니다. 통증 입력으로 질환이나 운동 가능 여부를 진단하지 않습니다.',
    evidenceIds: {'nunes_2021_exercise_order', 'ramos_2024_split_full_body'},
  ),
  timeEstimate(
    title: '운동 시간 안에 계획 맞추기',
    basis: WorkoutRuleBasis.planningEstimate,
    principle: '',
    implementation:
        '사용자가 정한 시간에 준비·종목 전환·세트·휴식을 포함합니다. 종목 전환 90초, 반복당 4초, 버티기 60초를 시간 추정의 기본값으로 둡니다.',
    rationale:
        '휴식과 기구 이동 시간을 빼놓아 실제로 끝내기 어려운 계획이 나오지 않게 합니다. 시간 제한은 사용자가 늘리거나 해제할 수 있습니다.',
    limitations:
        '최적 운동 속도·휴식 처방이나 사용자의 실제 소요시간을 측정한 값이 아닙니다. 개인 속도와 기구 대기에 따라 달라집니다.',
    evidenceIds: {},
  ),
  observedValues(
    title: '실제 수행과 새 계획 구분',
    basis: WorkoutRuleBasis.recordIntegrity,
    principle: '',
    implementation:
        '완료한 기록은 새 계획을 만들며 덮어쓰지 않습니다. 운동을 다른 날로 복사하거나 운동 과제·보유 루틴을 새 과제 계획으로 가져오면 완료 상태와 실제 RIR·RPE를 옮기지 않고 원본을 보존합니다. 기록이 없는 중량은 직접 선택하도록 둡니다. 트레이너가 회원별 공간에서 입력한 기록은 해당 회원 원본으로 분리하고 작성자를 표시하며 트레이너 본인의 운동으로 저장하지 않습니다. 회원 목록은 동의로 연결된 동일 계정만 한 사람으로 표시하고 이름·전화번호의 일치로 합치지 않습니다. 선택일의 기록 행동은 한 버튼에 모으되 회원 직접 기록은 읽기 전용으로 보존합니다. 커뮤니티의 운동 요약은 게시 당시 공개한 수치를 표시하며 조회자의 현재 기록으로 대체하지 않습니다.',
    rationale:
        '하지 않은 수행·느끼지 않은 RIR·들어본 적 없는 중량을 실제 기록처럼 만들지 않기 위해서입니다. 기록 정정용 복사는 실제 관찰값을 보존합니다.',
    limitations:
        '기록이 정확해도 개인의 회복이나 안전성을 자동으로 판단할 수는 없습니다. 관찰값과 목표값을 구분하는 데이터 원칙입니다.',
    evidenceIds: {},
  ),
  pendingSetPropagation(
    title: '남은 세트에 기록한 값 반영',
    basis: WorkoutRuleBasis.userControl,
    principle: '',
    implementation:
        '수정한 수행값은 아직 끝내지 않은 뒤의 세트에 반영할 수 있으며 되돌리기를 제공합니다. 완료 기록과 더 무거운 계획은 보존하고 관찰값인 RIR은 전파하지 않습니다.',
    rationale: '세트마다 같은 수치를 반복 입력하는 횟수를 줄이면서 원래 계획으로 돌아갈 길을 남깁니다.',
    limitations: '남은 세트도 같은 수행을 반드시 해야 한다는 처방이 아닙니다. 사용자가 다시 수정할 수 있습니다.',
    evidenceIds: {},
  ),
  sequentialCompletion(
    title: '세트 순서와 휴식 타이머',
    basis: WorkoutRuleBasis.recordIntegrity,
    principle: '',
    implementation:
        '첫 미완료 세트부터 완료하며 완료한 세트는 수정·되돌리기가 가능합니다. 휴식은 앱·기기·함께 방에서 같은 종료 시각을 사용하며, 연장은 기존 종료 시각에 더합니다. 복귀 조회의 늦은 응답은 새 휴식·연장·취소를 덮어쓰지 않습니다. 앱 밖 타이머 표시는 기본으로 켜며, 운동 기록 메뉴에서 바꿀 수 있습니다. 앱 밖 창은 시간·30초 연장·끝내기를 작은 두 줄에 두고, 시간 영역은 탭으로 운동 복귀·드래그로 이동합니다.',
    rationale: '앞의 세트가 비어 있는데 뒤 세트가 기록되거나, 다른 세트를 눌러 진행 중 휴식이 리셋되는 일을 방지합니다.',
    limitations:
        '생리적으로 모든 운동 순서를 고정해야 한다는 연구 주장이 아니라 기록 순서와 타이머 일관성을 위한 동작입니다. 앱 밖 창은 Android의 다른 앱 위에 표시 권한이 필요하며, 사용자가 끈 선택은 권한이 있어도 유지합니다. 표시 크기와 30초 연장은 조작 편의를 위한 앱 선택이며 개인의 적정 휴식 처방이 아닙니다.',
    evidenceIds: {},
  ),
  explicitEditing(
    title: '숫자 수정과 저장',
    basis: WorkoutRuleBasis.userControl,
    principle: '',
    implementation:
        '숫자 박스를 누르면 다이얼이 열리고 적용할 때 저장합니다. 앞 세트 삭제로 번호가 바뀌어도 편집 대상은 유지하며 키보드가 휴식 조작을 가리지 않게 합니다. 게스트 기록도 기기에 저장하며 계정으로 가져오기는 사용자가 선택합니다. 초기 서버 조회 중 새 기록은 늦은 응답으로 되돌리지 않습니다. 새 운동 선택에서는 미사용 제조사 종목을 숨기고 일반 종목의 선행 맨몸 표기를 줄입니다. 기존 기록·루틴·직접 만든 운동·내 기구는 원래 이름과 ID를 보존하며 동명 운동을 합치지 않습니다.',
    rationale:
        '뒤로가기·화면 잠금으로 편집 중인 값이 저장된 것처럼 보이는 문제를 줄이고, 로그인 여부로 운동 기록을 잃지 않게 합니다.',
    limitations: '입력 방식과 소유권에 관한 사용성·데이터 원칙이며 운동 효과에 관한 연구 결론이 아닙니다.',
    evidenceIds: {},
  ),
  inputBounds(
    title: '입력 범위와 표시 단위',
    basis: WorkoutRuleBasis.planningEstimate,
    principle: '',
    implementation:
        'kg·반복 등 입력 범위와 중량 표시 단위는 저장·다이얼 조작 범위로 제한합니다. 기구 증분은 실제 장비에 맞춰 사용자가 확인합니다.',
    rationale: '실수로 지나치게 긴 수치나 유효하지 않은 값이 저장되는 일을 줄이고 작은 화면에서 조작할 수 있게 합니다.',
    limitations:
        '입력 가능한 최댓값이 사람이 수행해도 되는 중량·횟수의 상한을 뜻하지 않습니다. 단위로 반올림한 실제 값은 목표 변화율과 다를 수 있습니다.',
    evidenceIds: {},
  );

  const WorkoutDesignRule({
    required this.title,
    required this.basis,
    required this.principle,
    required this.implementation,
    required this.rationale,
    required this.limitations,
    required this.evidenceIds,
  });

  final String title;
  final WorkoutRuleBasis basis;
  final String principle;
  final String implementation;
  final String rationale;
  final String limitations;
  final Set<String> evidenceIds;

  static const reviewedOn = '2026-10-24';
}
