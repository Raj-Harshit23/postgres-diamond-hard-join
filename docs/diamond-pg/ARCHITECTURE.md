# Diamond-PG architecture and Phase 0 source map

Last audited: 2026-10-19. **Status: documentation only. No Diamond execution,
planner paths, counters, or GUCs exist yet.** Proposed identifiers below are
design names, not declarations present in PostgreSQL.

## Reproducible base and audit scope

| Item | Observed value |
| --- | --- |
| Source version | PostgreSQL **20devel**, from `configure.ac:20` |
| Local base/HEAD | `6296e78c3d2c7406bb450c5ae477b2fef58f155e` |
| HEAD subject | Add "own_hash" to pg_stat_kind_info |
| HEAD author timestamp | 2026-10-13 13:47:25 +0900 |
| Working branch | `diamond-pg`, created locally from the above HEAD |
| Origin | `https://github.com/Raj-Harshit23/postgres-diamond-hard-join.git` |
| Initial tracked diff | Empty, including the index |
| Initial untracked file | `p3215-birler.pdf`, preserved |
| Upstream remote | Absent; no fetch or independent upstream-base verification |

This is the exact local baseline, not a claim that a remote upstream ref was
verified. `origin/master` pointed at the same commit at audit time. No remote
operation, commit, push, merge, rebase, or PR was performed.

The repository is the PostgreSQL source tree: `src/backend`, `src/include`,
clients/interfaces, `src/test`, `contrib`, `doc/src/sgml`, build configuration,
and developer tools. There was no project documentation or AGENTS.md found
in the checked repository/ancestor guidance paths. The audit inventoried the
tree and read the relevant subsystems below; it did not read every source
file in PostgreSQL. No implementation/build artifacts were added to `src`.

Runtime baseline verified on 2026-10-19 using system-installed dependencies:
assertion/debug build passed and all 239 core regressions passed. The
two-table fixture probes r/builds s and emits 3 rows (2 with the residual
filter). The three-table fixture probes f/builds h at the lower HashJoin,
emitting 8 rows; the upper join builds t and emits 4. Thus the lower input
orientation differs from the illustrative source trace below, as allowed.
Exact expected-result and native hash/non-hash multiset checks passed.
Commands and evidence paths are in TESTING.md; no Diamond behavior exists.

## Research basis

Birler, Kemper, Neumann, *Robust Join Processing with Diamond Hardened
Joins*, PVLDB 17(11), 3215-3228 (2024), DOI 10.14778/3681954.3681995.
Primary reference: <https://www.vldb.org/pvldb/vol17/p3215-birler.pdf>.
The supplied local PDF was text-extracted; page 3219 was also rendered to
verify the operator pseudocode and diagrams. Relevant sections:

- Section 3.2, p. 3219: Lookup finds the first match and returns the probe
  tuple plus an iterator; Expand enumerates the matches. Lookup is shrinking
  for inner joins. It need not materialize a list of every build match.
- Section 3.3, p. 3220: distinguish the expanded **head** (accessible values)
  from deferred relations reachable through iterators. An unexpanded
  relation's attributes cannot be used as ordinary tuple columns.
- Section 3.4, p. 3221: GYO ear removal supplies a two-phase plan for an
  alpha-acyclic predicate structure; nested Lookup payloads can also cross
  a hash build. Independent Lookups on one head are not the whole algorithm.
- Section 3.5.3, p. 3222: Expand3 chooses the smaller iterator and probes a
  secondary hash table on the other side using the primary key plus the
  closing-edge key. Duplicate multiplicities must survive enumeration.
- Section 4, pp. 3223-3225: optimizer state distinguishes L&E expressions,
  computes predicate boundaries, delays expansion until needed, and permits
  selected early expansion. Equivalence classes prevent redundant equality
  edges from being mistaken for cycles.

The paper targets in-memory hash joins in Umbra. PostgreSQL node protocols,
hybrid batching, ownership, work_mem/spill costing, and instrumentation are
our integration choices. We do not claim Umbra's generated machine-code
equivalence, worst-case bounds, or measured speedups for this prototype.
Aggregation, outer-join reordering, SIP/Bloom-filter extensions, and general
n-way WCOJ are outside the initial implementation scope.

