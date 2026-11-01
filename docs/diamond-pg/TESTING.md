# Building and testing Diamond-PG

## Demo and portable benchmark entry points

Install normal PostgreSQL build dependencies once (Ubuntu/Debian example), then
build and run from the repository root. Password entry stays in this terminal.

```sh
sudo apt install build-essential flex bison libreadline-dev zlib1g-dev \
  libicu-dev pkg-config python3
git switch diamond-pg-cloud
git pull --ff-only origin diamond-pg-cloud
```

The paper microbenchmark is self-contained: its script builds an optimized
server, creates a private cluster/database, generates all three scales, compares
native and automatic execution, saves raw JSON, and stops the server.

```sh
scripts/diamond-pg/run-paper-microbenchmark.sh
```

For the live professor demo, N=5000 finishes quickly and prints both readable
EXPLAIN ANALYZE plans after the measured comparison:

```sh
DIAMOND_PG_QUERY=n05000 DIAMOND_PG_DEMO=1 \
  scripts/diamond-pg/run-paper-microbenchmark.sh
```

The query is `X(a,b) JOIN Y(b,c) JOIN Z(c,d)`. At N=5000, X and Z have 5,001
rows and Y has 9,996. Native execution expands the many `b=2` matches first,
forming 24,985,001 rows that the Z join later discards. Diamond scans Y as the
head, uses Lookup into X to retain 4,998 possible heads, then Lookup into Z to
retain one. The two iterators are expanded only after filtering, producing the
same sole `(1,1,1,1)` row. This changes the dangerous intermediate from
quadratic work to approximately linear hash build/probe work.

TPC-H and JOB use their standard multi-GB datasets and query sets from the
portable benchmark workspace; the scripts never download them implicitly.
Point both runners at that workspace (the Data-disk path on this machine is
shown below):

```sh
export DIAMOND_PG_WORK=/media/harshit/data/2026-11-01/cloud-did-its-work-on-a/repository/scripts/diamond-pg/.work
scripts/diamond-pg/run-tpch-benchmark.sh

# First JOB run only: load the 21 already-unpacked May 2013 CSVs and indexes.
DIAMOND_PG_PREPARE=1 scripts/diamond-pg/run-job-benchmark.sh
# Later JOB reruns use the loaded database directly.
scripts/diamond-pg/run-job-benchmark.sh
```

Use `DIAMOND_PG_QUERY=03` or `DIAMOND_PG_QUERY=1a` before the corresponding
TPC-H/JOB command for a quick single-query check. After the first build,
`DIAMOND_PG_SKIP_BUILD=1` skips recompilation when the source has not changed.
On a slower laptop, `DIAMOND_PG_TIMEOUT=120` raises the per-query TPC-H/JOB
limit from 30 to 120 seconds. The live output reports correctness, both
medians, native/automatic speedup, selections, errors, and a suite geometric
ratio. Each script checks query counts and nonempty databases, records the Git
commit/server identity, saves results under
`$DIAMOND_PG_WORK/bench-final-<suite>/`, and stops its server even on failure.

Raw plans, result bags and JSON summaries stay in ignored `.work` storage.
Each completed query also updates its existing row in the tracked compact CSV,
while preserving planner-diagnosis columns. Review that diff, then commit only
the compact results and any accurate documentation:

```sh
git status --short
git add scripts/diamond-pg docs/diamond-pg
git commit -m "diamond-pg: record reviewed benchmark results"
git push origin diamond-pg-cloud
```

## Final minimized-expression memo and GEQO validation (2026-11-01)

From the repository root, the final source was formatted and validated with:

```sh
src/tools/pgindent/pgindent \
  --indent=scripts/diamond-pg/.work/build/src/tools/pg_bsd_indent/pg_bsd_indent \
  src/backend/optimizer/path/allpaths.c
git diff --check
make -C scripts/diamond-pg/.work/build -j4
make -C scripts/diamond-pg/.work/build/src/test/regress \
  check-tests TESTS=diamond_hashjoin
make -C scripts/diamond-pg/.work/build check
```

Compilation passed, focused `diamond_hashjoin` passed 1/1 in 37.049s, and all
240 core regressions passed; the Diamond test took 44.292s in the core run. The
new oracle sets `geqo_threshold=3`, forces only an already eligible candidate,
executes a four-relation acyclic chain with three Lookup/Expand pairs, and
compares both result bags with `EXCEPT ALL`.

During development, ASan identified a planner use-after-free after `add_path`
discarded a candidate; immutable template base paths now remain the source for
later roots. Full-cost singleton-state comparison restored the previously
selected chain. The final assertion runs above cover both fixes.

The optimized build was rebuilt from final commit `51f18a8781` on the Data
disk. The paper acyclic runner used identical settings, one bag-check warmup,
and three interleaved EXPLAIN ANALYZE repetitions. N=1000 measured
212.040/1.055ms native/automatic (200.99x); N=5000 measured
2625.554/3.923ms (669.27x). Both bags match. N=50000 automatic measured
30.785ms; native exceeded the 120s limit, so no paired ratio is reported. Every
automatic plan selected one Diamond region, executed two Lookups/two Expands,
used no runtime fallback, and wrote no temp blocks. Raw JSON and the live log
are in the Data-disk `.work/bench-section4-paper-final/` paths; compact results
are versioned in `benchmark-results.csv`.

The final-source TPC-H SF1 rerun completed all 22 queries in 263.23s with
matching bags, no errors/timeouts, and zero Diamond selections. Sum of medians
was 18.083764s native and 19.375675s automatic; Q18 runtime variance accounts
for more than the difference, while the per-query geometric native/automatic
ratio is 1.00107. Paired operator/condition structures are identical after
excluding runtime counters. This establishes correctness and neutral TPC-H
behavior, not a Diamond speedup. JOB still requires loading the copied CSVs.

## Forced eligible-candidate diagnosis (2026-11-01)

The post-fix optimized automatic run returned equal bags for all 22 TPC-H SF1
queries and selected zero Diamond regions. Planner DEBUG1 at 64MiB identified
four candidates: Q3 355075.52 versus native 257390.71; Q8 best 415499.65 versus
77614.75; Q9 best 446849.74 versus 37250.59; Q10 best 274090.74 versus
194299.97. The remaining queries stop on relation count, subquery/boundary,
cycle or other documented eligibility gates.

`diamond_acyclic_force=on` was then tested on the assertion/debug build without
bypassing eligibility. All four forced bags match native. Median native/forced
milliseconds were Q3 1666.220/1589.678, Q8 181.826/1380.026, Q9
6991.104/19493.415 and Q10 1451.831/2555.121. Thus Q3 is a possible cost-model
false negative; the other three rejections are correct. Focused 1/1 and full
core 240/240 pass with the force/EXPLAIN regression. Raw evidence is under
`.work/bench-force-debug*` and `.work/build-cloud/force-{build,focused,core}.log`.

## Live reproducible TPC-H run

The local SF1 database is `scripts/diamond-pg/.work/bench-data`; generated
tables, cluster and raw output remain ignored. From the repository root, the
following block creates the optimized install once, starts a private server on
a Linux abstract socket, prints one correctness/selection/timing line per query,
saves the same progress, and always stops the server:

```sh
diamond_src="$PWD"
diamond_work="$diamond_src/scripts/diamond-pg/.work"
diamond_build="$diamond_work/build-opt"
diamond_install="$diamond_work/install-opt"
if [ ! -x "$diamond_install/bin/postgres" ]; then
  mkdir -p "$diamond_build"
  (
    cd "$diamond_build"
    "$diamond_src/configure" --prefix="$diamond_install" --enable-depend
    make -j"$(nproc)"
    make install
  )
fi
mkdir -p "$diamond_work/bench-auto-opt"
(
  set -e
  "$diamond_install/bin/pg_ctl" -D "$diamond_work/bench-data" \
    -l "$diamond_work/bench-server.log" \
    -o "-k @diamond-pg-bench -p 55434 -c listen_addresses='' \
        -c shared_buffers=1GB -c work_mem=64MB \
        -c hash_mem_multiplier=2 -c jit=off" -w start
  trap '"$diamond_install/bin/pg_ctl" -D "$diamond_work/bench-data" -m fast -w stop' EXIT
  PYTHONUNBUFFERED=1 \
  DIAMOND_PG_INSTALL="$diamond_install" \
  DIAMOND_PG_SOCKET=@diamond-pg-bench \
  python3 -u scripts/diamond-pg/benchmark.py tpch 2>&1 | \
    tee "$diamond_work/bench-auto-opt/tpch-live.log"
)
```

Reruns use the same block; the optimized build is skipped when already
installed. Machine-readable per-query plans and the checkpointed summary are
under `.work/bench-auto-opt/tpch-sf1/`.

## 2026-11-01 local cloud-branch verification

The fetched `diamond-pg-cloud` head `2cb5c37062` was configured and rebuilt in
`scripts/diamond-pg/.work/build-cloud` with `--enable-cassert --enable-debug
--enable-depend`. Compilation passed, the focused `diamond_hashjoin` regression
passed 1/1, and the full core suite passed 240/240. Logs are `configure.log`,
`build.log`, `focused.log` and `core.log` in that ignored build directory.

The bounded implementation/diagnosis was committed as `441f907cf6`; benchmark
evidence followed in `76a429556e`, and independent scan/fallback construction
in `2cb5c37062`. General partial-region and early-Expand search remains future
work and is not implied by the validation results below.

Versioned per-query results are
[`benchmark-results.csv`](../../scripts/diamond-pg/benchmark-results.csv):
all22TPC-H,113JOB and3paper scales, plus observed planner-gate diagnosis for
each main query. Raw results/plans/logs/datasets remain ignored. Source is
checkpoint441f907cf6 (same tested source diff SHA25671881cb2b7a0f50d29ea8e6de902984c4aafddf0b6b474dfb0d01da27cfca6d4
against9ee4d297b3). Optimized default-O2 build, assertions off, GCC14.2,
AMD EPYC9V74/KVM with5exposed vCPU and33GiB RAM. Full TPC-H SF1 default dbgen/
qgen seed/substitutions, generator32f1c1b92d1664dba542e927d23d86ffa57aa253;
standard May2013 JOB queries a39603662e023e449cb2121997a5034df9e02ebf,
all21tables/standard PK+FK indexes. Exact/scaled paper data is deterministic.
Settings, generation SQL, warmup/three-repeat/interleaving/median method and
30s/120s caps are detailed below. Blank native full-paper fields mean timeout,
not zero. `counterfactual_min_cost`/`native_join_reference_cost` are diagnostic
planner cost units with candidate admission disabled, not execution times or
actual cost losses. Indexed/parallel native alternatives remained enabled.

## First correction increment validation

After removing the path-survivor prerequisite, the assertion/debug/header-
dependent build passes. Updated focused1/1 passes in17.133s; full core240/240
passes. Seven new reviewed oracles are true: normal-cost selected indexed
build/probe, IndexOnlyScan probe, BitmapHeapScan probe, indexed differential
bags and copied/rewound indexed native resource fallback. No planner method,
index or parallel option is disabled to select these positive cases. The C
fallback fixture changes only physical sizing after actual cost selection,
then verifies its160,000-row native bag and rescan. Existing tests are unchanged.
Logs: `.work/build/sec4-step1-{build,focused,core,indent}.log`; the first
new-expectation review diff contained only87 added lines, all positive oracles.
The standalone indexed build example is
`.work/diagnosis/sec4-step1-index.log`. These are correctness tests, not final
performance evaluation. Published benchmark-results.csv remains source 441f907cf6. At this first-
correction checkpoint, Section 4 state/boundary work was still active; the
final minimized-expression memo and GEQO validation at the top of this file
supersede that status. Boundary-driven early Expand remains future scope.

## Current automatic integration validation (2026-10-31)

The final current-source assertion/debug/header-dependent build completed,
then focused Diamond 1/1 and full core 240/240 passed at06:20UTC. Evidence:
`scripts/diamond-pg/.work/build/acyclic-{clean,build,targeted,check}.log`.
No expected-output changes were accepted without reviewing the added oracles.

New coverage includes actual cost-selected stars, nested four-relation chains
and branching, duplicate/NULL/text/multi-key bags, projection/base filters,
redundant same-EC triangle (ordered diagnostic), genuine cycle and unsupported
expression/cross-residual native fallback, native winning cheaply, generated
copy/read, full rewind, initial batching and actual allocation rejection,
prepared external parameters and cached plan stability after GUC changes,
forward cursor pause/resume,1ms cancellation after a live head and recovery.
The64 KiB execution-memory fixture plans at16 MiB and verifies the3.2m-row
native-fallback bag with EXCEPT ALL both ways. Raw pointer spill is prohibited.

Use the local dependency activation below, then from the repository root:

```sh
make -C "$diamond_work/build" -j4
make -C "$diamond_work/build/src/test/regress" check-tests TESTS=diamond_hashjoin
make -C "$diamond_work/build" check
```

The optimized build uses the same source with `--enable-depend`, without
assertions/debug, prefix `$diamond_work/install-opt`. Full TPC-H SF1 and
standard May2013 JOB data (all 21 tables, primary/supplied FK indexes) are loaded,
VACUUM ANALYZE completed. Preserved server uses Unix socket `$diamond_work/s`,
port55434,TCP disabled,1 GiB shared buffers,64 MiB work_mem,hash_mem_multiplier2,
jit off and normal native methods/indexes with parallel-gather workers2.
The automatic control is compared off/on; older adjacent controls stay off.

```sh
python3 scripts/diamond-pg/benchmark.py tpch job paper
```

The optimized run completed. The runner first compares result
bags (warmup), then measures three interleaved EXPLAIN ANALYZE BUFFERS JSON
repetitions and medians, recording planning/execution, chosen/executed Diamond,
fallback, rows/loops, hash memory/batches and temp I/O.30s per TPC-H/JOB query,
120s per paper query. Raw plans/results and incremental summaries are under
`.work/bench-auto-opt/`; manifest/source patch are `.work/benchmark-manifest.json`
and `.work/benchmark-source.patch`. TPC-H completed all22 queries in101.17s runner wall time:22 identical bags,
no errors/timeouts, zero selected/executed Diamond regions. Sum of query
execution medians:12.442794s native,12.476752s automatic (+0.27%); geometric
native/automatic ratio 1.00475. Q21 slowed14.6%, Q19 improved5.0%, both native
plans, so these differences do not demonstrate Diamond gains. JOB completed113/113 identical bags, no errors/timeouts,1125.80s wall time.
Zero Diamond selections; sums of medians137.344067s native and136.914269s
automatic; geometric native/automatic ratio0.997295. These native-plan
measurements establish no Diamond speedup. JOB Q1b slowed25.8%; Q23b
had the largest native/automatic ratio1.11445. All405 corresponding native
plan pairs (three repetitions across135 queries) match in operator structure,
conditions, relations/indexes, keys and planned parallel workers; execution
variation cannot establish a Diamond executor gain or regression. Evidence:
`.work/bench-auto-opt/native-plan-shape-review.json`. Paper
Section5.1 exact formula usesN=50,000;N=1,000/5,000 are explicitly scaled runs.
All must return the sole tuple(1,1,1,1). No forced native-method controls are
part of this comparison. Total suite duration and per-query results will be
recorded after completion.

