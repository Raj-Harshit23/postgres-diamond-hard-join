# Diamond-PG implementation plan

Updated 2026-11-01. Validated checkpoint on `diamond-pg-cloud`; original
`diamond-pg` remains 9ee4d297b3. User authorization covers nested Phase 3,
acyclic Phase 4, cost selection Phase 5 and relevant Phase 8 evaluation.
Architecture and continuation details are in ARCHITECTURE.md and EXECPLAN.md.

The bounded acyclic milestone is complete. Legal scan/fallback construction is
decoupled from pruned native survivors. A root-aware memo retains distinct
minimized L&E parent forests, enumerates legal GYO schedules, and adds complete
costed alternatives after standard, GEQO, or hook join search. General connected
partial-region states and boundary-driven early Expand remain future scope.

First correction increment validated: independent canonical serial fallback,
independently constructed heap paths and audited unparameterized native indexed
inputs replace the original path-survivor prerequisite. Assertion focused1/1
and full core240/240 pass, including selected IndexScan/IndexOnlyScan/BitmapHeapScan
and indexed native resource fallback. No constants lowered, no native options
disabled. The earlier benchmark table remains the measured baseline. Broader
partial-region/early-Expand search is not claimed by this bounded milestone.

## Current status and boundaries

| Phase | Current status | Evidence / remaining gate |
| --- | --- | --- |
|0 mapping | Complete,7756e8e52e | Historical source map and paper mapping |
|1 instrumentation | Complete,14ac927a8b | Native counters, serial/parallel regression coverage |
|2 immediate Lookup/Expand | Complete,c169183521 | Prior focused/core passes; historical sanitizer startup blocker |
|3 independent/nested ownership | Bounded implementation complete;0aa87a8624 plus this retained-build checkpoint | Owned probes, private sidecars, epochs, actual allocation/batch guards; nested/rewind/resource tests pass |
|4 acyclic planning | Bounded two-phase integration complete | Root-aware minimized-expression memo; standard/GEQO/hook placement; stars/chains/branching/redundant-EC tests pass |
|5 costing/selection | Heuristic native cost competition, safe diagnostic force and pre-output runtime fallback implemented | Q3 suggests conservative cost; Q8/Q9/Q10 forced runs validate rejection; optimized confirmation remains |
|6 Expand3 | Outside this milestone | No cyclic optimizer implemented |
|7 robustness extension | Outside this milestone | Initial resident-storage safety/cost is implemented; general spill/risk calibration remains future work |
|8 relevant evaluation | Final microbenchmark complete; real suites retain prior baseline | Final source: paper N1000/N5000 201.0x/669.3x; N50000 automatic 30.785ms/native >120s. Prior TPC-H22/22 and JOB113/113 bags agree with no selections |

Final current-source assertion/debug/header-dependent build: focused 1/1 and
full core 240/240 pass, including a forced GEQO four-relation chain with three
Lookup/Expand pairs and a native multiset oracle. Tests exercise actual
selected plans rather than merely manual fixtures. Automatic scope is complete
for eligible 3–16 plain-heap regions reached through standard or GEQO search with strict simple-column EC equalities and immutable base filters;
no live outer/lateral/security/locking/DML/subplan boundary. Native methods,
indexes and parallel alternatives remain. Runtime rejection can select native
only before any output; after output there is no restart. No general deferred
spill, arbitrary expression/cross-residual scheduling or exhaustive join-tree
search is implemented. Memory diagnostic startup failures remain visible.

Current calibration target is narrow: explain Q3's false cost rejection without
making Q8/Q9/Q10 win. Global cost discounting is ruled out by the forced runs.

## Completed acceptance and explicit limitations

1. Optimized attempts and result recording are complete; keep all native wins,
   coverage limits and the full-size native paper timeout visible.
2. Annotated focused 1/1 and partial-cursor close/recovery passed; no invalid
   access reported. Native startup/scanner leak and relcache/WAL findings
   remain unsuppressed: no clean memory pass is claimed.
3. Full diff, formatting, source/benchmark identity and current docs reviewed;
   checkpoint contains commands/evidence and an explicitly bounded scope.

## Historical phase design and acceptance checklist

The sections below preserve earlier plans/checkpoints. Their original
"outstanding", "unauthorized" and "not started" claims are historical;
the current status table above supersedes them. Future Phase6/7 design is
outside the current implementation.

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

Committed as `c169183521`: `diamond-pg: add immediate hash lookup and expand`.

## Phase 3: independently represented execution

Implemented separate serializable Lookup/Expand Plans and execution states.
The typed sidecar contract owns probe copies and validates query-owned owner
generations before accessing borrowed hash batches. Lookup can feed another
Lookup without expanding the first relation; Expand uses private cursor copies
to preserve multiplicity when another relation replicates the head.

Opt-in production integration decomposes already chosen eligible HashJoins into
adjacent pairs after native reference fixing. It adds no Paths or scheduling
policy. Native initialization/build/batching is shared, not duplicated. Node
copy/read, dispatch, deparse, parameter sets, rescans, shutdown and parallel
boundaries are integrated. See ARCHITECTURE.md for structures/functions and
TESTING.md for actual checks.

At the committed0aa87a checkpoint, production build inputs were direct heap
scans and nested transport/planning remained outstanding. Current retained
nested storage and automatic integration above supersede that restriction;
ordinary consumers still require full expansion and retained builds remain
resident. The user subsequently authorized Phase 4/5 and relevant evaluation.

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

## Remaining design work beyond the bounded implementation

1. Deferred spill beyond resident retained builds; no pointer payload may enter
   native files, and output must never be duplicated by a late restart.
2. Decouple retained serial native fallback and legal scan construction from
   already-pruned pure heap/hash path survivors. The135-query trace shows93
   JOB skeleton exits and20 GEQO bypasses; only TPC-H Q3 is an actual cost
   loser. Any broader indexed/native fallback needs parameter/security/rescan/
   resource tests and normal cost competition; diagnostic counterfactual costs
   are not performance evidence. See TESTING.md.
3. Better head-survival, copy/CPU and concurrent-live-memory calibration; native
   statistics may badly misestimate correlated/skewed results. Current costs
   are heuristic and work_mem is not a whole-query budget.
4. Connected partial-region and boundary-driven early-Expand search beyond
   the bounded complete two-phase memo, without comparing deferred heads to
   fully expanded relations.
5. Expand3 match counts/secondary indexes and duplicate semantics, outside this
   acyclic milestone.
