# Diamond-PG architecture

Updated 2026-11-01 on `diamond-pg-cloud`, PostgreSQL 20devel base
`6296e78c3d2c7406bb450c5ae477b2fef58f155e`. The current implementation is
the bounded alpha-acyclic, strictly two-phase specialization of the paper's
Section 4 state search.

## Automatic acyclic alternatives

`allpaths.c:add_diamond_acyclic_path` runs on the complete join relation after
the configured PostgreSQL search method returns, so standard dynamic
programming, GEQO, and a join-search hook can all receive the same independent
Diamond alternative. Native paths remain in ordinary `add_path` competition.

For each possible surviving root, a bounded memo enumerates legal GYO ear
removals over 3--16 regular heap relations. A memo entry encodes the minimized
L&E expression: its surviving heads and the parent forest of deferred payloads.
States with the same relation set but different forests remain distinct, as
required by Section 4's state-equivalence rule. Equivalent expressions retain
the cheapest schedule; complete expressions use the full Lookup, copy, Expand,
and enumeration cost before pruning. Equality edges are generated once from
PostgreSQL EquivalenceClasses, preserving strict same-type hash operator and
collation semantics and treating redundant equalities as one attribute.

Every transition checks that its retained hash build is predicted single-batch.
Only a complete, fully expanded `DiamondPath` is admitted. Its base scans and
ordinary serial hash fallback are built independently of native path pruning;
native indexed, merge, nested-loop, and parallel alternatives remain available.
`diamond_acyclic` defaults off and adds candidates. The diagnostic
`diamond_acyclic_force` only selects a candidate after all semantic, acyclicity,
and residency checks and preserves the model costs shown by EXPLAIN.

`createplan.c` first builds a canonical relational HashJoin tree, runs normal
reference and parameter processing, then factorizes the chosen Diamond arm into
Lookup/Expand nodes. `DiamondJoin` retains separate native and optimized Plan
arms. A checked resource signal may choose native only before output; SQL
errors, cancellation, and OOM propagate, and execution never restarts after a
row has been emitted.

This implements the complete two-phase search for the documented bounded
acyclic region. It does not implement Section 4's broader connected-subregion
search, predicate-boundary early Expands, Expand3, outer joins, or deferred
spill. Those features broaden the supported/search space; they are not needed
to execute an admitted two-phase acyclic plan correctly.

## Retained nested-build ownership

Native SQL `HashJoinTuple` layout is unchanged. Private
`HashJoinTableData.diamond_matches` indexes native tuple addresses in a
batch-owned dynahash. Each retained `DiamondDeferredMatch` owns its probe
MinimalTuple and validates its Lookup owner's `storage_generation`, separate
from next-head generation. Build initialization pins contributing Lookup
owners before pulling; actual multi-batch tables reject before descriptors
escape. Retained tables cannot repartition or spill. Allocator totals include
probe copies, sidecar map, native tuples/buckets and final bucket growth.
Single-batch native builds have no skew table. Ordinary native batching/skew
paths retain their behavior.

Expand resolves owners through typed outer chains and nested Hash build
branches, restores owned probes into its own MinimalTuple slot, and imports
the selected build tuple's nested descriptors. Private iterator copies preserve
duplicate multiplicity; invariant leaf sidecars are reused while draining
matches. Rescan/end invalidate epochs before cleanup. No process pointer is
stored as a SQL Datum or raw spill payload; parallel/materialized ordinary
consumers require full expansion.

## Current eligibility and validation

A candidate covers a complete 3--16-relation SELECT region with regular heap
relations, simple-column strict same-type hash equality ECs, immutable base
filters, no cross-relation residual, and no live outer/lateral/security/locking,
DML, placeholder, target-SRF, or subplan boundary. Genuine cycles and unsupported
expressions remain native. GEQO is supported; the regression lowers
`geqo_threshold` to force a four-relation chain through GEQO, executes three
Lookup/Expand pairs, and verifies its result bag against native execution.

The final assertion/debug build passes focused `diamond_hashjoin` 1/1 and all
240 core regressions. Existing optimized evidence remains: all 22 TPC-H SF1 and
113 JOB result bags matched native at the earlier checkpoint, with no automatic
Diamond selection. On final commit `51f18a8781`, paper acyclic N=1000/5000
selected Diamond and measured 201.0x/669.3x native-over-automatic medians;
N=50000 completed automatically in 30.785ms while native exceeded 120s.
A current external-disk TPC-H attempt verified Q1--Q4 bags with no selection, then Q5 timed out in both modes;
these slow storage-bound measurements do not replace the completed baseline.

