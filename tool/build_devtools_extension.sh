#!/usr/bin/env bash
# tool/build_devtools_extension.sh
#
# Builds the grid_devtools panel and copies the compiled web bundle into both
# extension/devtools/build/ destinations:
#
#   - packages/grid_devtools/extension/devtools/build/
#       For standalone development against devtools_extensions's simulated
#       DevTools environment.
#
#   - packages/grid_exploration/extension/devtools/build/
#       The host package whose presence in a connected app's package_config
#       triggers DevTools' auto-discovery. grid_cli (`grid watch`) depends on
#       grid_exploration, so attaching DevTools to a running `grid watch`
#       surfaces the `grid` panel from here (ADR-0002 Decision 3: the panel
#       rides the exploration protocol; grid_exploration is the pure-Dart host
#       apps depend on, never beads_dart).
#
# Both build/ destinations are gitignored — re-run after any change to
# packages/grid_devtools/{lib,web,pubspec.yaml}.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/packages/grid_devtools"

# The repo is a Dart pub workspace whose members need the Flutter SDK
# (grid_devtools declares `flutter: sdk: flutter`). Resolve with Flutter's pub
# up front so the `dart run` calls below reuse a valid package_config instead of
# triggering an implicit `dart pub get` that fails on the Flutter constraint.
flutter pub get

dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=extension/devtools
dart run devtools_extensions build_and_copy \
  --source=. \
  --dest=../grid_exploration/extension/devtools
echo "✓ grid_devtools bundle built into grid_devtools + grid_exploration"
