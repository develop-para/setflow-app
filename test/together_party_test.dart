import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/together_repository.dart';
import 'package:setflow/models.dart';

/// Two phones, one room. Every test below drives both sides through the same
/// backend, because the failures worth catching are the ones where the two
/// devices disagree — both thinking it is their turn, or resting to different
/// clocks.
void main() {
  late MemoryTogetherBackend backend;
  late MemoryTogetherRepository me;
  late MemoryTogetherRepository friend;

  setUp(() {
    backend = MemoryTogetherBackend();
    me = MemoryTogetherRepository(
      backend: backend,
      userId: 'u-me',
      displayName: '나',
    );
    friend = MemoryTogetherRepository(
      backend: backend,
      userId: 'u-friend',
      displayName: '친구',
    );
  });

  tearDown(() => backend.dispose());

  Future<TrainingParty> roomOfTwo({PartyMode mode = PartyMode.together}) async {
    final party = await me.createParty(mode: mode);
    await friend.joinParty(party.code);
    return backend.partyById(party.id)!;
  }

  group('joining', () {
    test('a code puts both people in the same room', () async {
      final party = await roomOfTwo();

      expect(party.members.map((m) => m.displayName), ['나', '친구']);
      expect(party.isHost('u-me'), isTrue);
    });

    test('the code is readable out loud', () async {
      final party = await me.createParty(mode: PartyMode.together);

      // Someone is going to read this over the phone, so the glyphs that get
      // misheard are not in the alphabet at all.
      expect(party.code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));
      expect(party.code, hasLength(6));
    });

    test('a wrong code says so instead of opening an empty room', () async {
      expect(() => friend.joinParty('ZZZZZZ'), throwsA(isA<TogetherFailure>()));
    });

    test('joining twice does not seat you twice', () async {
      final party = await me.createParty(mode: PartyMode.together);
      await friend.joinParty(party.code);
      await friend.joinParty(party.code);

      expect(backend.partyById(party.id)!.members, hasLength(2));
    });
  });

  group('같이 — one clock for everyone', () {
    test('start arms the same instant for both, not a duration each', () async {
      final room = await roomOfTwo();
      final started = await me.startTogether(
        room.id,
        lead: const Duration(seconds: 5),
      );

      // The value that travels is the moment itself. A phone that hears about
      // this two seconds late still counts down to the same instant.
      expect(started.startsAt, isNotNull);
      expect(started.countdownSeconds, inInclusiveRange(4, 5));
      expect(
        started.members.every((m) => m.state == PartyMemberState.lifting),
        isTrue,
      );
    });

    test('one person finishing rests the whole room to one clock', () async {
      final room = await roomOfTwo();
      await me.startTogether(room.id);

      final after = await me.reportSetDone(partyId: room.id, restSeconds: 90);

      expect(
        after.members.every((m) => m.state == PartyMemberState.resting),
        isTrue,
      );
      final ends = after.members.map((m) => m.restEndsAt).toSet();
      expect(ends, hasLength(1), reason: 'one rest, one deadline');
    });

    test('only the person who lifted gets the set counted', () async {
      final room = await roomOfTwo();
      await me.startTogether(room.id);
      final after = await me.reportSetDone(partyId: room.id, restSeconds: 60);

      expect(after.memberOf('u-me')!.completedSets, 1);
      expect(after.memberOf('u-friend')!.completedSets, 0);
    });
  });

  group('교대 — the turn is decided once', () {
    test('starting hands the first set to exactly one person', () async {
      final room = await roomOfTwo(mode: PartyMode.alternating);
      final started = await me.startTogether(room.id);

      expect(started.currentTurnUserId, 'u-me');
      expect(started.memberOf('u-me')!.state, PartyMemberState.lifting);
      expect(started.memberOf('u-friend')!.state, PartyMemberState.resting);
      expect(
        started.members.where((m) => m.state == PartyMemberState.lifting),
        hasLength(1),
        reason: 'two people believing it is their turn is the one broken state',
      );
    });

    test('finishing passes the turn and ends the waiting rest', () async {
      final room = await roomOfTwo(mode: PartyMode.alternating);
      await me.startTogether(room.id);

      final after = await me.reportSetDone(partyId: room.id, restSeconds: 90);

      expect(after.currentTurnUserId, 'u-friend');
      expect(after.memberOf('u-friend')!.state, PartyMemberState.lifting);
      // Their rest ends because your set ended, which is the whole feeling:
      // "you're up" arrives instead of a countdown they have to watch.
      expect(after.memberOf('u-friend')!.restEndsAt, isNull);
      expect(after.memberOf('u-me')!.state, PartyMemberState.resting);
    });

    test('the turn comes back around', () async {
      final room = await roomOfTwo(mode: PartyMode.alternating);
      await me.startTogether(room.id);
      await me.reportSetDone(partyId: room.id, restSeconds: 60);
      final after = await friend.reportSetDone(
        partyId: room.id,
        restSeconds: 60,
      );

      expect(after.currentTurnUserId, 'u-me');
      expect(after.memberOf('u-me')!.completedSets, 1);
      expect(after.memberOf('u-friend')!.completedSets, 1);
    });

    test('someone leaving mid-turn does not stall the room', () async {
      final room = await roomOfTwo(mode: PartyMode.alternating);
      await me.startTogether(room.id);
      expect(backend.partyById(room.id)!.currentTurnUserId, 'u-me');

      await me.leaveParty(room.id);

      // Waiting on a phone that is no longer listening is a room nobody can
      // rescue, so the turn moves to whoever is still there.
      expect(backend.partyById(room.id)!.currentTurnUserId, 'u-friend');
    });

    test('switching mode clears a turn the new rule never chose', () async {
      final room = await roomOfTwo(mode: PartyMode.alternating);
      await me.startTogether(room.id);

      final switched = await me.setMode(
        partyId: room.id,
        mode: PartyMode.together,
      );

      expect(switched.currentTurnUserId, isNull);
      expect(
        switched.members.every((m) => m.state == PartyMemberState.waiting),
        isTrue,
      );
    });
  });

  group('handing a routine over', () {
    RoutineData routine(String name) => RoutineData(
      id: 'r-$name',
      name: name,
      description: '',
      color: Colors.grey,
      exercises: const [],
    );

    test('what one person offers, the other can see', () async {
      final room = await roomOfTwo();

      await friend.offerRoutine(partyId: room.id, routine: routine('등 루틴'));
      final seen = backend.partyById(room.id)!.routines;

      expect(seen, hasLength(1));
      expect(seen.single.routine.name, '등 루틴');
      expect(seen.single.senderName, '친구');
    });

    test('the newest offer is on top', () async {
      final room = await roomOfTwo();
      await me.offerRoutine(partyId: room.id, routine: routine('먼저'));
      await friend.offerRoutine(partyId: room.id, routine: routine('나중'));

      expect(backend.partyById(room.id)!.routines.map((o) => o.routine.name), [
        '나중',
        '먼저',
      ]);
    });
  });

  group('watching', () {
    test('a listener gets the room before anything changes', () async {
      final room = await roomOfTwo();

      final first = await me.watchParty(room.id).first;

      expect(first.id, room.id);
      expect(first.members, hasLength(2));
    });

    test('a change reaches the other side', () async {
      final room = await roomOfTwo(mode: PartyMode.alternating);
      final seen = <TrainingParty>[];
      final sub = friend.watchParty(room.id).listen(seen.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(Duration.zero);

      await me.startTogether(room.id);
      await Future<void>.delayed(Duration.zero);

      expect(seen.last.currentTurnUserId, 'u-me');
    });
  });

  group('signed out', () {
    test('every verb refuses rather than making an anonymous member', () async {
      final guest = MemoryTogetherRepository(backend: backend, userId: null);

      // A room with an anonymous member has no way to say whose turn it is.
      expect(
        () => guest.createParty(mode: PartyMode.together),
        throwsA(isA<TogetherFailure>()),
      );
      expect(() => guest.joinParty('ABCDEF'), throwsA(isA<TogetherFailure>()));
    });
  });
}
