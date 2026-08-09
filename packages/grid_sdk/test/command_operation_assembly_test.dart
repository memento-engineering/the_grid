import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('station work assembly exposes and binds resident commands', () {
    final source = File('lib/src/work/work_assembly.dart').readAsStringSync();

    expect(source, contains('final GridCommandHandler commands;'));
    expect(source, contains('Map<String, BdCliService> workBdOverrides'));
    expect(source, contains('workCommandStores[spec.name] = binding;'));
    expect(source, contains('workCommandStores[spec.prefix] = binding;'));
    expect(source, contains('StationCommandHandler('));
    expect(source, contains('commands: commands,'));
  });
}
