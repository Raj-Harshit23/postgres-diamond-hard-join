#!/usr/bin/env bash
# Shared implementation for the three public benchmark entry points.
set -euo pipefail

suite=${1:?benchmark suite is required}
case "$suite" in paper|tpch|job) ;; *) echo "unknown suite: $suite" >&2; exit 2 ;; esac

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
local_work=$script_dir/.work
work=${DIAMOND_PG_WORK:-$local_work}
# Builds stay beside this checkout even when datasets live on a portable disk.
build=${DIAMOND_PG_BUILD:-$local_work/build-opt}
install=${DIAMOND_PG_INSTALL:-$local_work/install-opt}
data=${DIAMOND_PG_DATA:-$work/bench-data}
socket=${DIAMOND_PG_SOCKET:-$work/s}
port=${DIAMOND_PG_PORT:-55434}
output=${DIAMOND_PG_OUTPUT:-$work/bench-final-$suite}
jobs=${DIAMOND_PG_JOBS:-$(getconf _NPROCESSORS_ONLN)}

# Rebuild by default so a measurement cannot silently use an older executable.
if [[ ${DIAMOND_PG_SKIP_BUILD:-0} != 1 ]]; then
  mkdir -p "$build"
  if [[ ! -f $build/GNUmakefile ]]; then
    (cd "$build" && "$repo/configure" --prefix="$install" --enable-depend)
  fi
  make -C "$build" -j"$jobs"
  make -C "$build" install
fi
[[ -x $install/bin/postgres ]] || {
  echo "missing optimized install: $install (remove DIAMOND_PG_SKIP_BUILD=1)" >&2
  exit 1
}

# The paper fixture is small and self-contained. TPC-H/JOB intentionally use
# prepared datasets; their multi-GB source data is never downloaded implicitly.
if [[ $suite == paper && ! -f $data/PG_VERSION ]]; then
  mkdir -p "$data"
  "$install/bin/initdb" -D "$data" --auth=trust --no-instructions
elif [[ ! -f $data/PG_VERSION ]]; then
  echo "missing prepared cluster: $data" >&2
  echo "Set DIAMOND_PG_WORK to the preserved benchmark .work directory; see TESTING.md." >&2
  exit 1
fi

mkdir -p "$socket" "$output"
if "$install/bin/pg_ctl" -D "$data" status >/dev/null 2>&1; then
  echo "benchmark cluster is already running; stop it before this reproducible run" >&2
  exit 1
fi
"$install/bin/pg_ctl" -D "$data" -l "$output/server.log" \
  -o "-k $socket -p $port -c listen_addresses='' -c shared_buffers=${DIAMOND_PG_SHARED_BUFFERS:-1GB} -c work_mem=64MB -c hash_mem_multiplier=2 -c jit=off" -w start
stop_server() { "$install/bin/pg_ctl" -D "$data" -m fast -w stop; }
trap stop_server EXIT
psql=("$install/bin/psql" -X -qAt -v ON_ERROR_STOP=1 -h "$socket" -p "$port")

if [[ $suite == paper ]]; then
  # Recreate the exact Section 5.1 acyclic fixture for deterministic reruns.
  "$install/bin/dropdb" -h "$socket" -p "$port" --if-exists diamond_micro
  "$install/bin/createdb" -h "$socket" -p "$port" diamond_micro
  "${psql[@]}" -d diamond_micro <<'SQL'
DO $$
DECLARE n integer;
BEGIN
  FOREACH n IN ARRAY ARRAY[1000,5000,50000] LOOP
    EXECUTE format('CREATE TABLE x%s AS SELECT 1::int a,1::int b UNION ALL SELECT generate_series(1,%s),2',n,n);
    EXECUTE format('CREATE TABLE y%s AS SELECT 1::int b,1::int c UNION ALL SELECT 2,generate_series(4,%s) UNION ALL SELECT generate_series(3,%s),3',n,n,n);
    EXECUTE format('CREATE TABLE z%s AS SELECT 1::int c,1::int d UNION ALL SELECT 3,generate_series(1,%s)',n,n);
    EXECUTE format('ANALYZE x%s',n);
    EXECUTE format('ANALYZE y%s',n);
    EXECUTE format('ANALYZE z%s',n);
  END LOOP;