## First correction: pruning-independent inputs/fallback

The first follow-up increment removes the proven path-survivor dependency.
`create_seqscan_path` supplies a legal serial heap alternative even after
native pruning; cheaper supported unparameterized index/index-only/bitmap
paths compete as inputs. Canonical native fallback and optimized trees have
separate ordinary Plan states, identical immutable scans/targets/snapshot,
and no Gather/parallel or deferred payload in the fallback. Native competitors
remain unchanged. Runtime owns/copied-head slot deformation works with each
explicitly admitted native scan state. New selected-input, multiset, copy/read,
rewind and resource-fallback tests pass; focused1/1 and core240/240 pass.

The pruning-independent inputs and fallback remain part of the current
implementation. The subsequent root-aware minimized-expression memo supersedes
the earlier greedy scheduler. Predicate-boundary early Expand and arbitrary
partial-region search remain outside the bounded two-phase scope. Published
performance/diagnosis below belongs to checkpoint 441f907cf6 and is retained as
historical evidence, not current-source performance coverage.

## Observed planner-coverage limitation

The follow-up trace of all135 benchmark queries shows that the retained
fallback search runs on already-pruned final `joinrel->pathlist`, before the
semantic/EC/GYO checks. Requiring a recursively pure SeqScan/HashPath survivor
blocks93 JOB queries;20 others use GEQO. Base SeqScan availability is also a
pruning dependency (JOB15a/b/c). These are integration restrictions, not
fundamental requirements of Lookup/Expand or proof of semantic ineligibility.
Only TPC-H Q3 reaches real candidate costing and loses native path competition.
Diagnostic analysis behind the fallback gate never admits candidates; its
costs are counterfactual. TESTING.md gives exact counts, costs and evidence.
No functional change or claim of a corrected cost model follows from this trace.

## Historical source map and earlier phase checkpoints

The sections below describe the baseline audit and prior milestones. Their
branch/status/future-work statements refer to those earlier dates; the
current contract and restrictions above supersede them.

## Reproducible base and audit scope

| Item | Observed value |
| --- | --- |
| Source version | PostgreSQL **20devel**, from `configure.ac:20` |
| PostgreSQL source base | `6296e78c3d2c7406bb450c5ae477b2fef58f155e` |
| Base subject | Add "own_hash" to pg_stat_kind_info |
| Base author timestamp | 2026-10-13 13:47:25 +0900 |
| Completed project checkpoints | Phase 0: `7756e8e52e`; Phase 1: `14ac927a8b`; Phase 2: `c169183521`; bounded Phase 3: `0aa87a8624` |
| Current work | Phase 3 bounded independent execution committed; authenticated publication pending |
| Working branch | `diamond-pg`, created locally from the above HEAD |
| Origin | `https://github.com/Raj-Harshit23/postgres-diamond-hard-join.git` |
| Initial tracked diff | Empty, including the index |
| Initial untracked file | `p3215-birler.pdf`, preserved |
| Upstream remote | Absent; no fetch or independent upstream-base verification |

This is the exact local baseline, not a claim that a remote upstream ref was
verified. `origin/master` pointed at the base commit at the initial audit.
The project checkpoints above were subsequently committed locally. Publication
was authorized on 2026-10-25, but the HTTPS push failed for missing GitHub
authentication. No successful push, merge, rebase or PR has been performed.

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
Commands and evidence paths are in TESTING.md. These are Phase 0 results;
Phase 1 instrumentation and Phase 2's restricted immediate execution are
described below; these baseline measurements did not use either feature.

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
the build tuples; nested deferred build storage is still outstanding.

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

Phase 2 selects the first-match cursor and immediate expansion with the
restricted lifetime contract below. It avoids an O(fanout) reference array
or copied match list. This does not supply Expand3's per-key match counts or
secondary indexes: a mixed-key bucket length is not a match-set length.

**Phase 3:** separate Plan/PlanState types use typed, executor-private
sidecars for deferred relations; the implemented contract is described below.
They never encode a process pointer as a SQL Datum. Nested deferred build
payloads remain a separate unresolved storage problem before chain planning.

