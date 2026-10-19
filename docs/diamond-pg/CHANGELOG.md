# Diamond-PG changelog

File changes and reasons are recorded here; [TESTING.md](TESTING.md) owns
runnable commands, observed results and evidence paths. Execution flow,
ownership and paper mapping are in [ARCHITECTURE.md](ARCHITECTURE.md).

## 2026-10-19 - Phase 2: immediate Lookup/Expand (uncommitted)

Authorized by the user after Phase 1. Selected the paper's first-match cursor
over eager match arrays/copies. This proves immediate decomposition inside
HashJoin; it does not implement independent scheduling or Diamond planning.

| File | Change |
| --- | --- |
| `src/include/executor/hashjoin.h` | DiamondHashMatch: bounded query-owned descriptor borrowing the probe slot and one resident hash batch |
| `src/include/nodes/execnodes.h` | Optional HashJoinState.hj_DiamondMatch pointer; no Plan/node serialization change |
| `src/backend/executor/nodeHash.c` | ExecHashLookup retains the first equality match; ExecHashExpand consumes it once and resumes; common ExecHashScanBucket preserves native collision/equality checks and checks interrupts |
| `src/include/executor/nodeHash.h` | Lookup/Expand API declarations |
| `src/backend/executor/nodeHashjoin.c` | Simple strict-key/direct heap scan eligibility; parallel-mode/worker fallback; immediate Lookup/Expand dispatch; cursor invalidation before probe changes, rescans/end; preserve paused FETCH state during shutdown; batch-lifetime assertion |
| `src/include/executor/nodeHashjoin.h` | diamond_lookup_expand declaration; existing guc_tables.c include suffices |
| `src/backend/utils/misc/guc_parameters.dat` | Off-by-default PGC_USERSET experimental execution control; generator input only |
| `src/backend/commands/explain.c` | Latched Diamond Lookup Expand boolean property, including plain EXPLAIN |
| `doc/src/sgml/config.sgml` | Document execution scope, default, fallback, lifetime and EXPLAIN property |
| `src/test/regress/sql/diamond_hashjoin.sql` | Extend existing test with path-checked off/on bag comparisons, collisions, lifecycle, batch/skew and fallback cases |
| `src/test/regress/expected/diamond_hashjoin.out` | Reviewed expected output; all boolean oracles true |
| `AGENTS.md` | Phase 2 authorization/completion; Phase 3 requires user direction |
| `docs/diamond-pg/ARCHITECTURE.md` | Cursor decision, exact fields/functions, flow, borrowing/cleanup contract and restricted eligibility |
| `docs/diamond-pg/IMPLEMENTATION_PLAN.md` | Phase 2 complete; distinguish immediate proof from Phase 3's ownership/transport work |
| `docs/diamond-pg/EXECPLAN.md` | Uncommitted handoff, validation/limitation and next authorized boundary |
| `docs/diamond-pg/TESTING.md` | Runnable build/regression/runtime/sanitizer commands, actual results and evidence |
| `docs/diamond-pg/CHANGELOG.md` | This file/change/validation ledger |

Validation: assertion/debug build and targeted test passed; **all 240 core
tests passed**, including existing join/hash/subselect/partition/EXPLAIN tests.
Off/on EXCEPT ALL checks preserve duplicates/NULLs, multi-column and text keys,
residual/projection results, unique matches, empty/no matches, NO SCROLL FETCH
pause/resume, partial rescans, parameterized and spilled rebuilds, and skew.
Collision keys produce exactly
six equality matches; volatile residuals execute once per candidate. Outer,
semi, anti, inequality, expression and private/shared/forced-parallel plans
retain native execution. Plain EXPLAIN confirms unchanged native plan structure
apart from the new execution-choice property.
Review caught that shutdown also runs between FETCHes; keeping the private
cursor live until rescan/end preserves native resumability.

