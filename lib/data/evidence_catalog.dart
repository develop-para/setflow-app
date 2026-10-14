enum EvidenceCategory {
  strengthEstimate('근력 추정'),
  trainingPrescription('운동 처방'),
  exerciseOrder('운동 순서'),
  effort('운동 강도와 실패 지점'),
  generalActivity('건강 활동량'),
  weightManagement('체중 관리'),
  concurrentTraining('근력·유산소 병행'),
  cardiorespiratory('심폐 체력'),
  digitalTraining('디지털 운동 안내');

  const EvidenceCategory(this.label);

  final String label;
}

class EvidenceReference {
  const EvidenceReference({
    required this.id,
    required this.category,
    required this.koreanTitle,
    required this.takeaway,
    required this.title,
    required this.authors,
    required this.year,
    required this.source,
    required this.evidenceType,
    required this.officialUrl,
    required this.appRules,
    required this.limitations,
    this.reviewedOn = '2026-09-15',
    this.reviewScope = '공식 출처와 앱 적용 범위를 연결한 자료입니다. 본문 전체의 재현 검증은 아닙니다.',
    this.doi,
  });

  final String id;
  final EvidenceCategory category;
  final String koreanTitle;
  final String takeaway;
  final String title;
  final String authors;
  final int year;
  final String source;
  final String evidenceType;
  final String? doi;
  final Uri officialUrl;
  final List<String> appRules;
  final String limitations;
  final String reviewedOn;
  final String reviewScope;

  String get searchableText => [
    koreanTitle,
    takeaway,
    title,
    authors,
    category.label,
    doi ?? '',
    year.toString(),
  ].join(' ').toLowerCase();
}