## Native planner: exact responsibilities

Paths are candidate implementations; Plans are the chosen, serializable
instructions; PlanStates contain mutable execution state. Confusing these
layers would place deferred execution pointers in cached/serialized plans.

| File under `src/` | Relevant identifiers and current responsibility |
| --- | --- |
| `backend/optimizer/plan/planner.c` | `standard_planner`, `subquery_planner`, `grouping_planner`: plan query levels, choose upper paths, create the final plan |
| `backend/optimizer/plan/planmain.c` | `query_planner`: build scan/join planning state |
| `backend/optimizer/plan/initsplan.c` | RestrictInfo and join-domain/equivalence processing, including calls to `process_equivalence` |
| `backend/optimizer/path/allpaths.c` | `make_one_rel`, `make_rel_from_joinlist`, `standard_join_search`: base paths and join search entry points |
| `backend/optimizer/path/joinrels.c` | `join_search_one_level`, `make_join_rel`, `populate_joinrel_with_paths`: legal subset joins and input orientations |
| `backend/optimizer/path/joinpath.c` | `add_paths_to_joinrel`, `hash_inner_and_outer`, `try_hashjoin_path`, `try_partial_hashjoin_path`: eligible hash clauses and candidate paths |
| `backend/optimizer/path/equivclass.c` | `process_equivalence`, `generate_join_implied_equalities`: equality normalization/derived predicates, subject to operator-family/collation/security rules |
| `backend/optimizer/util/relnode.c` | Joinrel construction, restriction lists, parameterized relation metadata |
| `backend/optimizer/util/pathnode.c` | `create_hashjoin_path`, `add_path`, `set_cheapest`: construct, compare, prune candidate paths |
| `backend/optimizer/path/costsize.c` | `initial_cost_hashjoin`, `final_cost_hashjoin`: source/hash CPU, residual qualifiers, output/projection, bucket/fanout estimates, batch I/O |
| `backend/optimizer/plan/createplan.c` | `create_plan`, `create_hashjoin_plan`, `make_hash`, `make_hashjoin`: chosen HashPath becomes HashJoin with a Hash build child |
| `backend/optimizer/plan/setrefs.c` | `set_plan_references`, `set_join_references`: fix expressions to child target-list positions and special Vars |
| `include/nodes/pathnodes.h` | `PlannerInfo`, `RelOptInfo`, `Path`, `JoinPath`, `HashPath`, `RestrictInfo`, `EquivalenceClass` |
| `include/nodes/plannodes.h` | `Plan`, `Join`, `HashJoin`, `Hash`: read-only execution instructions |
| `include/optimizer/{paths.h,pathnode.h,cost.h,planmain.h}` | Interfaces for path search, construction, costing, and planning |

`hash_inner_and_outer()` checks `RestrictInfo.can_join`,
`hashjoinoperator`, clause sides, and an applicable commutator. A hashable
clause alone is not proof it belongs in Diamond's supported query class.
`try_hashjoin_path()` preserves required-outer/parameterization restrictions.
This checkout uses `JoinPathExtraData.pgs_mask`, `PGS_HASHJOIN`, and
`Path.disabled_nodes` in native candidate generation/costing; do not assume
older enable_hashjoin/disable-cost patterns are sufficient.

`HashPath` embeds `JoinPath`, containing both inputs and restrictions, and
adds `path_hashclauses`, `num_batches`, and `inner_rows_total`.
`create_hashjoin_path()` deliberately advertises no output pathkeys because
batching may reorder output. `add_path()` assumes competing paths for a
given relation/target/parameterization implement the same relational output.
A deferred head plus handles is not automatically interchangeable with a
fully expanded join result. Phase 4 must represent this distinction before
allowing ordinary path pruning to compare candidates.

