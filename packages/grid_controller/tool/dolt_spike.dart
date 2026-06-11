// Track 0.2 dolt auth spike (docs/M1-BUILD-ORDER.md): can a Dart MySQL
// client complete Dolt's auth handshake and read the tg database?
// Outcome recorded in ADR-0000. Read-only by construction.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:mysql_client/mysql_client.dart';

Future<void> main() async {
  final user = Platform.environment['GC_DOLT_USER'] ?? 'root';
  final password = Platform.environment['GC_DOLT_PASSWORD'] ?? '';

  for (final secure in [false, true]) {
    print('--- mysql_client connect (secure: $secure, user: $user) ---');
    try {
      final sw = Stopwatch()..start();
      final conn = await MySQLConnection.createConnection(
        host: '127.0.0.1',
        port: 34947,
        userName: user,
        password: password,
        databaseName: 'tg',
        secure: secure,
      );
      await conn.connect(timeoutMs: 5000);
      print('connected in ${sw.elapsedMilliseconds}ms');

      sw.reset();
      final working = await conn.execute('SELECT @@tg_working');
      final hash = working.rows.first.colAt(0);
      print('@@tg_working = $hash (${sw.elapsedMicroseconds}us)');

      sw.reset();
      final issues = await conn.execute(
        'SELECT id, title, status, issue_type FROM issues LIMIT 1',
      );
      for (final row in issues.rows) {
        print('issue: ${row.assoc()} (${sw.elapsedMicroseconds}us)');
      }
      if (issues.rows.isEmpty) print('issues table readable, 0 rows');

      sw.reset();
      final probe2 = await conn.execute('SELECT @@tg_working');
      print(
        'probe again = ${probe2.rows.first.colAt(0)} '
        '(${sw.elapsedMicroseconds}us)',
      );

      await conn.close();
      print('SPIKE OK (secure: $secure)');
      exit(0);
    } catch (e) {
      print('FAILED (secure: $secure): $e');
    }
  }
  exit(1);
}
