import 'dart:convert';
import 'dart:io';

const _fromKey = 'grid.link.from';
const _toKey = 'grid.link.to';
const _typeKey = 'grid.link.type';

void verifyLiveLinkReceipt(Object? decoded) {
  final beads = _jsonArray(decoded, 'live link receipt');
  final matches = beads.where((bead) {
    final metadata = bead['metadata'];
    return bead['issue_type'] == 'link' &&
        bead['status'] != 'closed' &&
        metadata is Map<String, dynamic> &&
        metadata[_fromKey] == 'tg-8x9' &&
        metadata[_toKey] == 'tg-ama' &&
        metadata[_typeKey] == 'blocks';
  }).toList();
  if (matches.length != 1) {
    throw FormatException(
      'expected exactly one open tg-8x9 -> tg-ama blocks link; '
      'found ${matches.length}',
    );
  }
  final id = _houstonId(matches.single['id'], 'live link receipt');
  stdout.writeln('live link receipt verified: $id');
}

void verifyClosedMigrationReceipt(Object? decoded) {
  final beads = _jsonArray(decoded, 'tg-q9k migration receipt');
  if (beads.length != 1 ||
      beads.single['id'] != 'tg-q9k' ||
      beads.single['status'] != 'closed') {
    throw const FormatException(
      'expected exactly one closed tg-q9k migration receipt',
    );
  }
  final notes = beads.single['notes'];
  if (notes is! String || !notes.contains('PR #76')) {
    throw const FormatException(
      'tg-q9k notes do not record the PR #76 migration determination',
    );
  }
  final ids = RegExp(
    r'Inaugural live Houston link: (houston-[a-z0-9]+)',
  ).allMatches(notes).map((match) => match.group(1)!).toSet();
  if (ids.length != 1) {
    throw FormatException(
      'expected one consistent Houston link id in tg-q9k notes; '
      'found ${ids.length}',
    );
  }
  final id = ids.single;
  if (!notes.contains('Inaugural live Houston link: $id') ||
      !notes.contains('$id (tg-8x9 blocked by tg-ama)')) {
    throw const FormatException(
      'tg-q9k notes do not tie the Houston id to the inaugural link',
    );
  }
  stdout.writeln('tg-q9k migration receipt verified: $id');
}

List<Map<String, dynamic>> _jsonArray(Object? decoded, String receipt) {
  if (decoded is! List<dynamic>) {
    throw FormatException('$receipt input must be a JSON array');
  }
  return decoded.map((value) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$receipt array entries must be JSON objects');
    }
    return value;
  }).toList();
}

String _houstonId(Object? value, String receipt) {
  if (value is! String || !RegExp(r'^houston-[a-z0-9]+$').hasMatch(value)) {
    throw FormatException('$receipt has an invalid Houston link id');
  }
  return value;
}

Future<void> main(List<String> args) async {
  final input = await stdin.transform(utf8.decoder).join();
  final decoded = jsonDecode(input);
  final tgQ9kMode = args.contains('--tg-q9k');
  if (tgQ9kMode) {
    verifyClosedMigrationReceipt(decoded);
  } else {
    verifyLiveLinkReceipt(decoded);
  }
}