`create_hashjoin_plan()` separates hash equality clauses from remaining
join qualifiers, extracts outer/inner hash keys, and wraps the build input
in a Hash plan. HashJoin's `hashkeys` refer to its outer child; Hash's
`hashkeys` refer to Hash's own outer child. `setrefs.c` must preserve that
distinction even with subplans/parameters in expressions.

`initial_cost_hashjoin()` already calls `ExecChooseHashTableSize()` and
charges for expected batch I/O. `get_hash_memory_limit()` computes the
hash limit from `work_mem * hash_mem_multiplier` (with overflow clamping).
Phase 7 extends native costing with deferred-state/intermediate-growth
effects; it must not double-charge existing spill estimates or treat
work_mem as one hard query-wide memory cap.

## Native executor and ownership

| File under `src/` | Relevant identifiers and current responsibility |
| --- | --- |
| `backend/executor/execMain.c` | `ExecutorStart`/`standard_ExecutorStart`, `InitPlan`, `ExecutorRun`/`standard_ExecutorRun`, `ExecutePlan`: initialize and pull a state tree |
| `backend/executor/execProcnode.c` | `ExecInitNode`, `MultiExecProcNode`, `ExecEndNode`, shutdown dispatch |
| `include/executor/executor.h` | `ExecProcNode` and executor interfaces |
| `backend/executor/nodeHashjoin.c` | `ExecInitHashJoin`, `ExecHashJoinImpl`, `ExecHashJoin`, `ExecParallelHashJoin`, `ExecHashJoinOuterGetTuple`, `ExecHashJoinNewBatch`, `ExecReScanHashJoin`, `ExecShutdownHashJoin`, `ExecEndHashJoin` |
| `backend/executor/nodeHash.c` | `MultiExecHash`, `MultiExecPrivateHash`, `MultiExecParallelHash`, `ExecHashTableCreate`, `ExecHashTableInsert`, `ExecScanHashBucket`, `ExecParallelScanHashBucket`, `ExecHashTableReset`, `ExecHashTableDestroy` |
| `include/executor/hashjoin.h` | `HashJoinTupleData`, `HashJoinTableData`, skew/batch/parallel structures |
| `include/nodes/execnodes.h` | `PlanState`, `JoinState`, `HashJoinState`, `HashState`, `ExprContext` |
| `include/executor/{nodeHash.h,nodeHashjoin.h}` | Build/probe/lifecycle and parallel entry points |
| `backend/executor/{execTuples.c,execExpr.c,execExprInterp.c}` | Slot operations, `ExecBuildHash32Expr`, expression evaluation |
| `include/executor/tuptable.h` | Slot types, descriptor and by-reference Datum ownership |
| `backend/executor/execAmi.c` | Rescan and node capability dispatch |
| `backend/executor/execParallel.c` | DSM initialization, worker startup, statistics retrieval |
| `backend/utils/mmgr/README` | MemoryContext ownership/reset semantics |

PostgreSQL is demand-pull: each `ExecProcNode()` returns one tuple slot or
end-of-stream. A Hash node is special: HashJoin calls `MultiExecProcNode()`
to populate the build table, not `ExecProcNode(Hash)` to obtain build rows.
The build input is Hash's **outer/left** child despite Hash being the
**inner/right** child of HashJoin.

`HashJoinState` retains `hj_HashTable`, `hj_OuterHash`, `hashclauses`,
`hj_CurHashValue`, `hj_CurBucketNo`, `hj_CurSkewBucketNo`, `hj_CurTuple`,
outer/build slots, `hj_JoinState`, and match/NULL bookkeeping.
`HashState` retains build-key `hash_expr`, its table, NULL tuplestore, and
hash instrumentation. These are execution objects, not planner estimates.

The serial state machine is:

```text
HJ_BUILD_HASHTABLE
  -> HJ_NEED_NEW_OUTER
       hash key; choose main/skew bucket and batch
       postpone wrong-batch tuple to file, otherwise:
  -> HJ_SCAN_BUCKET
       next equality match -> residual joinqual -> otherqual -> ExecProject
       return one slot; next parent call resumes this bucket
       exhausted -> HJ_FILL_OUTER_TUPLE
  -> HJ_NEED_NEW_OUTER (or HJ_FILL_INNER_TUPLES at end of outer batch)
  -> NULL-key fill states when required
  -> HJ_NEED_NEW_BATCH -> next batch or EOF
```

