import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

void main() {
  const beadId = 'work-1';

  test('three verdict-less retired rounds spend zero', () {
    final rounds = [
      for (var i = 1; i <= 3; i++)
        (workBeadKey: reworkKeyFor(beadId, i), reachedVerdict: false),
    ];
    expect(spentReworkRounds(beadId, rounds), 0);
  });

  test('three verdict rounds spend three', () {
    final rounds = [
      for (var i = 1; i <= 3; i++)
        (workBeadKey: reworkKeyFor(beadId, i), reachedVerdict: true),
    ];
    expect(spentReworkRounds(beadId, rounds), 3);
  });

  test(
    'lenny-749o (tg-9q58): one verdict and two infrastructure losses spend one',
    () {
      final rounds = [
        (workBeadKey: reworkKeyFor(beadId, 1), reachedVerdict: true),
        (workBeadKey: reworkKeyFor(beadId, 2), reachedVerdict: false),
        (workBeadKey: reworkKeyFor(beadId, 3), reachedVerdict: false),
      ];
      expect(spentReworkRounds(beadId, rounds), 1);
    },
  );

  test('foreign and malformed keys never spend', () {
    final rounds = [
      (workBeadKey: 'other#r1', reachedVerdict: true),
      (workBeadKey: '$beadId#rnope', reachedVerdict: true),
      (workBeadKey: voidKeyFor(beadId, 'dead'), reachedVerdict: true),
    ];
    expect(spentReworkRounds(beadId, rounds), 0);
  });

  test(
    'free retired rounds keep ordinal history without spending verdict budget',
    () {
      final keys = [for (var i = 1; i <= 3; i++) reworkKeyFor(beadId, i)];
      final rounds = [
        for (final key in keys) (workBeadKey: key, reachedVerdict: false),
      ];
      expect(maxReworkRound(beadId, keys), 3);
      expect(spentReworkRounds(beadId, rounds), 0);
      expect(reworkRoundOf(beadId, voidKeyFor(beadId, 'dead')), isNull);
    },
  );
}
