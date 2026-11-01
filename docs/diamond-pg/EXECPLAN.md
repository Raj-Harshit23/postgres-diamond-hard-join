# Diamond-PG continuation plan

## Final bounded Section 4 checkpoint (2026-11-01)

The complete join relation now receives an independent Diamond candidate after
standard, GEQO, or hook join search. For every root, the planner memo enumerates
legal GYO removals and keys states by the minimized L&E parent forest rather
than only the relation set. Complete states are compared with full physical
cost, and only single-batch fully expanded paths enter `add_path`.

Final assertion/debug compilation, focused `diamond_hashjoin` 1/1 (37.049s),
and core 240/240 pass. The new GEQO oracle executes a four-table chain with
three Lookup/Expand pairs and matches the native bag. The external optimized
build and full TPC-H SF1 rerun completed: 22/22 bags match, no errors/timeouts,
and zero Diamond selections. The per-query geometric native/automatic ratio is
1.00107; total medians are skewed by Q18 runtime variance despite an identical
plan structure. Raw plans and the updated CSV preserve the evidence.

Final-commit paper microbenchmark results are saved: N=1000
212.040/1.055ms native/automatic (200.99x), N=5000 2625.554/3.923ms
(669.27x), and N=50000 automatic 30.785ms with native timing out at 120s.
All comparable bags match; every automatic plan selected one Diamond region
and executed two Lookups/two Expands without fallback or temp I/O.

Remaining optimizer scope is explicit: connected partial regions, boundary-
driven early Expand, cyclic Expand3, and deferred spilling. The admitted
bounded acyclic two-phase region is integrated and correct.

## Active cost-selection validation (2026-11-01)

Post-fix TPC-H SF1 returns matching bags for 22/22 queries but automatically
selects no Diamond region. At 64MiB work_mem the planner generates candidates
for Q3/Q8/Q9/Q10. A new off-by-default diagnostic force preserves eligibility
and model costs. Assertion/debug forced comparisons are correct: Q3 is 1.048x
faster, while Q8/Q9/Q10 are respectively 7.59x, 2.79x and 1.76x slower than
native. Do not globally discount Diamond costs. Next, confirm Q3 on the
optimized build and calibrate only the overcharged work its plan demonstrates.

Updated 2026-10-31. Work only on `diamond-pg-cloud`; original `diamond-pg`
remains at `9ee4d297b3`. PostgreSQL base remains
`6296e78c3d2c7406bb450c5ae477b2fef58f155e`. Preserve all changes. The user now authorizes coherent validated commits and
normal pushes on diamond-pg-cloud, author AND committer exactly
`harshit <harshitraj969@gmail.com>`, no co-author attribution. No force-push,
PR, history rewriting, environment publication or configuration replay.
The user authorized Phase 3 completion, Phase 4, Phase 5 and relevant Phase 8,
superseding the old Phase 3-only instruction. One platform-delegated worker is
authorized and owns editing; do not start any duplicate coding attempt.

## Completed correction: independent inputs and native fallback

Published checkpoints are441f907cf6 (tested bounded source/diagnosis) and
76a429556e (versioned per-query results). Remote diamond-pg-cloud SHA was
verified76a429556e4ba9f546cdf2b89da538c7c35891be; both commits have author AND
committer harshit <harshitraj969@gmail.com>. Original diamond-pg unchanged.

The user requests proper paper Section4 integration, explicitly excluding GEQO,
and unattended continuation through implementation/tests/optimized evaluation.
First increment now edits allpaths.c,createplan.c,nodeLookupExpand.c and
pathnodes.h: independently construct legal serial scans and an ordinary serial
hash fallback from the normalized EC shape; consider only audited, unparameterized
native heap/index/index-only/bitmap inputs. Native indexed/parallel competitors
remain external, no Gather in the private wrapper, no mutable/boundary/parallel
guard removed and no cost constants lowered. Assertion/header-dependent build
passed (`.work/build/sec4-step1-build.log`). Focused1/1 in17.133s and full core240/240 now pass, with seven new reviewed
indexed/bitmap, differential and copied/rewound indexed-fallback positive
oracles. Logs `.work/build/sec4-step1-{build,focused,core,indent}.log`.
This coherent correction is published as `2cb5c37062`.
No new benchmark coverage or performance change is claimed by that correction.

The bounded acyclic milestone is complete: every admitted star, chain or
branching region receives a two-phase GYO Lookup/Expand alternative and an
independently valid serial fallback. The root-aware minimized-expression memo
now replaces the greedy schedule and
also runs after GEQO. Connected partial-region states and early Expand remain
future search-space work; they are not required for correctness or completeness
inside the documented admitted two-phase region.

## Completed follow-up: zero-coverage diagnosis

All135 queries traced with EXPLAIN (no execution) in isolated physical backup
`.work/diagnosis/data`; diagnostic server55436 stopped. Temporary allpaths/
costsize DEBUG instrumentation restored byte-for-byte from saved originals;
normal debug build/install restored. Main benchmark source/hash and optimized
server55434 are unchanged. No functional correction or performance rerun was
needed; no extra coding agent, commit, push or publication.

