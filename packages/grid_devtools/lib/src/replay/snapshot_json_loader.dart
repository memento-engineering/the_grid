import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

/// Injectable boundary for selecting the contents of a snapshot recording.
typedef SnapshotJsonPicker = Future<String?> Function();

/// Decodes one snapshot object or an array of snapshot objects.
List<TreeSnapshot> decodeSnapshotRecording(String contents) {
  final decoded = jsonDecode(contents);
  final values = decoded is List<Object?> ? decoded : <Object?>[decoded];
  if (values.isEmpty) {
    throw const FormatException('Snapshot recording must not be empty');
  }
  return List<TreeSnapshot>.unmodifiable(
    values.map((value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Each snapshot must be a JSON object');
      }
      return TreeSnapshot.fromJson(value);
    }),
  );
}

/// Opens a browser-supported JSON file and returns its contents.
Future<String?> pickSnapshotJson() async {
  const group = XTypeGroup(label: 'TreeSnapshot JSON', extensions: ['json']);
  final file = await openFile(acceptedTypeGroups: const [group]);
  return file?.readAsString();
}
