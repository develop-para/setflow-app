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
                    const SetflowWordmark(
                      key: ValueKey('setflow-loading-logo'),
                      fontSize: SetflowFontSize.displayLarge,
                    ),
                    const SizedBox(height: SetflowSpacing.xl),
                    // A hairline rule instead of a spinner: monochrome systems
                    // signal progress with geometry, not a coloured swirl.
                    Container(
                      width: 96,
                      height: 2,
                      color: theme.colorScheme.outlineVariant,
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
