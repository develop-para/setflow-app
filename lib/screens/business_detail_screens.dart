import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum BusinessTool {
  profile,
  calendar,
  refunds,
  plan,
  notifications,
  withdraw,
  badges,
  contentReports,
  sanctions,
  minorAlerts,
  ranking,
  ocr,
  plans,
  keywords,
  logs,
}

class BusinessToolScreen extends StatefulWidget {
  const BusinessToolScreen({required this.tool, required this.role, super.key});
  final BusinessTool tool;
  final UserRole role;

  @override
  State<BusinessToolScreen> createState() => _BusinessToolScreenState();
}

class _BusinessToolScreenState extends State<BusinessToolScreen> {
  bool first = true;
  bool second = true;
  double slider = 72;
  final keywords = <String>['무조건', '기적', '100% 보장', '한 달 완성'];

  String get title => switch (widget.tool) {
    BusinessTool.profile =>
      widget.role == UserRole.gym ? '헬스장 프로필 편집' : '트레이너 프로필 편집',
    BusinessTool.calendar => '코칭 캘린더',
    BusinessTool.refunds => '환불 및 미정산 내역',
    BusinessTool.plan => '플랜 관리',
    BusinessTool.notifications => '알림 설정',
    BusinessTool.withdraw => '계정 탈퇴',
    BusinessTool.badges => '배지 발급 관리',
    BusinessTool.contentReports => '커뮤니티 신고 큐',
    BusinessTool.sanctions => '제재 이력',
    BusinessTool.minorAlerts => '미성년자 위험 신호',
    BusinessTool.ranking => '랭킹 알고리즘 설정',
    BusinessTool.ocr => 'OCR 모델 및 한도',
    BusinessTool.plans => '구독 플랜 정책',
    BusinessTool.keywords => '금지 키워드 관리',
    BusinessTool.logs => '시스템 로그',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: _content(context),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    return switch (widget.tool) {
      BusinessTool.profile => _profile(context),
      BusinessTool.calendar => _calendar(context),
      BusinessTool.refunds => _refunds(context),
      BusinessTool.plan => _plan(context),
      BusinessTool.notifications => _notifications(),
      BusinessTool.withdraw => _withdraw(context),
      BusinessTool.badges => _badges(context),
      BusinessTool.contentReports => _reports(context),
      BusinessTool.sanctions => _sanctions(),
      BusinessTool.minorAlerts => _minorAlerts(context),
      BusinessTool.ranking => _ranking(context),
      BusinessTool.ocr => _ocr(context),
      BusinessTool.plans => _plans(context),
      BusinessTool.keywords => _keywords(context),
      BusinessTool.logs => _logs(),
    };
  }

