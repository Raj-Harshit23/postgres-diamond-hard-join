#!/usr/bin/env bash
# Paper Section 5.1 acyclic fixture; add DIAMOND_PG_DEMO=1 for readable plans.
exec "$(dirname "$0")/_run-benchmark.sh" paper