**Phase 4:** add L&E-aware Path representation in `pathnodes.h`, construction
and interface support in `util/pathnode.c`/`include/optimizer/pathnode.h`,
eligibility/dependency logic around `initsplan.c`, `equivclass.c`,
`joinrels.c`, `joinpath.c`/`allpaths.c`, and plan construction/reference
fixing. Different deferred states need separate comparability rules or a
separate memo keyed by L&E state. Only fully expanded alternatives can
compete as ordinary results. New costs belong in `costsize.c`/`cost.h`.
This is an architectural decision to review in its own phase, not a promise
that adding two node tags alone implements the paper optimizer.

## Phase 1: optional native HashJoin counters

`SET diamond_hashjoin_stats = on` enables counters for instrumented execution
such as EXPLAIN ANALYZE. The default is off. This diagnostic does not change
join planning, qualifiers, transitions, or match enumeration. No Lookup/Expand
execution is implemented by this phase.

`DiamondHashJoinInstrumentation` in `include/executor/instrument_node.h`
contains three uint64 counters. `HashJoinState.hj_DiamondStats` owns an
optional query-lifetime block; `hj_DiamondMatched` records equality success
for the current probe. The disabled/uninstrumented path allocates no block.
`ExecInitHashJoin()` uses `estate->es_instrument`, because `ExecInitNode()`
installs `PlanState.instrument` only after the node initializer returns.

| EXPLAIN property | Exact event/meaning |
| --- | --- |
| Diamond Hash Probes | Row admitted to its resident main/skew batch and entering HJ_SCAN_BUCKET; a row written to a later batch is not yet counted |
| Diamond Successful Probes | First true bucket-scan return for that admitted row, after equality recheck and before residual qualifiers |
| Diamond Build Matches | Every true bucket-scan return actually consumed; probe/build pairs, including duplicates, not distinct build rows |
| Diamond Tuples Emitted | Native finalized NodeInstrumentation.ntuples; cumulative output including outer-join NULL extension |

Counters describe observed work. LIMIT, empty-input shortcuts, inner_unique,
semi/anti behavior and right-semi skips can avoid potential matches. Collection
never forces extra scans. Strict NULL keys discarded before admission do not
probe. `hj_MatchedOuter` cannot replace the separate equality-success flag:
residual qualifiers may reject every equality match. Rescan clears transient
success state but retains totals. A child join's emitted rows give observed
intermediate cardinality, not bytes or peak resident memory.

The two hooks are inside `ExecHashJoinImpl()`; `nodeHash.c` is unchanged.
Both serial and shared-hash scanners return through them. Projection/output
counts use existing instrumentation rather than extra projection hooks.

### Parallel lifetime

`SharedDiamondHashJoinInfo` provides one pointer-free counter record per
worker. `ExecHashJoinEstimate()` / `ExecHashJoinInitializeDSM()` are called for
both parallel-aware and private worker hashes; native shared-table setup
remains guarded inside them. The existing secondary instrumentation key
`plan_node_id + PARALLEL_KEY_SCAN_INSTRUMENT_OFFSET` is safe here because a
plan_node_id identifies exactly one node type.

`ExecHashJoinInitializeWorker()` attaches to the leader-selected collection
block. That presence also controls worker collection if the GUC changed after
leader initialization. Each worker owns its own slot: no atomic updates or
shared counters are needed in the probe loop.

`ExecShutdownHashJoin()` adds local deltas to that worker's slot and clears
its local block, making repeated publication idempotent. Shared records are
not reset on Gather relaunch: fresh worker instances add to the existing
slot. This preserves work from earlier launches.

After workers finish, `ExecHashJoinRetrieveInstrumentation()` sums worker
records into the leader's query-owned totals before DSM destruction, then
clears the shared pointer to avoid stale access or repeated merging. This is
smaller than retaining copies of all worker records. Native emitted rows
already have their own worker merge; they are not added again here.

### Presentation and configuration

`show_diamond_hashjoin_info()` in `commands/explain.c` prints properties on
the HashJoin node through normal text/JSON/XML/YAML helpers. It requires
ANALYZE and a collection block; ordinary EXPLAIN and stats-off output retain
native presentation. Counts are totals, whereas native Actual Rows is an
average per loop. Build-child `show_hash_info()` remains unchanged.