Actual first exits: TPC-H2single-table,1parent-root-only (Q13),7two-relation,
6SubLinks,5missing native skeleton,1real candidate competition (Q3). JOB93
missing native skeleton,20GEQO. Of93 JOB skeleton exits,90 pass later semantic/
EC/GYO checks:21all-root predicted batching,69counterfactual costed trees;3
stop on missing SeqScan path (15a/b/c alias at/aka_title, only IndexPaths).
All69 cheapest counterfactual costs exceed native references (4.83–504.60x,
median85.48). These are not admitted candidates or actual cost losses. Q3
candidate355,914.23/startup52,541.97 is dominated by a native NestLoop path
278,887.56/startup5,845.31; native HashPath total257,409.81 also cheaper.
All135 diagnostic plan shapes match the original benchmark. Findings identify
an explicit serial-survivor integration limitation; not a semantic defect or
proof of cost miscalibration. Broader audited serial native fallback/independent
scan construction is future work, retaining all correctness/native cost gates.

Evidence: `.work/diagnosis/{per-query.csv,report.json,trace-summary.json}`,
per-query plans/logs, detailed path logs, temporary patch and exact source
backup/checksums, restored build/install and stop logs. TESTING.md gives full
counts, examples and limitations. Do not reapply one-use instrumentation to
new changes without reviewing/restoring its saved originals.

## Implemented, with conservative eligibility

- Retained nested-build execution: private batch-owned address index, owned
  probe copies, independent storage epochs, actual allocation/batch guards,
  nested owner resolution and per-build-tuple sidecar propagation.
- `DiamondPath` represents a fully expanded native alternative. PostgreSQL
  EquivalenceClasses form hyperedges; GYO ear removal tries each possible
  root, handles equality-redundant triangles and rejects genuine cycles.
- Canonical native reference fixing precedes factorization into independent
  Lookup/Expand chains and nested builds. Final projection is fused into the
  last fully expanded Expand. Hash sizing uses the filtered head estimate.
- `cost_diamond_path` charges scans, hash build/probe, owned probe/descriptor
  copying, preorder enumeration, projections and live memory. It uses native
  join selectivity with dummy SpecialJoinInfo. Predicted batching remains
  native. These are heuristic estimates, not measured speedup promises.
- `DiamondJoin` retains a serial native branch. Actual retained resource
  rejection can choose it only before the first output; cancellation/SQL/OOM
  errors are not caught. Its internal signal has a checked function origin.
- Off-by-default `diamond_acyclic` adds cost competitors rather than forcing
  selection. Ordinary native methods/indexes/parallel alternatives remain.

Current automatic scope: a complete 3–16-relation region of plain heap
relations, strict same-type simple-column EC equalities, immutable base quals,
no live outer/special/lateral/security/locking/DML/subplan boundary, and a
retained serial heap/hash fallback skeleton. Candidate generation follows
standard, GEQO, or hook join search; unsupported expressions, cross residuals,
and other input methods stay native. No Expand3, eager aggregation, or
outer-join reordering is implemented.

## Validation checkpoint

Current-source assertion/debug/header-dependent build completed at06:19UTC.
Focused Diamond 1/1 and full core 240/240 passed at06:20UTC, after the final
filtered-head sizing, actual-memory fallback and cache checks. Logs:
`.work/build/acyclic-{clean,build,targeted,check}.log`. No build/test process
is active during benchmark timing.

Reviewed positive/differential oracles cover actual selected stars, nested
four-relation chains, branching, NULL/duplicates, text/multi-key joins,
projection/base filters, redundant equality (ordered diagnostic), generated
copy/read, whole-plan rewind, native resource fallback before output, generic
prepared parameters, forward cursors, cancellation after a live first head,
and recovery. Genuine cycle/expression/cross-residual and cheap-plan native
fallbacks are checked. The new low-memory fixture plans at16 MiB, executes at
64 KiB and verifies its3.2m-row native fallback bag; its reviewed oracle is true.
Expected-output additions are reviewed before accepting them.

Annotated assertion/debug/USE_VALGRIND focused SQL regression passed 1/1 in
819.154s. The extra actually selected partial-cursor close/recovery oracle
passed. Diagnostic server55435 is stopped; no build/test/benchmark job remains
active. No invalid read/write/free or conditional-jump report was found.
Unsuppressed reports remain: native relcache/WAL uninitialized writes and
startup/PLpgSQL scanner allocations. Main SQL backend:4,003 definitely-lost
bytes/459blocks,106errors/74contexts, suppressed0; reviewed leak records have
no new executor frames. This is not a clean Valgrind pass. Strict initial
error-exitcode95 stopped before SQL; default nonfatal behavior subsequently
allowed full annotated SQL while retaining checks/reports. Matching signed
glibc symbols/debuglink search stayed verified. Evidence:
`.work/build-memcheck/{focused,early-close,stop}.log`, `valgrind.*.log`,
`report.json`; current-source build/install logs are there too.