`scripts/diamond-pg/benchmark.py` preserves the runner for review; the current
run uses its identical `.work/benchmark-auto.py` predecessor (only root-path
resolution and the paper timeout description differ). Tables/queries must
already exist. To reproduce the paper data in a fresh `diamond_micro` database,
execute this SQL once, then use the SELECT template for eachN:

```sql
DO $$
DECLARE n integer;
BEGIN
  FOREACH n IN ARRAY ARRAY[1000,5000,50000] LOOP
    EXECUTE format('CREATE TABLE x%s AS SELECT 1::int a,1::int b
      UNION ALL SELECT generate_series(1,%s),2',n,n);
    EXECUTE format('CREATE TABLE y%s AS SELECT 1::int b,1::int c
      UNION ALL SELECT 2,generate_series(4,%s)
      UNION ALL SELECT generate_series(3,%s),3',n,n,n);
    EXECUTE format('CREATE TABLE z%s AS SELECT 1::int c,1::int d
      UNION ALL SELECT 3,generate_series(1,%s)',n,n);
    EXECUTE format('ANALYZE x%s',n);
    EXECUTE format('ANALYZE y%s',n);
    EXECUTE format('ANALYZE z%s',n);
  END LOOP;
END $$;
SELECT x.a,x.b,y.c,z.d FROM x50000 x
 JOIN y50000 y ON x.b=y.b JOIN z50000 z ON y.c=z.c;
```

A source-review check examined generic parameter-only gating quals. Native
planning distributes these as join RestrictInfos, so the existing `joininfo`
eligibility guard keeps the Result/One-Time Filter boundary native. Prepared
paper/star-shaped EXPLAINs confirmed that boundary, and the false paper gate
returned zero rows. Evidence: `.work/gating-review-{before,fixture}.log`.
No source change or benchmark restart was needed.

Earlier checkpoint 441f907cf6 scaled paper measurements (retained for
historical comparison; final-commit results are recorded above):

|N|Native median ms|Automatic median ms|Native/automatic|Executed Lookup/Expand|
|---|---:|---:|---:|---:|
|1,000 (scaled)|128.031|0.583|219.61x|2/2|
|5,000 (scaled)|2254.423|2.484|907.58x|2/2|

Both automatically choose one Diamond wrapper with no runtime fallback.
Native intermediate joins produce997,001 and24,985,001 rows respectively;
Lookup chains reduce998/4,998 heads to one before either Expand. AtN1000,
native hash peak is51,032KiB versus48KiB per Diamond table; atN5000 the
largest native/automatic tables are519/260KiB. These completed runs show
zero temp blocks; full-sizeN50,000 automatic execution completed with 23.877ms median,
2/2 executed Lookup/Expand, no fallback, one expected result, two2466KiB
single-batch hash tables and zero temp blocks. Native exceeded120s during
the result check, so that scale has no paired native median, verified native
bag or numeric speedup ratio; its three automatic repetitions have no
interleaved native peer after the timeout. Total suite wall times: TPC-H101.17s,
JOB1125.80s, paper131.55s; combined1358.53s (22m38.53s). Per-query results
are `.work/bench-auto-opt/per-query.csv`; aggregate summaries are
`.work/bench-auto-opt/report.json` and each suite's `summary.json`. They are PostgreSQL
measurements of the paper's formula, not the paper's absolute-number reproduction.

Annotated assertion/debug Valgrind SQL diagnostics completed: focused 1/1
passed in 819.154s (13m39s), including the final actual-memory fallback and
3.2m-row bag. A separate actually selected forward cursor closed after one of
160,000 rows, then a native count verified recovery. Its EXPLAIN confirms a selected
Diamond wrapper; the cursor closes before draining the remaining matches. Private diagnostic server
on55435 is stopped; the optimized benchmark cluster on55434 is preserved.

No invalid read/write/free or conditional-jump report appears in the diagnostic
logs. Reports remain unsuppressed: native relcache/WAL uninitialized writes,
native PostmasterMain startup allocations, and PL/pgSQL scanner allocations.
The main SQL backend reports4,003 definitely-lost bytes in459 blocks and106
errors from74 contexts, suppressed0. Reviewed leak records originate in
unchanged native startup/scanner functions; none contains the new executor
functions. This is a functional SQL pass under Valgrind, **not a clean memory
pass**. Findings are retained rather than suppressing checks or claiming
success. The earlier strict error-exitcode95 attempt failed before SQL on
startup leaks; default nonfatal Valgrind exit behavior allowed this annotated
SQL run while retaining every report. Matching signed glibc debug symbols and
extra debuglink search resolved loader redirection; verification stayed on.
Evidence: `.work/build-memcheck/{focused,early-close,server,stop}.log`,
`valgrind.*.log` and `report.json`. The early-close reproduction SQL is
`.work/build-memcheck/early-close.sql`. Earlier results below are historical
checkpoints, including resolved dependencies and the adjacent-only baseline.

The annotated memory build adds `-DUSE_VALGRIND` to CPPFLAGS and retains
assertions/debug/header dependencies. Current diagnostic commands (preserved
private `data-memcheck` cluster; never initialize over it) are:

```sh
make -C "$diamond_work/build-memcheck" -j4
make -C "$diamond_work/build-memcheck" install
VALGRIND_LIB="$diamond_work/tools/usr/libexec/valgrind" \
 "$diamond_work/tools/usr/bin/valgrind" \
 --extra-debuginfo-path="$diamond_work/tools/usr/lib/debug" \
 --leak-check=full --show-leak-kinds=definite,indirect,possible \
 --error-limit=no --num-callers=25 \
 --log-file="$diamond_work/build-memcheck/valgrind.%p.log" \
 "$diamond_work/install-memcheck/bin/postgres" \
 -D "$diamond_work/data-memcheck" -k "$diamond_work/s" -p 55435 \
 -c listen_addresses='' >"$diamond_work/build-memcheck/server.log" 2>&1 &
# After the server log reports ready:
PGHOST="$diamond_work/s" PGPORT=55435 \
 make -C "$diamond_work/build-memcheck/src/test/regress" \
 installcheck-tests TESTS=diamond_hashjoin
"$diamond_work/install-memcheck/bin/pg_ctl" \
 -D "$diamond_work/data-memcheck" -m fast -w stop
```

No memory-diagnostic workload overlapped final benchmark timing. Native
`pgindent --check` on touched C/headers passed; `git diff --check` is clean.
The measured and tracked benchmark runner function ASTs agree after excluding
root-path resolution, docstrings and timeout-description metadata; both compile.
Evidence: `.work/build/acyclic-indent-check.log` and
`.work/benchmark-runner-review.log`.

## Why automatic Diamond selection was zero (2026-10-31 follow-up)

Traced all135 benchmark queries with temporary DEBUG-only planner diagnostics
and EXPLAIN without ANALYZE, using a private physical backup of the benchmark
cluster/statistics on socket55436 and identical planner settings. The first
production exit is distinguished from independent analysis behind that exit.
When no retained skeleton existed, diagnostic-only analysis continued with
candidate admission disabled; its costs are counterfactual, not selected plans
or performance measurements. All135 final diagnostic operator trees match the
original automatic benchmark plans. No functional implementation change was
made, and the diagnostic source/binary changes were restored; server55436 is
stopped. Main optimized server55434 and benchmark artifacts are preserved.

|Observed first gate/outcome|TPC-H22|JOB113|
|---|---:|---:|
|Single table: no join search|2 (Q1,Q6)|0|
|Only parent-root/outer-join subquery region|1 (Q13)|0|
|Two-relation complete region, below3-relation minimum|7|0|
|SubLinks boundary|6|0|
|No surviving serial SeqScan/HashPath fallback skeleton|5|93|
|GEQO bypasses standard-search integration|0|20|
|Actual generated candidate loses path competition|1 (Q3)|0|