The GUC definition is source data in `utils/misc/guc_parameters.dat`, with
its variable declared in `nodeHashjoin.h` and defined in `nodeHashjoin.c`.
It is PGC_USERSET, DEVELOPER_OPTIONS, GUC_NOT_IN_SAMPLE, following native
developer diagnostics. `doc/src/sgml/config.sgml` documents the semantics;
no sample configuration or generated GUC file is edited.

Regression coverage and exact commands/results are in TESTING.md. No Path,
Plan, costing, hash storage, or join-search changes are needed for Phase 1.

## Phase 2: first-match cursor with immediate Expand

`diamond_lookup_expand` is an off-by-default developer GUC, independent of
`diamond_hashjoin_stats`. It selects execution at node initialization without
changing planner alternatives, costs or Plan nodes. EXPLAIN's boolean
`Diamond Lookup Expand` property records that selection, including in plain
EXPLAIN; absence means native execution. An unexecuted node can still have
this property, so execution evidence also requires ANALYZE/Actual Loops.

`ExecHashJoinCanLookupExpand()` checks two direct SeqScans over regular heap
relations, JOIN_INNER, and strict hash operators with simple column keys.
It follows slot Vars through scan target lists, rejecting computed keys
which setrefs has hidden behind a Var. It rejects parallel-mode statements
(including forced Gather), parallel-aware scans/joins and worker execution.
Other join types, expression keys, index/foreign scans, intermediate join
inputs and unsupported plans remain native. Scan filters may contain
parameters; native chgParam handling still controls hash reuse/rebuild.

`DiamondHashMatch` in `executor/hashjoin.h` is a query-owned, bounded record
of the table, current matching tuple, probe slot, saved hash, batch number
and first-match-pending flag. It borrows tuple storage, allocates no match
array, and holds no Datums allocated in the resettable expression context.
The probe child is not pulled during expansion, so its slot and by-reference
column values remain valid. This borrowing contract applies only to immediate
expansion; it is not Phase 3's transport/ownership contract.

Execution in `nodeHashjoin.c` / `nodeHash.c`:

1. HJ_NEED_NEW_OUTER invalidates any previous descriptor before pulling the
   child. Native hashing, strict-NULL rejection, main/skew bucket selection
   and future-batch deferral run first.
2. `ExecHashLookup()` calls the serial scanner once to find the first true
   equality match. No match rejects this inner-join probe. Success retains
   only the first-match iterator and enters HJ_SCAN_BUCKET.
3. `ExecHashExpand()` consumes the retained match once without repeating its
   equality test. Later pulls scan from its next chain link using the shared
   `ExecHashScanBucket()` helper, rechecking both hash and equality. The helper
   also serves native serial probing and checks cancellation within a chain.
4. Each returned pair goes through the existing counters, residual joinqual,
   single-match rule, otherqual and projection. Volatile residual effects
   occur once per consumed pair, in native order. Expand does not fetch or
   prequalify the remaining duplicates at Lookup time.
5. Exhaustion, the next probe, rescan and end clear borrowed references,
   including query end after LIMIT. Shutdown can also run between forward-only
   cursor FETCHes: it preserves unfinished expansion because native detach
   frees only shared storage and this cursor's private table/probe remain
   live. An assertion before batch transition forbids a live cursor across
   batchCxt reset. Native query-context/error cleanup handles cancellation;
   no separate allocation, resource owner or cleanup callback is introduced.

Native batching, repartition and skew storage remain supported because a
probe is expanded entirely within its resident batch. Only native tuples
and saved hashes spill; a cursor never does. This is immediate decomposition,
not independent scheduling, a new executor node, acyclic planning or a
speedup result. Commands, test evidence and limitations are in TESTING.md.

## Phase 3: independent Lookup and Expand execution

`diamond_independent_lookup_expand` defaults off and acts during planning.
Cached plans retain the selected nodes. The constructor decomposes an already
chosen eligible native HashJoin into adjacent Expand -> Lookup -> probe and
Hash/build inputs, after native reference fixing in `setrefs.c`. There are no
new Paths, scheduling policy, join-order search or calibrated costs. Existing
chosen costs are retained as display metadata; Lookup's rows are an upper
bound from its probe input, not a new selectivity model.