  List<Widget> _profile(BuildContext context) => [
    Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 52,
            backgroundColor:
                (widget.role == UserRole.gym
                        ? SetflowColors.purple
                        : SetflowColors.blue)
                    .withValues(alpha: .15),
            child: Icon(
              widget.role == UserRole.gym ? Icons.apartment : Icons.person,
              size: 50,
              color: widget.role == UserRole.gym
                  ? SetflowColors.purple
                  : SetflowColors.blue,
            ),
          ),
          const Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 17,
              backgroundColor: SetflowColors.primary,
              child: Icon(
                Icons.camera_alt_outlined,
                size: 17,
                color: SetflowColors.ink,
              ),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 24),
    TextField(
      decoration: InputDecoration(
        labelText: widget.role == UserRole.gym ? '헬스장명' : '이름',
        hintText: widget.role == UserRole.gym ? '모션짐 강남점' : '김코치',
      ),
    ),
    const SizedBox(height: 12),
    const TextField(
      maxLines: 3,
      decoration: InputDecoration(
        labelText: '소개',
        hintText: '전문 분야와 코칭 철학을 소개해주세요.',
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      decoration: InputDecoration(
        labelText: widget.role == UserRole.gym ? '위치' : '경력',
        hintText: widget.role == UserRole.gym ? '서울 강남구' : '퍼스널 트레이닝 8년',
      ),
    ),
    const SizedBox(height: 20),
    PrimaryButton(
      label: '프로필 저장',
      onPressed: () => showMessage(context, '프로필을 저장했습니다.'),
    ),
  ];

  List<Widget> _calendar(BuildContext context) => [
    const SetflowCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Day(label: '월', count: 3),
          _Day(label: '화', count: 5),
          _Day(label: '수', count: 2),
          _Day(label: '목', count: 4),
          _Day(label: '금', count: 3),
          _Day(label: '토', count: 1),
        ],
      ),
    ),
    const SizedBox(height: 22),
    const SectionTitle('오늘 일정'),
    const SizedBox(height: 8),
    for (final item in const [
      ('10:00', '박민지', '운동 기록 피드백'),
      ('13:30', '이준호', '4주차 상담'),
      ('17:00', '정민아', '루틴 수정'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: SetflowColors.primary.withValues(alpha: .18),
          child: Text(
            item.$1.substring(0, 2),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(
          item.$2,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${item.$1} · ${item.$3}'),
        trailing: Checkbox(
          value: false,
          onChanged: (_) => showMessage(context, '${item.$2} 일정을 완료했습니다.'),
        ),
      ),
  ];

  List<Widget> _refunds(BuildContext context) => [
    const Row(
      children: [
        MetricCard(
          label: '미정산',
          value: '1.28',
          suffix: '백만원',
          icon: Icons.hourglass_bottom,
          tint: SetflowColors.orange,
        ),
        SizedBox(width: 10),
        MetricCard(
          label: '환불 처리',
          value: '3',
          suffix: '건',
          icon: Icons.replay,
          tint: SetflowColors.red,
        ),
      ],
    ),
    const SizedBox(height: 22),
    for (final item in const [
      ('박민지', '중도 해지', '검토 중'),
      ('이준호', '결제 오류', '환불 완료'),
      ('최서연', '서비스 불만족', '분쟁 중'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SetflowCard(
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFFFEFEF),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: SetflowColors.red,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.$3,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: SetflowColors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _plan(BuildContext context) => [
    const SetflowCard(
      color: SetflowColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('현재 플랜', style: TextStyle(color: Colors.white70, fontSize: 11)),
          SizedBox(height: 5),
          Text(
            'PRO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          Text('관리 회원 12 / 50명', style: TextStyle(color: Colors.white70)),
        ],
      ),
    ),
    const SizedBox(height: 20),
    const SectionTitle('플랜 비교'),
    const SizedBox(height: 8),
    for (final item in const [
      ('스타터', '무료', '회원 1명'),
      ('프로', r'$39/월', '회원 4~50명'),
      ('엔터프라이즈', '별도 문의', '회원 51~500명+'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SetflowCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.$3,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.$2,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _notifications() => [
    SwitchListTile(
      title: const Text('새 상담 알림'),
      value: first,
      onChanged: (value) => setState(() => first = value),
    ),
    SwitchListTile(
      title: const Text('피드백 마감 알림'),
      value: second,
      onChanged: (value) => setState(() => second = value),
    ),
    SwitchListTile(
      title: const Text('정산 완료 알림'),
      value: true,
      onChanged: (_) {},
    ),
    SwitchListTile(
      title: const Text('마켓 성과 리포트'),
      value: false,
      onChanged: (_) {},
    ),
  ];

  List<Widget> _withdraw(BuildContext context) => [
    const SetflowCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: SetflowColors.red),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              '탈퇴 요청 후 30일 동안 계정이 비활성화됩니다. 관리 회원에게 알림이 발송되고 미정산 수익은 영업일 10일 이내 최종 정산됩니다.',
              style: TextStyle(height: 1.5, color: SetflowColors.secondaryText),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 18),
    const TextField(
      maxLines: 3,
      decoration: InputDecoration(labelText: '탈퇴 사유'),
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: () => showMessage(context, '데모에서는 탈퇴 요청을 실제 처리하지 않습니다.'),
      style: FilledButton.styleFrom(
        backgroundColor: SetflowColors.red,
        minimumSize: const Size.fromHeight(54),
      ),
      child: const Text('탈퇴 요청'),
    ),
  ];

  List<Widget> _badges(BuildContext context) => [
    const TextField(
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: '사용자 검색',
      ),
    ),
    const SizedBox(height: 18),
    for (final item in const [
      ('김코치', '국가공인 · 사업자', true),
      ('박트레이너', '민간자격', true),
      ('이코치', '갱신 필요', false),
    ])
      SwitchListTile(
        secondary: CircleAvatar(child: Text(item.$1.characters.first)),
        title: Text(
          item.$1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.$2),
        value: item.$3,
        onChanged: (_) => showMessage(context, '${item.$1} 배지 상태를 변경했습니다.'),
      ),
  ];

  List<Widget> _reports(BuildContext context) => [
    for (final item in const [
      ('Red', '불법 약물 판매 의심', '38분 남음'),
      ('Orange', '과도한 비방 표현', '8시간 남음'),
      ('Yellow', '부적절한 홍보', '2일 남음'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: SetflowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _reportColor(item.$1).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      item.$1,
                      style: TextStyle(
                        color: _reportColor(item.$1),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.$3,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.$2,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => showMessage(context, '신고 상세 검토를 시작했습니다.'),
                child: const Text('검토하기'),
              ),
            ],
          ),
        ),
      ),
  ];

  Color _reportColor(String grade) => grade == 'Red'
      ? SetflowColors.red
      : grade == 'Orange'
      ? SetflowColors.orange
      : SetflowColors.primary;

  List<Widget> _sanctions() => [
    for (final item in const [
      ('운동초보', '경고', '부적절한 댓글'),
      ('다이어터', '7일 정지', '반복 신고'),
      ('헬스왕', '30일 정지', '금지 콘텐츠'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFEFEF),
          child: Icon(Icons.gavel_outlined, color: SetflowColors.red),
        ),
        title: Text(
          item.$1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.$3),
        trailing: Text(
          item.$2,
          style: const TextStyle(
            fontSize: 11,
            color: SetflowColors.red,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
  ];

  List<Widget> _minorAlerts(BuildContext context) => [
    const SetflowCard(
      child: Row(
        children: [
          Icon(Icons.child_care, color: SetflowColors.orange),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              '위험 행동 패턴은 최소 수집 원칙으로 탐지하며 운영자 검토 전 자동 제재하지 않습니다.',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    for (final item in const [
      ('user_2481', '과도한 체중 감량 목표 반복'),
      ('user_5130', '심야 운동 7일 연속'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          item.$1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.$2),
        trailing: OutlinedButton(
          onPressed: () => showMessage(context, '계정 안전 검토를 시작했습니다.'),
          child: const Text('검토'),
        ),
      ),
  ];

  List<Widget> _ranking(BuildContext context) => [
    const SetflowCard(
      child: Text(
        'Final Score = Base Score × Time Decay − Penalty',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    const SizedBox(height: 18),
    Text('조회 가중치 ${slider.toInt()}'),
    Slider(
      value: slider,
      min: 0,
      max: 100,
      onChanged: (value) => setState(() => slider = value),
    ),
    const ListTile(title: Text('상담 가중치'), trailing: Text('40')),
    const ListTile(title: Text('구매 가중치'), trailing: Text('80')),
    const ListTile(title: Text('72시간 미응답 패널티'), trailing: Text('-100')),
    const SizedBox(height: 18),
    PrimaryButton(
      label: '파라미터 저장',
      onPressed: () => showMessage(context, '변경 이력을 남기고 랭킹 재계산을 예약했습니다.'),
    ),
  ];

  List<Widget> _ocr(BuildContext context) => [
    const ListTile(
      title: Text('현재 비전 모델'),
      subtitle: Text('Gemini Flash'),
      trailing: Icon(Icons.chevron_right),
    ),
    ListTile(
      title: const Text('월간 OCR 한도'),
      subtitle: Slider(
        value: slider.clamp(10, 100),
        min: 10,
        max: 100,
        divisions: 9,
        onChanged: (value) => setState(() => slider = value),
      ),
      trailing: Text('${slider.clamp(10, 100).toInt()}건'),
    ),
    SwitchListTile(
      title: const Text('낮은 신뢰도 필드 경고'),
      value: first,
      onChanged: (value) => setState(() => first = value),
    ),
    const SizedBox(height: 18),
    PrimaryButton(
      label: 'OCR 설정 저장',
      onPressed: () => showMessage(context, 'OCR 설정을 저장했습니다.'),
    ),
  ];

  List<Widget> _plans(BuildContext context) => [
    for (final item in const [
      ('일반 무료', r'$0', '루틴 4개'),
      ('일반 프리미엄', r'$3.99', '루틴 무제한 · OCR'),
      ('트레이너 프로', r'$39', '회원 4~50명'),
      ('엔터프라이즈', '구간제', '회원 51~500명+'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SetflowCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.$3,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.$2,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                onPressed: () =>
                    showMessage(context, '${item.$1} 정책 편집을 열었습니다.'),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _keywords(BuildContext context) => [
    TextField(
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) setState(() => keywords.add(value.trim()));
      },
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.add),
        hintText: '키워드 입력 후 Enter',
      ),
    ),
    const SizedBox(height: 18),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keywords
          .map(
            (item) => InputChip(
              label: Text(item),
              onDeleted: () => setState(() => keywords.remove(item)),
            ),
          )
          .toList(),
    ),
  ];

  List<Widget> _logs() => [
    const Row(
      children: [
        MetricCard(
          label: '업타임',
          value: '99.98',
          suffix: '%',
          icon: Icons.cloud_done_outlined,
          tint: SetflowColors.green,
        ),
        SizedBox(width: 10),
        MetricCard(
          label: '오류율',
          value: '0.02',
          suffix: '%',
          icon: Icons.error_outline,
          tint: SetflowColors.red,
        ),
      ],
    ),
    const SizedBox(height: 22),
    for (final item in const [
      ('08:21:32', 'INFO', '정산 배치 완료 · 284건'),
      ('08:18:05', 'WARN', 'OCR 응답 지연 · 1.8초'),
      ('08:02:44', 'INFO', '랭킹 재계산 완료'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Text(
          item.$1,
          style: const TextStyle(
            fontSize: 10,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        title: Text(
          item.$3,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: Text(
          item.$2,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: item.$2 == 'WARN'
                ? SetflowColors.orange
                : SetflowColors.green,
          ),
        ),
      ),
  ];
}

class _Day extends StatelessWidget {
  const _Day({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: SetflowColors.secondaryText,
        ),
      ),
      const SizedBox(height: 7),
      CircleAvatar(
        radius: 18,
        backgroundColor: count > 3 ? SetflowColors.primary : SetflowColors.soft,
        child: Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );
}