These are first-exit categories, not mutually exclusive SQL properties. For
example, some two-relation TPC-H queries also have SubLinks/special joins.
GEQO JOB regions have12–17 relations;29a/b/c additionally exceed the16-relation
cap. All JOB winners use indexes;42/113 also use parallel plans. TPC-H winners
use indexes18/22 and parallel plans19/22 (these method counts overlap).

The early fallback gate masks later analysis. Of the five TPC-H skeleton
exits, Q5 fails GYO, Q7 has a cross-relation residual, and Q8/Q9/Q10 pass those
checks. Their cheapest diagnostic memory-eligible costs versus surviving
native join costs are415,558.84/77,724.01,450,686.94/45,855.28, and
273,916.40/194,172.83 respectively. These were never admitted candidates.

Of JOB's93 skeleton exits,90 pass the subsequent semantic/EC/GYO checks;
21 predict batching for every root, and69 have at least one memory-eligible
counterfactual tree. Three others (15a/b/c) stop earlier on path availability:
alias`at` (`aka_title`) has only IndexPaths left, including an unparameterized
IndexScan, no serial SeqScan. This is not a semantic or GYO rejection. Across
those69 diagnostic cost comparisons, cheapest Diamond/native cost ratios are
4.83–504.60, median85.48; none is below the surviving native reference. Examples:
JOB1a251,763.56 versus19,540.16 (12.88x),15d858,840.89 versus177,988.62 (4.83x),
6c1,909,184.40 versus3,783.60 (504.60x). Do not describe any of these as actual
planner cost losses: the production gate exits before creating a candidate.

TPC-H Q3 is the sole actual generated candidate: total355,914.23,
startup52,541.97. The serial native HashPath costs257,409.81 overall; a native
NestLoop path costs278,887.56 with startup5,845.31, dominating the candidate
in both startup and total cost, and `add_path` removes it. Other two GYO roots
predict a two-batch build of the filtered3,259,996-row lineitem input at the
128MiB hash allowance. Predicted batching is separate from cost competition.
The final winning plan uses native parallel/index alternatives.

Conclusion: zero coverage is mostly a conservative integration/path-survivor
limitation, not evidence that all135 queries were costed and Diamond lost, nor
that the operators cannot help. The documented complete-region, parent-root,
GEQO and retained skeleton restrictions are working as implemented. Costs
remain heuristic; this trace does not establish miscalibration or a semantic
execution defect. Even relaxing the skeleton gate alone would not make these
counterfactual trees cheapest under the current model. No scope broadening,
forced choices or performance reruns were made to manufacture coverage.

A future integration improvement should preserve an independently valid,
fully expanded serial native fallback (including audited indexed/NestLoop/
Merge inputs), rather than depend on a pure heap/hash survivor after pruning;
construct required legal scan alternatives independently of the pruned base
pathlist. Preserve parameter/security/lifetime guards and native competition,
and add indexed-fallback/rescan/resource tests before enabling that wider scope.

Evidence under `.work/diagnosis/`: `per-query.csv`, `report.json`,
`trace-summary.json`, per-query JSON/logs, detailed15a/b/c path logs,
`temporary-instrumentation.patch`, original source bytes/checksums and restored
build/install/stop logs. `.work/diagnosis/trace.py` and `instrument.py` record
the procedure; instrument.py is one-use and must not overwrite saved originals.
Reproduction requires a fresh backup/temporary instrumentation; do not run it
against source containing different uncommitted changes without reviewing it.

## Retained nested-build validation (2026-10-31)

After exec-state layout changes, `make -C "$diamond_work/build" clean` and
`make -C "$diamond_work/build" -j4` with the existing header-dependent
assertion/debug configuration passed. The first compile diagnosed the base's
two-argument `heap_copy_minimal_tuple(tuple, extra)` API and a missing fixture
makefuncs include; corrected without removing assertions. Reviewed the new
expected-output diff before accepting it: 66-row EXCEPT ALL oracle true,
whole-plan rewind performed, owner rescan rejected, initial multi-batch
rejected, intentionally underestimated64 KiB storage hit the actual allocation
limit, and a following fresh nested run returned66. Existing expectations
were unchanged outside the added fixture.

`make -C "$diamond_work/build/src/test/regress" check-tests
TESTS=diamond_hashjoin` passed 1/1; `make -C "$diamond_work/build" check`
passed all240. Evidence: `.work/build/nested-{clean,build,targeted,check}.log`.
No new sanitizer/automatic-planner/optimized benchmark pass is claimed.


## Cloud baseline recovery and remote batch (2026-10-31)

The later user reply authorized local verified Debian packages after the
system-install failure below. Extracted matching build/runtime packages under
`scripts/diamond-pg/.work/tools`: bison, flex, m4, libicu-dev/libicu76,
libreadline-dev/libreadline8t64, libncurses-dev/libtinfo6. apt downloads used
signature-verified Debian trixie metadata; TLS and package checks stayed on.
An initial link failure selected static ICU because runtime symlink targets
were absent. Adding matching runtime packages fixed it; no source change.

For this checkout, set `diamond_work="$PWD/scripts/diamond-pg/.work"` and:

```sh
export PATH="$diamond_work/tools/usr/bin:$diamond_work/install/bin:$PATH"
export BISON_PKGDATADIR="$diamond_work/tools/usr/share/bison"
export M4="$diamond_work/tools/usr/bin/m4"
export LD_LIBRARY_PATH="$diamond_work/tools/usr/lib/x86_64-linux-gnu"
export PKG_CONFIG_LIBDIR="$diamond_work/tools/usr/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$diamond_work/tools"
export CPPFLAGS="-I$diamond_work/tools/usr/include"
export LDFLAGS="-L$diamond_work/tools/usr/lib/x86_64-linux-gnu"
export TMPDIR="$diamond_work/build/scratch"
export PG_REGRESS_SOCK_DIR="$diamond_work/s"
```

Section 2 configuration with these exports and `--enable-depend` passed.
`make -j4`, `make -C src/test/regress check-tests TESTS=diamond_hashjoin`,
`make check`, and `make install` passed. Targeted: 1/1; core: **240/240**.
Evidence in `.work/build`: `configure.log`, `build.log`,
`baseline-targeted.log`, `baseline-check.log`, `baseline-install.log`.
These are fresh existing-Phase-3 checks on `9ee4d297b3`, not new optimizer tests.

TPC-H source at `.work/tpch-dbgen`, revision
`32f1c1b92d1664dba542e927d23d86ffa57aa253`, built with `make -j4 MACHINE=LINUX
DATABASE=ORACLE WORKLOAD=TPCH CC=gcc`. `DSS_CONFIG="$PWD"
DSS_PATH="$PWD/../tpch-sf1" ./dbgen -s 1` generated SF1. All eight tables
loaded, with realistic PK/FK indexes; `.work/tpch-load.log` records counts.
Queries use qgen defaults (`DSS_QUERY=queries ./qgen -d -s 1 N`), porting only
Oracle rownum output to LIMIT and interval day(3) to PostgreSQL spelling.

