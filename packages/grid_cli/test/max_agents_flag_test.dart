// tg-42f — the concurrency governor's `--max-agents` flag. This file locks the
// RUNNER contract: `addStationFlags` grows the option, `StationArgs.from`
// parses it (defaulting to `kDefaultMaxConcurrentWork` so a single-bead flow
// is unchanged), and `buildLiveWiring` threads it into
// `StationServices.maxConcurrentWork` — the ambient value `WorkList` reads at
// the mount boundary (`track_a_concurrency_governor_test.dart`, grid_engine).
// FULLY offline — Fakes, not mocks; no real process/git/bd is touched.
import 'package:args/args.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

void main() {
  group('--max-agents: the flag + the threading contract (tg-42f)', () {
    test('addStationFlags grows --max-agents; StationArgs.from parses it '
        '(default: kDefaultMaxConcurrentWork)', () {
      final parser = ArgParser();
      addStationFlags(parser);

      expect(
        StationArgs.from(parser.parse(['--substation', 'tgdog'])).maxAgents,
        kDefaultMaxConcurrentWork,
        reason: 'a generous default so a single-bead flow is unchanged',
      );
      expect(
        StationArgs.from(
          parser.parse(['--substation', 'tgdog', '--max-agents', '8']),
        ).maxAgents,
        8,
      );
    });

    test('buildLiveWiring threads StationArgs.maxAgents into '
        'StationServices.maxConcurrentWork', () async {
      final wiring = await buildLiveWiring(
        args: const StationArgs(
          substations: {'tgdog'},
          dryRun: true,
          maxAgents: 7,
        ),
        sources: StationSources(work: FakeSnapshotSource()),
      );
      expect(wiring.stationServices.maxConcurrentWork, 7);
    });

    test(
      'omitting --max-agents leaves StationServices at the generous default',
      () async {
        final wiring = await buildLiveWiring(
          args: const StationArgs(substations: {'tgdog'}, dryRun: true),
          sources: StationSources(work: FakeSnapshotSource()),
        );
        expect(
          wiring.stationServices.maxConcurrentWork,
          kDefaultMaxConcurrentWork,
        );
      },
    );
  });
}
