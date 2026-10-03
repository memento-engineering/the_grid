#!/usr/bin/env bash
# tg-ejzb acceptance driver: runs test/substation_attach_live_test.dart as
# CONCURRENT processes, ITERATIONS times in a row, and fails on the first
# iteration in which any instance fails. The live tests serialise themselves
# through the machine-wide live-store queue (test/support/live_store_lock.dart),
# so every instance must pass while its peers run beside it.
#
# Usage (from packages/grid_sdk):
#   tool/live_attach_concurrent_pair.sh             # 10 iterations, 2 at once
#   ITERATIONS=3 WIDTH=3 tool/live_attach_concurrent_pair.sh
#
# Plain POSIX-ish bash 3.2: no process substitution, no comments inside
# command substitutions (the review lane runs plans under sh -c).
set -u

iterations="${ITERATIONS:-10}"
width="${WIDTH:-2}"
logs="$(mktemp -d "${TMPDIR:-/tmp}/live-attach-pair.XXXXXX")"
echo "live-attach pair: ${iterations} iterations x ${width} concurrent; logs in ${logs}"

i=1
while [ "$i" -le "$iterations" ]; do
  pids=""
  j=1
  while [ "$j" -le "$width" ]; do
    dart test test/substation_attach_live_test.dart >"${logs}/iter${i}-proc${j}.log" 2>&1 &
    pids="${pids} $!"
    j=$((j + 1))
  done
  failed=0
  j=1
  for pid in $pids; do
    if wait "$pid"; then
      echo "iteration ${i} process ${j}: pass"
    else
      echo "iteration ${i} process ${j}: FAIL (see ${logs}/iter${i}-proc${j}.log)"
      failed=1
    fi
    j=$((j + 1))
  done
  if [ "$failed" -ne 0 ]; then
    echo "live-attach pair: FAILED at iteration ${i}"
    exit 1
  fi
  i=$((i + 1))
done
echo "live-attach pair: ${iterations}/${iterations} iterations passed with ${width} concurrent processes"
