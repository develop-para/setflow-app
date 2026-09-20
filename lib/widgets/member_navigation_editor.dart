import 'package:flutter/material.dart';

import '../member_navigation.dart';
import '../theme.dart';
import 'bottom_bar.dart';
import 'member_navigation_items.dart';

class MemberNavigationDraggable extends StatelessWidget {
  const MemberNavigationDraggable({
    required this.destination,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final MemberDestination destination;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => LongPressDraggable<MemberDestination>(
    data: destination,
    maxSimultaneousDrags: enabled ? 1 : 0,
    dragAnchorStrategy: pointerDragAnchorStrategy,
    feedback: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(SetflowRadii.md),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 112),
        padding: const EdgeInsets.all(SetflowSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(destination.icon),
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              destination.label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    ),
    child: child,
  );
}

/// The real bar underneath five accessible drag/drop and tap targets.
class MemberNavigationEditor extends StatelessWidget {
  const MemberNavigationEditor({
    required this.destinations,
    required this.onPlace,
    required this.onPick,
    super.key,
  });

  final List<MemberDestination> destinations;
  final void Function(MemberDestination destination, int slot) onPlace;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return SizedBox(
      height:
          SetflowActionNavBar.barHeight +
          SetflowActionNavBar.discRise +
          bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: SetflowActionNavBar.discRise,
            bottom: 0,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: SetflowActionNavBar(
                  items: [
                    for (final slot in const [0, 1, 3, 4])
                      destinations[slot].navItem,
                  ],
                  selectedIndex: null,
                  onSelected: onPick,
                  centerLabel: destinations[2].label,
                  centerIcon: destinations[2].icon,
                  centerSelected: false,
                  onCenterTap: () => onPick(2),
                ),
              ),
            ),
          ),
          Positioned.fill(
            bottom: bottomInset,
            child: Row(
              children: [
                for (var slot = 0; slot < destinations.length; slot++)
                  Expanded(
                    child: DragTarget<MemberDestination>(
                      key: ValueKey('navigation-drop-$slot'),
                      onAcceptWithDetails: (details) =>
                          onPlace(details.data, slot),
                      builder: (context, candidates, rejected) =>
                          MemberNavigationDraggable(
                            key: ValueKey('navigation-drag-$slot'),
                            destination: destinations[slot],
                            child: Semantics(
                              button: true,
                              label:
                                  '${slot + 1}번째 하단 메뉴: ${destinations[slot].label}, 변경',
                              onTap: () => onPick(slot),
                              child: Tooltip(
                                message: '눌러서 변경 · 길게 눌러 이동',
                                // Long press belongs to the draggable, not the tooltip.
                                triggerMode: TooltipTriggerMode.manual,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  excludeFromSemantics: true,
                                  onTap: () => onPick(slot),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.sm,
                                      ),
                                      border: candidates.isEmpty
                                          ? null
                                          : Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.secondary,
                                              width: 2,
                                            ),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