END $$;
SQL
  mkdir -p "$work/paper-acyclic-queries"
  for spec in n01000:1000 n05000:5000 n50000:50000; do
    name=${spec%%:*}; n=${spec##*:}
    cat >"$work/paper-acyclic-queries/$name.sql" <<SQL
SELECT x.a,x.b,y.c,z.d
FROM x$n x JOIN y$n y ON x.b=y.b JOIN z$n z ON y.c=z.c
SQL
  done
elif [[ $suite == tpch ]]; then
  [[ $(find "$work/tpch-queries" -maxdepth 1 -name '*.sql' 2>/dev/null | wc -l) -eq 22 ]] || {
    echo "expected 22 SQL files under $work/tpch-queries" >&2; exit 1; }
  rows=$("${psql[@]}" -d tpch_sf1 -c 'select count(*) from lineitem' 2>/dev/null || true)
  [[ ${rows:-0} -gt 0 ]] || { echo "tpch_sf1 is not loaded; see TESTING.md" >&2; exit 1; }
else
  [[ $(find "$work/job" -maxdepth 1 -name '[0-9]*.sql' 2>/dev/null | wc -l) -eq 113 ]] || {
    echo "expected 113 SQL files under $work/job" >&2; exit 1; }
  rows=$("${psql[@]}" -d job_cloud -c 'select count(*) from title' 2>/dev/null || true)
  if [[ ${rows:-0} -le 0 && ${DIAMOND_PG_PREPARE:-0} == 1 ]]; then
    # Load the standard May 2013 CSV archive already unpacked in the workspace.
    [[ -f $work/job/schema.sql && -f $work/job/fkindexes.sql ]] || {
      echo "missing JOB schema/index files under $work/job" >&2; exit 1; }
    [[ $(find "$work/imdb-data" -maxdepth 1 -name '*.csv' | wc -l) -eq 21 ]] || {
      echo "expected 21 CSV files under $work/imdb-data" >&2; exit 1; }
    "$install/bin/dropdb" -h "$socket" -p "$port" --if-exists job_cloud
    "$install/bin/createdb" -h "$socket" -p "$port" job_cloud
    "${psql[@]}" -d job_cloud -f "$work/job/schema.sql"
    for csv in "$work"/imdb-data/*.csv; do
      table=$(basename "$csv" .csv)
      echo "Loading $table..."
      "${psql[@]}" -d job_cloud -c "\copy $table FROM '$csv' WITH (FORMAT csv, ESCAPE '\')"
    done
    "${psql[@]}" -d job_cloud -f "$work/job/fkindexes.sql"
    "$install/bin/vacuumdb" -h "$socket" -p "$port" -d job_cloud --analyze
    rows=$("${psql[@]}" -d job_cloud -c 'select count(*) from title')
  fi
  [[ ${rows:-0} -gt 0 ]] || {
    echo "job_cloud is empty; rerun with DIAMOND_PG_PREPARE=1 after placing the 21 CSV files in $work/imdb-data" >&2
    exit 1
  }
fi

# Store enough identity to interpret or reproduce the raw JSON results.
{
  echo "commit=$(git -C "$repo" rev-parse HEAD)"
  echo "suite=$suite"
  echo "postgres=$($install/bin/postgres --version)"
  echo "work=$work"
  echo "started_utc=$(date -u +%FT%TZ)"
} >"$output/run-metadata.txt"

PYTHONUNBUFFERED=1 DIAMOND_PG_WORK="$work" DIAMOND_PG_INSTALL="$install" \
DIAMOND_PG_SOCKET="$socket" DIAMOND_PG_PORT="$port" DIAMOND_PG_OUTPUT="$output" \
python3 -u "$script_dir/benchmark.py" "$suite" 2>&1 | tee "$output/live.log"

# Demo mode prints both physical plans for one manageable paper instance.
if [[ $suite == paper && ${DIAMOND_PG_DEMO:-0} == 1 ]]; then
  demo_query=${DIAMOND_PG_QUERY:-n05000}
  query_file=$work/paper-acyclic-queries/$demo_query.sql
  [[ -f $query_file ]] || { echo "unknown demo query: $demo_query" >&2; exit 1; }
  query=$(cat "$query_file")
  "${psql[@]}" -d diamond_micro <<SQL
SET jit=off;
SET work_mem='64MB';
SET hash_mem_multiplier=2;
SET diamond_acyclic=off;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON) $query;
SET diamond_acyclic=on;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON) $query;
SQL
fi