`ExecHashJoinImpl()` resets its per-tuple expression context on entry.
`ExecHashJoinOuterGetTuple()` evaluates outer hashes on batch 0 and reads
saved hashes/tuples for later batches. Strict NULL keys cannot match; the
native path discards them or saves them for outer-join NULL extension.
Non-strict hash operators have separate native semantics and must not be
mistaken for ordinary SQL equality in Diamond eligibility checks.

### Exact Lookup/Expand boundary

1. In `HJ_NEED_NEW_OUTER`, `ExecHashGetBucketAndBatch()` and
   `ExecHashGetSkewBucket()` select storage; wrong-batch rows are deferred.
2. In `HJ_SCAN_BUCKET`, `ExecScanHashBucket()` starts at a bucket head or
   advances from `hj_CurTuple`. It checks stored hash values, stores a
   borrowed build MinimalTuple in `hj_HashTupleSlot`, then executes the
   hash equality clauses using `ExecQualAndReset()`.
3. A true return records one matching tuple in `hj_CurTuple` and the inner
   expression slot. This is the natural **first-match Lookup** boundary.
   Equal hash codes are not sufficient: equality rechecks are required.
4. Back in `ExecHashJoinImpl()`, `js.joinqual` decides join-match status;
   `ps.qual` (otherqual) decides whether a result may be returned. Match
   flags and semi/anti/inner_unique rules are handled between those checks.
5. `ExecProject()` creates a result slot for this pair. On the next parent
   pull, the bucket scan resumes. Advancing the cursor, residual checks,
   and producing each result together comprise today's **expansion**.

Thus there is already a suspended one-match cursor, but no independently
schedulable Lookup result in the tuple stream. Returning `hj_CurTuple` as
an ordinary SQL column would not establish such a protocol. Projection
usually produces a virtual slot, not necessarily a copied heap tuple;
"materialize a joined tuple" here means exposing its logical values.

### Lifetime invariants

- `HashJoinTupleData` has a chain link (private pointer or shared DSA
  pointer), hash value, and inline MinimalTuple. A bucket may mix distinct
  keys/collisions; the remaining chain is not a prevalidated match set.
- Serial `HashJoinTableData.hashCxt` owns whole-table metadata;
  `batchCxt` owns current-batch tuples/buckets; `spillCxt` owns file buffers.
  `ExecHashTableReset()` resets batchCxt and invalidates borrowed pointers.
- A child slot and its by-reference Datums may be overwritten on its next
  pull. Deferred use needs an owned copy or a documented retained lifetime.
  It cannot rely on a per-tuple context that expression evaluation resets.
- A reference into a table is valid only while its owner/batch remains
  alive. Rescan, repartition, shutdown, cancellation, and query end must
  invalidate or release every deferred reference before freeing storage.
- `ExecReScanHashJoin()` reuses an unparameterized, single-batch table when
  possible; otherwise destroys/rebuilds it. It resets the current cursor,
  outer state, and applicable match flags; changes to inner parameters must
  defeat reuse. Any Diamond state needs the same discipline.
- Shared Parallel Hash has participant barriers and DSA links; a private
  raw pointer cannot be shared or spilled. Parallel-oblivious hash joins
  under Gather also run in workers, despite `parallel_aware == false`.
- Preserve cancellation checks, expression semantics, collation/operator
  handling, NULL extension, and multiplicity. An inner join's residual
  filter can reject one duplicate and accept another; one equality match
  is not proof that any complete joined row survives.

Local history resolved a relevant version difference: commit
`1811f1af98fb237fdd5adb588cd4b57c433b75f8` (2026-03-19), "Improve hash
join's handling of tuples with null join keys", explains why strict-NULL
outer-join tuples now live in local tuplestores, including in parallel
execution. It also explains why immediate NULL-row return is problematic
on rescan. No remote history lookup was needed.

## Two-table planning and execution trace

