# Diamond-PG changelog

## 2026-10-31 - Preserve reviewed per-query benchmark evidence

Checkpoint441f907cf6 contains the tested bounded source/diagnosis. Added one
compact versioned benchmark-results.csv with all138 measurements/timeouts,
actual selection/row verification and main-query planner-gate diagnosis.
Reviewed against raw summaries;137paired bags agree, full-paper native times
out. Config/source/data revisions/method are in TESTING.md; raw data/logs stay
ignored. Source remains unchanged; paper Section4 correction is still next.

## 2026-10-31 - Authorized validated checkpoint before Section4 correction

The user authorized normal commits/pushes on diamond-pg-cloud, with author and
committer harshit <harshitraj969@gmail.com>, no co-author attribution. This
checkpoint preserves the tested bounded acyclic implementation, reproducible
runner, actual results and zero-coverage diagnosis. Proper paper Section4
integration is the next requested milestone, excluding GEQO; no unfinished
correction source is included. Remote publication is verified after commit.

## 2026-10-31 - Explain zero benchmark coverage

Traced all135 benchmark queries with temporary diagnostics on an isolated
physical copy, separating first exits, semantic/GYO checks, path availability,
predicted batching and actual cost pruning. JOB:93 missing pure serial
heap/hash fallback survivors,20 GEQO bypasses; no real candidate costing.
TPC-H: only Q3 generates a candidate, pruned by cheaper native alternatives.
Counterfactual analysis does not admit paths or claim measured speed losses.
All diagnostic native plan shapes match the benchmark. Source restored exactly,
diagnostic server stopped, normal debug binary rebuilt. No functional/cost
change, scope broadening, commit, publication or new performance claim.
TESTING.md records complete counts/cost examples and `.work/diagnosis` evidence.

## 2026-10-31 - Native automatic acyclic alternatives and safe selection

Added `DiamondPath` and `DiamondJoin` plan/state, complete-region EC/GYO
recognition with each-root scheduling, canonical reference fixing followed by
nested Lookup/Expand factorization, native hash/selectivity-based heuristic
costing, filtered-head sizing and retained native pre-output resource fallback.
`diamond_acyclic` defaults off and adds cost competitors. Native indexed,
parallel and other join methods remain available; unsupported regions stay
native. Added dispatch, copy/read, rescan/parameter, EXPLAIN/deparse and parallel
boundary integration, plus manual documentation for the developer control.

Current-source focused 1/1 and full core 240/240 pass, including actually selected
star/chain/branch cases, multiset comparisons, memory/batch fallback, copy/read,
rewind, parameters, cached plans, cursor and cancellation. Complete standard
JOB data and indexes loaded/analyzed; optimized same-binary/settings evaluation
of all 22 TPC-H,113 JOB and exact paper acyclic scales completed. Added one
reviewable benchmark runner under scripts/diamond-pg; raw data/plans stay ignored.
TPC-H completed22/22 and JOB113/113 identical bags with no Diamond selection.
Scaled exact paper N1000/5000 automatically execute 219.6x/907.6x faster; full
N50000 automatic median 23.877ms/native 120s timeout (no paired ratio).
Combined optimized suite wall time 1358.53s. Annotated Valgrind focused 1/1
passed in 819.154s and an actually selected partial cursor closed/recovered.
No invalid read/write/free/conditional-jump report; native startup/scanner
leaks and relcache/WAL findings stay unsuppressed. Diagnostic server stopped.
The initial strict Valgrind attempt stopped before SQL; the later annotated
run above completed. No clean memory pass or real-suite Diamond gain claimed.
Uncommitted changes only; no push, PR or environment publication.

## 2026-10-31 - Retained nested-build execution groundwork

Added a private batch-owned address-indexed sidecar map to native Hash builds,
owned retained probe copies, independent storage epochs and pinned batch
contracts. Actual allocator totals and final bucket-resize checks reject
oversized retained builds before output. Native SQL tuple/spill layout stays
unchanged. Expand resolves typed build owners and restores/propagates nested
snapshots; the existing C regression module tests real R→(S→T) execution,
rewind, text/NULL/duplicates, expiration, batching and actual memory exhaustion.
Fresh focused 1/1 and all240 core regressions pass; no optimizer/cost selection
or final benchmark claim. Changes remain uncommitted on diamond-pg-cloud.


## 2026-10-31 - Isolated cloud branch and verified baseline

Created `diamond-pg-cloud` from `9ee4d297b3` on user direction, without advancing
`diamond-pg`. User authorized local verified Debian build dependencies after
system installation failed. Added matching runtime libraries to resolve the
static-ICU link failure. Fresh assertion/debug/header-dependent build passed;
targeted Diamond 1/1 and core 240/240 passed; installation passed.

