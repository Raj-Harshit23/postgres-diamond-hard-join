# Diamond-PG implementation plan

Updated 2026-10-19. Base: `6296e78c3d2c7406bb450c5ae477b2fef58f155e`,
PostgreSQL 20devel; local branch `diamond-pg`. ARCHITECTURE.md is the source
map and design explanation; EXECPLAN.md is the session continuation guide.

## Status and boundaries

| Phase | Status | Deliverable / acceptance gate |
| --- | --- | --- |
| 0: repository/paper mapping | Complete; system-package build, 239 regressions and runtime fixtures passed | Native planner/executor traces, paper mapping, invariants, tests, next-phase proposal; no functional changes |
| 1: native instrumentation | Complete; build, all 240 regressions and two-worker runtime checks passed | Optional EXPLAIN counters with precise event semantics; native results/plans unchanged; serial/parallel/rescan tests |
| 2: match representation | Complete, uncommitted; assertion/debug build, targeted test, 240 core tests and timeout/recovery passed; sanitizer execution blocked before SQL | First-match cursor with immediate Expand inside eligible serial inner HashJoins; native alternatives/fallback preserved |
| 3: first-class operations | Not started | Independent Lookup/Expand execution with explicit head/handle transport and lifetime/materialization contracts |
| 4: acyclic plans | Not started | Eligible alpha-acyclic inner-equijoin regions; legal paper-derived scheduling; native alternatives retained |
| 5: cost and selection | Not started | Cost-based competition plus optional experimental controls; eligible does not mean forced |
| 6: Expand3 | Not started | Correct three-relation cyclic equijoin using smaller-set iteration and secondary hashing |
| 7: robustness extension | Not started | Documented intermediate-growth/memory/spill risk influences cost-based selection |
| 8: evaluation | Not started | Reproducible local paper microbenchmarks/JOB/TPC-H, correctness, latency, planning and resource measurements |

No functional milestone is considered validated until compilation and the
applicable tests pass. The user installed system dependencies; Phase 0 now
has a passing assertion/debug build, all 239 core regressions, and exact
fixture/native hash-vs-non-hash result checks. See TESTING.md.

## Phase 0 evidence

- Inventory/version/remotes/status/diffs and relevant local history checked.
- Read HashJoin/Hash code, structures, executor/optimizer/node support
  READMEs, path search/construction/costing, plan construction/reference
  fixing, instrumentation, memory context and slot contracts, join tests.
- Read paper sections 3.2-3.5.3 and 4 for the initial scope; verified the
  Lookup/Expand figure and pseudocode on rendered p. 3219.
- Created root AGENTS.md and five project documents, including EXECPLAN.md.
- Existing untracked paper preserved; no tracked PostgreSQL file changed.
- Runtime EXPLAIN confirms the documented two-/three-table behavior, including
  an 8-row intermediate and 4-row final result; actual input orientation is
  recorded in ARCHITECTURE.md. These are the original native baseline results.

## Phase 1: completed native instrumentation

The user authorized this milestone after committing Phase 0 as `7756e8e52e`.
`diamond_hashjoin_stats` is off by default and affects instrumentation only.
ARCHITECTURE.md defines the counter events and lifetime contract.

Changed production files:

- `src/include/executor/instrument_node.h`: pointer-free counter/worker records.
- `src/include/nodes/execnodes.h`: optional HashJoinState counters and probe flag.
- `src/backend/executor/nodeHashjoin.c`: initialization, two counter hooks,
  rescan, shutdown publication, DSM estimate/init/worker support and retrieval.
- `src/include/executor/nodeHashjoin.h`: GUC/retrieval declarations.
- `src/backend/executor/execParallel.c`: private/shared hash instrumentation
  setup and retrieval, preserving native shared-table coordination guards.
- `src/backend/commands/explain.c`: HashJoin properties, using native total
  emitted-row statistics without a second worker merge.
- `src/backend/utils/misc/{guc_parameters.dat,guc_tables.c}` and
  `doc/src/sgml/config.sgml`: diagnostic declaration and documentation.