Example: `SELECT r.id, s.payload FROM r JOIN s ON r.k = s.k`, with a chosen
serial hash plan building `s`. This is a source trace of a possible chosen
plan, not a claim that the cost-based planner always picks this orientation.
Executable fixtures and expected row counts are in TESTING.md.

```text
Query
 -> standard_planner -> subquery_planner -> grouping_planner
 -> query_planner -> make_one_rel -> make_rel_from_joinlist
 -> standard_join_search (two base relations, ordinary small-query case)
 -> join_search_one_level(2) -> make_join_rel
 -> populate_joinrel_with_paths -> add_paths_to_joinrel
 -> hash_inner_and_outer -> try_hashjoin_path
 -> initial_cost_hashjoin -> create_hashjoin_path -> final_cost_hashjoin
 -> add_path / set_cheapest -> final path choice
 -> create_plan -> create_hashjoin_plan -> make_hash / make_hashjoin
 -> set_plan_references / set_join_references

HashJoin [probe r, build s]
  SeqScan r
  Hash [key s.k]
    SeqScan s
```

`ExecutorStart()` initializes the tree through `ExecInitNode()` and
`ExecInitHashJoin()`, compiles hashes/quals, and creates result slots.
`ExecutePlan()` pulls the root. `HJ_BUILD_HASHTABLE` creates the table and
`MultiExecHash()` consumes `s` (unless an empty-input optimization stops
earlier). Each admitted `r` probes its batch, obtains its first equality
match, applies residual checks, projects, and returns. Repeated root calls
enumerate duplicates. No matching build row means no inner-join output.
`ExecEndHashJoin()` and hash teardown release resources.

## Three-table trace and the diamond

Example: `r(a,b) JOIN s(a) ON r.a=s.a JOIN t(b) ON r.b=t.b`.
At search level 2 PostgreSQL generates legal two-relation joinrels and
paths. Level 3 combines a two-relation joinrel with the third relation
(also respecting joinlist restrictions); orientations and alternative
algorithms compete by cost. More general searches include bushy plans.
GEQO or `join_search_hook` may replace standard search; neither is modified
or assumed Diamond-capable in this phase.

One possible native plan is:

```text
HashJoin J2 [r.b=t.b]
  HashJoin J1 [r.a=s.a]
    SeqScan r
    Hash -> SeqScan s
  Hash -> SeqScan t
```

J2 builds `t` then pulls J1; J1 builds `s`. For every `r`, J1 finds and
expands all `s` matches one at a time. J2 probes `t` once for each returned
J1 pair. An `r` with 1,000 `s` matches and no `t` match causes 1,000
intermediate J1 emissions and J2 probes even though it contributes no
final row. A small parent result does not imply a small child result.

For this predicate dependency the paper permits:

```text
r -> Lookup(s on r.a) -> Lookup(t on r.b) -> Expand(s) -> Expand(t)
```

Both Lookups use already-expanded r attributes, so t can reject r before
s fanout is enumerated. If a later key instead requires an attribute from
s, this simple pushdown is illegal until that value is expanded. For a
chain, the paper also permits nested state (`r -> (s -> t)`) stored with
the build tuples; Phase 3 must leave room for that.

Three textual edges `r.a=s.a`, `s.a=t.a`, `r.a=t.a` do not make a genuine
cycle: equality implication removes the redundant edge. The true triangle
`r(a,b), s(b,c), t(c,a)` has a closing predicate on unexpanded c; this is
the Phase 6 case, not a reason to treat every three-table join as Expand3.

## Minimum change surfaces and design alternatives

**Phase 2, immediate proof of decomposition:** the minimum production
surface is `backend/executor/nodeHashjoin.c` plus
`include/nodes/execnodes.h` (state), with `include/executor/hashjoin.h` if
the reusable match descriptor is defined alongside hash storage types.
`backend/executor/nodeHash.c` and `include/executor/nodeHash.h` become
necessary if an independent cursor API replaces the scanner's mutable
HashJoinState coupling. Tests, GUC source/manual, and project documents
also change. No Path/Plan node is needed merely to prove immediate L&E.

