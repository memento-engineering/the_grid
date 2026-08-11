import 'dart:convert';
import 'dart:io';

/// Selects operator prose from an inline value or a strict UTF-8 file/stdin.
Future<String?> selectOperatorText({
  required String inlineFlag,
  required String fileFlag,
  required String? inlineValue,
  required String? filePath,
  Stream<List<int>>? input,
}) async {
  if (inlineValue != null && filePath != null) {
    throw OperatorTextUsage('$inlineFlag and $fileFlag are mutually exclusive');
  }
  if (filePath == null) return inlineValue;
  if (filePath == '-') {
    return (input ?? stdin).transform(const Utf8Decoder()).join();
  }
  return File(filePath).readAsString(encoding: utf8);
}

/// A command-line selection error detected before file IO or dispatch.
final class OperatorTextUsage implements Exception {
  const OperatorTextUsage(this.message);

  final String message;
}