Real 500ms timeout caught after entering a residual with a live match; the
following 16-batch join reported 20,000 for all four counters. JSON plans and
notice log retained; server stopped. Native pgindent and diff checks passed.
ASan build passed, but its test stopped before SQL: LeakSanitizer reports
777 bytes in unchanged save_ps_display_args during postgres -V. No sanitizer,
benchmark, check-world or performance pass is claimed. Details/evidence are
in [TESTING.md](TESTING.md#actual-validation-ledger).

No source/helper/Markdown files were added; generated validation output stays
in ignored .work. No commit or push was made. Suggested message:
`diamond-pg: add immediate hash lookup and expand`.

## 2026-10-19 - Post-commit documentation audit (uncommitted)

- `AGENTS.md`: make automatic maintenance of affected documents explicit;
  record the completed Phase 1 checkpoint.
- `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`, `EXECPLAN.md`: distinguish the
  PostgreSQL base from project commits and remove stale pre-commit status.
- `TESTING.md`: correct pre-instrumentation wording and connect validation
  commands to actual logs/plans; distinguish initial expected-output capture
  from the passing suite. `CHANGELOG.md`: record the actual commit IDs and
  this audit. All 18 Phase 1 changed files match the file table below.
- Documentation only; no executor changes or new test runs in this audit.

## 2026-10-19 - Phase 1: optional native HashJoin instrumentation

Based on the user's Phase 0 commit `7756e8e52e`; authorized to proceed with
Phase 1 only. Added no planner paths or Lookup/Expand execution.

### Files and behavior

| File | Change |
| --- | --- |
| `src/backend/executor/nodeHashjoin.c` | Optional query-owned counters in ExecInitHashJoin; admission/first-success/match hooks in ExecHashJoinImpl; transient reset in ExecReScanHashJoin; additive worker publication in ExecShutdownHashJoin; existing DSM estimate/init/worker functions support private hashes too; new ExecHashJoinRetrieveInstrumentation folds totals before cleanup |
| `src/include/executor/instrument_node.h` | DiamondHashJoinInstrumentation and SharedDiamondHashJoinInfo; reuse the existing secondary instrumentation TOC key space |
| `src/include/nodes/execnodes.h` | HashJoinState's hj_DiamondStats, hj_DiamondShared and hj_DiamondMatched |
| `src/include/executor/nodeHashjoin.h` | GUC and retrieval declarations |
| `src/backend/executor/execParallel.c` | Invoke statistics setup/retrieval for both private/shared worker hashes; preserve native shared-table guards |
| `src/backend/commands/explain.c` | show_diamond_hashjoin_info prints totals through native format helpers; emitted rows reuse native instrumentation |
| `src/backend/utils/misc/guc_parameters.dat` | Off-by-default PGC_USERSET diamond_hashjoin_stats diagnostic; generator input only |
| `src/backend/utils/misc/guc_tables.c` | Include the variable's declaration |
| `doc/src/sgml/config.sgml` | Exact counter/loop/worker/early-exit semantics |
| `src/test/regress/sql/diamond_hashjoin.sql` | Self-contained counter, differential, lifecycle and format tests |
| `src/test/regress/expected/diamond_hashjoin.out` | Reviewed expected results; boolean oracles all true |
| `src/test/regress/parallel_schedule` | Include the new test in the full schedule |
| `AGENTS.md` | Record Phase 1 authorization and retain the one-phase boundary |
| `docs/diamond-pg/ARCHITECTURE.md` | Replace the proposal with implemented events, fields and lifetime flow |
| `docs/diamond-pg/IMPLEMENTATION_PLAN.md` | Mark Phase 1 complete and retain future design decisions |
| `docs/diamond-pg/EXECPLAN.md` | Current commit/state and Phase 2 handoff |
| `docs/diamond-pg/TESTING.md` | Usage, exact regression commands and evidence |
| `docs/diamond-pg/CHANGELOG.md` | This ledger entry |

A probe is counted after batch deferral, equality success before residual
quals, and every consumed matching pair once. Normal state transitions,
qualifiers and projection are unchanged. Stats-off/uninstrumented execution
allocates no counters. Gather worker slots add deltas across relaunches;
leader retrieval clears its DSM pointer after merging to avoid stale access
or duplicate merging. Native emitted-row merging remains independent.

### Validation

- Assertion/debug system-package build passed without reported warnings.
- Reviewed hand-calculated regression oracles before accepting expected output;
  the on-path EXCEPT ALL capture uses EXPLAIN ANALYZE CTAS to execute hooks.
- **All 240 core regression tests passed**, including diamond_hashjoin and
  the existing join/hash/subselect/partition/EXPLAIN tests.
- New tests cover off/plain output and unchanged plans, NULLs, zero/one/many
  matches, duplicates on both sides, projection/residual rejection, multi-key
  equality, LIMIT, native outer/semi/anti behavior, batch deferral, rescans,
  changed hash-key parameters, worker totals/relaunch and all EXPLAIN formats.
- Runtime private/shared hash plans each launched two workers, leader
  participation off: exactly 20,000 probes/successes/matches/emitted rows.
  Regression relaunch case reports 60,000 probes/matches across three launches.
- pgindent check passed on touched C/headers with the two added typedefs.
  Final diff/whitespace review passed. Private server stopped.

Commands and ignored evidence paths are in
[TESTING.md](TESTING.md#actual-validation-ledger). No sanitizer, check-world,
benchmark or performance result is claimed. This is baseline
instrumentation, not a Lookup/Expand implementation. Committed at the user's
request as `14ac927a8b`, using the user's author/committer identity without AI
co-author attribution. Nothing was pushed.

Commit: `14ac927a8b` - `diamond-pg: add baseline hash join instrumentation`.

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

At Phase 0 completion, this validated native PostgreSQL only. No Diamond
counters/execution, Diamond off/on tests, sanitizer runs or benchmarks existed.
Phase 1's architecture was documented; its implementation awaited direction.
The user subsequently committed this checkpoint as `7756e8e52e`:
`diamond-pg: document architecture and validated baseline`. Nothing was pushed.