| Representation | Benefit | Main constraint |
| --- | --- | --- |
| Eager array/list of matching tuple references or copies | Explicit multiplicity and enumeration | O(fanout) work/state before the next selective Lookup; copies amplify memory; references still depend on batch lifetime |
| First-match cursor plus stable probe/key context | Closest to paper; bounded initial handle; defer remaining scan | Must recheck collisions, retain keys, isolate cursor/slots, define reset/owner lifetime; no O(1) match-count guarantee |

Recommend investigating the cursor design in Phase 2, using existing
bucket-scan semantics and immediate expansion first. The choice is
**provisional**, not an approved lifetime/spill protocol. An eager prototype
cannot be described as the final paper-efficient Lookup. Neither design
gives Expand3 the per-key match counts or secondary composite-key indexes
it needs; PostgreSQL's mixed-key bucket length is not a match-set length.

**Phase 3:** independently schedulable operations require a new internal
stream contract, proposed Lookup/Expand PlanStates and Plans, and a way to
carry head values plus multiple/nested deferred descriptors. A dedicated
internal slot/sidecar protocol versus an executor-owned composite payload
must be compared before implementation. Do not pass a process pointer as
a generic SQL Datum through Sort, Material, Gather, or disk storage.

At minimum inspect/change `include/nodes/plannodes.h`, `execnodes.h`,
executor node files/headers, `execProcnode.c`, `execAmi.c`, `explain.c`,
`optimizer/plan/{createplan.c,setrefs.c}`, and node walkers in
`backend/nodes/nodeFuncs.c`. `backend/nodes/README` describes generated
NodeTags/copy/output/read support: edit annotated source headers, audit
generated results, never hand-edit the generated files. Audit
`execParallel.c`, `optimizer/plan/subselect.c`, capability checks, and all
comparable native node references before claiming infrastructure complete.

**Phase 4:** add L&E-aware Path representation in `pathnodes.h`, construction
and interface support in `util/pathnode.c`/`include/optimizer/pathnode.h`,
eligibility/dependency logic around `initsplan.c`, `equivclass.c`,
`joinrels.c`, `joinpath.c`/`allpaths.c`, and plan construction/reference
fixing. Different deferred states need separate comparability rules or a
separate memo keyed by L&E state. Only fully expanded alternatives can
compete as ordinary results. New costs belong in `costsize.c`/`cost.h`.
This is an architectural decision to review in its own phase, not a promise
that adding two node tags alone implements the paper optimizer.

## Proposed Phase 1: optional native HashJoin counters

**Recommendation for review; not implemented.** Add instrumentation to the
existing HashJoin state machine. Keep its transitions, tuple flow, planner
costs, and quals unchanged. Baseline instrumentation covers native join
behavior; it does not enable Diamond join execution.

Alternatives: backend DEBUG logs are easy but awkward to attribute/aggregate;
adding universal `NodeInstrumentation` fields enlarges every operator and
shared record; a node-specific counter block follows Hash/Memoize and
keeps these measurements associated with HashJoin. Recommend the latter,
reported through normal EXPLAIN property helpers in text/JSON/XML/YAML.

Proposed opt-in GUC: `diamond_hashjoin_stats`, default off, `PGC_USERSET`,
latched at executor initialization and collected only with row
instrumentation (e.g. EXPLAIN ANALYZE). This is separate from a future
`enable_diamond_join` plan-selection GUC. Recheck GUC naming/category
against nearby diagnostic parameters before adding its declaration.

Proposed pointer-free `DiamondHashJoinInstrumentation` belongs in
`include/executor/instrument_node.h`; query-lifetime ownership and a
pointer/collection flag belong in `HashJoinState` in `execnodes.h`.
The public configuration variable/interface can live in `nodeHashjoin.c`
and `include/executor/nodeHashjoin.h`, following surrounding exports.

Initialization ordering matters: `ExecInitNode()` allocates
`PlanState.instrument` **after** the node-specific initializer returns.
If collection is selected inside `ExecInitHashJoin()`, consult
`estate->es_instrument`; checking `hjstate->js.ps.instrument` there would
incorrectly conclude that instrumentation is disabled. Later execution/DSM
hooks can use the initialized node instrumentation pointer.

