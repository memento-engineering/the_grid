#!/usr/bin/env bash
# Resolve a workspace package against its OWN DECLARED floors and compile it.
#
# Every package here sets `resolution: workspace`, so a local `dart pub get`
# binds siblings by PATH and the declared constraints are exercised by nothing.
# A package can therefore call an API that exists only in an unpublished
# sibling, pass its whole suite, publish, and break every consumer that
# resolves from pub. That is exactly how grid_cli 0.5.0-rc.22 shipped (tg-qwsx).
#
# This copies the package outside the workspace, drops the workspace
# resolution, resolves from pub alone, and analyzes. Usage:
#   tool/verify_published_floors.sh packages/grid_engine
set -euo pipefail
pkg="${1:?usage: verify_published_floors.sh <package-dir>}"
[ -f "$pkg/pubspec.yaml" ] || { echo "no pubspec at $pkg" >&2; exit 2; }
name="$(grep -m1 '^name:' "$pkg/pubspec.yaml" | sed 's/name: *//')"
work="$(mktemp -d "${TMPDIR:-/tmp}/floors-$name-XXXXXX")"
trap 'rm -rf "$work"' EXIT
# Source only: a copied .dart_tool or pubspec.lock would carry the workspace
# resolution straight back in.
( cd "$pkg" && tar --exclude=.dart_tool --exclude=build --exclude=pubspec.lock -cf - . ) | ( cd "$work" && tar -xf - )
# `resolution: workspace` is what binds siblings by path; without it pub must
# satisfy every dependency from the declared constraints alone.
sed -i.bak '/^resolution: workspace$/d' "$work/pubspec.yaml" && rm -f "$work/pubspec.yaml.bak"
echo "== $name: resolving against declared floors only =="
if ! ( cd "$work" && dart pub get --no-example ); then
  echo "FLOOR FAILURE ($name): its declared constraints do not resolve from pub." >&2
  exit 1
fi
echo "== $name: analyzing against the resolved published closure =="
if ! ( cd "$work" && dart analyze --no-fatal-warnings lib ); then
  echo "FLOOR FAILURE ($name): compiles in the workspace but NOT against its declared floors." >&2
  echo "Raise the floor of whichever dependency owns the missing API, and publish that first." >&2
  exit 1
fi
echo "OK ($name): resolves and compiles against its own declared floors."