Generated/loaded standard TPC-H SF1 into a separate indexed database. Prepared
all 22 default-substitution queries with PostgreSQL syntax ports. Baseline
runner compares native and existing adjacent execution, checks result bags,
and retains interleaved timings/JSON plans. Publication interrupted the first
run after 11 queries; detached batch reruns the suite and downloads standard
JOB data. Paper and JOB access now work after publication. No PostgreSQL source
changes, new optimizer, benchmark completion or speedup claimed. Updated the
five documents; no commits/push/publication by the agent.


## 2026-10-31 - Cloud midterm prerequisite checkpoint

Fetched and selected existing remote `diamond-pg` at `9ee4d297b3`; confirmed
pinned PostgreSQL base ancestry and clean source. Read required project docs
and inspected typed sidecar ownership. No source, tests or costs changed.
Updated the five existing documents with expanded authorization, accurate
cloud build failure, missing system dependencies and precise restart steps.
System package install failed for lack of OS privileges; default configure
failed on ICU. No fresh Diamond tests or benchmarks ran. No commit/push/PR.


File changes and reasons are recorded here; [TESTING.md](TESTING.md) owns
runnable commands, observed results and evidence paths. Execution flow,
ownership and paper mapping are in [ARCHITECTURE.md](ARCHITECTURE.md).

## 2026-10-25 - Phase 3 checkpoint and publication attempt

Committed the reviewed Phase 3 work as `0aa87a8624`,
`diamond-pg: add independent lookup and expand execution`, with the user's
author/committer identity and no co-author attribution. Preserved the PDF and
ignored artifacts. Existing passing test evidence and staged whitespace checks
were verified; no functional changes or new test runs.

The user authorized pushing current progress. Remote inspection found only
master. The normal `git push --set-upstream origin diamond-pg` failed because
GitHub HTTPS credentials are unavailable; no branch was created. Authentication
in the user's terminal is required before publication can complete.

Documentation follow-up: `AGENTS.md`, `ARCHITECTURE.md`, `IMPLEMENTATION_PLAN.md`
and `EXECPLAN.md` record the Phase 3 commit and pending publication; `TESTING.md`
records exact commands/results; `CHANGELOG.md` records this checkpoint.
No additional source/helper/Markdown files were added.

## 2026-10-19 - Phase 3: independent execution (committed 2026-10-25)

The user requested and verified Phase 2's commit, then authorized Phase 3.
Selected native Plan/PlanState inheritance and typed sidecars over SQL pointer
Datums or copied match arrays. Public planning only splits a chosen HashJoin
into adjacent operators; the existing C test module constructs separated
physical stacks. No Phase 4 Paths/search or cost-based selection was added.

