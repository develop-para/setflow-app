import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'data/app_repository.dart';
import 'data/business_repository.dart';
import 'data/hive_app_repository.dart';
import 'data/community_repository.dart';
import 'data/exercise_catalog.dart';
import 'data/routine_catalog_repository.dart';
import 'data/together_repository.dart';
import 'data/supabase_app_repository.dart';
import 'data/supabase_business_repository.dart';
import 'data/supabase_community_repository.dart';
import 'data/supabase_routine_catalog_repository.dart';
import 'data/supabase_together_repository.dart';
import 'screens/business_screens.dart';
import 'screens/member_screens.dart';
import 'screens/password_screens.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/supabase_config.dart';
import 'services/supabase_auth_service.dart';
import 'theme.dart';
import 'services/firebase_push_service.dart';
import 'services/push_service.dart';
import 'widgets/common.dart';
import 'widgets/guest_data_prompt.dart';
import 'widgets/portal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.projectUrl,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  // The one place that knows which backend serves auth. Swapping providers
  // later is a change here plus one more AuthService implementation.
  SupabaseAuthService.instance.configure(Supabase.instance.client);
  Auth.use(SupabaseAuthService.instance);
  // 배달부를 고르는 유일한 자리. 설정 파일이 없는 플랫폼에서는 조용히 꺼진
  // 구현이 돌아온다 — 알림이 없는 것과 앱이 안 켜지는 것은 등급이 다르다.
  Push.bind(await FirebasePushService.create());

  AppRepository? migrationSource;
  try {
    migrationSource = await HiveAppRepository.open();
  } catch (_) {
    migrationSource = null;
  }
  final repository = SupabaseAppRepository(
    Supabase.instance.client,
    migrationSource: migrationSource,
  );
  runApp(
    SetflowApp(
      repository: repository,
      businessRepository: SupabaseBusinessRepository(Supabase.instance.client),
      routineCatalogRepository: SupabaseRoutineCatalogRepository(
        Supabase.instance.client,
      ),
      communityRepository: SupabaseCommunityRepository(
        Supabase.instance.client,
      ),
      togetherRepository: SupabaseTogetherRepository(
        Supabase.instance.client,
        exerciseCatalog: exerciseCatalog,
      ),
    ),
  );
}

class SetflowApp extends StatefulWidget {
  const SetflowApp({
    this.repository,
    this.businessRepository,
    this.routineCatalogRepository,
    this.communityRepository,
    this.togetherRepository,
    super.key,
  });

  final AppRepository? repository;
  final BusinessRepository? businessRepository;
  final RoutineCatalogRepository? routineCatalogRepository;
  final CommunityRepository? communityRepository;
  final TogetherRepository? togetherRepository;

  @override
  State<SetflowApp> createState() => _SetflowAppState();
}

class _SetflowAppState extends State<SetflowApp> with WidgetsBindingObserver {
  late final AppState state;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinkSubscription;
  StreamSubscription<AuthChange>? _authSubscription;
  Timer? _persistenceSyncTimer;
  String? _observedAuthUserId;

  /// The recovery link arrives on a stream, not from a widget, so there is no
  /// BuildContext to navigate from.
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// Guards against stacking a second reset screen — the recovery event can
  /// repeat (initial link plus the session restore that follows it).
  bool _passwordRecoveryOpen = false;

