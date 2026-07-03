import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';

import 'watch_command.dart';

/// `grid demo` — a zero-setup reactivity proof.
///
/// Creates a throwaway `bd init` workspace, watches it, drives a scripted
/// sequence of mutations, and tears the workspace down — so the full typed
/// event stream (BeadCreated / ReadySetChanged / BeadUpdated / BeadClosed, each
/// with its measured reaction latency) scrolls past with no credentials and no
/// live server. Run it under the VS Code debugger to also get an attachable VM
/// service ("Dart: Open DevTools" → the `grid` panel).
class DemoCommand extends Command<int> {
  @override
  final String name = 'demo';

  @override
  final String description =
      'Self-contained reactivity demo in a throwaway bd workspace (no creds).';

  @override
  Future<int> run() async {
    final tmp = await Directory.systemTemp.createTemp('grid_demo_');
    void log(String m) => stdout.writeln(m);

    try {
      final init = await Process.run('bd', [
        'init',
        '--prefix',
        'demo',
      ], workingDirectory: tmp.path);
      if (init.exitCode != 0) {
        stderr.writeln('grid demo: `bd init` failed: ${init.stderr}');
        return 1;
      }
      final workspace = BeadsWorkspace.discover(start: tmp.path);
      if (workspace == null) {
        stderr.writeln('grid demo: could not discover the demo workspace');
        return 1;
      }

      log('▶ hermetic workspace: ${tmp.path}');
      log('▶ grid watch starts now; mutations begin in ~3s …\n');

      // Drive mutations on the event loop while `runWatch` holds for runFor.
      unawaited(_drive(tmp.path));

      final code = await runWatch(
        workspaceOverride: workspace,
        runFor: const Duration(seconds: 11),
      );
      log('\n▶ demo complete — workspace cleaned up');
      return code;
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  Future<void> _drive(String root) async {
    final bd = BdCliService(ProcessBdRunner(workspaceRoot: root));
    Future<void> pause() =>
        Future<void>.delayed(const Duration(milliseconds: 1600));
    await Future<void>.delayed(const Duration(seconds: 3));
    await bd.create(title: 'tron lives', type: IssueType.molecule, priority: 1);
    await pause();
    final task = await bd.create(
      title: 'reach the I/O tower',
      type: IssueType.task,
      priority: 1,
    );
    await pause();
    await bd.update(task, status: BeadStatus.inProgress);
    await pause();
    await bd.close(task, reason: 'end of line');
  }
}
