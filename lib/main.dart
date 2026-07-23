import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'data/app_repository.dart';
import 'data/hive_app_repository.dart';
import 'screens/business_screens.dart';
import 'screens/member_screens.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppRepository repository;
  try {
    repository = await HiveAppRepository.open();
  } catch (_) {
    repository = MemoryAppRepository();
  }
  runApp(SetflowApp(repository: repository));
}

class SetflowApp extends StatefulWidget {
  const SetflowApp({this.repository, super.key});

  final AppRepository? repository;

  @override
  State<SetflowApp> createState() => _SetflowAppState();
}

class _SetflowAppState extends State<SetflowApp> {
  late final AppState state;

  @override
  void initState() {
    super.initState();
    state = AppState(repository: widget.repository);
    unawaited(state.initialize());
  }

  @override
  void dispose() {
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
          builder: (context, child) => Stack(
            children: [
              child ?? const SizedBox.shrink(),
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
            ],
          ),
          home: const RootScreen(),
        ),
      ),
    );
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
    final Widget page = switch (state.role) {
      UserRole.guest => const WelcomeScreen(),
      UserRole.member => const MemberShell(),
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
                  : KeyedSubtree(key: ValueKey(state.role), child: page),
            ),
          ),
        ),
      ),
    );
  }
}
