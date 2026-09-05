import 'dart:async';
import 'dart:io';

import 'package:beads_dart/src/errors/bd_exception.dart';
import 'package:beads_dart/src/services/bd_runner.dart';
import 'package:test/test.dart';

/// tg-jbji — a child KILLED between the bytes of one multibyte character must
/// not kill the resident.
///
/// The runner's deadline SIGKILLs a wedged `bd`. With the STRICT utf8 decoder
/// on the pipes, a pipe cut mid-character made the decoder throw
/// `Unfinished UTF-8 octet sequence` from its `close()`; the pipe's done event
/// (and that error) lands BEFORE `process.exitCode` resolves, so the
/// subscription's done-future errors while nothing listens to it yet and the
/// error surfaces as an UNCAUGHT zone error — the station isolate died on it
/// (lunar epoch 39, 2026-09-05, twice, ~90 s into every boot). The torn tail
/// now decodes to U+FFFD and the call fails the way it already did:
/// [BdTimeoutException].
///
/// The child is python with UNBUFFERED `os.write`: a shell builtin buffers its
/// output and never reproduces the tear.
const _tornChild =
    "import os, time\nos.write(1, b'\\xe2\\x80'); os.write(2, b'\\xe2\\x80')\n"
    'time.sleep(30)';

void main() {
  test('a SIGKILL between the bytes of a multibyte character is a '
      'BdTimeoutException, never an uncaught zone error', () async {
    final runner = ProcessBdRunner(
      workspaceRoot: Directory.systemTemp.path,
      executable: '/usr/bin/python3',
      environment: const {},
    );
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await expectLater(
        runner.run(['-c', _tornChild], timeout: const Duration(seconds: 1)),
        throwsA(isA<BdTimeoutException>()),
      );
      // Let the pipes' done events (and any close-time throw) deliver.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, (error, stack) => uncaught.add(error));
    expect(
      uncaught,
      isEmpty,
      reason:
          'the strict decoder threw FormatException from close() as an '
          'UNCAUGHT zone error; the resident isolate dies on it',
    );
  });

  test('a clean run decodes multibyte output byte-for-byte', () async {
    final runner = ProcessBdRunner(
      workspaceRoot: Directory.systemTemp.path,
      executable: '/bin/bash',
      environment: const {},
    );
    final result = await runner.run(['-c', r"printf 'a — b\n'"]);
    expect(result.stdout, 'a — b\n');
  });
}
