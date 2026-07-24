import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SetflowMotion.standard,
    )..forward();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Setflow 앱을 시작하는 중',
      liveRegion: true,
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: SetflowMotion.emphasisCurve,
                ),
              ),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: theme.brightness == Brightness.dark
                            ? null
                            : SetflowShadows.level2,
                      ),
                      child: SetflowMark(
                        size: 96,
                        background: theme.colorScheme.primary,
                        color: SetflowColors.ink,
                        radius: 28,
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.section),
                    Text('Setflow', style: theme.textTheme.displayLarge),
                    const SizedBox(height: SetflowSpacing.section),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