`.work/tpch-baseline.py` compares native against CURRENT ADJACENT Diamond:
result bags first (warmup), then three alternating off/on repetitions,
EXPLAIN ANALYZE BUFFERS JSON, medians, planning time and actual Diamond node
coverage; 30s statement timeout, jit off, native indexes/planner choices kept.
Assertion build; these are diagnostic results, not final optimized evaluation.
Publication interrupted the first run after 11 queries. A detached batch is
rerunning all 22; inspect `.work/remote-batch.log`, `.work/remote-batch.exit`
and `.work/tpch-baseline/summary.json` before claiming completion. Earlier
parser-failed outputs are retained separately and are not timings.
JOB queries are at `.work/job`, revision
`a39603662e023e449cb2121997a5034df9e02ebf`; batch downloads the standard
May2013 archive from `https://event.cwi.nl/da/job/imdb.tgz` (1,263,193,115
compressed bytes). Dataset download is not loaded/executed JOB evaluation.


## Cloud attempt (2026-10-31; not a validation pass)

On Debian 13, uid 1000, system Bison/Flex/m4 and ICU/readline headers are absent.
There is no sudo/doas. `apt-get install -y bison flex m4 libicu-dev
libreadline-dev`, through the execution tool's supported escalation, exited
100: permission denied on `/var/lib/dpkg/lock-frontend`. An administrator must
install section 1's packages (using root apt-get on this machine).

From `scripts/diamond-pg/.work/build`, executed:

```sh
/workspace/postgres-diamond-hard-join/configure \
  --prefix=/workspace/postgres-diamond-hard-join/scripts/diamond-pg/.work/install \
  --enable-cassert --enable-debug --enable-depend > configure.log 2>&1
```

Exited 1: ICU pkg-config dependencies not found. Compiler probes passed;
compilation, Diamond tests, sanitizer tests and benchmarks have not run.
The log is ignored under the project `.work` path. No prior laptop results or
earlier master-only 239-test onboarding results count as this branch's fresh
validation. Do not use earlier workspace-local extracted build dependencies:
the current request requires system-installed tools. RAM is 33 GiB and disk
had about 59 GiB free at inspection; no benchmark data has been loaded.


Updated 2026-10-25. Baseline: PostgreSQL 20devel,
`6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
Use the native build tools below. Staging or committing is **not** required
before building/testing: both use the current working tree. Phase 2 is
committed as `c169183521`; bounded Phase 3 is committed as `0aa87a8624`.

## 1. System dependencies (Ubuntu 24.04)

Run in your terminal so sudo prompts privately:

```sh
sudo apt-get update
sudo apt-get install -y build-essential bison flex libicu-dev \
  libreadline-dev zlib1g-dev pkg-config perl python3
```

The user completed installation on 2026-10-19. Verified versions: GCC 13.3,
Bison 3.8.2, Flex 2.6.4, m4 1.4.19, ICU 74.2, readline 8.2,
zlib 1.3, pkg-config 1.8.1, Python 3.12.3. These packages support the
current default configuration; optional features such as LLVM/SSL and
check-world prerequisites are not included in this baseline.

## 2. Configure and compile

From the repository root, run these commands in one shell. All generated
files stay in the ignored `.work` directory; no external temporary-prefix
packages or alternate setup scripts are needed.

```sh
diamond_src="$PWD"
diamond_work="$diamond_src/scripts/diamond-pg/.work"
diamond_build="$diamond_work/build"
diamond_install="$diamond_work/install"
mkdir -p "$diamond_build/scratch" "$diamond_work/s"
chmod 700 "$diamond_work/s"
export TMPDIR="$diamond_build/scratch"
export PG_REGRESS_SOCK_DIR="$diamond_work/s"
cd "$diamond_build"
"$diamond_src/configure" --prefix="$diamond_install" \
  --enable-cassert --enable-debug --enable-depend > configure.log 2>&1
make -j4 > build.log 2>&1
```

After introducing NodeTags or changing node layouts, run `make clean` in an
existing build and reconfigure with `--enable-depend` before rebuilding. This
is required to avoid stale objects interpreting shifted NodeTag numbers.

Run the next command only if the previous one succeeded. Inspect a command's
exit status with `echo $?`, and read its log on failure. The socket directory
must be short enough for a Unix socket path (107 bytes on Linux); the above
path fits this checkout. On a longer checkout path, select a shorter private
socket directory on your machine. Build/run as your normal user, not root.

## 3. Native regression suite

In the same shell, after successful compilation:

```sh
make check > check.log 2>&1
```

This starts and stops a test server from this build and runs the full core
regression schedule. It includes `join`, `join_hash`, `subselect`,
`partition_join`, and `explain`. Existing join tests depend on setup scripts;
do not run them alone in a fresh regression database. Relevant coverage:

- `join_hash`: serial/private-per-worker/shared parallel hash, batching,
  skew, underestimated sizes, empty/full joins, NULLs, oversized tuples,
  match bits, hash-key subplans, and parameter changes across rescans.
- `join`: multi-key/subplan joins, skew with batch growth, join-type/qual cases.
- `subselect`, `partition_join`, `explain`: related planner/executor behavior.

Inspect `src/test/regress/regression.diffs`, `results/`, and `log/` under
`diamond_build` on failure. A sandbox socket-creation denial is an environment
block before SQL execution, not a regression assertion failure. Run the same
command from your normal terminal if sandbox execution is denied.

To run the self-contained Diamond test (Phases 1–3) alone:

```sh
make -C "$diamond_build/src/test/regress" check-tests \
  TESTS=diamond_hashjoin > "$diamond_build/diamond_hashjoin.log" 2>&1
```

The full schedule includes this test automatically. It checks exact counters,
batch deferral, NULLs/duplicates, residual qualifiers, multi-key joins, early
termination, native outer/semi/anti joins, reusable/parameterized rescans,
worker totals/relaunches, plan invariance, instrumented off/on EXCEPT ALL
comparisons and text/JSON/XML/YAML output. The on-path result capture uses
EXPLAIN ANALYZE CREATE TABLE AS so the counter hooks actually execute.
Phase 2's differential cases require the expected count of Lookup/Expand
execution markers and compare off/on bags through diamond_same_rows.
It covers collision rechecks, text keys/payloads, multiple columns, volatile
residual call counts, unique build rows, NO SCROLL FETCH pause/resume,
partial/rescanned expansion, parameterized/spilled rebuilds, skew and native
fallback, including forced
Gather. A raised query_canceled tests error unwinding; the real timeout test
below verifies cancellation during live execution. Phase 3 additionally checks
actual Lookup/Expand row counts, stacked deferred heads with duplicate bags,
whole-stack rewind, copy/read round trips, owner-rescan invalidation, internal
spill rejection, and native DML/row-lock/subplan/parallel fallback.

To repeat the formatting check, from the repository root with the
same shell variables, build PostgreSQL's formatter and check the touched files:

```sh
make -C "$diamond_build/src/tools/pg_bsd_indent"
src/tools/pgindent/pgindent \
  --indent="$diamond_build/src/tools/pg_bsd_indent/pg_bsd_indent" \
  --list-of-typedefs='DiamondHashJoinInstrumentation SharedDiamondHashJoinInfo DiamondHashMatch Lookup Expand LookupState ExpandState DiamondDeferredMatch' \
  --check src/backend/commands/explain.c src/backend/executor/execParallel.c \
  src/backend/executor/nodeHashjoin.c src/backend/executor/nodeHash.c \
  src/backend/utils/misc/guc_tables.c src/include/executor/hashjoin.h \
  src/include/executor/instrument_node.h src/include/executor/nodeHash.h \
  src/include/executor/nodeHashjoin.h \
  src/include/nodes/execnodes.h src/include/nodes/plannodes.h \
  src/backend/executor/execAmi.c src/backend/executor/execProcnode.c \
  src/backend/executor/nodeLookupExpand.c src/include/executor/nodeLookupExpand.h \
  src/backend/optimizer/plan/createplan.c src/backend/optimizer/plan/setrefs.c \
  src/include/optimizer/planmain.h src/backend/utils/adt/ruleutils.c \
  src/test/regress/regress.c