Tests: `src/test/regress/sql/diamond_hashjoin.sql`, its expected output, and
`parallel_schedule`. All 240 core tests pass. Manual private/shared HashJoin
plans each launched two workers with leader participation disabled; total
probes/successes/matches/emissions were 20,000 each. Regression coverage
includes three Gather launches (60,000 probes/matches), batching, serial
rescans, changed hash-key parameters, NULLs/duplicates, qualifiers/projection,
LIMIT, native join types, unchanged plans, instrumented multiset comparison,
and all four EXPLAIN formats. Build is assertion/debug enabled and pgindent
checks pass. Exact commands/evidence are in TESTING.md.

No changes to `nodeHash.c`, hash storage, HashPath/HashJoin Plan, costing or
join search were required. Reinitialization retains additive worker records;
retrieval folds totals into query-owned memory rather than copying DSM.
Developer settings use GUC_NOT_IN_SAMPLE, so no sample configuration changes.
No speedup claim, sanitizer run, or Lookup/Expand execution is implied.

Committed as `14ac927a8b`: `diamond-pg: add baseline hash join instrumentation`.

## Phase 2: match representation

Authorized by the user after Phase 1. Selected a bounded first-match cursor
over eager arrays/copies. `DiamondHashMatch`, `ExecHashLookup()` and
`ExecHashExpand()` retain the first equality match and lazily enumerate the
rest. ARCHITECTURE.md specifies fields, execution flow, eligibility and the
borrowed probe/batch lifetime contract.

`diamond_lookup_expand` defaults off. Eligible serial inner joins over direct
heap SeqScans with simple strict hash keys use immediate expansion; other
plans remain native. Native batching/skew remain supported: expansion drains
or is discarded before the next probe/reset. No Path/Plan/node, optimizer,
hash storage format or independent scheduling is introduced.

Extended the existing diamond_hashjoin test with positive execution markers,
off/on EXCEPT ALL comparisons, collisions, text/multi-column keys, volatile
residuals, unique matches, empty/no matches, forward-only FETCH pause/resume,
partial/rescanned expansion, parameterized and spilled rebuilds, skew,
cancellation/error cleanup, and
parallel/native fallback. All 240 core regressions and the targeted test pass.
A real timeout interrupted a live residual; a following 16-batch join returned
20,000 matches with all four counters correct. The ASan build passed, but its
test could not initialize because LeakSanitizer reports unchanged PostgreSQL
startup allocations during `postgres -V`. No sanitizer test pass is claimed.
Exact commands/results and evidence are recorded in TESTING.md.

Suggested commit: `diamond-pg: add immediate hash lookup and expand`.

## Phase 3: independently represented execution

Compare native Plan/PlanState nodes and internal payload protocols before
choosing one. Scope: `include/nodes/{plannodes.h,execnodes.h}`,
`backend/executor` new Lookup/Expand nodes and headers,
`execProcnode.c`, `execAmi.c`, `execParallel.c`,
`backend/commands/explain.c`,
`backend/optimizer/plan/{createplan.c,setrefs.c,subselect.c}`,
`backend/nodes/nodeFuncs.c`, and generated-support source annotations.
Audit comparable node references for additional required cases.

Specify owner, MemoryContext, batch/table identity, invalidation generation,
probe/key copy rules, nested descriptor layout, rescan, parameter changes,
early shutdown, and materialization/serialization boundaries. Allow a
Lookup result through another Lookup without expanding its build payload.
Avoid exposing pointer-valued handles to arbitrary native nodes. Explicit
parallel/spill/parameter fallback restrictions are acceptable only when
correctly enforced and documented.

## Phase 4: alpha-acyclic scheduling

Scope: `include/nodes/pathnodes.h`, `include/optimizer/{paths.h,pathnode.h}`,
`optimizer/path/{allpaths.c,joinrels.c,joinpath.c,equivclass.c}`,
`optimizer/util/{pathnode.c,relnode.c}`,
`optimizer/plan/{initsplan.c,createplan.c,setrefs.c}` and dedicated helpers
as justified. Plan the memo/comparability contract before adding paths.

Normalize eligible predicates with PostgreSQL operator/collation/EC rules;
recognize the hypergraph, perform GYO ear removal, distinguish expanded
head from deferred payload, track boundaries/required predicates and
nonredundant closing edges, and construct legal orders. Do not infer
acyclicity from SQL table count or a plain relation-edge drawing.

