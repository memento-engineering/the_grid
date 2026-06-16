import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';

void main() {
  group('GridHandshake.fromWire', () {
    test('decodes protocol version + extensions, ignoring extra keys', () {
      // ADR-0000 A33: the host emits the manifest under the `extensions` wire
      // key (matching leonard's reader), not the legacy `plugins`.
      final handshake = GridHandshake.fromWire(const {
        'protocolVersion': '1',
        'bindingType': 'GridControllerHost',
        'hostType': 'dart',
        'extensions': [
          {
            'namespace': 'grid',
            'tools': ['requery', 'events', 'stats'],
          },
        ],
      });

      expect(handshake.protocolVersion, '1');
      expect(handshake.plugins.single.namespace, 'grid');
      expect(handshake.plugins.single.tools, ['requery', 'events', 'stats']);
    });

    test('ignores the legacy `plugins` key (no fallback, like leonard)', () {
      final handshake = GridHandshake.fromWire(const {
        'protocolVersion': '1',
        'plugins': [
          {
            'namespace': 'grid',
            'tools': ['events'],
          },
        ],
      });
      // Reading only `extensions` means a legacy-`plugins` host advertises
      // nothing — exactly leonard's no-fallback behavior.
      expect(handshake.plugins, isEmpty);
    });

    test('throws FormatException when protocolVersion is missing', () {
      expect(
        () => GridHandshake.fromWire(const {'extensions': []}),
        throwsFormatException,
      );
    });

    test('drops malformed extension entries without losing valid ones', () {
      final handshake = GridHandshake.fromWire(const {
        'protocolVersion': '1',
        'extensions': [
          'not-a-map',
          {'tools': <String>[]},
          {
            'namespace': 'grid',
            'tools': ['events'],
          },
        ],
      });
      expect(handshake.plugins.length, 1);
      expect(handshake.plugins.single.namespace, 'grid');
    });
  });

  group('GridEventsPage.fromWire', () {
    test('unwraps the {ok, value:{count, events}} host envelope', () {
      final page = GridEventsPage.fromWire(const {
        'ok': true,
        'value': {
          'count': 2,
          'events': [
            {
              'type': 'beadCreated',
              'bead': {'id': 'grid-aaa'},
            },
            {
              'type': 'readySetChanged',
              'entered': ['x'],
              'exited': <String>[],
            },
          ],
        },
      });

      expect(page.count, 2);
      expect(page.events.length, 2);
      // bead.id is lifted to the surfaced id for create events.
      expect(page.events.first.type, 'beadCreated');
      expect(page.events.first.id, 'grid-aaa');
      // set-level event has no id but preserves its extra fields.
      expect(page.events[1].id, isNull);
      expect(page.events[1].extra['entered'], ['x']);
    });

    test('accepts a bare {count, events} payload', () {
      final page = GridEventsPage.fromWire(const {
        'count': 1,
        'events': [
          {
            'type': 'beadUpdated',
            'id': 'grid-bbb',
            'changedFields': ['status'],
          },
        ],
      });
      expect(page.events.single.id, 'grid-bbb');
      expect(page.events.single.extra['changedFields'], ['status']);
    });

    test('throws when the envelope reports not-ok', () {
      expect(
        () => GridEventsPage.fromWire(const {'ok': false, 'error': 'nope'}),
        throwsFormatException,
      );
    });
  });

  group('GridEventRecord.fromWire', () {
    test('preserves unknown fields in extra (never drops data)', () {
      final record = GridEventRecord.fromWire(const {
        'type': 'dependencyAdded',
        'issueId': 'a',
        'dependsOnId': 'b',
        'depType': 'blocks',
      });
      expect(record, isNotNull);
      expect(record!.type, 'dependencyAdded');
      expect(record.id, isNull);
      expect(record.extra['issueId'], 'a');
      expect(record.extra['depType'], 'blocks');
    });

    test('returns null for a non-map or a map without a string type', () {
      expect(GridEventRecord.fromWire('x'), isNull);
      expect(GridEventRecord.fromWire(const {'id': 'a'}), isNull);
    });
  });
}
