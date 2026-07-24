import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';

Future<void> main(List<String> args) async {
  final lock = await StationLockService().acquire(
    stateWorkspaceDir: args.single,
    pid: pid,
    now: DateTime.now().toUtc(),
  );
  final child = await Process.start('sleep', <String>['30']);
  stdout.writeln(jsonEncode(<String, int>{'pid': pid, 'child': child.pid}));
  await stdin.drain<void>();
  child.kill();
  await lock.release();
}