  /// Asked at most once per run. Declining leaves the records on the device,
  /// so re-asking on every session restore would only be nagging.
  bool _guestDataOffered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state = AppState(
      repository: widget.repository,
      businessRepository: widget.businessRepository,
      routineCatalogRepository: widget.routineCatalogRepository,
      communityRepository: widget.communityRepository,
      togetherRepository: widget.togetherRepository,
    );
    _persistenceSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(state.syncPersistenceToServer().catchError((_) {}));
    });
    _appLinks = AppLinks();
    _observedAuthUserId = Auth.instance.currentUser?.id;
    _authSubscription = Auth.instance.authChanges.listen(
      _handleAuthState,
      onError: (_) {},
    );
    _appLinkSubscription = _appLinks.uriLinkStream.listen(
      state.captureIncomingUri,
      onError: (_) {},
    );
    unawaited(_captureInitialAppLink());
    unawaited(_initializeState());
  }

  Future<void> _initializeState() async {
    await state.initialize();
    await state.syncRestTimerFromPlatform();
    // 세션이 복원된 채로 시작하면 signedIn 이벤트가 안 올 수 있다. 등록은
    // upsert라 두 번 불려도 같은 결과다.
    unawaited(state.syncPushRegistration());
  }

  void _handleAuthState(AuthChange change) {
    final userId = change.user?.id;
    if (change.event == AuthEvent.passwordRecovery) {
      _openPasswordRecovery();
      return;
    }
    if (change.event == AuthEvent.signedOut ||
        userId == null && change.event == AuthEvent.tokenRefreshed) {
      _observedAuthUserId = null;
      state.handleExternalAuthSignedOut();
      return;
    }
    if (change.event == AuthEvent.signedIn &&
        userId != null &&
        userId != _observedAuthUserId) {
      _observedAuthUserId = userId;
      unawaited(_adoptGuestDataThenSync(userId));
    }
  }

  /// The claim has to settle *before* the account loads, because the import
  /// happens inside that load. Syncing first would show an empty account and
  /// then change under the user.
  Future<void> _adoptGuestDataThenSync(String userId) async {
    try {
      await _maybeAdoptGuestData(userId);
    } catch (_) {
      // Never block sign-in on the offer; the records stay on the device.
    }
    try {
      await state.syncAfterAuthentication();
    } catch (_) {
      // AppState surfaces the failure through persistenceError.
    }
    // 계정이 정해진 뒤에 등록해야 토큰이 맞는 사람에게 붙는다. 실패해도
    // 로그인을 막지 않는다.
    unawaited(state.syncPushRegistration());
  }

  Future<void> _maybeAdoptGuestData(String userId) async {
    if (_guestDataOffered) return;
    final source = widget.repository;
    if (source is! GuestDataAdoption) return;
    final repository = source as GuestDataAdoption;

    final guest = await repository.peekGuestSnapshot(state.exercises);
    if (guest == null) return;
    // Settings-only leftovers are not worth a question. Only actual work is.
    final workoutDays = guest.sessions.length;
    final routineCount = guest.routines.length;
    if (workoutDays == 0 && routineCount == 0) return;

    _guestDataOffered = true;
    final navigator = _navigatorKey.currentState;
    final context = navigator?.context;
    if (navigator == null || context == null || !context.mounted) return;

    final adopt = await askToAdoptGuestData(
      context,
      workoutDays: workoutDays,
      routineCount: routineCount,
    );
    if (adopt) await repository.adoptGuestSnapshot(userId);
  }

  /// A reset link puts the user in a session that can do exactly one useful
  /// thing. Dropping them on the home screen would look like a successful login
  /// while their password is still the one they cannot remember, so the reset
  /// form is pushed for them.
  void _openPasswordRecovery() {
    if (_passwordRecoveryOpen) return;
    _passwordRecoveryOpen = true;
    // The event can land before the first frame, when there is no navigator to
    // push onto yet.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        _passwordRecoveryOpen = false;
        return;
      }
      final changed = await navigator.push<bool>(
        MaterialPageRoute(builder: (_) => const NewPasswordScreen()),
      );
      _passwordRecoveryOpen = false;
      // Backing out leaves a half-authenticated session behind; ending it is
      // the honest state, and the user can sign in with the new password.
      if (changed != true) unawaited(Auth.instance.signOut());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.detached) {
      unawaited(_commitEditsThenPersist());
      return;
    }
    if (lifecycleState == AppLifecycleState.resumed) {
      unawaited(state.syncRestTimerFromPlatform());
      unawaited(state.syncPersistenceToServer().catchError((_) {}));
    }
    if (lifecycleState != AppLifecycleState.resumed ||
        !state.isInitialized ||
        !state.usesLiveBusinessData ||
        state.role == UserRole.guest) {
      return;
    }
    unawaited(
      state.refreshBusinessDashboard(state.role).catchError((_) {
        // AppState keeps the previous data and exposes the refresh error to UI.
      }),
    );
  }

  /// Saves what is on screen, not what was last committed.
  ///
  /// A set is often abandoned mid-edit — the phone locks, a call arrives, the
  /// app is swiped away — and Android may kill the process without ever
  /// returning. Dismissing the keyboard with the system back gesture does not
  /// drop focus, so the field still holds an uncommitted number at this point;
  /// persisting straight away writes the value from *before* the user typed.
  ///
  /// Verified on an emulator: typing 82.5, pressing back, then force-stopping
  /// the app used to come back as 0.
  Future<void> _commitEditsThenPersist() async {
    FocusManager.instance.primaryFocus?.unfocus();
    // FocusManager applies the change in a microtask, and the field's blur
    // listener runs with it. Yielding to the event loop lets that finish, so
    // the snapshot taken below already contains the typed value.
    await Future<void>.delayed(Duration.zero);
    try {
      await state.syncPersistenceToServer();
    } catch (_) {
      // The account-scoped outbox is durable; the retry paths finish the
      // upload when the network returns.
    }
  }

  Future<void> _captureInitialAppLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) state.captureIncomingUri(uri);
    } catch (_) {
      // The live stream still handles links delivered after startup.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSubscription?.cancel());
    unawaited(_appLinkSubscription?.cancel());
    _persistenceSyncTimer?.cancel();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
          title: 'Setflow',
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: SetflowTheme.light,
          darkTheme: SetflowTheme.dark,
          themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          scrollBehavior: const SetflowScrollBehavior(),
          // The frame lives HERE, not inside the home screen. `builder` wraps
          // the Navigator, so every pushed route (routine editor, settings,
          // detail screens) gets the same column. Framing `home:` instead only
          // narrows the shell -- pushed routes render above it and would
          // stretch to the full browser width, which is the width jump this
          // fixes.
          builder: (context, child) => _AppFrame(
            child: Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (state.pendingBusinessInviteToken != null)
                  Positioned(
                    left: SetflowSpacing.md,
                    right: SetflowSpacing.md,
                    top: SetflowSpacing.sm,
                    child: SafeArea(
                      bottom: false,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: _BusinessInviteBanner(state: state),
                        ),
                      ),
                    ),
                  ),
                // 휴식은 두 모습을 갖는다. 기본은 화면을 덮는 판 — 세트 사이에 폰을
                // 들면 딴짓이 시작되고 휴식이 끝난 줄도 모른다. "화면 보기"로 접으면
                // 타이머는 그대로 가면서 아래 슬림 바로 내려온다.
                if (state.restRemaining > 0 && !state.restFocusCollapsed)
                  Positioned.fill(
                    child: RestFocusOverlay(
                      seconds: state.restRemaining,
                      totalSeconds: state.restDefaultSeconds,
                      exerciseName: state.restFocus?.exerciseName,
                      setsLeft: state.restFocus?.setsLeft ?? 0,
                      nextExercise: state.restFocus?.nextExercise,
                      onAddTime: () =>
                          state.startRestTimer(state.restRemaining + 30),
                      onFinish: state.cancelRestTimer,
                      onCollapse: state.collapseRestFocus,
                    ),
                  ),
                if (state.restRemaining > 0 && state.restFocusCollapsed)
                  Positioned(
                    left: SetflowSpacing.lg,
                    right: SetflowSpacing.lg,
                    // Under the header, not above the bottom bar: down there it
                    // covered the set rows the timer is counting for. The 52 is
                    // the header's own height, added only when the header has
                    // something in it (a pushed route has none).
                    top: portalSwitcherVisible(state) ? 48 : 0,
                    child: SafeArea(
                      bottom: false,
                      child: GlobalRestTimerOverlay(
                        seconds: state.restRemaining,
                        totalSeconds: state.restDefaultSeconds,
                        onAddTime: () =>
                            state.startRestTimer(state.restRemaining + 30),
                        onCancel: state.cancelRestTimer,
                      ),
                    ),
                  ),
                // Last child: the portal hold must cover the shell, the nav bar
                // and any pushed route while the swap happens underneath.
                if (state.isPortalSwitching)
                  const Positioned.fill(child: PortalTransitionOverlay()),
              ],
            ),
          ),
          home: const RootScreen(),
        ),
      ),
    );
  }
}

