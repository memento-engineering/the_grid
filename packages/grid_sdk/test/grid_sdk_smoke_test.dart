// The public surface is an intentionally empty skeleton at Track A (the
// composition types land in Track B). Importing the barrel proves it resolves
// from a consumer's vantage; `dart analyze` covers its contents. The unused
// import is expected until Track B adds exports.
// ignore: unused_import
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('grid_sdk barrel is importable (Track A skeleton)', () {
    // Nothing to exercise yet — the export skeleton is deliberately empty.
    // This keeps the workspace `melos test` green while the package is born.
    expect(true, isTrue);
  });
}
