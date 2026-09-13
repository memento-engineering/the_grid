import 'dart:io';

/// A shared cross-process spawn semaphore for molecule tests.
///
/// The single permit covers only the state trigger through verification of the
/// exact `START`. It never covers the running/completion phase and never
/// increases a timeout. Binding a fixed loopback port makes the permit visible
/// to package:test isolates and to independent Dart test runner processes;
/// process-level file locks do not serialize sibling isolates reliably.
abstract final class MoleculeSpawnSemaphore {
  static const _permitPort = 54281;

  static Future<T> run<T>(Future<T> Function() action) async {
    ServerSocket? permit;
    while (permit == null) {
      try {
        permit = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          _permitPort,
          shared: false,
        );
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    try {
      return await action();
    } finally {
      await permit.close();
    }
  }
}
