/// `grid read` — the vended bounded source read.
///
/// The first file-reading instance of
/// `power_station#a-mechanical-lookup-is-a-vended-command-with-a-bounded-output`.
/// It replaces the loop a seat runs by hand today — `rg` to find where a
/// symbol lives, then `sed -n '1,260p'` with a GUESSED line range, then the
/// same file again with a different guess — with resolve, bounded slice,
/// cached.
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'read_source.dart';

/// The default byte budget for one invocation.
///
/// Measured: a hand-rolled `sed` read averaged 17,940 characters per call
/// across the 2026-09 agent pool, uncapped. This budget is deliberately below
/// that — a seat that needs more asks for more, and the truncation marker
/// tells it exactly how.
const int kDefaultReadCapBytes = 8000;

/// A session's record of the answers it has already been given.
///
/// Content-addressed: the key is path, span and a fingerprint of the text, so
/// an edited file produces a different key and is re-read. Keying on the
/// command string instead would serve a stale read while reporting success,
/// which in a build lane is the common case, not the edge case.
class ReadLedger {
  /// Creates a ledger over [file], which need not exist yet.
  ReadLedger(this.file);

  /// Where the session's seen identities are persisted.
  final File file;

  /// The identities already served in this session.
  Set<String> read() {
    if (!file.existsSync()) return <String>{};
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is List) return {...decoded.whereType<String>()};
    } on FormatException {
      // A corrupt ledger must never fail a read: it degrades to no
      // suppression, which is always CORRECT, merely less economical.
      return <String>{};
    }
    return <String>{};
  }

  /// Adds [identities] to the ledger, creating it if needed.
  void record(Iterable<String> identities) {
    final all = {...read(), ...identities};
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(all.toList()..sort()));
  }
}

/// Reads bounded excerpts of source files, by span or by symbol.
class ReadCommand extends Command<int> {
  /// Creates the read command.
  ReadCommand() {
    argParser
      ..addOption(
        'span',
        help:
            'Line range START:END (1-based, inclusive). Whole file if '
            'neither --span nor --symbol is given.',
        valueHelp: 'a:b',
      )
      ..addOption(
        'symbol',
        help:
            'Resolve the declaration of this symbol instead of guessing a '
            'line range. Reports every declaring site.',
        valueHelp: 'name',
      )
      ..addOption(
        'cap',
        help: 'Byte budget shared across every file in this invocation.',
        valueHelp: 'bytes',
        defaultsTo: '$kDefaultReadCapBytes',
      )
      ..addOption(
        'ledger',
        help:
            'Session ledger path. With it, an answer already served in this '
            'session is reported as unchanged instead of re-emitted.',
        valueHelp: 'path',
      )
      ..addFlag(
        'json',
        help: 'Emit exactly one JSON report object.',
        negatable: false,
      );
  }

  @override
  String get name => 'read';

  @override
  String get description =>
      'Read bounded excerpts of source files by span or symbol.';

  @override
  String get invocation => 'grid read <path>... [--symbol name | --span a:b]';

  @override
  Future<int> run() async {
    final paths = argResults!.rest;
    if (paths.isEmpty) {
      stderr.writeln('grid read: name at least one file.');
      return 64;
    }
    final capText = argResults!.option('cap')!;
    final cap = int.tryParse(capText);
    if (cap == null || cap <= 0) {
      stderr.writeln(
        'grid read: --cap must be a positive integer, got "$capText".',
      );
      return 64;
    }
    final spanText = argResults!.option('span');
    final symbol = argResults!.option('symbol');
    if (spanText != null && symbol != null) {
      stderr.writeln('grid read: pass --span or --symbol, not both.');
      return 64;
    }
    LineSpan? requested;
    if (spanText != null) {
      requested = parseSpan(spanText);
      if (requested == null) {
        stderr.writeln('grid read: --span wants START:END, got "$spanText".');
        return 64;
      }
    }

    final slices = <SourceSlice>[];
    final misses = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        stderr.writeln('grid read: no such file: $path');
        return 66;
      }
      final source = file.readAsStringSync();
      if (symbol != null) {
        final spans = resolveSymbol(source, symbol);
        if (spans.isEmpty) {
          misses.add(path);
          continue;
        }
        for (final span in spans) {
          slices.add(sliceOf(path, source, span));
        }
      } else {
        final span = clampSpan(source, requested ?? wholeFile(source));
        if (span == null) continue;
        slices.add(sliceOf(path, source, span));
      }
    }
    if (symbol != null && slices.isEmpty) {
      stderr.writeln(
        'grid read: "$symbol" is declared in none of: ${misses.join(', ')}',
      );
      return 1;
    }

    final ledgerPath = argResults!.option('ledger');
    final ledger = ledgerPath == null ? null : ReadLedger(File(ledgerPath));
    final report = capSlices(
      slices,
      capBytes: cap,
      seenIdentities: ledger?.read() ?? const {},
    );
    ledger?.record([
      for (final capped in report.slices)
        if (!capped.suppressed && !capped.truncated) capped.slice.identity,
    ]);

    if (argResults!.flag('json')) {
      stdout.writeln(
        jsonEncode(readReportJson(report, missingSymbolIn: misses)),
      );
    } else {
      stdout.write(renderRead(report));
      for (final path in misses) {
        stdout.writeln('== $path — "$symbol" not declared here ==');
      }
    }
    return 0;
  }
}

/// Parses a `START:END` span, or null when [text] is not one.
LineSpan? parseSpan(String text) {
  final parts = text.split(':');
  if (parts.length != 2) return null;
  final start = int.tryParse(parts[0]);
  final end = int.tryParse(parts[1]);
  if (start == null || end == null || start < 1 || end < start) return null;
  return LineSpan(start, end);
}

/// The JSON form of [report] — structured results, never scraped prose.
Map<String, Object?> readReportJson(
  ReadReport report, {
  List<String> missingSymbolIn = const [],
}) => {
  'capBytes': report.capBytes,
  'emittedBytes': report.emittedBytes,
  'missingSymbolIn': missingSymbolIn,
  'slices': [
    for (final capped in report.slices)
      {
        'path': capped.slice.path,
        'start': capped.slice.span.start,
        'end': capped.slice.span.end,
        'totalLines': capped.slice.totalLines,
        'identity': capped.slice.identity,
        'suppressed': capped.suppressed,
        'withheldLines': capped.withheldLines,
        if (!capped.suppressed) 'text': capped.text,
      },
  ],
};
