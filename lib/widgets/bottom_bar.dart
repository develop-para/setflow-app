import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'common.dart';

/// Bottom bar with a raised center action, OKX "Trade" style.
///
/// The center slot is a destination *and* an action: tapping it from anywhere
/// else opens the core surface, and tapping it again while already there opens
/// that surface's own action sheet. The caller owns that state machine — it
/// decides which glyph the disc shows and what a tap means.
///
/// **The bar reserves no space for the disc.** It is exactly one bar tall and
/// the disc paints out of its top edge. Two earlier attempts were wrong: giving
/// the bar extra height showed up as a dead white band above the border, and
/// floating the disc from the shell's body stack put it *under* the bar, since
/// Scaffold paints the navigation bar after the body.
///
/// Selection styling follows [SetflowNavBar]: ink icon + label with an ink top
/// indicator. The disc is the inverted block — black on light, white on dark —
/// so its glyph uses onPrimary, never ink.
class SetflowActionNavBar extends StatelessWidget {
  const SetflowActionNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.centerLabel,
    required this.centerIcon,
    required this.centerSelected,
    required this.onCenterTap,
    super.key,
  }) : assert(
         items.length == 4,
         'two destinations sit on each side of the center action',
       );

  /// Exactly four destinations: indices 0 and 1 sit left of the center action,
  /// 2 and 3 sit right of it.
  final List<SetflowNavItem> items;

  /// Which side destination is showing, or null while the center destination
  /// owns the screen.
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final String centerLabel;

  /// Swap this for a close glyph while the center action's sheet is open.
  final IconData centerIcon;

  /// True while the center destination is the visible page.
  final bool centerSelected;

  /// Fires from the label strip under the disc as well as from the disc, so the
  /// half of the disc that hangs over the bar is never a dead zone.
  final VoidCallback onCenterTap;

  static const barHeight = 62.0;
  static const discSize = 52.0;

  /// How far the disc pokes above the bar's top border. Kept small on purpose:
  /// most of the disc sits inside the bar, so most of it stays tappable —
  /// anything above the bar's box is outside its hit-test area.
  static const discRise = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: barHeight,
          child: Stack(
            // The disc paints out of the bar's box by design.
            clipBehavior: Clip.none,
            children: [
              Row(
                children: [
                  _destination(0),
                  _destination(1),
                  Expanded(
                    child: _CenterLabelSlot(
                      label: centerLabel,
                      selected: centerSelected,
                      onTap: onCenterTap,
                    ),
                  ),
                  _destination(2),
                  _destination(3),
                ],
              ),
              Positioned(
                top: -discRise,
                left: 0,
                right: 0,
                child: Center(
                  child: _CenterActionDisc(
                    icon: centerIcon,
                    label: centerLabel,
                    onTap: onCenterTap,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _destination(int index) {
    return Expanded(
      child: _ActionNavDestination(
        item: items[index],
        selected: index == selectedIndex,
        onTap: () {
          if (index != selectedIndex) HapticFeedback.selectionClick();
          onSelected(index);
        },
      ),
    );
  }
}

class _ActionNavDestination extends StatelessWidget {
  const _ActionNavDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SetflowNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: SetflowMotion.standard,
              curve: SetflowMotion.kineticCurve,
              height: 3,
              width: selected ? 24 : 0,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(3),
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 24,
                    color: color,
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: .1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The center slot inside the bar: the disc covers its upper half, so this
/// draws only the label — and stays tappable so the covered half still works.
class _CenterLabelSlot extends StatelessWidget {
  const _CenterLabelSlot({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: .1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised disc. A child of the bar so it paints above it, positioned out
/// of the bar's box so the bar needs no extra height.
class _CenterActionDisc extends StatefulWidget {
  const _CenterActionDisc({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_CenterActionDisc> createState() => _CenterActionDiscState();
}

class _CenterActionDiscState extends State<_CenterActionDisc> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? .92 : 1,
          duration: SetflowMotion.micro,
          curve: SetflowMotion.standardCurve,
          child: Container(
            key: const ValueKey('bottom-bar-center-action'),
            width: SetflowActionNavBar.discSize,
            height: SetflowActionNavBar.discSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              // A ring in the page colour keeps the disc legible where it
              // overlaps content instead of relying on a shadow.
              border: Border.all(
                color: theme.scaffoldBackgroundColor,
                width: 3,
              ),
            ),
            child: AnimatedSwitcher(
              duration: SetflowMotion.micro,
              child: Icon(
                widget.icon,
                key: ValueKey(widget.icon.codePoint),
                size: 24,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
