enum EvidenceCategory {
  strengthEstimate('근력 추정'),
  trainingPrescription('운동 처방'),
  exerciseOrder('운동 순서'),
  effort('운동 강도와 실패 지점'),
  generalActivity('건강 활동량'),
  weightManagement('체중 관리'),
  concurrentTraining('근력·유산소 병행'),
  cardiorespiratory('심폐 체력');

  const EvidenceCategory(this.label);

  final String label;
}

class EvidenceReference {
  const EvidenceReference({
    required this.id,
    required this.category,
    required this.title,
    required this.authors,
    required this.year,
    required this.source,
    required this.evidenceType,
    required this.officialUrl,
    required this.appRules,
    required this.limitations,
    this.doi,
  });

  final String id;
  final EvidenceCategory category;
  final String title;
  final String authors;
  final int year;
  final String source;
  final String evidenceType;
  final String? doi;
  final Uri officialUrl;
  final List<String> appRules;
  final String limitations;
}

final evidenceCatalog = List<EvidenceReference>.unmodifiable([
  EvidenceReference(
    id: 'brzycki-1993',
    category: EvidenceCategory.strengthEstimate,
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
      '낮은 반복 기록을 더 신뢰합니다. 11회 이상 기록은 참고용 e1RM만 표시하고 e1RM PR·추천 중량 계산에서는 제외하지만, 실제 중량·반복 PR에는 포함될 수 있습니다.',
    ],
    limitations:
        '표본은 웨이트 수업에 참여한 비훈련 대학생 67명이었고 운동별 정확도가 달랐습니다. 앱의 높음·보통·참고용 구간은 안전한 해석을 돕는 제품 규칙이지 임상적으로 검증된 등급은 아닙니다.',
  ),
  EvidenceReference(
    id: 'acsm_currier_2026_resistance',
    category: EvidenceCategory.trainingPrescription,
    title:
        'Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews',
    authors:
        'Brad S. Currier, Alysha C. D’Souza, Maria A. Fiatarone Singh, Caroline V. Lowisz, Eric S. Rawson, Brad J. Schoenfeld, Abbie E. Smith-Ryan, Jeremy P. Steen, Gwendolyn A. Thomas, N. Travis Triplett, Tyrone A. Washington, Timothy J. Werner, Stuart M. Phillips',
    year: 2026,
    source: 'Medicine & Science in Sports & Exercise',
    evidenceType: 'ACSM 포지션 스탠드 · 우산형 문헌고찰',
    doi: '10.1249/MSS.0000000000003897',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/41843416/'),
    appRules: const [
      '근력 목표는 상대적으로 높은 강도, 근비대 목표는 높은 주간 볼륨을 우선합니다.',
      '근육군별 주간 완료 세트를 집계해 약 10세트 기준의 운동량 인사이트를 제공합니다.',
      '사용자 목표에 따라 중량·반복·세트 추천을 다르게 구성합니다.',
    ],
    limitations:
        '건강한 성인의 집단 평균 근거이며 개인의 부상, 질환, 회복 상태를 평가하지 않습니다. 앱의 정확한 중량·반복 수는 연구 결과를 보수적으로 단순화한 규칙입니다.',
  ),
  EvidenceReference(
    id: 'acsm-2009',
    category: EvidenceCategory.trainingPrescription,
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
    title:
        'Prediction of One Repetition Maximum Strength from Multiple Repetition Maximum Testing and Anthropometry',
    authors: 'Jeff M. Reynolds, Toryanno J. Gordon, Robert A. Robergs',
    year: 2006,
    source: 'Journal of Strength and Conditioning Research, 20(3), 584–592',
    evidenceType: '예측식 검증 연구',
    doi: '10.1519/R-15304.1',
    officialUrl: Uri.parse('https://pubmed.ncbi.nlm.nih.gov/16937972/'),
    appRules: const [
      '반복 기록으로 최대근력을 추정하되 낮은 반복 기록에 더 높은 신뢰도를 부여합니다.',
      'e1RM은 직접 측정한 1RM과 구분해 예상값으로 표시합니다.',
    ],
    limitations:
        '18–69세 성인 70명(남성 34명·여성 36명)의 체스트 프레스와 레그 프레스 결과입니다. 다른 운동과 높은 반복 구간에 동일한 정확도를 보장하지 않습니다.',
  ),
  EvidenceReference(
    id: 'schoenfeld_2017_weekly_volume',
    category: EvidenceCategory.trainingPrescription,
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
    id: 'acsm_garber_2011_prescription',
    category: EvidenceCategory.generalActivity,
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
      '앱은 목표에 따라 기본 지속 세션을 30분 또는 40분으로 나누고, 기록된 RPE를 주간 활동량 환산에 사용합니다.',
    ],
    limitations:
        '겉보기에 건강한 성인을 위한 일반 지침입니다. 앱의 30분·40분 기본값, RPE 구간 분류, 최근 최대 5회 중앙 속도로 계산하는 거리 목표는 논문이 직접 검증한 개인 처방이 아니라 제품 휴리스틱입니다. 만성질환, 통증 또는 심혈관 위험이 있으면 의료진 평가와 개별 처방이 우선합니다.',
  ),
  EvidenceReference(
    id: 'who_bull_2020_pa_guideline',
    category: EvidenceCategory.generalActivity,
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
      '앱에서는 기록된 RPE를 이용해 중강도 환산 주간 시간을 단순 계산합니다.',
    ],
    limitations:
        '인구집단 수준의 공중보건 권고로 개인별 운동 종목, 심박수 구간 또는 세션 강도를 직접 처방하지 않습니다. 앱의 정확한 RPE 경계와 주간 환산 로직은 가이드라인 자체가 검증한 알고리즘이 아니라 제품 휴리스틱입니다.',
  ),
  EvidenceReference(
    id: 'acsm_jakicic_2024_adiposity',
    category: EvidenceCategory.weightManagement,
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
      '앱은 감량 목표의 기본 지속 유산소 세션을 40분으로 제시합니다.',
    ],
    limitations:
        '체중과 체지방 변화는 섭취량, 수면, 약물, 질환 등 많은 요인의 영향을 받습니다. 40분 기본 세션은 합의문이 모든 개인에게 직접 처방한 값이 아니라 앱의 제품 휴리스틱이며, 앱은 체중 감량의 크기나 속도를 보장하지 않습니다.',
  ),
  EvidenceReference(
    id: 'schumann_2022_concurrent',
    category: EvidenceCategory.concurrentTraining,
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
        '건강하고 중간 수준으로 훈련된 남성 40명을 8주간 관찰한 연구입니다. 앱의 최근 4주 6회 이상 같은 인터벌 활성 조건과 RPE 7–9 표시는 안전한 적용을 위한 제품 휴리스틱이며, 초보자·여성·고령자·질환자에게 동일 강도를 그대로 적용할 근거는 아닙니다.',
  ),
]);

final evidenceCatalogById = Map<String, EvidenceReference>.unmodifiable({
  for (final reference in evidenceCatalog) reference.id: reference,
});
