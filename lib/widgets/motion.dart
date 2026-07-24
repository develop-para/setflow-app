import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// ── Setflow motion system ──────────────────────────────────────────────────
/// Reusable, restrained motion so the whole app feels alive without being
/// noisy: staggered entrances, tactile press physics, and animated reveals.

/// Fade + rise entrance. Give siblings increasing [order] for a stagger.
class Reveal extends StatefulWidget {
  const Reveal({
    required this.child,
    this.order = 0,
    this.stagger = const Duration(milliseconds: 60),
    this.duration = const Duration(milliseconds: 460),
    this.offset = 14,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final int order;
  final Duration stagger;
  final Duration duration;
  final double offset;
  final bool enabled;

  /// Wrap a list of children in staggered [Reveal]s.
  static List<Widget> list(
    List<Widget> children, {
    Duration stagger = const Duration(milliseconds: 60),
    double offset = 14,
    int startOrder = 0,
  }) {
    return [
      for (var i = 0; i < children.length; i++)
        Reveal(
          order: startOrder + i,
          stagger: stagger,
          offset: offset,
          child: children[i],
        ),
    ];
  }

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween(
    begin: Offset(0, widget.offset),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: SetflowMotion.kineticCurve));

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(widget.stagger * widget.order, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(offset: _slide.value, child: child),
      ),
      child: widget.child,
    );
  }
}

/// Tactile press: scales down slightly and fires a haptic on tap. The standard
/// wrapper for cards, tiles, and any bespoke tappable surface.
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final BorderRadius? borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (!_enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!.call();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.mediumImpact();
                widget.onLongPress!.call();
              },
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: SetflowMotion.micro,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
