import 'package:flutter/material.dart';

import '../member_navigation.dart';
import '../theme/icons.dart';
import 'common.dart';

extension MemberDestinationPresentation on MemberDestination {
  String get label => switch (this) {
    MemberDestination.home => '홈',
    MemberDestination.together => '함께',
    MemberDestination.record => '기록',
    MemberDestination.community => '커뮤니티',
    MemberDestination.my => '마이',
    MemberDestination.routines => '내 루틴',
    MemberDestination.market => '전문가 루틴',
    MemberDestination.library => '운동 찾기',
    MemberDestination.dashboard => '대시보드',
    MemberDestination.body => '체성분',
    MemberDestination.coaching => '코칭',
    MemberDestination.membership => '운동 장소',
    MemberDestination.settings => '설정',
  };

  IconData get icon => switch (this) {
    MemberDestination.home => SetflowIcons.home,
    MemberDestination.together => SetflowIcons.together,
    MemberDestination.record => SetflowIcons.record,
    MemberDestination.community => SetflowIcons.community,
    MemberDestination.my => SetflowIcons.my,
    MemberDestination.routines => SetflowIcons.routine,
    MemberDestination.market => SetflowIcons.market,
    MemberDestination.library => SetflowIcons.exerciseSearch,
    MemberDestination.dashboard => SetflowIcons.stats,
    MemberDestination.body => SetflowIcons.goal,
    MemberDestination.coaching => SetflowIcons.coaching,
    MemberDestination.membership => SetflowIcons.membership,
    MemberDestination.settings => SetflowIcons.settings,
  };

  IconData get selectedIcon => switch (this) {
    MemberDestination.home => SetflowIcons.homeActive,
    MemberDestination.together => SetflowIcons.togetherActive,
    MemberDestination.community => SetflowIcons.communityActive,
    MemberDestination.my => SetflowIcons.myActive,
    _ => icon,
  };

  SetflowNavItem get navItem =>
      SetflowNavItem(icon: icon, selectedIcon: selectedIcon, label: label);
}