| File | Change |
| --- | --- |
| `src/include/nodes/plannodes.h` | Serializable Lookup (HashJoin metadata) and Expand (original Join, owner plan ID, final boundary) |
| `src/include/nodes/execnodes.h` | LookupState owner/generation/copied head; ExpandState private cursor, match slot and propagated sidecar |
| `src/include/executor/nodeLookupExpand.h` | New required node header; immutable DiamondDeferredMatch and lifecycle APIs |
| `src/backend/executor/nodeLookupExpand.c` | New required node implementation; first-match head copying, typed transport, duplicate-safe Expand, stale-reference checks, rescan/end ordering and FETCH lifetime |
| `src/backend/executor/nodeHashjoin.c` | Share initialization/native hash state machine; first-match-only entry, dynamic equality slot deformation, deferred-stack batch guard; native behavior remains specialized |
| `src/include/executor/nodeHashjoin.h` | Shared initializer and first-match entry declarations |
| `src/backend/executor/execProcnode.c` | Init/End and Lookup shutdown dispatch |
| `src/backend/executor/execAmi.c` | Lookup/Expand rescan dispatch; conservative capability defaults retained |
| `src/backend/executor/execParallel.c` | Explicit rejection of private-sidecar nodes during DSM estimation |
| `src/backend/executor/Makefile` | Build the node implementation |
| `src/backend/executor/meson.build` | Corresponding source registration; Meson not executed |
| `src/backend/optimizer/plan/createplan.c` | Conservative post-reference physical constructor, whole-statement gates, simple-key lineage and Lookup owner resolution |
| `src/backend/optimizer/plan/setrefs.c` | Invoke decomposition after native references/Params/parallel decisions; unique additional node ID |
| `src/include/optimizer/planmain.h` | Constructor/owner lookup declarations |
| `src/backend/utils/adt/ruleutils.c` | Resolve Expand INNER_VAR to the owning Lookup build for EXPLAIN |
| `src/backend/commands/explain.c` | Separate node names, Lookup equality and Expand residual/filter reporting |
| `src/backend/utils/misc/guc_parameters.dat` | Off-by-default planning-time diamond_independent_lookup_expand; generator input only |
| `src/backend/utils/misc/guc_tables.c` | Include its declaration |
| `doc/src/sgml/config.sgml` | Planning/cache behavior, scope, row measurements and fallback |
| `src/test/regress/regress.c` | Existing C module constructs L1-L2-E1-E2, remaps head keys, copy/read roundtrip, counts intermediate rows, rewinds, invalidates a paused owner and forces batch rejection |
| `src/test/regress/sql/diamond_hashjoin.sql` | Reuse differential helper for both modes; independent node/bag/lifecycle/fallback cases and stacked 66-row multiset |
| `src/test/regress/expected/diamond_hashjoin.out` | Reviewed true boolean oracles and two deliberate ownership/spill errors |
| `AGENTS.md` | Phase 2 checkpoint, Phase 3 authorization and Phase 4 boundary |
| `docs/diamond-pg/ARCHITECTURE.md` | Actual fields/functions, ownership, execution and audited node infrastructure; explicit unsupported nested build storage |
| `docs/diamond-pg/IMPLEMENTATION_PLAN.md` | Bounded Phase 3 implementation and remaining chain/nested-build prerequisite |
| `docs/diamond-pg/EXECPLAN.md` | Current checkpoint, validation and review handoff |
| `docs/diamond-pg/TESTING.md` | Header-dependent build instructions, reusable runtime command, regression/sanitizer evidence and results |
| `docs/diamond-pg/CHANGELOG.md` | This change/decision/evidence ledger and Phase 2 commit status |

Meaningful development corrections: new NodeTags exposed stale objects in the
old build without header dependencies (initdb failed before SQL); a standard
clean rebuild with --enable-depend fixed it. Assertion testing then caught
Buffer/Virtual versus owned MinimalTuple probe deformation in equality; dynamic
outer equality preserves slot assertions and fixes that real ABI mismatch.
Output review corrected numeric JSON row comparisons and used the standard
PG_LIBDIR/PG_DLSUFFIX regression library loading. The internal spill fixture
now changes only a sizing estimate, so planner orientation cannot hide the
batch guard. No temporary dependency or disabled correctness checks were used.

Validation: native assertion/debug build, focused regression and **all 240
core regressions pass**;
all multiset/row-count oracles are true. Per stacked execution L2 returns 11
heads before E1 emits 33 pairs and E2 emits 66 rows, including a full rewind.
Actual owner rescan fails safely; a multi-batch stack fails before output.
Public cases cover duplicate/NULL, text/multi-key/collision, residual/projection,
volatile calls, unique/empty/no-match/LIMIT, batches/skew, parameterized partial
rebuild, NO SCROLL FETCH, serialization and native fallbacks. A real 500ms
timeout interrupts a live residual; recovery returns 20,000 rows at both new
nodes using 16 hash batches. The private server is stopped. Native pgindent and final whitespace/diff
checks pass. TESTING.md records runnable commands and saved evidence.

ASan compilation passes; its test again stops before SQL on the existing
777-byte save_ps_display_args startup leak report. No sanitizer execution,
check-world, benchmark or speedup pass is claimed. Nested deferred build
storage/general acyclic scheduling remains unimplemented; no sidecars enter
ordinary materialization or disk storage. Committed on 2026-10-25 as
`0aa87a8624`; authenticated publication remains pending. Only the two required native node source/header files were added;
no helper scripts or Markdown files. Raw output stays in ignored .work.

## 2026-10-19 - Phase 2: immediate Lookup/Expand

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
in ignored .work. Committed at the user's request as `c169183521`,
`diamond-pg: add immediate hash lookup and expand`, with the user's author
and committer identity and no co-author attribution. Nothing was pushed.

## 2026-10-19 - Post-Phase 1 documentation audit (included in Phase 2)

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

## 2026-10-31 - Detached job and blocked coding handoff

User authorized one remote coding worker, replacing the earlier prohibition
for this one handoff. Created ignored handoff/status/log files; CLI worker
startup was denied by proxy policy before model work. Stopped retries and
saved a new additive chatgpt.com network requirement without publishing.
Detached finite TPC-H/JOB preparation continues independently of the coding
worker. Recorded precise restart instructions; no unattended guarantee.