| Metric | Exact proposed event/meaning |
| --- | --- |
| Hash probes | Once when an outer row is admitted to its resident main/skew batch and transitions to `HJ_SCAN_BUCKET`; do not count a row merely written to a later batch file |
| Successful probes | Once on the first true bucket-scan return for that admitted row, after hash equality recheck; independent of residual joinqual/otherqual |
| Build matches | Once for every true `ExecScanHashBucket` / `ExecParallelScanHashBucket` result actually consumed by the state machine; counts probe/build pairs, not globally distinct build rows |
| Joined tuples emitted | Reuse native finalized `NodeInstrumentation.ntuples`/loops at the HashJoin; native count includes NULL-extended rows for outer joins |
| Intermediate cardinality | Emitted rows of a non-root join over its observed executions, using native instrumentation; not bytes or peak resident memory |

Optionally add a separately named joinqual-pass pair counter to explain
residual rejection; do not silently redefine equality success as output
success. `hj_MatchedOuter` records residual join-match status, so it is
not a substitute for the successful-equality-probe flag. A per-probe flag
must reset at admission and rescan, not after every output tuple.

Counters measure **observed work**: LIMIT/early shutdown, inner_unique,
semi/anti early exits, empty-build/empty-outer shortcuts, and right-semi
skips may avoid enumerating possible matches. Never force additional
scans to make the counters exhaustive. A strict-NULL key discarded before
admission is not a hash probe. Empty/skipped nodes must not display
invented full-scan counts. Define sum-over-loops integer totals separately
from native EXPLAIN's average rows per loop.

Minimum serial counter hooks can remain in `nodeHashjoin.c`: both scanners
already return to `HJ_SCAN_BUCKET`. Editing `nodeHash.c` is unnecessary
unless the design adds chain-visit/collision metrics (not required now).

Parallel collection must handle both shared Parallel Hash and private
hash joins under Gather. Follow `MemoizeInstrumentation`/`SharedMemoizeInfo`
and `ExecHashRetrieveInstrumentation()` for pointer-free worker records and
leader-side copies before DSM destruction. Add a separately keyed stats
allocation: HashJoin's existing plan_node_id TOC key is already used for
`ParallelHashJoinState`. `instrument_node.h` documents the offset-key
pattern; audit collisions before choosing a key. Update the HashJoin cases
in the estimate/DSM/reinitialize/worker/retrieve walkers in `execParallel.c`
so stats are not conditional solely on `plan->parallel_aware`. Preserve
the existing guards for shared hash-table coordination itself.

`ExecShutdownHashJoin()` must publish worker stats before cleanup;
`ExecReScanHashJoin()` clears only transient probe flags and preserves
cumulative totals. Worker relaunch/reinitialization must neither lose nor
double-count prior totals. Sum additive counters across leader/workers;
existing `HashInstrumentation` memory/bucket statistics use maxima and
cannot simply be reused as an additive probe-counter container.

Native row instrumentation has its own worker merge path. Reusing its
final emitted-row total must not add worker row counts a second time when
the helper aggregates the separate Diamond probe/match records.

Presentation belongs on the HashJoin branch of `ExplainNode()` (a proposed
`show_diamond_hashjoin_info()` helper); existing `show_hash_info()` stays
on the Hash build child. Use `ExplainPropertyUInteger()` and group helpers,
guarded by actual collection and ANALYZE. Off means no new output and no
counter allocation; no claim of literally zero branch overhead.

Additional files: `utils/misc/guc_parameters.dat` (source, not generated
`utils/guc_tables.inc.c`), `postgresql.conf.sample`, the relevant SGML
configuration documentation, regression SQL/expected output/schedule, and
this documentation. Phase 1 does not need `HashPath`, `HashJoin` Plan,
costing, or join-search changes.

Acceptance and counter oracle are in TESTING.md. The native build/runtime
baseline now passes; review this proposal before Phase 1 implementation.
