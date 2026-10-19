# Diamond-PG implementation plan

Updated 2026-10-19. Base: `6296e78c3d2c7406bb450c5ae477b2fef58f155e`,
PostgreSQL 20devel; local branch `diamond-pg`. ARCHITECTURE.md is the source
map and design explanation; EXECPLAN.md is the session continuation guide.

## Status and boundaries

| Phase | Status | Deliverable / acceptance gate |
| --- | --- | --- |
| 0: repository/paper mapping | Complete; system-package build, 239 regressions and runtime fixtures passed | Native planner/executor traces, paper mapping, invariants, tests, next-phase proposal; no functional changes |
| 1: native instrumentation | Proposed, not started; user review pending | Optional EXPLAIN counters with precise event semantics; native results/plans unchanged; serial/parallel/rescan tests |
| 2: match representation | Not started | Lookup immediately followed by Expand matches native results with duplicates, NULLs, filters, projections, rescans |
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
  recorded in ARCHITECTURE.md. Phase 1 instrumentation remains unimplemented.

## Phase 1 work packages (proposal only)

1. Resolve build prerequisites and establish native regression baseline.
2. Agree on ARCHITECTURE.md's event definitions and off-by-default GUC.
3. Add the serial node-specific instrumentation block and hooks; verify
   hand-calculated counts, JSON/text rendering, off behavior, and rescans.
4. Add parallel worker lifecycle/aggregation using separate DSM stats keys;
   verify both shared and parallel-oblivious hash joins and worker relaunch.
5. Run full native regression schedule, differential SQL, and update ledger.

These can be separate reviewable commits inside Phase 1; a serial-only
commit must explicitly report missing parallel measurements and must not
claim Phase 1's complete instrumentation support.

Planned production files:

- `src/include/executor/instrument_node.h`: proposed pointer-free
  `DiamondHashJoinInstrumentation` and per-worker container.
- `src/include/nodes/execnodes.h`: HashJoinState counter ownership,
  transient success state, and shared/local statistics references.
- `src/backend/executor/nodeHashjoin.c`: `ExecInitHashJoin`,
  `ExecHashJoinImpl`, `ExecReScanHashJoin`, `ExecShutdownHashJoin`,
  parallel stats estimate/init/reinit/worker/retrieval helpers.
- `src/include/executor/nodeHashjoin.h`: exported diagnostic variable and
  any new lifecycle helper declarations.
- `src/backend/executor/execParallel.c`: integrate stats lifecycle for all
  worker-executed HashJoins; keep shared-table coordination guards intact.
- `src/backend/commands/explain.c`: HashJoin node-specific property output
  and leader/worker summation; preserve existing Hash build statistics.
- `src/backend/utils/misc/guc_parameters.dat`, `postgresql.conf.sample`,
  `doc/src/sgml/config.sgml`: diagnostic control and semantics.
- `src/test/regress/sql/diamond_hashjoin.sql`,
  `src/test/regress/expected/diamond_hashjoin.out`,
  `src/test/regress/parallel_schedule`: proposed self-contained tests.

No Phase 1 changes to `nodeHash.c`, HashPath, HashJoin Plan, or costing are
required for the proposed three new probe/match counters. Reuse native
row instrumentation for emitted/intermediate cardinality. Additive worker
counts must not use the maxima used by Hash build memory statistics.

Acceptance: off preserves output/semantics; on preserves result multisets
and plan choices; counters obey the documented event definitions; duplicates
do not collapse; collision checks remain; no double counting across batch
deferral, rescans, or workers; LIMIT reports observed work; ordinary
EXPLAIN without ANALYZE does not fabricate measurements. Native and new
regression tests pass.

Suggested first functional commit after authorization:
`diamond-pg: add baseline hash join instrumentation`.

## Phase 2: match representation

Inspect/change `nodeHashjoin.c`, `execnodes.h`, and, as needed,
`executor/hashjoin.h`, `nodeHash.c`, `nodeHash.h`; add test and control
documentation. Compare eager copied/reference arrays with a lazy
first-match cursor using exact storage/lifetime/collision semantics.
ARCHITECTURE.md provisionally favors the paper-aligned cursor; Phase 2
must review the detailed descriptor before implementation.

Separate first-match discovery from remaining enumeration but immediately
expand, with no reordering or new plan shape. Initial eligible execution
should be tightly restricted to the documented inner-equijoin class.
Determine whether the first proof supports native batches with complete
drain-before-reset or explicitly restricts/falls back before partial output.
Do not keep references into reset batch storage or redo volatile qualifiers.

Acceptance includes zero/one/many matches, duplicate probe/build keys,
strict NULLs, multiple keys/columns, residual filters, projections,
empty relations, LIMIT/cancellation, rescan, changed parameters, and
cleanup. Phase 2 cannot claim independent scheduling merely because two
helpers exist inside HashJoin.

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

1. Phase 1 exact GUC naming/category and separate stats DSM key allocation;
   total/loop presentation and worker relaunch accounting.
2. Cursor versus eager match representation and independence from mutable
   HashJoinState expression slots; evaluated key ownership.
3. Internal payload/slot protocol, nested Lookup build storage, and safe
   treatment of Material/Sort/Gather/spill and parameterized execution.
4. L&E optimizer state identity and path-pruning equivalence classes;
   initial search scope and planning-time bound.
5. Runtime batching/fallback strategy: estimates cannot guarantee no spill,
   and restarting after emitting rows would duplicate results.
6. Expand3 match counts/secondary indexes and duplicate semantics.
7. Memory/risk calibration and benchmark scale on available hardware.
