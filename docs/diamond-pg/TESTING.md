# Building and testing Diamond-PG

Updated 2026-10-19. Baseline: PostgreSQL 20devel,
`6296e78c3d2c7406bb450c5ae477b2fef58f155e`.
Use the native build tools below. Staging or committing is **not** required
before building/testing: both use the current working tree.

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
  --enable-cassert --enable-debug > configure.log 2>&1
make -j4 > build.log 2>&1
```

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

Future self-contained Diamond tests may use native
`make -C "$diamond_build/src/test/regress" check-tests TESTS=diamond_hashjoin`
after the corresponding SQL/expected files exist. No Diamond test exists yet.

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

For future Phase 1 counters, if r probes s: 4 admitted probes, 2 equality
successes, 3 consumed build matches; emitted rows are 3 or 2 with the filter.
The strict-NULL probe is skipped. Reversing inputs gives 3 probes/successes
and 3 matches. For the three-table orientation in ARCHITECTURE.md: lower
join emits 8; upper probes 8 times and emits 4. Native EXPLAIN cannot yet
measure the proposed new probe counters.

Exit psql with `\q`, then stop the server:

```sh
"$diamond_install/bin/pg_ctl" -D "$diamond_work/data" -w stop -m fast
```

## 5. Later functional validation

Compare the same query/data/snapshot with Diamond off/on using **EXCEPT ALL
in both directions**, preserving duplicates. Phase 1 compares stats off/on.
Cover zero/one/many matches, duplicate keys on both inputs, strict NULLs,
multiple keys/columns, residual predicates/projection, empty inputs,
rescans/changed parameters, batching/skew, LIMIT, cancellation and cleanup.
Unsupported query classes must retain native semantics.

Parallel tests need ordinary tables: temporary tables cannot supply parallel
table scans. Check both shared Parallel Hash and private hashes under Gather,
leader participation, actual launched workers and rescan/relaunch accounting.
Use the existing `join_hash` tests for the baseline.

For ownership bugs use a separate assertion/debug ASan build with
`CFLAGS='-O1 -g -fsanitize=address -fno-omit-frame-pointer'` and
`LDFLAGS='-fsanitize=address'`. New nodes also need the round-trip checks in
`src/backend/nodes/README`. No sanitizer run is claimed for Phase 0.

Benchmarks are Phase 8: paper microbenchmarks, JOB and TPC-H. Record commit,
query/data seed/scale, hardware/configuration, warmups/repetitions, latency,
planning time, intermediate rows, observed hash memory/batches/temp I/O and
correctness. No benchmark runner/results exist yet. EXPLAIN row counts are
averages per loop; width-times-rows is not measured peak memory.

## Actual validation ledger

Verified 2026-10-19 on the persistent system-package build:

- Configure and `make -j4`: PASS; assertions/debug/ICU/readline enabled;
  no compiler warnings reported.
- `make check`: **all 239 core tests passed**, including every test named above.
- Installed server: PostgreSQL 20devel; `debug_assertions=on`.
- Two-table, residual-filter and three-table fixtures: exact expected
  multisets PASS; native hash/non-hash comparisons PASS.
- EXPLAIN JSON: equality 3 rows, residual 2; three-table lower join 8 and
  upper join 4. Actual lower orientation is f probes/h builds.
- Private runtime server stopped after validation.

Evidence under `diamond_build`: `configure.log`, `build-console.log`,
`check.log`, `install.log`, `initdb.log`, `server.log`, `runtime.log`,
and `{equality,residual,three_table}-plan.json`. The captured assertion SQL
is `diamond_work/baseline.sql`. These are ignored generated output, not
files to stage. No Diamond off/on, sanitizer or benchmark run is claimed.
