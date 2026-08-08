import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final class FakeTrust implements Trust {
  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) =>
      throw StateError('the guard must not resolve trust');
}

Bead _bead(String id, [Map<String, dynamic> metadata = const {}]) =>
    Bead(id: id, metadata: metadata);

Map<String, dynamic> _stamp(Object? level) => {
  OriginTrustKeys.scheme: 'github',
  OriginTrustKeys.actor: 'octocat',
  OriginTrustKeys.level: level,
};

Set<String> _guard(
  Bead bead, {
  TrustLevel floor = TrustLevel.trusted,
  bool configured = true,
  void Function(String)? report,
}) => applyTrustGuard(
  candidates: {bead.id},
  beadsById: {bead.id: bead},
  floor: TrustFloor(floor),
  trustConfigured: configured,
  onUnresolved: report,
);

void main() {
  test('trust levels have the admission ordering', () {
    expect(TrustLevel.values.map((level) => level.name), [
      'external',
      'trusted',
      'self',
    ]);
    expect(TrustLevel.external.index, lessThan(TrustLevel.trusted.index));
    expect(TrustLevel.trusted.index, lessThan(TrustLevel.self.index));
    expect(const ServiceBundle().trustFloor.level, TrustLevel.trusted);
    expect(FakeTrust(), isA<Trust>());
  });

  test('unstamped candidates are admitted', () {
    expect(_guard(_bead('tg-1')), {'tg-1'});
  });

  test('at-floor and above-floor candidates are admitted', () {
    expect(_guard(_bead('tg-1', _stamp('trusted'))), {'tg-1'});
    expect(_guard(_bead('tg-2', _stamp('self'))), {'tg-2'});
    expect(
      _guard(_bead('tg-3', _stamp('external')), floor: TrustLevel.external),
      {'tg-3'},
    );
  });

  test('below-floor candidates are refused loudly once', () {
    final messages = <String>[];
    expect(
      _guard(_bead('tg-1', _stamp('external')), report: messages.add),
      isEmpty,
    );
    expect(messages, [
      'grid: tg-1 origin trust external is below floor trusted — '
          'excluding tg-1 from ready.',
    ]);
  });

  test('a stamped candidate requires a configured collaborator', () {
    final messages = <String>[];
    expect(
      _guard(
        _bead('tg-1', _stamp('trusted')),
        configured: false,
        report: messages.add,
      ),
      isEmpty,
    );
    expect(messages.single, contains('has no trust resolver'));
  });

  test('partial, unknown, and non-string stamps fail closed', () {
    final malformed = <Bead>[
      _bead('partial', {OriginTrustKeys.scheme: 'github'}),
      _bead('unknown', _stamp('superuser')),
      _bead('scheme', {..._stamp('trusted'), OriginTrustKeys.scheme: 1}),
      _bead('actor', {..._stamp('trusted'), OriginTrustKeys.actor: false}),
      _bead('level', _stamp(1)),
      _bead('empty', {..._stamp('trusted'), OriginTrustKeys.actor: ''}),
    ];
    for (final bead in malformed) {
      final messages = <String>[];
      expect(_guard(bead, report: messages.add), isEmpty);
      expect(messages, hasLength(1));
      expect(messages.single, contains('malformed origin trust stamp'));
    }
  });

  test('a missing candidate bead fails closed once', () {
    final messages = <String>[];
    expect(
      applyTrustGuard(
        candidates: {'missing'},
        beadsById: const {},
        floor: const TrustFloor(TrustLevel.trusted),
        trustConfigured: true,
        onUnresolved: messages.add,
      ),
      isEmpty,
    );
    expect(messages, hasLength(1));
    expect(messages.single, contains('candidate bead is unobserved'));
  });

  test('repeated calls are deterministic and leave inputs unchanged', () {
    final metadata = <String, dynamic>{..._stamp('trusted'), 'other': 'value'};
    final bead = _bead('tg-1', metadata);
    final candidates = <String>{'tg-1'};
    final beads = <String, Bead>{'tg-1': bead};
    final candidatesBefore = {...candidates};
    final metadataBefore = {...metadata};
    final first = applyTrustGuard(
      candidates: candidates,
      beadsById: beads,
      floor: const TrustFloor(TrustLevel.trusted),
      trustConfigured: true,
    );
    final second = applyTrustGuard(
      candidates: candidates,
      beadsById: beads,
      floor: const TrustFloor(TrustLevel.trusted),
      trustConfigured: true,
    );
    expect(first, second);
    expect(candidates, candidatesBefore);
    expect(metadata, metadataBefore);
  });

  test('guard source contains no I/O, async work, or resolver invocation', () {
    final source = File('lib/src/bridge/trust_guard.dart').readAsStringSync();
    for (final forbidden in [
      'dart:io',
      'dart:async',
      'Future<',
      'levelOf(',
      'Trust ',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