Eligibility is serial inner joins with strict, simple-column hash keys over
regular heap SeqScans. A fully expanded prior Expand may supply the probe;
the build must remain a direct heap SeqScan. Parallel-mode statements/workers,
subplans, row locking, DML/modifying CTEs, expression keys and other inputs
retain native plans. Simple key lineage is checked through final Expand
projections. The whole-statement DML gate also covers SELECT subqueries.

| Structure/function | Responsibility |
| --- | --- |
| `Lookup` / `LookupState` | Native HashJoin/HashJoinState inheritance; hash metadata plus query-owned owner/generation, per-head context, copied probe and deferred sidecar |
| `Expand` / `ExpandState` | Original join projection/residuals, Lookup plan ID, final-boundary flag; owner, private mutable iterator, borrowed input head, match slot and per-head sidecar context |
| `DiamondDeferredMatch` | Immutable snapshot: query-owned Lookup owner, generation and first-match cursor borrowing its probe/table batch |
| `ExecInitHashJoinState` / `ExecHashJoinFirstMatch` | Reuse native serial hash initialization/build/batching/admission, stopping at the first equality match without residuals or joined-row projection |
| `ExecLookup` | Retire previous generation, find a match, copy the probe into an owned MinimalTuple and copy incoming immutable sidecars before appending its own |
| `ExecExpand` | Bind the owner's snapshot, copy its cursor locally, remove only that owner from the transported sidecar, enumerate/equality-recheck, apply original residuals and projection |
| `create_diamond_lookup_expand` / `find_diamond_lookup_plan` | Conservative physical constructor and owner resolution through a contiguous Lookup/Expand chain |

The copied probe is essential: child Buffer/Virtual slots can change on the
next pull. Equality runs first on the child and later on the MinimalTuple
copy, so its outer deformation is dynamic; admission hashing still uses the
native child specialization. Expand's inner slot is also dynamic because its
build owner is not a physical right child. Slot-type assertions remain active.

Sidecar records/list cells belong to the current producer's head context.
The owner/generation remains in the query context. Each Expand validates the
generation **before** dereferencing the borrowed probe or hash tuple. Next
head, rescan and end invalidate before clearing tuples/resetting contexts or
native storage. Each Expand uses its own cursor: another relation's expansion
may replicate a head and restart its still-deferred immutable match set,
preserving duplicate multiplicities. Expression contexts reset per candidate;
shutdown preserves live state between NO SCROLL FETCHes. PostgreSQL query and
resource-owner cleanup handles cancellation/error unwinding.

Only Lookup/Expand transport sidecars. `final=true` requires no remaining
deferred relations before ordinary SQL tuple consumers (Sort, Material,
Aggregate, native joins, etc.). There are no runtime pointers in Plans or SQL
Datums. Hash build input is fully expanded; **nested deferred build storage
is not implemented**. Thus general chain/GYO plans are not yet supported.

Production closes each pair, so native hash batching/skew and parameterized
rebuilds remain valid. An internally assembled deferred-head stack requires
its consuming Lookup's table to stay single-batch: native batch files contain
SQL tuples, not sidecars. A post-build guard rejects multiple batches before
any output. It cannot silently restart after emitting rows. These guards are
an execution boundary, not the later spill-aware optimization extension.

Infrastructure audit: generated copy/output/read support derives from the
node headers, with no generated-file edits. New IDs are unique; original
projection/quals and conservative extParam/allParam sets are preserved.
`SS_finalize_plan` precedes reference fixing, so it never receives new nodes;
no new Param expressions are introduced. PlanState walkers follow generic
left/right children; Init/End/Rescan/Shutdown dispatch and EXPLAIN/deparse are
integrated. Native capability defaults reject backward/mark support. Parallel
planning is gated, initialization checks again, and DSM estimation rejects
these private-sidecar nodes. Both Make and Meson source lists include the node.
Meson execution itself has not been tested.

The existing C regression module assembles real L1 -> L2 -> E1 -> E2 states
without shipping an optimizer policy. Per execution L2 returns 11 heads,
E1 emits 33 pairs and E2 emits 66 rows, compared as a multiset against native
execution. It also exercises copy/read round trips, whole-stack rewind,
actual owner rescan invalidation and pre-output batch rejection. Ordinary SQL
checks cover adjacent pairs and conservative fallbacks. Final results and
commands are maintained in TESTING.md; no paper speedup/bound claim follows.