```

## 4. Manual HashJoin traces

Install these binaries into the private prefix and start a private local
server. Use a fresh data directory; do not overwrite an existing cluster.

```sh
make install > install.log 2>&1
"$diamond_install/bin/initdb" -D "$diamond_work/data" \
  --no-locale --encoding=UTF8 -A trust > initdb.log 2>&1
"$diamond_install/bin/pg_ctl" -D "$diamond_work/data" \
  -l "$diamond_build/server.log" \
  -o "-k $PG_REGRESS_SOCK_DIR -p 55432 -c listen_addresses=''" -w start
"$diamond_install/bin/psql" -X -v ON_ERROR_STOP=1 \
  -h "$PG_REGRESS_SOCK_DIR" -p 55432 -d postgres
```

Run this SQL in psql. The settings encourage serial HashJoins; inspect the
actual orientation rather than assuming which input is the build side.

```sql
SELECT version();
SHOW debug_assertions;
BEGIN;
SET LOCAL max_parallel_workers_per_gather=0;
SET LOCAL enable_hashjoin=on;
SET LOCAL enable_nestloop=off;
SET LOCAL enable_mergejoin=off;
SET LOCAL join_collapse_limit=1;
SET LOCAL jit=off;
CREATE TEMP TABLE dp_r(id int,k int,x int);
CREATE TEMP TABLE dp_s(id int,k int,v int);
INSERT INTO dp_r VALUES (1,1,10),(2,2,20),(3,3,30),(4,4,40),(5,NULL,50);
INSERT INTO dp_s VALUES (11,1,5),(12,1,15),(13,2,25),(14,NULL,0);
ANALYZE dp_r;
ANALYZE dp_s;
EXPLAIN (ANALYZE,BUFFERS,VERBOSE,COSTS OFF,TIMING OFF)
SELECT r.id,s.id FROM dp_r r JOIN dp_s s ON r.k=s.k;
SELECT r.id,s.id FROM dp_r r JOIN dp_s s ON r.k=s.k ORDER BY 1,2;
SELECT r.id,s.id FROM dp_r r JOIN dp_s s ON r.k=s.k AND r.x<s.v ORDER BY 1,2;
CREATE TEMP TABLE dp_head(a int,b int);
CREATE TEMP TABLE dp_fanout(a int,sid int);
CREATE TEMP TABLE dp_selective(b int,tid int);
INSERT INTO dp_head VALUES (1,10),(2,99),(3,20);
INSERT INTO dp_fanout VALUES
  (1,11),(1,12),(1,13),(2,21),(2,22),(2,23),(2,24),(3,31);
