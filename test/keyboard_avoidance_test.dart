import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_routine_flow_screens.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/routine_editor_screen.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

const _keyboardInset = 300.0;

void main() {
  group('shell keyboard inset ownership', () {
    testWidgets('member shell consumes the bottom inset exactly once', (
      tester,
    ) async {
      final state = AppState();
      addTearDown(state.dispose);
      _configureView(tester, const Size(400, 900));

      await tester.pumpWidget(
        _appWithState(state: state, home: const MemberShell()),
      );
      await _showKeyboardInset(tester);

      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(MemberShell)),
        ).bottom,
        _keyboardInset,
      );
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(CalendarScreen)),
        ).bottom,
        0,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('business shell consumes the bottom inset exactly once', (
      tester,
    ) async {
      final state = AppState();
      addTearDown(state.dispose);
      _configureView(tester, const Size(400, 900));

      await tester.pumpWidget(
        _appWithState(
          state: state,
          home: const BusinessShell(role: UserRole.trainer),
        ),
      );
      await _showKeyboardInset(tester);

      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(BusinessShell)),
        ).bottom,
        _keyboardInset,
      );
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(TrainerHome)),
        ).bottom,
        0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'keyboard-safe sheet keeps the focused field and CTA reachable on a small phone',
    (tester) async {
      _configureView(tester, const Size(360, 640));

      await tester.pumpWidget(
        MaterialApp(
          theme: SetflowTheme.light,
          scrollBehavior: const SetflowScrollBehavior(),
          home: const _KeyboardSheetHost(),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-keyboard-sheet')));
      await tester.pumpAndSettle();

      final sheet = find.byType(KeyboardSafeBottomSheet);
      final field = find.byKey(const ValueKey('keyboard-sheet-field'));
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final cta = find.byKey(const ValueKey('keyboard-sheet-cta'));
      final scrollView = find.descendant(
        of: sheet,
        matching: find.byType(SingleChildScrollView),
      );

      expect(sheet, findsOneWidget);
      expect(
        tester
            .widget<SingleChildScrollView>(scrollView)
            .keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(
        tester.widget<AppTextField>(field).scrollPadding,
        const EdgeInsets.fromLTRB(20, 20, 20, 104),
      );

      await tester.showKeyboard(editable);
      await _showKeyboardInset(tester);

      const keyboardTop = 640 - _keyboardInset;
      expect(tester.takeException(), isNull);
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      expect(tester.getRect(scrollView).bottom, lessThanOrEqualTo(keyboardTop));

      await tester.ensureVisible(cta);
      await tester.pump();

      expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.getRect(cta).bottom, lessThanOrEqualTo(keyboardTop));
      expect(cta.hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'routine exercise picker stays usable in landscape with the keyboard open',
    (tester) async {
      _configureView(tester, const Size(640, 360));
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      final routine = state.routines.first;
      final targetExercise = state.exercises.firstWhere(
        (exercise) => !routine.exercises.any((item) => item.id == exercise.id),
      );

      await tester.pumpWidget(
        _appWithState(
          state: state,
          home: RoutineEditorScreen(routine: routine),
        ),
      );
      final openPicker = find.text('운동 추가·삭제');
      await tester.scrollUntilVisible(
        openPicker,
        180,
        scrollable: find
            .descendant(
              of: find.byType(RoutineEditorScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(openPicker);
      await tester.pumpAndSettle();

      final searchField = _appTextField('운동 검색');
      final editable = find.descendant(
        of: searchField,
        matching: find.byType(EditableText),
      );
      await tester.showKeyboard(editable);
      final searchFocusNode = tester.widget<EditableText>(editable).focusNode;
      await _showKeyboardInset(tester, bottom: 200);

      const keyboardTop = 360 - 200.0;
      final compactScroll = find.byWidgetPredicate(
        (widget) =>
            widget is CustomScrollView &&
            widget.keyboardDismissBehavior ==
                ScrollViewKeyboardDismissBehavior.onDrag,
        description: '운동 선택 compact CustomScrollView',
      );
      expect(compactScroll, findsOneWidget);
      expect(
        tester.widget<CustomScrollView>(compactScroll).keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(searchFocusNode.hasFocus, isTrue);
      expect(
        tester.widget<EditableText>(editable).focusNode,
        same(searchFocusNode),
      );
      expect(
        tester.getRect(compactScroll).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(searchField);
      await tester.pump();
      expect(searchField.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(searchField).bottom,
        lessThanOrEqualTo(keyboardTop),
      );

      await tester.enterText(editable, targetExercise.name);
      await tester.pump();
      final exerciseRow = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == targetExercise.name,
        description: '검색된 운동 행',
      );
      expect(exerciseRow, findsOneWidget);
      await tester.ensureVisible(exerciseRow);
      await tester.pump();
      expect(exerciseRow.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(exerciseRow).bottom,
        lessThanOrEqualTo(keyboardTop),
      );

      final cta = find.textContaining('선택 완료');
      await tester.ensureVisible(cta);
      await tester.pump();
      expect(cta.hitTestable(), findsOneWidget);
      expect(tester.getRect(cta).bottom, lessThanOrEqualTo(keyboardTop));
      expect(searchFocusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'member share sheet preserves message focus when the keyboard switches it to compact layout',
    (tester) async {
      _configureView(tester, const Size(360, 700));
      final state = _memberShareState();
      addTearDown(state.dispose);

      await tester.pumpWidget(
        _appWithState(state: state, home: const _MemberShareSheetHost()),
      );
      await tester.tap(find.text('회원 공유 열기'));
      await tester.pumpAndSettle();

      final messageField = _messageField();
      expect(
        find.ancestor(of: messageField, matching: find.byType(ListView)),
        findsNothing,
      );
      final firstMemberTile = find.ancestor(
        of: find.text('회원 1'),
        matching: find.byType(CheckboxListTile),
      );
      await tester.tap(firstMemberTile);
      await tester.pump();

      final editable = find.descendant(
        of: messageField,
        matching: find.byType(EditableText),
      );
      await tester.showKeyboard(editable);
      final messageFocusNode = tester.widget<EditableText>(editable).focusNode;
      await _showKeyboardInset(tester, bottom: 500);

      const keyboardTop = 700 - 500.0;
      final compactScroll = find.ancestor(
        of: _messageField(),
        matching: find.byType(ListView),
      );
      expect(compactScroll, findsOneWidget);
      expect(
        tester.widget<ListView>(compactScroll).keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(messageFocusNode.hasFocus, isTrue);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _messageField(),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode,
        same(messageFocusNode),
      );
      expect(
        tester.getRect(compactScroll).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(tester.takeException(), isNull);

      final lastMember = find.text('회원 6');
      await tester.ensureVisible(lastMember);
      await tester.pump();
      expect(lastMember.hitTestable(), findsOneWidget);
      expect(tester.getRect(lastMember).bottom, lessThanOrEqualTo(keyboardTop));

      await tester.ensureVisible(_messageField());
      await tester.pump();
      expect(_messageField().hitTestable(), findsOneWidget);
      expect(
        tester.getRect(_messageField()).bottom,
        lessThanOrEqualTo(keyboardTop),
      );

      final cta = find.widgetWithText(AppButton, '1명에게 공유');
      await tester.ensureVisible(cta);
      await tester.pump();
      expect(tester.widget<AppButton>(cta).onPressed, isNotNull);
      expect(cta.hitTestable(), findsOneWidget);
      expect(tester.getRect(cta).bottom, lessThanOrEqualTo(keyboardTop));
      expect(messageFocusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('global scroll behavior dismisses a focused field on drag', (
    tester,
  ) async {
    _configureView(tester, const Size(360, 640));
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        scrollBehavior: const SetflowScrollBehavior(),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              AppTextField(
                key: const ValueKey('drag-dismiss-field'),
                focusNode: focusNode,
                label: '운동 메모',
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );

    final editable = find.descendant(
      of: find.byKey(const ValueKey('drag-dismiss-field')),
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(editable);
    expect(focusNode.hasFocus, isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pump();

    expect(focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Widget _appWithState({required AppState state, required Widget home}) {
  return AppScope(
    notifier: state,
    child: MaterialApp(
      theme: SetflowTheme.light,
      scrollBehavior: const SetflowScrollBehavior(),
      home: home,
    ),
  );
}

void _configureView(WidgetTester tester, Size logicalSize) {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
}

Future<void> _showKeyboardInset(
  WidgetTester tester, {
  double bottom = _keyboardInset,
}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: bottom);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

Finder _appTextField(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
  description: 'AppTextField labelled $label',
);

Finder _messageField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == '회원에게 보낼 메시지 (선택)',
  description: '회원 공유 메시지 TextField',
);

AppState _memberShareState() {
  const access = BusinessAccess(
    userId: 'keyboard-test-trainer-user',
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: {UserRole.member, UserRole.trainer},
  );
  final members = List.generate(
    6,
    (index) => BusinessMember(
      id: 'keyboard-test-member-${index + 1}',
      gymId: 'keyboard-test-gym',
      userId: 'keyboard-test-member-user-${index + 1}',
      name: '회원 ${index + 1}',
      goal: '근력 향상',
      remainingPtSessions: 8,
    ),
  );
  return AppState()
    ..role = UserRole.trainer
    ..businessAccess = access
    ..businessWorkspace = BusinessWorkspaceData(
      role: UserRole.trainer,
      access: access,
      dashboardStats: const BusinessDashboardMetrics(),
      members: members,
      ownedRoutines: const [_memberShareRoutine],
    );
}

const _memberShareRoutine = OwnedCoachingRoutine(
  id: 'keyboard-test-routine',
  title: '회원 맞춤 루틴',
  status: BusinessRoutineStatus.approved,
  difficulty: BusinessRoutineDifficulty.intermediate,
  exercises: [],
  cumulativeUsers: 0,
);

class _KeyboardSheetHost extends StatelessWidget {
  const _KeyboardSheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          key: const ValueKey('open-keyboard-sheet'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => KeyboardSafeBottomSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '운동 상담',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 280),
                  const AppTextField(
                    key: ValueKey('keyboard-sheet-field'),
                    label: '상담 내용',
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    key: const ValueKey('keyboard-sheet-cta'),
                    label: '상담 신청',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
          child: const Text('상담 열기'),
        ),
      ),
    );
  }
}

class _MemberShareSheetHost extends StatelessWidget {
  const _MemberShareSheetHost();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showRoutineMemberShareSheet(
            context,
            routine: _memberShareRoutine,
          ),
          child: const Text('회원 공유 열기'),
        ),
      ),
    );
  }
}