## Data and completed evaluation

- Full TPC-H SF1:8tables, realistic PK/FK indexes, default qgen substitutions
  with only PostgreSQL interval/LIMIT ports. Full standard May2013 JOB:
  all21tables, supplied primary/FK indexes; exact COPY counts in manifest and
  `.work/job-load.log`. Both databases VACUUM ANALYZE completed.
- Final optimized no-assert build/install are `.work/build-opt`/`install-opt`.
  Preserved `.work/data` server55434, Unix socket `.work/s`, TCP disabled;
  1GiB shared buffers,64MiB work_mem,hash_mem_multiplier2,jit off, normal
  native methods/indexes, gather workers2. Same binary/settings for off/on.
- Runner first verifies bags/warmups then3 interleaved EXPLAIN ANALYZE BUFFERS
  JSON medians;30s TPC-H/JOB and120s paper query caps. Failed peer remains
  visible; no paired speedup is reported without both bags/three samples.
  Reviewable runner `scripts/diamond-pg/benchmark.py`; measured predecessor
  `.work/benchmark-auto.py`; manifest/source patch and raw logs retained.
- TPC-H22/22 matching bags, no errors/timeouts,101.17s wall time; Diamond0/22.
  Sum query medians12.442794s native/12.476752s automatic (+0.27%); geometric
  native/automatic1.00475. These native outcomes establish no Diamond gain.
- JOB113/113 matching bags, no errors/timeouts,1125.80s wall time; Diamond0/113.
  Sum medians137.344067s native/136.914269s automatic (-0.31%); geometric
  native/automatic0.997295. No Diamond gain established.
- Paper Section5.1 exact X/Y/Z formula is reproduced atN50,000, plus explicitly
  scaledN1000/5000. Expected sole tuple(1,1,1,1). Scaled paired medians:
  128.031/0.583ms (219.61x),2254.423/2.484ms (907.58x), native/automatic.
  Each actually selects 1wrapper/executes 2Lookup+2Expand without fallback.
  Native intermediates997,001/24,985,001 rows; Lookup shrinks998/4,998 heads
  to one. FullN50,000 automatic 23.877ms, expected tuple,2Lookup+2Expand,
  no fallback; native 120s timeout during bag check, so no paired ratio. Its
  automatic samples have no native interleaving peer after that timeout.
- Combined suite wall time 1358.53s (22m38.53s). Per-query CSV,report.json and
  suite summary/raw plans/results are under `.work/bench-auto-opt/`. These
  measure the paper's formula on PostgreSQL, not Umbra absolute-number results.
  Failed native full-paper actual memory/temp-I/O is unavailable; successful
  plans retain observed rows/memory/batches/temp blocks. No heavy memory/build
  job overlapped timing.
- `.work/remote-batch.exit`0 and `.work/tpch-baseline/summary.json` refer to
  earlier existing-adjacent diagnostics, not this final automatic evaluation.

## Review handoff and remaining limits

The authorized bounded implementation, correctness validation, optimized suite
attempts and feasible unsuppressed memory diagnostic are finished. All five
project docs and the developer GUC manual are current. Complete diff reviewed;
native pgindent check and git diff --check pass. Current source diff hash still
matches the benchmark manifest; no source change occurred during/after timing.
Reviewable benchmark runner functions agree with the measured predecessor
apart from path/metadata/docstrings; both compile.

No active coding/test/benchmark process remains. Preserved optimized server
on55434 is available with the benchmark databases; memory server55435 is
stopped. No cluster or user branch was overwritten; original diamond-pg is
still 9ee4d297b3. This bounded implementation/diagnosis is the validated checkpoint being
committed on diamond-pg-cloud. Remote publication must be verified normally.

Material limits: narrow complete-region/plain-heap/serial fallback eligibility;
heuristic costs and bounded each-root scheduling; no deferred spill, Expand3,
eager aggregation or outer reordering. TPC-H/JOB show zero Diamond coverage;
only exact/scaled paper data demonstrates gains. Native full-paper120s timeout
means no paired full-size ratio. Memory diagnostics retain native findings;
no clean sanitizer/Valgrind pass is claimed. Future work may broaden coverage
and calibrate costs, but should not weaken ownership/semantics guards.

Validated checkpoint title:
`diamond-pg: plan and execute bounded acyclic lookup/expand joins`.

All dependencies, builds, clusters, paper, datasets and raw outputs stay in
ignored `scripts/diamond-pg/.work/`. Local verified Debian packages were
explicitly authorized after system installation proved unavailable. A standalone
CLI worker failed before coding (proxy then401 auth); do not retry login or
read credentials. Platform delegation is active, but cloud/agent survival after
closing a tab or publishing has no guarantee. This file is the completed restart checkpoint.
