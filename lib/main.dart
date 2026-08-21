import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'data/app_repository.dart';
import 'data/business_repository.dart';
import 'data/hive_app_repository.dart';
import 'data/community_repository.dart';
import 'data/routine_catalog_repository.dart';
import 'data/supabase_app_repository.dart';
import 'data/supabase_business_repository.dart';
import 'data/supabase_community_repository.dart';
import 'data/supabase_routine_catalog_repository.dart';
import 'screens/business_screens.dart';
import 'screens/member_screens.dart';
import 'screens/splash_screen.dart';
import 'services/supabase_config.dart';
import 'services/supabase_auth_service.dart';
import 'theme.dart';
import 'widgets/common.dart';
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
  SupabaseAuthService.instance.configure(Supabase.instance.client);

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
    ),
  );
}

class SetflowApp extends StatefulWidget {
  const SetflowApp({
    this.repository,
    this.businessRepository,
    this.routineCatalogRepository,
    this.communityRepository,
    super.key,
  });

  final AppRepository? repository;
  final BusinessRepository? businessRepository;
  final RoutineCatalogRepository? routineCatalogRepository;
  final CommunityRepository? communityRepository;

  @override
  State<SetflowApp> createState() => _SetflowAppState();
}

class _SetflowAppState extends State<SetflowApp> with WidgetsBindingObserver {
  late final AppState state;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _appLinkSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _persistenceSyncTimer;
  String? _observedAuthUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state = AppState(
      repository: widget.repository,
      businessRepository: widget.businessRepository,
      routineCatalogRepository: widget.routineCatalogRepository,
      communityRepository: widget.communityRepository,
    );
    _persistenceSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(state.syncPersistenceToServer().catchError((_) {}));
    });
    _appLinks = AppLinks();
    _observedAuthUserId = SupabaseAuthService.instance.currentUser?.id;
    _authSubscription = SupabaseAuthService.instance.authChanges.listen(
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
  }

  void _handleAuthState(AuthState authState) {
    final event = authState.event;
    final userId = authState.session?.user.id;
    if (event == AuthChangeEvent.signedOut ||
        userId == null && event == AuthChangeEvent.tokenRefreshed) {
      _observedAuthUserId = null;
      state.handleExternalAuthSignedOut();
      return;
    }
    if ((event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession) &&
        userId != null &&
        userId != _observedAuthUserId) {
      _observedAuthUserId = userId;
      unawaited(state.syncAfterAuthentication().catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden ||
        lifecycleState == AppLifecycleState.detached) {
      unawaited(state.syncPersistenceToServer().catchError((_) {}));
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
          debugShowCheckedModeBanner: false,
          theme: SetflowTheme.light,
          darkTheme: SetflowTheme.dark,
          themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          scrollBehavior: const SetflowScrollBehavior(),
          builder: (context, child) => Stack(
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
              if (state.restRemaining > 0)
                Positioned(
                  left: SetflowSpacing.lg,
                  right: SetflowSpacing.lg,
                  bottom: 84,
                  child: SafeArea(
                    top: false,
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
      borderRadius: BorderRadius.circular(20),
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

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 432),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: const [
                BoxShadow(color: Color(0x18000000), blurRadius: 32),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _showSplash || !state.isInitialized
                  ? SplashScreen(
                      key: const ValueKey('splash'),
                      onFinished: () => setState(() => _showSplash = false),
                    )
                  : KeyedSubtree(key: ValueKey(shellRole), child: page),
            ),
          ),
        ),
      ),
    );
  }
}
