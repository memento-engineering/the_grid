/// Shared `IOOverrides` capture and store seeding for the CLI command tests.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Accumulates everything written to a captured [Stdout].
final class ByteConsumer implements StreamConsumer<List<int>> {
  final _bytes = <int>[];

  /// Called with the accumulated text after every chunk.
  void Function(String text)? onText;

  /// Everything written so far.
  String get text => utf8.decode(_bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.addAll(chunk);
      onText?.call(text);
    }
  }

  @override
  Future<void> close() async {}
}

/// A [Stdout] that records into a [ByteConsumer].
final class RecordingStdout implements Stdout {
  /// Records everything written into [consumer].
  RecordingStdout(ByteConsumer consumer) : _sink = IOSink(consumer);

  final IOSink _sink;

  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  String lineTerminator = '\n';
  @override
  Future<void> get done => _sink.done;
  @override
  bool get hasTerminal => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  IOSink get nonBlocking => _sink;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> flush() => _sink.flush();
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
}

/// Seeds a minimal embedded `.beads/` store at [root].
void seedStore(String root) {
  final store = Directory(p.join(root, '.beads'))..createSync(recursive: true);
  File(
    p.join(store.path, 'metadata.json'),
  ).writeAsStringSync('{"dolt_mode":"embedded"}');
}