INSERT INTO dp_selective VALUES (10,101),(20,201);
ANALYZE dp_head;
ANALYZE dp_fanout;
ANALYZE dp_selective;
EXPLAIN (ANALYZE,BUFFERS,VERBOSE,COSTS OFF,TIMING OFF)
SELECT h.a,f.sid,t.tid FROM (dp_head h JOIN dp_fanout f ON h.a=f.a)
JOIN dp_selective t ON h.b=t.b;
SELECT h.a,f.sid,t.tid FROM (dp_head h JOIN dp_fanout f ON h.a=f.a)
JOIN dp_selective t ON h.b=t.b ORDER BY 1,2,3;
ROLLBACK;
```

Expected equality rows: `(1,11), (1,12), (2,13)`; with residual filter:
`(1,12), (2,13)`. Three-table output:
`(1,11,101), (1,12,101), (1,13,101), (3,31,201)`.
The h/f intermediate has 8 rows and final output 4.

With Phase 1 collection enabled, if r probes s: 4 admitted probes, 2 equality
successes, 3 consumed build matches; emitted rows are 3 or 2 with the filter.
The strict-NULL probe is skipped. Reversing inputs gives 3 probes/successes
and 3 matches. For the three-table orientation in ARCHITECTURE.md: lower
join emits 8; upper probes 8 times and emits 4. Enable
`diamond_hashjoin_stats` before EXPLAIN ANALYZE to observe these counters.

Exit psql with `\q`, then stop the server:

```sh
"$diamond_install/bin/pg_ctl" -D "$diamond_work/data" -w stop -m fast
```

## 5. Use Phase 1 instrumentation

In a server built/installed from the current source, enable collection before
executing the query to measure:

```sql
SET diamond_hashjoin_stats = on;
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) SELECT ...;
RESET diamond_hashjoin_stats;
```

Replace `SELECT ...` with the concrete query, for example the fixtures above.
Use `FORMAT JSON` for machine-readable measurements. HashJoin nodes report
`Diamond Hash Probes`, `Diamond Successful Probes`, `Diamond Build Matches`,
and `Diamond Tuples Emitted`. These are totals over loops and workers;
`Actual Rows` remains PostgreSQL's per-loop mean. Plain EXPLAIN and default
stats-off output omit these properties. Collection is latched per node at
executor initialization; regular execution without row instrumentation does
not allocate counters. See ARCHITECTURE.md for the precise event definitions.

Parallel runtime checks need ordinary tables (temporary tables cannot supply
parallel scans). Verify `Workers Launched` rather than assuming workers ran;
our recorded checks launched two in both private/shared hash modes with
leader participation disabled. In the psql session from section 4, reproduce
that check with the following SQL (output appears in the terminal):

```sql
BEGIN;
SET LOCAL diamond_hashjoin_stats=on;
SET LOCAL enable_nestloop=off;
SET LOCAL enable_mergejoin=off;
SET LOCAL jit=off;
SET LOCAL max_parallel_workers_per_gather=2;
SET LOCAL min_parallel_table_scan_size=0;
SET LOCAL parallel_setup_cost=0;
SET LOCAL parallel_tuple_cost=0;
SET LOCAL parallel_leader_participation=off;
SET LOCAL work_mem='64kB';
SET LOCAL hash_mem_multiplier=1;
CREATE TABLE diamond_phase1_runtime AS SELECT generate_series(1,20000) AS id;
ALTER TABLE diamond_phase1_runtime SET (parallel_workers=2);
ANALYZE diamond_phase1_runtime;
SET LOCAL enable_parallel_hash=off;
EXPLAIN (ANALYZE,BUFFERS,COSTS OFF,TIMING OFF,FORMAT JSON)
SELECT count(*) FROM diamond_phase1_runtime l JOIN diamond_phase1_runtime r USING(id);
SET LOCAL enable_parallel_hash=on;
EXPLAIN (ANALYZE,BUFFERS,COSTS OFF,TIMING OFF,FORMAT JSON)
SELECT count(*) FROM diamond_phase1_runtime l JOIN diamond_phase1_runtime r USING(id);
ROLLBACK;
```

Each HashJoin should report 20,000 for all four Diamond counters. Actual worker
availability depends on the server; the saved plans prove that two launched
in the recorded run. ROLLBACK removes the fixture table.

## 6. Lookup/Expand execution and real cancellation

`SET diamond_lookup_expand=on` enables immediate Lookup/Expand independently
of counter collection. It defaults off. Only eligible serial inner joins over
direct heap SeqScans with simple strict hash keys use it; other plans retain
native execution. Parallel-mode queries (including forced Gather) stay native.
EXPLAIN reports `Diamond Lookup Expand: true` on selected nodes; check ANALYZE
and Actual Loops to distinguish selection from actual execution. No independent
scheduling or speedup is implied. ARCHITECTURE.md defines the lifetime contract.

Phase 3: `SET diamond_independent_lookup_expand=on` before planning exposes
separate Diamond Lookup/Expand nodes. It defaults off; cached plans retain
the choice. Public plans close each pair; the private C regression fixture
alone separates their scheduling. Actual Rows/Loops measure new nodes; the
four Phase 1 counters continue to apply only to native HashJoin nodes.
Unsupported inputs, DML/locking, subplans and parallel statements stay native.
Nested deferred builds/general acyclic scheduling are not implemented.

After building/installing, with section 2's shell variables, use the existing
private cluster initialized in section 4; do not run initdb over it. The
following is the recorded runtime check. The subshell stops its server even
on failure; output plans are raw JSON. Use `diamond_phase=2` to repeat the
immediate path or `diamond_phase=3` for separate nodes (the default below).

```sh
diamond_phase=3
diamond_lookup_guc=diamond_independent_lookup_expand
if [ "$diamond_phase" = 2 ]; then diamond_lookup_guc=diamond_lookup_expand; fi
(
set -e
export TMPDIR="$diamond_build/scratch"
"$diamond_install/bin/pg_ctl" -D "$diamond_work/data" \
  -l "$diamond_build/phase${diamond_phase}-server.log" \
  -o "-k $diamond_work/s -p 55432 -c listen_addresses=''" -w start
trap '"$diamond_install/bin/pg_ctl" -D "$diamond_work/data" -w stop -m fast' EXIT
"$diamond_install/bin/psql" -X -qAt -v ON_ERROR_STOP=1 \
  -h "$diamond_work/s" -p 55432 -d postgres \
  -v lookup_guc="$diamond_lookup_guc" \
  -v cancel_plan="$diamond_build/phase${diamond_phase}-cancel-plan.json" \
  -v runtime_plan="$diamond_build/phase${diamond_phase}-runtime-plan.json" \
  > "$diamond_build/phase${diamond_phase}-runtime.log" 2>&1 <<'SQL'
BEGIN;
SET LOCAL diamond_lookup_expand=off;
SET LOCAL diamond_independent_lookup_expand=off;
SET LOCAL :lookup_guc=on;
SET LOCAL diamond_hashjoin_stats=on;
SET LOCAL max_parallel_workers_per_gather=0;
SET LOCAL enable_nestloop=off;
SET LOCAL enable_mergejoin=off;
SET LOCAL jit=off;
SET LOCAL work_mem='64kB';
SET LOCAL hash_mem_multiplier=1;
CREATE TABLE diamond_runtime AS
  SELECT i AS id, repeat('x',128) AS payload FROM generate_series(1,20000) i;
ANALYZE diamond_runtime;
CREATE FUNCTION diamond_delay(a int, b int) RETURNS boolean
LANGUAGE plpgsql VOLATILE AS $$
BEGIN
  RAISE NOTICE 'Residual entered with a live match';
  PERFORM pg_sleep(2);
  RETURN a=b;
END;
$$;
\o :cancel_plan
EXPLAIN (COSTS OFF, FORMAT JSON)
SELECT l.id FROM diamond_runtime l JOIN diamond_runtime r
  ON l.id=r.id AND diamond_delay(l.id,r.id);
\o
SET LOCAL statement_timeout='500ms';
DO $$
BEGIN
  BEGIN
    PERFORM l.id FROM diamond_runtime l JOIN diamond_runtime r
      ON l.id=r.id AND diamond_delay(l.id,r.id);
    RAISE EXCEPTION 'expected statement timeout';
  EXCEPTION WHEN query_canceled THEN
    RAISE NOTICE 'Cancellation caught: %', SQLERRM;
  END;
END;
$$;
SET LOCAL statement_timeout=0;
\o :runtime_plan
EXPLAIN (ANALYZE,BUFFERS,COSTS OFF,TIMING OFF,FORMAT JSON)
SELECT l.id,l.payload,r.payload FROM diamond_runtime l
  JOIN diamond_runtime r USING(id);
\o
ROLLBACK;
SQL
)
cat "$diamond_build/phase${diamond_phase}-runtime.log"
```

Phase 2 recorded result: the residual-entry notice preceded the real timeout;
the following join used 16 batches with all four counters 20,000. Phase 3
recorded the same real timeout followed by 20,000 Actual Rows at each new
node, one loop each and 16 Hash batches. ROLLBACK removes the fixture/function. Both saved plans must show the selected mode.

## 7. Later functional validation and sanitizer attempt

For Lookup/Expand phases compare the same query/data/snapshot with Diamond
off/on using EXCEPT ALL in both directions, preserving duplicates. Unsupported
classes must retain native behavior. Add lifecycle/materialization cases as
new ownership is introduced; do not claim instrumentation proves deferred
execution is correct.

Phases 2 and 3 attempted a separate assertion/debug ASan build using the same
system dependencies. From a normal terminal, with section 2's variables (run
`make clean` first if reusing an older build after node-layout changes):

```sh
diamond_asan="$diamond_work/build-asan"
mkdir -p "$diamond_asan/scratch"
(
set -e
cd "$diamond_asan"
export TMPDIR="$diamond_asan/scratch"
export PG_REGRESS_SOCK_DIR="$diamond_work/s"
"$diamond_src/configure" --prefix="$diamond_work/install-asan" \
  --enable-cassert --enable-debug --enable-depend \
  CFLAGS='-O1 -g -fsanitize=address -fno-omit-frame-pointer' \
  LDFLAGS='-fsanitize=address' > configure.log 2>&1
make -j4 > build.log 2>&1
make -C src/test/regress check-tests TESTS=diamond_hashjoin \
  EXTRA_REGRESS_OPTS='--port=55433' > phase3-targeted.log 2>&1
)
```

Configuration/compilation passed. The test failed before SQL: initdb's
`postgres -V` subprocess exits nonzero after LeakSanitizer reports 777 bytes
in unchanged `save_ps_display_args` (process-title environment copying).
Evidence: `build-asan/phase2-targeted.log` and
`build-asan/phase2-initdb.log`, relative to diamond_work. Phase 3 repeated
a clean ASan build and test with the same failure; its evidence is
`build-asan/{phase3-build,phase3-targeted,phase3-initdb}.log`.
The tracing sandbox also prevents LeakSanitizer's configure probe;
configuration and the subsequent failed test attempt ran outside it. No
sanitizer check was disabled, no suppression/configuration workaround was added, and no sanitizer
test pass is claimed. This leaves sanitizer validation outstanding.
Phase 3 includes round-trip checks from `src/backend/nodes/README`.

Benchmarks are Phase 8: paper microbenchmarks, JOB and TPC-H. Record commit,
query/data seed/scale, hardware/configuration, warmups/repetitions, latency,
planning time, intermediate rows, hash memory/batches/temp I/O and correctness.
No benchmark results or performance claim exist yet.

## Actual validation ledger

Publication attempt, 2026-10-25: committed the reviewed 28-file Phase 3 diff
(+1,594/-150 lines) as `0aa87a8624`, using the user's author/committer identity
and no co-author trailer. `git ls-remote --heads origin diamond-pg master`
found only master. `git push --set-upstream origin diamond-pg` failed with
`could not read Username for 'https://github.com'`: no Git credential helper
is configured and `gh` is not installed. No remote branch was created. Resume
that exact push from an authenticated terminal, then compare `git rev-parse
HEAD` with `git ls-remote --heads origin diamond-pg`. PDF/build output remains
excluded. Existing test evidence below was verified; no tests rerun for this
commit/publication-only task.


- Phase 0: system-package assertion/debug build, all 239 original core tests,
  and two-/three-table native fixtures passed (2026-10-19).
- Phase 1: assertion/debug build without reported compiler warnings; all
  **240 core tests passed**, including diamond_hashjoin. pgindent passed on
  touched C/headers using the in-tree pg_bsd_indent and the two new typedefs.
- Manual runtime: private/shared hash each launched two workers; all four
  total counters were 20,000. Regression worker relaunch case counted 60,000
  probes/matches over three launches. Private server stopped after validation.
- Phase 2 (`c169183521`): assertion/debug build, focused diamond_hashjoin and all 240 core
  tests passed. A live-match residual was interrupted by a real 500ms timeout;
  the subsequent 16-batch join produced 20,000 for all counters. Private server
  stopped. ASan compilation passed; its test was blocked before SQL as above.

Phase 3 (2026-10-19) passed the assertion/debug build, focused Diamond test,
and **all 240 core regressions**, including the representative join tests.
The C fixture runs/rewinds a real separated stack: per run, L2 outputs 11
heads, E1 outputs 33 pairs and E2 outputs the correct 66-row multiset.
Rescanning a paused owner raises the intended stale-reference error; an
internally forced multi-batch stack raises the intended pre-output rejection.
All positive/differential boolean oracles are true. Public batching, skew,
partial parameter rebuilds, forward FETCH, volatile residuals, native fallbacks
and generated Plan copy/read checks pass. The exact section 6 command was
executed from this document: live residual -> real timeout -> 20,000 rows at
both separate nodes, one loop each, 16 batches; raw JSON parsed/checked and
private server stopped. ASan compiled including the regression C module, but
its test stopped before SQL as above. Meson/check-world/benchmarks were not run.

| Executed command / step | Actual result | Evidence relative to diamond_build |
| --- | --- | --- |
| `make -C "$diamond_build" clean`, configure as section 2 with `--enable-depend`, `make -C "$diamond_build" -j4` | Clean assertion/debug rebuild passed; final incremental compile passed without reported warnings | `phase3-clean.log`, `phase3-configure.log`, `phase3-build.log` (latest incremental) |
| `make -C "$diamond_build/src/test/regress" check-tests TESTS=diamond_hashjoin` | Focused test passed against reviewed expectations | `phase3-targeted.log` |
| `make -C "$diamond_build" check` | All 240 core tests passed | `phase3-check.log`; latest native `src/test/regress/{results,log}` |
| `make -C "$diamond_build" install` | Private-prefix installation passed | `phase3-install.log` |
| pgindent `--check`, section 3 | Passed with all eight Diamond typedefs | `phase3-indent.log` (empty; exit status checked) |
| Section 6 shell/psql block, `diamond_phase=3` | Real timeout/recovery passed; server stopped | `phase3-runtime.log`, `phase3-server.log`, `phase3-{cancel,runtime}-plan.json` |
| ASan section 7, plus final `make -C "$diamond_work/build-asan/src/test/regress" regress.so` | Compile passed; regression initialization blocked by the 777-byte startup leak | `../build-asan/phase3-{clean,configure,build,targeted,initdb}.log` |

Development evidence: `phase3-initdb-initial.log` records stale NodeTags in the
old build without dependencies; a standard clean rebuild fixed that. The
slot assertion excerpt/backtrace in `phase3-slot-initial.log` led to dynamic
outer equality deformation for the owned MinimalTuple copy; assertions were
preserved. `phase3-targeted-review.log` contains expected differences from the
Phase 2 expectations before review, not a passing log. Output review also
fixed the numeric JSON oracle and standard regression-library environment
loading. No suppressions, disabled checks or dependency workarounds were used.

Phase 2 used the same native commands below, with phase2 log filenames:

| Executed command | Observed result | Evidence relative to diamond_build |
| --- | --- | --- |
| `make -C "$diamond_build" -j4` | Assertion/debug build passed without reported compiler warnings | `phase2-build.log` |
| `make -C "$diamond_build/src/test/regress" check-tests TESTS=diamond_hashjoin` | Focused test passed against reviewed expectations | `phase2-targeted.log` |
| `make -C "$diamond_build" check` | All 240 core tests passed | `phase2-check.log`; `c169183521:src/test/regress/expected/diamond_hashjoin.out` |
| `make -C "$diamond_build" install` | Private-prefix installation passed | `phase2-install.log` |
| pgindent `--check`, section 3 | Passed on touched C/headers with the three Diamond typedefs | `phase2-indent.log` (empty on success; exit status checked) |
| pg_ctl / psql / SQL in section 6 | Real timeout and recovery passed; server stopped | `phase2-runtime.log`, `phase2-server.log`, `phase2-{cancel,runtime}-plan.json` |

Initial output-review runs differed from Phase 1's expected output; one test
query with a constant key filter had been simplified to no HashJoin and was
corrected to a genuine no-match column equijoin. All final boolean oracles
were reviewed before recording expectations. `phase2-targeted-initial.log`
and `phase2-targeted-review.log` are development evidence, not passing logs.

The commands above are reproduction instructions. The following table maps
the relevant executed Phase 1 commands to their recorded evidence; paths in
the last column are relative to `diamond_build`:

| Executed command | Observed result | Evidence |
| --- | --- | --- |
| `make -C "$diamond_build" -j4` | Assertion/debug build passed; no reported compiler warnings | `phase1-build.log`; configuration in `configure.log` |
| `make -C "$diamond_build/src/test/regress" check-tests TESTS=diamond_hashjoin` | Initial run differed from the then-empty expected file; reviewed the boolean oracles before recording expectations | `phase1-targeted.log`; this is not a passing-run log |
| `make -C "$diamond_build" check` | All 240 core tests passed, including diamond_hashjoin | `phase1-check.log`; expected output at `14ac927a8b:src/test/regress/expected/diamond_hashjoin.out` |
| `make -C "$diamond_build" install` | Private-prefix installation passed | `phase1-install.log` |
| In-tree pgindent check with Phase 1's two added typedefs | Passed on the seven Phase 1 C/headers | Exit status checked in terminal; no separate saved check log; formatter build in `phase1-indent-build.log` |
| `"$diamond_install/bin/psql" -X -qAt -v ON_ERROR_STOP=1 -h "$PG_REGRESS_SOCK_DIR" -p 55432 -d postgres -f "$diamond_work/phase1-runtime.sql"` | Both runtime plans launched two workers and reported 20,000 for all four counters | `phase1-private-plan.json`, `phase1-shared-plan.json`; server lifecycle in `phase1-server.log` |

The captured local `phase1-runtime.sql` contains section 5's SQL plus psql
`\o` commands writing those JSON files at this checkout's absolute paths.
It is validation output, not a required helper or portable source file.
`phase1-runtime.log` is empty because query output went to the JSON files;
use the plans as evidence. The committed regression SQL and expected output
preserve the automated checks for a fresh checkout.

Phase 0 evidence remains under `diamond_build`: `configure.log`,
`build.log`, `check.log` (239 tests), `install.log`, `initdb.log`,
`server.log`, `runtime.log`, and `{equality,residual,three_table}-plan.json`.
Native driver details remain under `src/test/regress/{results,log}`.
Those directories describe the latest run; phase-specific console logs and
versioned expectations preserve earlier checkpoints.
Summaries and regression expectations are versioned; raw logs, plans, clusters
and build outputs stay ignored under `scripts/diamond-pg/.work/` and must not
be staged. No sanitizer/check-world/benchmark pass is claimed.
[CHANGELOG.md](CHANGELOG.md) records changed files and implementation decisions.

## Remote execution readiness (2026-10-31)

After publication restored files, restarted the existing private database on
port55434 and launched `.work/remote-batch.sh` using `nohup setsid`, with
stdin closed and logs redirected. Verified its own session and PPID 1. This
is detachment evidence, not a cloud lifetime guarantee. The sole authorized
Codex worker used existing ChatGPT CLI login but failed before model work
with proxy HTTP CONNECT 403 to chatgpt.com. Stopped its retries; no coding
pass claimed. Status/evidence `.work/remote-worker.*`; a new network draft
adds chatgpt.com but needs user application/publication. No proxy bypass.
