// Pure-logic proof of STATIC membership (ADR-0011 D4): the [Peer]/[Membership]
// value types round-trip, and [MembershipLoader] parses through an INJECTED
// reader so no real file IO is touched.
import 'package:grid_federation/grid_federation.dart';
import 'package:test/test.dart';

void main() {
  group('Peer', () {
    test('round-trips through JSON (with and without a token)', () {
      const withTok = Peer(
        id: 'the-dashboard',
        host: 'linux-dashboard.local',
        port: 8080,
        token: 'sekret',
      );
      const noTok = Peer(id: 'studio', host: '127.0.0.1', port: 9090);

      expect(Peer.fromJson(withTok.toJson()), withTok);
      expect(Peer.fromJson(noTok.toJson()), noTok);
      // The token is omitted from JSON when null.
      expect(noTok.toJson().containsKey('token'), isFalse);
    });

    test('address is host:port and equality is value-based', () {
      const a = Peer(id: 'x', host: 'h', port: 1);
      const b = Peer(id: 'x', host: 'h', port: 1);
      const c = Peer(id: 'x', host: 'h', port: 2);
      expect(a.address, 'h:1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('Membership', () {
    test('parses a peers document and looks up by id', () {
      const json = '''
      {
        "peers": [
          {"id": "the-dashboard", "host": "linux-dashboard.local", "port": 8080, "token": "sekret"},
          {"id": "studio", "host": "127.0.0.1", "port": 9090}
        ]
      }
      ''';
      final m = Membership.parse(json);
      expect(m.peers, hasLength(2));
      expect(
        m.byId('the-dashboard'),
        const Peer(
          id: 'the-dashboard',
          host: 'linux-dashboard.local',
          port: 8080,
          token: 'sekret',
        ),
      );
      expect(m.byId('studio')?.address, '127.0.0.1:9090');
      expect(m.byId('nope'), isNull);
    });

    test('an absent/empty peers list is an empty membership', () {
      expect(Membership.parse('{}').peers, isEmpty);
      expect(Membership.parse('{"peers": []}').peers, isEmpty);
    });

    test('round-trips through JSON preserving declaration order', () {
      const m = Membership(
        peers: [
          Peer(id: 'a', host: 'a', port: 1),
          Peer(id: 'b', host: 'b', port: 2, token: 't'),
        ],
      );
      expect(Membership.fromJson(m.toJson()).peers, m.peers);
    });
  });

  group('MembershipLoader', () {
    test('loads through an injected reader — no real file IO', () {
      var readPath = '';
      final loader = MembershipLoader(
        reader: (path) {
          readPath = path;
          return '{"peers": [{"id": "p", "host": "h", "port": 7}]}';
        },
      );
      final m = loader.load('/etc/grid/peers.json');
      expect(readPath, '/etc/grid/peers.json'); // the loader used the reader
      expect(m.peers.single, const Peer(id: 'p', host: 'h', port: 7));
    });

    test('propagates a parse error on malformed config', () {
      final loader = MembershipLoader(reader: (_) => 'not json');
      expect(() => loader.load('x'), throwsA(isA<FormatException>()));
    });
  });
}