final evidenceCatalog = List<EvidenceReference>.unmodifiable([
  EvidenceReference(
    id: 'larsen_2021_autoregulation',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '수행에 맞춰 조절하는 근력 훈련',
    takeaway: '자율조절은 실제 수행을 참고하는 접근이며, 앱의 조정 규칙이 더 효과적이라는 검증은 아닙니다.',
    title:
        'Effects of subjective and objective autoregulation methods for intensity and volume on enhancing maximal strength during resistance-training interventions: a systematic review',
    authors: 'Stian Larsen, Eirik Kristiansen, Roland van den Tillaar',
    year: 2021,
    source: 'PeerJ, 9, e10663',
    evidenceType: '체계적 문헌고찰',
    doi: '10.7717/peerj.10663',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/33520457/'),
    appRules: const [
      '개인 코칭은 여러 날짜의 동일 종목 수행과 기록된 RIR을 참고해 새 추천을 조정합니다.',
      '지난 3개 주의 수행량으로 주간 목표를 정하고 비교 근거가 부족하면 추가 증량을 하지 않습니다.',
    ],
    limitations:
        '주로 건강한 참가자의 최대 근력 연구입니다. 이 앱의 3주·4일 기준, 주간 2세트 조정, 상한과 휴식 비교 범위를 검증한 논문은 아닙니다. 운동량 증가나 근비대의 개인별 효과를 보장하지 않습니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 PubMed 초록의 대상·포함 기준·결과를 재확인했습니다. 개별 연구의 전체 자료를 재분석하지 않았습니다.',
  ),
  EvidenceReference(
    id: 'pelland_2026_dose_response',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '주간 운동량과 직접·간접 세트',
    takeaway: '운동량과 효과의 용량 반응·수익 체감을 참고하며, 개인의 하루 세트 상한을 정한 연구는 아닙니다.',
    title:
        'The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains',
    authors:
        'Joshua C. Pelland, Jacob F. Remmert, Zac P. Robinson, Seth R. Hinson, Michael C. Zourdos',
    year: 2026,
    source: 'Sports Medicine, 56(2), 481–505',
    evidenceType: '체계적 문헌고찰 · 메타회귀',
    doi: '10.1007/s40279-025-02344-w',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/41343037/'),
    appRules: const [
      '자동 추천은 이번 주 월요일부터 오늘까지의 완료 세트와 오늘 계획을 함께 보고 추가 운동량을 정합니다.',
      '검토한 복합 운동의 주동근은 1세트, 보조근은 0.5세트로 계산합니다.',
    ],
    limitations:
        '67개 연구, 2,058명의 집단 평균이며 남성 79.1%·여성 20.9%, 평균 나이 25.16세입니다. 고령자나 개인별 최적량을 확정하지 않습니다. 부위 분류와 일일 4–8세트·주간 6–16세트는 앱의 시작 계획이며, 논문이 개인별 상한을 정한 것은 아닙니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 PubMed와 출판사 초록의 대상·0.5 환산·결과를 확인했습니다. 본문은 구독 제한으로 전체 검토하지 못했습니다.',
  ),
  EvidenceReference(
    id: 'ramos_2024_split_full_body',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '분할 운동과 전신 운동 비교',
    takeaway: '운동량을 맞췄을 때 분할·전신 방식의 근력과 근비대 차이가 뚜렷하지 않았습니다.',
    title:
        'Efficacy of Split Versus Full-Body Resistance Training on Strength and Muscle Growth: A Systematic Review With Meta-Analysis',
    authors:
        'Domingo J. Ramos-Campo, Pedro J. Benito-Peinado, Luis Andreu-Caravaca, Miguel A. Rojo-Tirado, Jacobo Á. Rubio-Arias',
    year: 2024,
    source: 'Journal of Strength and Conditioning Research, 38(7), 1330–1340',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1519/JSC.0000000000004774',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/38595233/'),
    appRules: const [
      '오늘 부위를 직접 고르는 3·5분할과 부위 제한 없는 완전 추천을 제공합니다.',
      '분할 이름의 우열 대신 선택한 부위, 누적 운동량과 수행 기록을 우선합니다.',
    ],
    limitations:
        '운동량이 같을 때 분할과 전신 방식의 근력·근비대 차이가 뚜렷하지 않았습니다. 앱의 3·5분할 부위 조합 각각이 최적이라는 검증은 아닙니다.',
  ),
  EvidenceReference(
    id: 'brzycki-1993',
    category: EvidenceCategory.strengthEstimate,
    koreanTitle: '반복 기록으로 추정하는 1RM',
    takeaway: '중량과 반복으로 계산한 1RM은 실제 최대 중량과 다른 추정값입니다.',
    title: 'Strength Testing—Predicting a One-Rep Max from Reps-to-Fatigue',
    authors: 'Matt Brzycki',
    year: 1993,
    source: 'Journal of Physical Education, Recreation & Dance, 64(1), 88–90',
    evidenceType: '방법론 논문',
    doi: '10.1080/07303084.1993.10606684',
    officialUrl: Uri.parse('https://doi.org/10.1080/07303084.1993.10606684'),
    appRules: const [
      '완료한 중량과 반복 수에서 Brzycki 방식의 예상 1RM을 계산합니다.',
      'Epley·Brzycki 추정치와 그 산술평균을 참고값으로 표시합니다.',
    ],
    limitations:
        '반복 실패 지점까지 정확히 수행했다는 가정이 필요합니다. Epley·Brzycki 산술평균이 더 정확하다는 직접 검증 근거는 없으며, 훈련 수준·운동 종목·피로에 따라 오차가 생깁니다.',
  ),
  EvidenceReference(
    id: 'lesuer_1997_e1rm',
    category: EvidenceCategory.strengthEstimate,
    koreanTitle: '1RM 예측식의 종목별 오차',
    takeaway: '반복 기반 예측식의 정확도는 운동 종목에 따라 달라 실제 최대 중량으로 확정하지 않습니다.',
    title:
        'The Accuracy of Prediction Equations for Estimating 1-RM Performance in the Bench Press, Squat, and Deadlift',
    authors:
        'Dale A. LeSuer, James H. McCormick, Jerry L. Mayhew, Ronald L. Wasserstein, Michael D. Arnold',
    year: 1997,
    source: 'Journal of Strength and Conditioning Research, 11(4), 211–213',
    evidenceType: '예측식 검증 연구',
    doi: '10.1519/00124278-199711000-00001',
    officialUrl: Uri.parse('https://doi.org/10.1519/00124278-199711000-00001'),
    appRules: const [
      'Epley·Brzycki 등 반복 기반 1RM 예측식의 운동별 오차 가능성을 반영합니다.',
      '기록을 낮은 반복·중간 반복·고반복 구간으로 구분합니다. 11회 이상 기록은 참고용 e1RM만 표시하고 e1RM PR·추천 중량 계산에서는 제외하지만, 실제 중량·반복 PR에는 포함될 수 있습니다.',
    ],
    limitations:
        '표본은 웨이트 수업에 참여한 비훈련 대학생 67명이었고 운동별 정확도가 달랐습니다. 앱의 낮은 반복·중간 반복·고반복 참고 구간은 입력 반복 수의 제품 분류이며 검증된 정확도 등급은 아닙니다. 최대 노력 여부를 확인하지 않은 1회 기록도 실측 1RM으로 확정하지 않습니다.',
  ),
  EvidenceReference(
    id: 'acsm_currier_2026_resistance',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '건강한 성인의 저항운동 지침',
    takeaway: '꾸준한 점진적 저항운동을 우선하며 목표별 부하·주간 운동량을 참고합니다.',
    title:
        'American College of Sports Medicine Position Stand. Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews',
    authors:
        'Brad S. Currier, Alysha C. D’Souza, Maria A. Fiatarone Singh, Caroline V. Lowisz, Eric S. Rawson, Brad J. Schoenfeld, Abbie E. Smith-Ryan, Jeremy P. Steen, Gwendolyn A. Thomas, N. Travis Triplett, Tyrone A. Washington, Timothy J. Werner, Stuart M. Phillips',
    year: 2026,
    source: 'Medicine & Science in Sports & Exercise, 58(4), 851–872',
    evidenceType: 'ACSM 포지션 스탠드 · 우산형 문헌고찰',
    doi: '10.1249/MSS.0000000000003897',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/41843416/'),
    appRules: const [
      '근력 목표는 상대적으로 높은 강도, 근비대 목표는 높은 주간 볼륨을 우선합니다.',
      '근육군별 주간 완료 세트를 집계해 약 10세트 기준의 운동량 인사이트를 제공합니다.',
      '사용자 목표에 따라 중량·반복·세트 추천을 다르게 구성합니다.',
    ],
    limitations:
        '건강한 18세 이상 성인의 6주 이상 훈련 연구를 종합했으며 대부분 운동 경험이 적은 대상입니다. 비만·근감소증·허약 등 정의된 질환이 없는 대상으로 범위를 정했습니다. 자율조절의 근력 효과를 판단할 자료는 부족했고 앱의 정확한 중량·반복·세트 규칙이나 개인의 안전성을 검증하지 않았습니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 PubMed와 Europe PMC 제공 본문의 포함 기준·주요 결과·토의·적용 한계를 확인했습니다. 포함된 137개 고찰의 원자료 전체를 재현 검증한 것은 아닙니다.',
  ),
  EvidenceReference(
    id: 'acsm-2009',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '반복 수행에 따른 점진적 증량',
    takeaway: '수행 향상에 맞춘 부하 증가 원칙을 참고하며 현재 권고는 ACSM 2026과 함께 해석합니다.',
    title: 'Progression Models in Resistance Training for Healthy Adults',
    authors: 'American College of Sports Medicine',
    year: 2009,
    source: 'Medicine & Science in Sports & Exercise, 41(3), 687–708',
    evidenceType: 'ACSM 포지션 스탠드',
    doi: '10.1249/MSS.0b013e3181915670',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/19204579/'),
    appRules: const [
      '목표 반복 범위를 모두 달성하면 다음 운동의 중량을 올리는 점진적 과부하 규칙을 적용합니다.',
      '근력·근비대·근지구력 목표에 서로 다른 반복 범위와 휴식시간을 제안합니다.',
    ],
    limitations:
        '2009년 권고는 2026년 ACSM 포지션 스탠드로 업데이트되었습니다. 자동 추천은 장기 프로그램 전체를 대신하지 않으며 실제 수행 결과에 따라 조정해야 합니다.',
  ),
  EvidenceReference(
    id: 'grgic-2018',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '근력 훈련의 세트 사이 휴식',
    takeaway: '근력 향상에서 충분한 휴식을 고려하되 정확한 개인 최적 휴식시간을 확정하지 않습니다.',
    title:
        'Effects of Rest Interval Duration in Resistance Training on Measures of Muscular Strength: A Systematic Review',
    authors:
        'Jozo Grgic, Brad J. Schoenfeld, Mislav Skrepnik, Timothy B. Davies, Pavle Mikulic',
    year: 2018,
    source: 'Sports Medicine, 48(1), 137–151',
    evidenceType: '체계적 문헌고찰',
    doi: '10.1007/s40279-017-0788-x',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/28933024/'),
    appRules: const [
      '근력 목표에는 긴 휴식, 일반·근지구력 목표에는 짧거나 중간 휴식을 기본값으로 제시합니다.',
      '세트별 휴식시간은 추천값을 그대로 강제하지 않고 사용자가 수정할 수 있습니다.',
    ],
    limitations:
        '23개 연구, 491명에 대한 근력 결과가 중심이며 훈련 경험과 성별 분포가 균등하지 않았습니다. 근비대·체중 감량의 최적 휴식시간을 직접 확정하는 근거는 아닙니다.',
  ),
  EvidenceReference(
    id: 'nunes_2021_exercise_order',
    category: EvidenceCategory.exerciseOrder,
    koreanTitle: '우선 운동을 앞에 배치하는 이유',
    takeaway: '먼저 수행한 운동의 근력 향상 원칙을 참고하며 모든 사람의 운동 순서를 고정하지 않습니다.',
    title:
        'What Influence Does Resistance Exercise Order Have on Muscular Strength Gains and Muscle Hypertrophy?',
    authors:
        'João Pedro Nunes, Jozo Grgic, Paolo M. Cunha, Alex S. Ribeiro, Brad J. Schoenfeld, Belmiro F. de Salles, Edilson S. Cyrino',
    year: 2021,
    source: 'European Journal of Sport Science, 21(2), 149–157',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1080/17461391.2020.1733672',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/32077380/'),
    appRules: const [
      '근력 목표에서는 우선순위가 높은 복합 동작을 세션 앞쪽에 추천합니다.',
      '완료한 운동과 사용자 목표를 바탕으로 아직 수행하지 않은 다음 운동을 제안합니다.',
    ],
    limitations:
        '메타분석에 포함된 연구는 11개였습니다. 우선 운동의 근력 향상 근거는 있지만, 앱의 개별 운동 연결 순서 전체가 논문에서 직접 비교된 것은 아닙니다.',
  ),
  EvidenceReference(
    id: 'reynolds_2006_rm_prediction',
    category: EvidenceCategory.strengthEstimate,
    koreanTitle: '반복 수와 1RM 추정의 정확도',
    takeaway: '1RM 추정의 오차는 반복 수와 종목에 따라 달라 다른 운동에 같은 정확도를 보장하지 않습니다.',
    title:
        'Prediction of One Repetition Maximum Strength from Multiple Repetition Maximum Testing and Anthropometry',
    authors: 'Jeff M. Reynolds, Toryanno J. Gordon, Robert A. Robergs',
    year: 2006,
    source: 'Journal of Strength and Conditioning Research, 20(3), 584–592',
    evidenceType: '예측식 검증 연구',
    doi: '10.1519/R-15304.1',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/16937972/'),
    appRules: const [
      '반복 수에 따른 추정 오차를 고려하며 낮은 반복·중간 반복·고반복 참고 구간으로 표시합니다. 이 구간은 정확도 점수가 아닙니다.',
      'e1RM은 직접 측정한 1RM과 구분해 예상값으로 표시합니다.',
    ],
    limitations:
        '18–69세 성인 70명(남성 34명·여성 36명)의 체스트 프레스와 레그 프레스 결과입니다. 다른 운동과 높은 반복 구간에 동일한 정확도를 보장하지 않습니다.',
  ),
  EvidenceReference(
    id: 'schoenfeld_2017_weekly_volume',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '주간 세트 수와 근육 증가',
    takeaway: '평균적으로 높은 주간 운동량과 근육 증가가 관련되며 10세트가 개인의 절대 최소·최대치는 아닙니다.',
    title:
        'Dose-Response Relationship Between Weekly Resistance Training Volume and Increases in Muscle Mass: A Systematic Review and Meta-Analysis',
    authors: 'Brad J. Schoenfeld, Dan Ogborn, James W. Krieger',
    year: 2017,
    source: 'Journal of Sports Sciences, 35(11), 1073–1082',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1080/02640414.2016.1210197',
    officialUrl: Uri.parse('https://doi.org/10.1080/02640414.2016.1210197'),
    appRules: const [
      '완료한 근육군별 주간 세트 수를 집계해 근비대 운동량 인사이트를 제공합니다.',
      '단일 세션의 세트 수보다 한 주 동안 누적된 볼륨을 함께 봅니다.',
    ],
    limitations:
        '15개 연구의 34개 처치군을 분석했으며 높은 볼륨의 상한과 개인별 회복 차이는 확정하지 못했습니다. 주간 10세트는 절대적인 최소·최대치가 아닙니다.',
  ),
  EvidenceReference(
    id: 'refalo_2023_proximity_failure',
    category: EvidenceCategory.effort,
    koreanTitle: '매 세트를 실패까지 해야 할까',
    takeaway: '매번 실패 지점까지 할 필요가 있다고 확정하지 않으며 정확한 최적 RIR도 단정하지 않습니다.',
    title:
        'Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy: A Systematic Review with Meta-Analysis',
    authors:
        'Martin C. Refalo, Eric R. Helms, Eric T. Trexler, D. Lee Hamilton, Jackson J. Fyfe',
    year: 2023,
    source: 'Sports Medicine, 53(3), 649–665',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1007/s40279-022-01784-y',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/36334240/'),
    appRules: const [
      '모든 세트를 실패 지점까지 수행하도록 강제하지 않고 일반·실패 세트를 구분해 기록합니다.',
      '자동 추천은 일반 완료 세트를 우선하며 특정 RIR 값이 모두에게 최적이라고 단정하지 않습니다.',
    ],
    limitations:
        '포함 연구 15개의 실패 정의와 측정 방법이 서로 달랐습니다. 특정 RIR 값이 모든 사람과 운동에서 최적이라는 직접 근거는 아닙니다.',
  ),
  EvidenceReference(
    id: 'craven_2022_sleep_loss',
    category: EvidenceCategory.effort,
    koreanTitle: '수면 부족과 운동 수행 변화',
    takeaway: '수면 부족은 수행에 영향을 줄 수 있지만 앱의 감량 비율이나 부상 위험 감소를 검증한 연구는 아닙니다.',
    title:
        'Effects of Acute Sleep Loss on Physical Performance: A Systematic and Meta-Analytical Review',
    authors:
        'Jonathan Craven, Danielle McCartney, Ben Desbrow, Surendran Sabapathy, Phillip Bellinger, Llion Roberts, Christopher Irwin',
    year: 2022,
    source: 'Sports Medicine, 52(11), 2669–2690',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1007/s40279-022-01706-y',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/35708888/'),
    appRules: const [
      '회복 설문에서 피로 또는 수면 부족을 선택한 당일에만 운동량과 기록 기반 시작 중량을 보수적으로 낮춥니다.',
      '오래된 회복 응답은 다음 날 이후 추천에 적용하지 않습니다.',
    ],
    limitations:
        '69개 연구의 집단 평균 결과이고 연구 간 차이가 컸습니다. 앱의 세트 1개·중량 10%·유산소 시간 25% 감량 폭은 피로 응답에 따라 새 제안의 부담을 줄이려는 제품 규칙입니다. 이 조정 폭의 개인별 효과나 부상 위험 감소는 논문에서 검증하지 않았습니다.',
  ),
  EvidenceReference(
    id: 'acsm_garber_2011_prescription',
    category: EvidenceCategory.generalActivity,
    koreanTitle: '유산소·근력 활동을 함께 계획하기',
    takeaway: '주간 활동량과 개인 상태를 함께 보고 현재 할 수 있는 양부터 점진적으로 늘립니다.',
    title:
        'Quantity and Quality of Exercise for Developing and Maintaining Cardiorespiratory, Musculoskeletal, and Neuromotor Fitness in Apparently Healthy Adults',
    authors:
        'Carol E. Garber, Bryan Blissmer, Michael R. Deschenes, Barry A. Franklin, Michael J. Lamonte, I-Min Lee, David C. Nieman, David P. Swain; ACSM',
    year: 2011,
    source: 'Medicine & Science in Sports & Exercise, 43(7), 1334–1359',
    evidenceType: 'ACSM 포지션 스탠드',
    doi: '10.1249/MSS.0b013e318213fefb',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/21694556/'),
    appRules: const [
      '건강·체력 목표에서는 유산소와 주요 근육군 저항운동을 함께 구성합니다.',
      '훈련 경험과 현재 활동량에 따라 강도와 볼륨을 점진적으로 높이도록 안내합니다.',
      '앱은 주간 활동량을 여러 날에 배분하는 시작 제안으로 일반 30분, 활동 시간을 더 배정하는 감량 목표는 40분을 사용하며 시간에 맞춰 조절합니다.',
    ],
    limitations:
        '겉보기에 건강한 성인을 위한 일반 지침입니다. 앱의 30분·40분 기본값과 RPE 구간 분류는 논문이 직접 검증한 개인 처방이 아닙니다. 거리 목표는 같은 종목의 날짜별 시간·거리로 계산한 최근 최대 5일 속도의 중앙값이며, 구간을 많이 기록한 날이나 극단값의 영향을 줄이려는 제품 규칙입니다. 만성질환, 통증 또는 심혈관 위험이 있으면 의료진 평가와 개별 처방이 우선합니다.',
  ),
  EvidenceReference(
    id: 'who_bull_2020_pa_guideline',
    category: EvidenceCategory.generalActivity,
    koreanTitle: 'WHO 성인의 주간 신체활동 지침',
    takeaway: '중강도·고강도 주간 활동량을 함께 보며 권고량에 못 미친 활동도 의미가 있습니다.',
    title:
        'World Health Organization 2020 Guidelines on Physical Activity and Sedentary Behaviour',
    authors:
        'Fiona C. Bull, Salih S. Al-Ansari, Stuart Biddle, Katja Borodulin, Matthew P. Buman, Greet Cardon, Catherine Carty, Jean-Philippe Chaput, Sebastien Chastin, Roger Chou, Paddy C. Dempsey, Loretta DiPietro, Ulf Ekelund, Joseph Firth, Christine M. Friedenreich, Leandro Garcia, Muthoni Gichu, Russell Jago, Peter T. Katzmarzyk, Estelle Lambert, Michael Leitzmann, Karen Milton, Francisco B. Ortega, Chathuranga Ranasinghe, Emmanuel Stamatakis, Anne Tiedemann, Richard P. Troiano, Hidde P. van der Ploeg, Vicky Wari, Juana F. Willumsen',
    year: 2020,
    source: 'British Journal of Sports Medicine, 54(24), 1451–1462',
    evidenceType: 'WHO 국제 가이드라인',
    doi: '10.1136/bjsports-2020-102955',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/33239350/'),
    appRules: const [
      '건강·체력 목표의 주간 활동 계획에서 중강도와 고강도 유산소 활동을 함께 고려합니다.',
      '목표량에 못 미쳐도 수행한 활동을 기록하고 점진적으로 늘리도록 안내합니다.',
      '앱에서는 완료한 각 유산소 구간의 시간과 기록된 RPE를 이용해 중강도 환산 주간 시간을 단순 계산합니다. 서로 다른 강도의 구간을 평균으로 합치지 않습니다.',
    ],
    limitations:
        '인구집단 수준의 공중보건 권고로 개인별 운동 종목, 심박수 구간 또는 세션 강도를 직접 처방하지 않습니다. 앱의 정확한 RPE 경계와 주간 환산 로직은 가이드라인 자체가 검증한 알고리즘이 아니라 제품 휴리스틱입니다.',
  ),
  EvidenceReference(
    id: 'acsm_jakicic_2024_adiposity',
    category: EvidenceCategory.weightManagement,
    koreanTitle: '체중 관리와 전체 활동량',
    takeaway: '체중 관리는 운동량·섭취량 등 여러 요인의 영향을 받으며 특정 운동 시간의 감량 효과를 보장하지 않습니다.',
    title:
        'Physical Activity and Excess Body Weight and Adiposity for Adults: American College of Sports Medicine Consensus Statement',
    authors:
        'John M. Jakicic, Caroline M. Apovian, Daheia J. Barr-Anderson, Anita P. Courcoulas, Joseph E. Donnelly, Panteleimon Ekkekakis, Mark Hopkins, Estelle V. Lambert, Melissa A. Napolitano, Stella L. Volpe',
    year: 2024,
    source: 'Medicine & Science in Sports & Exercise, 56(10), 2076–2091',
    evidenceType: 'ACSM 합의문',
    doi: '10.1249/MSS.0000000000003520',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/39277776/'),
    appRules: const [
      '체중 감량 목표에서도 근력운동을 유지하면서 유산소 활동과 전체 활동량을 함께 제안합니다.',
      '운동 완료 기록을 체중 변화와 별개인 건강 행동 성과로 보여줍니다.',
      '앱은 감량 목표에서 활동 시간을 더 배정하는 시작 제안으로 지속 유산소 40분을 제시하고, 현재 수행 능력과 시간에 맞춰 조절하도록 안내합니다.',
    ],
    limitations:
        '체중과 체지방 변화는 섭취량, 수면, 약물, 질환 등 많은 요인의 영향을 받습니다. 40분 기본 세션은 합의문이 모든 개인에게 직접 처방한 값이 아니라 앱의 제품 휴리스틱이며, 앱은 체중 감량의 크기나 속도를 보장하지 않습니다.',
  ),
  EvidenceReference(
    id: 'schumann_2022_concurrent',
    category: EvidenceCategory.concurrentTraining,
    koreanTitle: '근력 운동과 유산소의 병행',
    takeaway: '병행 훈련은 가능하며 폭발력이 우선일 때는 세션 간격을 고려합니다.',
    title:
        'Compatibility of Concurrent Aerobic and Strength Training for Skeletal Muscle Size and Function: An Updated Systematic Review and Meta-Analysis',
    authors:
        'Moritz Schumann, Joshua F. Feuerbacher, Marvin Sünkeler, Nils Freitag, Bent R. Rønnestad, Kenji Doma, Tommy R. Lundberg',
    year: 2022,
    source: 'Sports Medicine, 52(3), 601–612',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1007/s40279-021-01587-7',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/34757594/'),
    appRules: const [
      '체중 감량·체력 목표에서 근력운동과 유산소 운동을 같은 계획 안에 함께 제안할 수 있습니다.',
      '폭발적 근력이 중요한 경우 두 운동 방식의 세션 간격을 고려하도록 안내합니다.',
    ],
    limitations:
        '최대근력과 근비대는 대체로 저해되지 않았지만 같은 세션에서 폭발적 근력 향상이 둔화될 가능성이 있었습니다. 개인 회복과 종목 특성이 우선합니다.',
  ),
  EvidenceReference(
    id: 'helgerud_2007_4x4',
    category: EvidenceCategory.cardiorespiratory,
    koreanTitle: '4분 고강도 인터벌의 연구 범위',
    takeaway: '건강한 훈련 남성의 특정 인터벌 결과이며 모든 사용자에게 같은 강도를 적용하는 근거는 아닙니다.',
    title:
        'Aerobic High-Intensity Intervals Improve VO₂max More Than Moderate Training',
    authors:
        'Jan Helgerud, Kjetill Høydal, Eivind Wang, Trine Karlsen, Pål Berg, Marius Bjerkaas, Thomas Simonsen, Cecilie Helgesen, Nina Hjorth, Ragnhild Bach, Jan Hoff',
    year: 2007,
    source: 'Medicine & Science in Sports & Exercise, 39(4), 665–671',
    evidenceType: '무작위 대조시험',
    doi: '10.1249/mss.0b013e3180304570',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/17414804/'),
    appRules: const [
      '추천 엔진은 4분 고강도·3분 회복을 반복하는 4×4 구조를 지원하지만, 현재 앱은 숙련도와 고강도 운동 가능 여부를 확인하지 않으므로 자동 활성화하지 않고 지속 운동을 제안합니다.',
      '고강도 세션은 일반 유산소와 구분하고 충분한 회복을 포함합니다.',
    ],
    limitations:
        '건강하고 중간 수준으로 훈련된 남성 40명을 8주간 관찰한 연구입니다. 앱의 최근 28일 중 20분 이상 유산소를 기록한 서로 다른 6일 조건은 구간 수로 훈련 경험이 부풀려지는 것을 막는 제품 규칙입니다. RPE 7–9 안내와 이 조건이 개인의 고강도 운동 적합성이나 안전성을 검증하지는 않으며, 초보자·여성·고령자·질환자에게 동일 강도를 그대로 적용할 근거는 아닙니다.',
  ),
  EvidenceReference(
    id: 'singer_2024_rest_hypertrophy',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '근비대와 세트 사이 휴식',
    takeaway: '60초보다 긴 휴식의 작은 이점이 시사되지만, 90초가 개인의 최적값이나 상한은 아닙니다.',
    title:
        'Give it a rest: a systematic review with Bayesian meta-analysis on the effect of inter-set rest interval duration on muscle hypertrophy',
    authors:
        'Alec Singer, Milo Wolf, Leonardo Generoso, Elizabeth Arias, Kenneth Delcastillo, Edwin Echevarria, Amaris Martinez, Patroklos Androulakis Korakakis, Martin C. Refalo, Paul A. Swinton, Brad J. Schoenfeld',
    year: 2024,
    source: 'Frontiers in Sports and Active Living, 6, 1429789',
    evidenceType: '체계적 문헌고찰 · 베이지안 메타분석',
    doi: '10.3389/fspor.2024.1429789',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/39205815/'),
    appRules: const [
      '근비대 훈련에서도 다음 세트의 수행을 유지할 수 있도록 휴식시간을 고려합니다.',
      '복합 120초·보조 90초는 수정 가능한 시작값이며 짧은 휴식을 강제하거나 90초 이후의 휴식을 무효로 취급하지 않습니다.',
    ],
    limitations:
        '건강한 성인 대상 9개 연구이며 대부분 젊은 비훈련자, 훈련 기간은 5–10주였습니다. 가슴·등·어깨의 직접 측정과 숙련자 하위 자료가 부족합니다. 90초를 넘는 휴식의 추가 차이가 명확하지 않았다는 결과는 효과가 없거나 정확히 90초가 최적이라는 뜻이 아닙니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 PubMed와 Frontiers 본문의 방법·대상·결과·토의·한계를 확인했습니다. 개별 연구 원자료를 재분석하지 않았습니다.',
  ),
  EvidenceReference(
    id: 'robinson_2024_proximity_failure',
    category: EvidenceCategory.effort,
    koreanTitle: '실패까지 남은 횟수와 운동 목표',
    takeaway: '실패에 가까운 수행과 근비대의 관계를 참고하되, 근력과 근비대의 최적 RIR을 하나로 정하지 않습니다.',
    title:
        'Exploring the Dose-Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy: A Series of Meta-Regressions',
    authors:
        'Zac P. Robinson, Joshua C. Pelland, Jacob F. Remmert, Martin C. Refalo, Ivan Jukic, James Steele, Michael C. Zourdos',
    year: 2024,
    source: 'Sports Medicine, 54(9), 2209–2231',
    evidenceType: '탐색적 메타회귀',
    doi: '10.1007/s40279-024-02069-2',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/38970765/'),
    appRules: const [
      '근비대 목표에서는 충분한 노력을 고려하면서 모든 세트를 실패까지 해야 한다고 강제하지 않습니다.',
      '사용자가 기록한 RIR을 수행과 함께 참고하며, 2–3회 여유나 증량 조건을 개인별 최적값으로 표시하지 않습니다.',
    ],
    limitations:
        'RIR은 포함 연구의 설명으로 추정했고 모델 적합도에는 한계가 있습니다. 근비대는 실패에 가까울수록 커지는 방향이었고 근력은 폭넓은 RIR에서 비슷했지만, 정확한 개인 최적 RIR이나 이 앱의 RIR 2 증량 기준을 검증하지 않았습니다. 추정된 연구 RIR과 사용자가 실제로 느껴 입력한 값도 동일한 측정이 아닙니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 PubMed와 출판사 초록의 방법·결과·결론을 확인했습니다. 본문은 구독 제한으로 전체 검토하지 못했습니다.',
  ),
  EvidenceReference(
    id: 'halperin_2022_rir_accuracy',
    category: EvidenceCategory.effort,
    koreanTitle: '남은 횟수 RIR 추정의 오차',
    takeaway: '사용자가 판단한 RIR에는 오차가 있으며, 운동 경험만으로 정확성을 보장하지 않습니다.',
    title:
        'Accuracy in Predicting Repetitions to Task Failure in Resistance Exercise: A Scoping Review and Exploratory Meta-analysis',
    authors:
        'Israel Halperin, Tomer Malleron, Itai Har-Nir, Patroklos Androulakis-Korakakis, Milo Wolf, James Fisher, James Steele',
    year: 2022,
    source: 'Sports Medicine, 52(2), 377–390',
    evidenceType: '범위 문헌고찰 · 탐색적 메타분석',
    doi: '10.1007/s40279-021-01559-x',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/34542869/'),
    appRules: const [
      'RIR은 사용자의 주관적 추정으로 기록하며 실측 최대 반복 수나 안전성 점수로 취급하지 않습니다.',
      '여러 날짜의 완료 수행과 함께 참고하고 새 계획에 과거의 실제 RIR을 복사하지 않습니다.',
    ],
    limitations:
        '건강한 참가자 414명의 12개 연구를 메타분석했습니다. 남은 횟수를 평균 0.95회 적게 예측했지만 연구 간 이질성이 매우 컸습니다(I² 97.9%). 이는 개인 기록에 1회를 더해 보정할 근거가 아니며, RIR 2가 정확한 여유나 안전을 보장하지도 않습니다. 여성·고령자·질환자 각각의 정확도를 확정하지 않습니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 PubMed와 출판사 초록의 포함 기준·오차 결과·한계를 확인했습니다. 본문 전체와 개별 참가자 자료는 재검증하지 않았습니다. 온라인 공개는 2021년, 권호 연도는 2022년입니다.',
  ),
  EvidenceReference(
    id: 'hickmott_2022_autoregulation',
    category: EvidenceCategory.trainingPrescription,
    koreanTitle: '자율조절과 고정 계획의 비교',
    takeaway: '부하 자율조절과 고정 처방의 근력 차이가 명확하지 않아 자율조절이 항상 더 좋다고 단정하지 않습니다.',
    title:
        'The Effect of Load and Volume Autoregulation on Muscular Strength and Hypertrophy: A Systematic Review and Meta-Analysis',
    authors:
        'Landyn M. Hickmott, Philip D. Chilibeck, Keely A. Shaw, Scotty J. Butcher',
    year: 2022,
    source: 'Sports Medicine - Open, 8, 9',
    evidenceType: '체계적 문헌고찰 · 메타분석',
    doi: '10.1186/s40798-021-00404-9',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/35038063/'),
    appRules: const [
      '개인 코칭은 실제 수행을 참고하는 한 방법으로 설명하고 고정 계획보다 우월하다고 보장하지 않습니다.',
      '수행 기록이 부족하면 기본 계획을 유지하고 사용자가 제안된 중량·세트 수를 수정할 수 있게 합니다.',
    ],
    limitations:
        '부하 비교 6개 연구 133명의 근력 차이는 2.07kg(95% 신뢰구간 −0.32~4.46)로 명확하지 않았습니다. 대부분 젊은 훈련 남성이며 여성만 포함한 부하 연구는 청소년 대상이었습니다. 운동량 비교는 속도 손실 측정에 따른 별도 연구로, 속도를 측정하지 않는 앱의 주간 ±2세트나 RIR 조정 규칙을 검증하지 않습니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 출판사 본문의 포함 기준·참가자 특성·부하/운동량 결과·한계를 확인했습니다. 포함 연구의 원자료 전체를 재분석하지 않았습니다.',
  ),
  EvidenceReference(
    id: 'cox_2026_mhealth_resistance',
    category: EvidenceCategory.digitalTraining,
    koreanTitle: '모바일 저항운동 안내의 효과와 한계',
    takeaway: '모바일 운동 안내의 평균 효과를 참고하되 이 앱이나 특정 추천 기능의 효과가 검증됐다고 주장하지 않습니다.',
    title:
        'Effects of mHealth interventions to prescribe resistance training: a systematic review and meta-analysis of randomized controlled trials',
    authors:
        'Emily R. Cox, Sam Beacroft, Anna K. Jansson, Levi Wade, Mitch J. Duncan, David R. Lubans, Sara L. Robards, Manuel Leitner, Niklas Gutberlet, Ronald C. Plotnikoff',
    year: 2026,
    source:
        'International Journal of Behavioral Nutrition and Physical Activity, 23, 7',
    evidenceType: '체계적 문헌고찰 · 무작위 대조시험 메타분석',
    doi: '10.1186/s12966-025-01868-8',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/41430613/'),
    appRules: const [
      '운동 계획과 실제 기록을 구분하고 처방 내용·진행 이유·검토 범위를 확인할 수 있게 설명합니다.',
      '디지털 안내 연구와 Setflow 자체의 효과 검증을 구분하며 개별 추천·버튼·기록 방식의 효과를 보장하지 않습니다.',
    ],
    limitations:
        '32개 무작위 대조시험 15,045명이며 임상 대상이 많고 건강한 성인 대상은 6개 연구였습니다. 18개 연구에서 무중재·통상관리 대비 작은 신경근 체력 개선이 있었지만 처방 보고 부족·짧은 기간·방법론적 우려·출판 편향 가능성이 있습니다. 참여 변화 연구는 2개뿐이므로 지속 참여 향상이나 이 앱의 효과를 확정하지 않습니다.',
    reviewedOn: '2026-10-14',
    reviewScope:
        '공식 출판사 본문의 방법·대상·결과·위험 평가·토의·한계를 확인했습니다. 온라인 공개는 2025-12-22이며 권호 연도는 2026년입니다. Setflow를 평가한 연구가 아닙니다.',
  ),
]);

final evidenceCatalogById = Map<String, EvidenceReference>.unmodifiable({
  for (final reference in evidenceCatalog) reference.id: reference,
});
