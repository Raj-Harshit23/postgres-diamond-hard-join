#!/usr/bin/env bash
# TPC-H SF1: 22 correctness-checked native/automatic comparisons.
exec "$(dirname "$0")/_run-benchmark.sh" tpch
