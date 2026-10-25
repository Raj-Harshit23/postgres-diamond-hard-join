# Building and testing Diamond-PG

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
was configured and `gh` was not installed. That attempt created no branch.
A subsequent `git ls-remote --heads origin diamond-pg` returned
`9ee4d297b3a85cfb6022e598135b38810bc8184a`, matching `git rev-parse HEAD`;
publication of the project and docs is therefore verified through that commit.
`git ls-tree -r --name-only HEAD docs/diamond-pg` confirms all five documents
are tracked. PDF/build output remains excluded. Existing test evidence below was verified; no tests rerun for this
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
