import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _FakeSink implements WebSocketSink {
  int closeCalls = 0;

  @override
  void add(Object? data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    closeCalls++;
    return Future.value();
  }

  @override
  Future<void> get done => Future.value();
}

final class _FakeChannel extends StreamChannelMixin<Object?>
    implements WebSocketChannel {
  final input = StreamController<Object?>();
  final _FakeSink output = _FakeSink();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  @override
  WebSocketSink get sink => output;

  @override
  Stream<Object?> get stream => input.stream;
}

TreeSnapshot _snapshot(int day) => TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 7, day),
  root: const TreeNode(
    seedType: 'Grid',
    id: 'root',
    properties: [],
    children: [],
  ),
);

void main() {
  test(
    'constructs browser stream URI with query bearer and no protocol',
    () async {
      final channel = _FakeChannel();
      Uri? connectedUri;
      Iterable<String>? connectedProtocols;
      final source = WebSocketTreeWireSource.connect(
        controlUrl: Uri.parse('https://user@host:42/control?q=x#fragment'),
        token: 'padded-token==',
        connector: (uri, {required protocols}) {
          connectedUri = uri;
          connectedProtocols = protocols;
          return channel;
        },
      );

      expect(
        connectedUri,
        Uri.parse('wss://host:42/stream?token=padded-token%3D%3D'),
      );
      expect(connectedProtocols, isEmpty);
      await source.dispose();
    },
  );

  test(
    'updates latest before ordered broadcasts and forwards errors',
    () async {
      final channel = _FakeChannel();
      final source = WebSocketTreeWireSource.connect(
        controlUrl: Uri.parse('http://localhost:42'),
        token: 'secret',
        connector: (_, {required protocols}) => channel,
      );
      final observed = <TreeSnapshot>[];
      final errors = <Object>[];
      source.snapshots.listen((snapshot) {
        expect(source.latest, same(snapshot));
        observed.add(snapshot);
      }, onError: errors.add);
      final first = _snapshot(1);
      final second = _snapshot(2);

      channel.input.add(jsonEncode(first.toJson()));
      channel.input.add(jsonEncode(second.toJson()));
      channel.input.add('not json');
      channel.input.addError(StateError('socket'));
      await Future<void>.delayed(Duration.zero);

      expect(observed.map((value) => value.projectedAt), [
        first.projectedAt,
        second.projectedAt,
      ]);
      expect(errors, hasLength(2));
      await source.dispose();
      await source.dispose();
      expect(channel.output.closeCalls, 1);
    },
  );
}
