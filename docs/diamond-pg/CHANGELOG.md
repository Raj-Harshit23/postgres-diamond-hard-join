# Diamond-PG changelog

## 2026-10-19 - Phase 0: mapping and baseline validation

### Changes

- Created local `diamond-pg` at PostgreSQL 20devel commit
  `6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
- Added AGENTS.md and the five required project documents: architecture,
  implementation plan, continuation plan, testing guide, and this ledger.
- Mapped native planning/execution, two-/three-table joins, paper
  Lookup/Expand/Expand3, node infrastructure, ownership/batching/rescans,
  native tests, and the proposed Phase 1 instrumentation.
- Added one build-output ignore entry to `.gitignore`.
- Preserved the user's untracked paper. No PostgreSQL functions, structs,
  planner/executor behavior, GUCs, or regression sources changed.

### Dependency and validation steps

1. Initial configuration found missing development dependencies. The user
   then installed standard system packages through sudo in their own
   terminal; verified versions and the exact installation command are in
   TESTING.md. The earlier scratch dependency/build attempt is superseded.
2. Configured a fresh persistent out-of-tree build with
   `--enable-cassert --enable-debug`, using system ICU/readline/Bison/Flex.
   `make -j4` passed without reported compiler warnings.
3. Ran native `make check`: **all 239 core tests passed**, including
   `join`, `join_hash`, `subselect`, `partition_join`, and `explain`.
4. Installed into the private project prefix, initialized a private local
   server, and verified 20devel with `debug_assertions=on`.
5. Ran TESTING.md fixtures: equality 3 rows, residual-filter 2 rows;
   three-table intermediate 8 rows and final output 4. Exact expected
   multisets and native hash/non-hash comparisons passed. Saved EXPLAIN
   JSON confirms the cardinalities; the lower three-table join builds h.
6. Stopped the private server. Source/index/whitespace and ignored-output
   checks passed. Evidence and reproduction commands are in TESTING.md.

### Permanent workflow correction

At the user's request, AGENTS.md now requires minimal, correct, efficient,
well-commented code and concise useful documentation. Removed the extra
setup/build/runtime helper scripts introduced during validation. Use native
configure/make/psql commands and system dependencies; keep generated files
in ignored `scripts/diamond-pg/.work/`. No /tmp workaround is part of the
supported workflow. Do not add speculative scaffolding or redundant files.

### Limits and handoff

This validates native PostgreSQL only. No Diamond counters/execution,
Diamond off/on tests, sanitizer run or benchmarks exist yet. Phase 1's
architecture is documented; its implementation still needs user direction.
Nothing was staged, committed or pushed.

Suggested commit: `diamond-pg: document architecture and validated baseline`.