class _BusinessInviteBanner extends StatefulWidget {
  const _BusinessInviteBanner({required this.state});

  final AppState state;

  @override
  State<_BusinessInviteBanner> createState() => _BusinessInviteBannerState();
}

class _BusinessInviteBannerState extends State<_BusinessInviteBanner> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    final signedIn =
        widget.state.businessAccess != null &&
        widget.state.role != UserRole.guest;
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(SetflowRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(SetflowSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.mark_email_unread_rounded,
                  color: SetflowColors.primary,
                ),
                const SizedBox(width: SetflowSpacing.sm),
                const Expanded(
                  child: Text(
                    '센터 초대가 도착했어요',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: '나중에 확인',
                  visualDensity: VisualDensity.compact,
                  onPressed: _accepting
                      ? null
                      : widget.state.clearPendingBusinessInviteToken,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              signedIn
                  ? '회원 또는 트레이너 소속 초대를 확인하고 수락할 수 있어요.'
                  : '로그인한 뒤 같은 초대 링크를 다시 열어주세요.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('business-invite-accept'),
                onPressed: !signedIn || _accepting ? null : _accept,
                icon: _accepting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded),
                label: Text(_accepting ? '연결 중...' : '초대 수락'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      final result = await widget.state.acceptBusinessInviteToken();
      if (!mounted) return;
      if (result.accepted) {
        AppSnackbar.success(context, '센터와 계정이 연결됐어요.');
      } else {
        AppSnackbar.error(context, '만료되었거나 취소된 초대예요.');
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '초대를 수락하지 못했어요. 링크를 확인해주세요.');
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    // Launch straight into the member home. Signing in is optional and lives in
    // settings, so a signed-out (guest) session gets the same shell as a member
    // and only trainer/gym/admin roles swap the shell out.
    final shellRole = state.role == UserRole.guest
        ? UserRole.member
        : state.role;
    final Widget page = switch (shellRole) {
      UserRole.member || UserRole.guest => const MemberShell(),
      UserRole.trainer => const BusinessShell(role: UserRole.trainer),
      UserRole.gym => const BusinessShell(role: UserRole.gym),
      UserRole.admin => const BusinessShell(role: UserRole.admin),
    };

    // No width constraint here on purpose -- _AppFrame in the MaterialApp
    // builder already framed this route and every route pushed on top of it.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showSplash || !state.isInitialized
          ? SplashScreen(
              key: const ValueKey('splash'),
              onFinished: () => setState(() => _showSplash = false),
            )
          : KeyedSubtree(key: ValueKey(shellRole), child: page),
    );
  }
}

/// Holds the app to a phone-shaped column on wide screens.
///
/// Setflow is a phone app that also ships as a web bundle. Left to fill a
/// desktop browser, a 1440px-wide list of exercise sets is unreadable. The
/// column is applied once, above the Navigator, so the home shell and a pushed
/// routine editor are exactly the same width -- they used to differ, because
/// only the shell was framed.
class _AppFrame extends StatelessWidget {
  const _AppFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 한때 432px 폰 프레임으로 가운데에 세웠던 자리다(웹 폭 대응). 폴드·
    // 태블릿에서 콘텐츠가 좌우 여백에 뜬 섬으로 보인다는 실기기 피드백으로
    // 걷어냈다 — 어떤 기기든 화면 폭을 그대로 쓰고, 여백은 각 페이지의
    // gutter가 책임진다. builder 자리는 유지한다: 모든 라우트에 공통으로
    // 씌울 것이 생기면 다시 이곳이다.
    return child;
  }
}
