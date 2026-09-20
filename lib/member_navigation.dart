/// Stable destinations, independent of their position in the bottom bar.
/// The first five keep the shell's existing push/deep-link page indices.
enum MemberDestination {
  home,
  together,
  record,
  community,
  my,
  routines,
  market,
  library,
  dashboard,
  body,
  coaching,
  membership,
  settings,
}

abstract final class MemberNavigation {
  static const defaults = [
    MemberDestination.home,
    MemberDestination.together,
    MemberDestination.record,
    MemberDestination.community,
    MemberDestination.my,
  ];

  /// Old, damaged or newer snapshots must not make the app unreachable.
  static List<MemberDestination> restore(Object? source) {
    final result = <MemberDestination>[];
    if (source is List) {
      for (final value in source) {
        final destination = MemberDestination.values
            .where((item) => item == value || item.name == value)
            .firstOrNull;
        if (destination != null && !result.contains(destination)) {
          result.add(destination);
        }
        if (result.length == defaults.length) break;
      }
    }
    for (final destination in defaults) {
      if (result.length == defaults.length) break;
      if (!result.contains(destination)) result.add(destination);
    }
    return List.unmodifiable(result);
  }

  /// Dragging an existing item swaps positions; a new item replaces one slot.
  static List<MemberDestination> place(
    List<MemberDestination> current,
    MemberDestination destination,
    int slot,
  ) {
    RangeError.checkValidIndex(slot, defaults);
    final result = List<MemberDestination>.of(restore(current));
    final previous = result.indexOf(destination);
    if (previous >= 0) result[previous] = result[slot];
    result[slot] = destination;
    return List.unmodifiable(result);
  }
}
