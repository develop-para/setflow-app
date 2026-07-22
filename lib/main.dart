import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/business_screens.dart';
import 'screens/member_screens.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SetflowApp());
}

class SetflowApp extends StatefulWidget {
  const SetflowApp({super.key});

  @override
  State<SetflowApp> createState() => _SetflowAppState();
}

class _SetflowAppState extends State<SetflowApp> {
  final AppState state = AppState();

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
          home: const RootScreen(),
        ),
      ),
    );
  }
}

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

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
              child: KeyedSubtree(key: ValueKey(state.role), child: page),
            ),
          ),
        ),
      ),
    );
  }
}