Preserve required-outer, lateral, volatility, security, join-domain, and
projection dependencies; reject unsupported regions. Retain ordinary
paths. Define a conservative initial cost/selection policy here; calibrated
costing comes in Phase 5. An opt-in eligibility gate may protect the
prototype, but must not become an unconditional choose-Diamond rule.
GEQO/hook interaction needs a documented fallback or explicit integration.

Acceptance: acyclic star AND chain/nested-build cases; duplicate/NULL
semantics; redundant equality triangle classified correctly; genuine cycle
rejected; unsupported join regions remain native; result multisets agree.

## Phase 5: cost and selection

Scope: `optimizer/path/costsize.c`, `include/optimizer/cost.h`, Diamond Path
construction/state metadata, `guc_parameters.dat`, config/manual and tests.
Estimate hash build, first-match lookup, remaining enumeration, output
multiplicity, key/probe copying, nested-handle storage, and memory/batch
cost. Fully expanded relational cardinality is different from head rows.
Use existing estimates without overstating their reliability.

Retain native paths and choose on comparable cost. If an experimental force
control is added, it must never bypass semantic/ownership eligibility.
Acceptance includes cheap ordinary joins where native wins, actual growing
intermediates where Diamond can win, estimate sensitivity, and fallback.

## Phase 6: Expand3

Scope: Phase 3 executor node/payload/hash helpers, `hashjoin.h` if needed,
node/path/plan declarations and lifecycle/reference infrastructure,
planner closing-edge detection, and `costsize.c`.
Start with `R(a,b), S(b,c), T(c,a)` only. Store/provide exact per-key
iterator lengths and secondary composite-key hash indexes (primary key,
closing key); choose the smaller iterator per probe, enumerate all opposite
duplicates, and avoid the full pair cross-product. Account for index build
and metadata memory. Native hash bucket length is not sufficient.

Acceptance: triangles, skew, disjoint/nonmatching cycles, duplicates,
NULLs, both smaller-side choices, correct reset/lifetime behavior. Do not
claim arbitrary cyclic-query or general n-way worst-case optimality.

## Phase 7: PostgreSQL-specific robustness

Scope: `costsize.c`, Diamond Path metadata, hash-memory sizing interfaces,
EXPLAIN diagnostic documentation and tests as justified. Define and calibrate
a diamond-risk estimate using intermediate cardinality/width, concurrent
live hash/deferred structures, hash_mem_multiplier/work_mem, and expected
spill I/O. The risk affects a justified cost, not an unconditional rule.
Avoid double counting native batch I/O; estimates are not measured peak
RSS and work_mem is not a single query budget.

## Phase 8: evaluation

Add versioned small data generators/query manifests and a benchmark runner
under a proposed `benchmarks/diamond-pg/`; keep datasets, clusters, and raw
large logs outside Git. Record seeds, scale, compiler/configuration,
hardware, commit, planner controls, warmup/repetitions, results, and timeout
policy. Use paper microbenchmarks, JOB, and TPC-H; preserve structure,
fanout/skew/selectivity when scaling down. Compare native and Diamond on
the same checkout/settings/data, and distinguish instrumentation overhead.
Record execution/planning time, intermediate rows, observed operator memory,
temp I/O, probes/emissions, and differential correctness. Never claim the
paper's absolute-number reproduction on different hardware/configuration.

## Decisions still requiring design review

1. Generalize the immediate cursor's borrowed slots into independently owned
   deferred heads/keys; eager arrays were rejected for Phase 2.
2. Internal payload/slot protocol, nested Lookup build storage, and safe
   treatment of Material/Sort/Gather/spill and parameterized execution.
3. L&E optimizer state identity and path-pruning equivalence classes;
   initial search scope and planning-time bound.
4. Runtime batching/fallback strategy: estimates cannot guarantee no spill,
   and restarting after emitting rows would duplicate results.
5. Expand3 match counts/secondary indexes and duplicate semantics.
6. Memory/risk calibration and benchmark scale on available hardware.
