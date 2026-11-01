-- Diamond-PG: native counters and opt-in immediate Lookup/Expand.  Compare
-- multisets as well as execution markers so a silent fallback cannot pass.
begin;
set local enable_mergejoin = off;
set local enable_nestloop = off;
set local max_parallel_workers_per_gather = 0;
set local jit = off;

create schema diamond_hashjoin_test;
set local search_path = diamond_hashjoin_test, public;

-- Return HashJoin nodes only, avoiding unstable timing/cost/buffer output.
-- The SQL argument is a test query; run_analyze=false checks plain EXPLAIN.
create function diamond_plan(query text, run_analyze boolean default true)
returns setof jsonb language plpgsql as $$
declare
  plan jsonb;
begin
  execute 'explain (format json, costs off, timing off, analyze ' ||
          run_analyze || ') ' || query into plan;
  return query
    with recursive nodes(node) as (
      select plan->0->'Plan'
      union all
      select child from nodes,
        lateral jsonb_array_elements(node->'Plans') child
    )
    select node from nodes where node->>'Node Type' in
      ('Hash Join', 'Diamond Lookup', 'Diamond Expand', 'Diamond Join');
end;
$$;

create table probe(id int, k int, x int);
create table build(id int, k int, v int);
insert into probe values (1,1,10),(2,2,20),(3,3,30),(4,4,40),(5,null,50);
insert into build values (11,1,5),(12,1,15),(13,2,25),(14,null,0);
analyze probe, build;

show diamond_hashjoin_stats;
select bool_and(not (p ? 'Diamond Hash Probes')) as disabled_output
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k') p;

-- Capture the baseline multiset before enabling collection.
create table expected_result as
  select r.k as probe_key,s.k as build_key,r.x+1 as projected
  from probe r join build s on r.k=s.k;
create table expected_plan as
  select p from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k', false) p;
set local diamond_hashjoin_stats = on;
select bool_and(not (p ? 'Diamond Hash Probes')) as plain_explain
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k', false) p;

select not exists (
  (table expected_plan except all
   select p from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k', false) p)
  union all
  (select p from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k', false) p
   except all table expected_plan)
) as unchanged_plan;

-- Account for either legal build/probe orientation.  NULL keys do not probe;
-- two duplicate build keys produce three pairs, not two distinct keys.
select
  (p->>'Diamond Hash Probes')::int =
    case when p#>>'{Plans,0,Alias}' = 'r' then 4 else 3 end as probes,
  (p->>'Diamond Successful Probes')::int =
    case when p#>>'{Plans,0,Alias}' = 'r' then 2 else 3 end as successes,
  p->>'Diamond Build Matches' = '3' as matches,
  p->>'Diamond Tuples Emitted' = '3' as emitted
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k') p;

-- Equality success survives a residual predicate rejecting every pair.
select p->>'Diamond Build Matches' = '3' as matches_before_filter,
       (p->>'Diamond Successful Probes')::int > 0 as equality_success,
       p->>'Diamond Tuples Emitted' = '0' as all_rejected
from diamond_plan(
  'select r.id,s.id from probe r join build s on r.k=s.k and r.x<s.v-100') p;

-- EXPLAIN ANALYZE executes CTAS with row instrumentation, so the on-path
-- comparison exercises the actual counter hooks, not just the GUC setting.
select p->>'Diamond Tuples Emitted' = '3' as instrumented_capture
from diamond_plan('create table observed_result as
  select r.k as probe_key,s.k as build_key,r.x+1 as projected
  from probe r join build s on r.k=s.k') p;
select not exists (
  (table expected_result except all table observed_result)
  union all
  (table observed_result except all table expected_result)
) as off_on_same_multiset;

select p->>'Diamond Build Matches' = '1' as multiple_hash_keys,
       p->>'Diamond Tuples Emitted' = '1' as one_match
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k and r.id=s.id-10') p;

insert into probe values (6,1,12);
analyze probe;
select p->>'Diamond Build Matches' = '5' as duplicates_on_both_sides,
       p->>'Diamond Tuples Emitted' = '5' as duplicate_outputs
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k') p;
delete from probe where id=6;
analyze probe;

select p->>'Diamond Build Matches' = '0' as no_matches,
       p->>'Diamond Successful Probes' = '0' as no_successes
from diamond_plan('select * from probe r join build s on r.k=s.k+100') p;
create table empty_build(k int);
select p->>'Diamond Hash Probes' = '0' as empty_shortcut,
       p->>'Diamond Tuples Emitted' = '0' as empty_output
from diamond_plan('select * from probe r join empty_build s on r.k=s.k') p;

-- LIMIT counts observed work, not every possible match in the relation.
select p->>'Diamond Tuples Emitted' = '1' as limited_output,
       p->>'Diamond Build Matches' = '1' as limited_matches
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k limit 1') p;

-- Native outer/semi/anti behavior is preserved; every actual join output,
-- including NULL extension, is represented in the native emitted-row total.
select bool_and((p->>'Diamond Tuples Emitted')::numeric =
                (p->>'Actual Rows')::numeric * (p->>'Actual Loops')::numeric)
       as native_join_types
from (values
  ('select r.id,s.id from probe r full join build s on r.k=s.k'),
  ('select r.id from probe r where exists (select from build s where r.k=s.k)'),
  ('select r.id from probe r where not exists (select from build s where r.k=s.k)')
) q(sql), lateral diamond_plan(sql) p;

-- Reset the success flag per probe/rescan, but retain total work over loops.
-- The parameter affects only a residual predicate; the build is reusable.
set local enable_material = off;
select p->>'Actual Loops' = '3' as rescanned,
       p->>'Diamond Build Matches' = '9' as cumulative_matches,
       p->>'Diamond Tuples Emitted' = '6' as cumulative_outputs
from diamond_plan($q$
  select o.n,j.* from (values (1),(2),(3)) o(n)
  cross join lateral (
    select r.id,s.id from probe r join build s on r.k=s.k
    where r.x<s.v+o.n offset 0
  ) j
$q$) p;

-- A parameter inside the build's hash key must defeat hash-table reuse.
select p->>'Actual Loops' = '3' as parameter_rescans,
       p->>'Diamond Build Matches' = '9' as rebuilt_matches,
       p->>'Diamond Tuples Emitted' = '9' as rebuilt_outputs
from diamond_plan($q$
  select o.n,j.* from (values (0),(1),(2)) o(n)
  cross join lateral (
    select r.id,s.id from probe r join build s on r.k=s.k+o.n offset 0
  ) j
$q$) p;

-- JSON is checked above.  Other EXPLAIN formats must expose the same fields.
do $$
declare
  fmt text;
  ln text;
  found boolean;
begin
  foreach fmt in array array['text','xml','yaml'] loop
    found := false;
    for ln in execute 'explain (analyze, costs off, timing off, format ' ||
      fmt || ') select r.id,s.id from probe r join build s on r.k=s.k'
    loop
      found := found or ln like '%Diamond%';
    end loop;
    if not found then
      raise exception 'missing Diamond statistics in %', fmt;
    end if;
  end loop;
end;
$$;

-- Phase 2: execute each deterministic query off/on, compare bags in both
-- directions, and require exactly the expected number of eligible joins.
-- EXPLAIN ANALYZE CTAS exercises real enumeration and records its choice.
create function diamond_same_rows(query text, expected_joins int default 1,
                                  independent boolean default false)
returns boolean language plpgsql as $$
declare
  enabled_joins int;
  lookups int;
  same_rows boolean;
begin
  perform set_config('diamond_lookup_expand', 'off', true);
  perform set_config('diamond_independent_lookup_expand', 'off', true);
  execute 'create table native_rows as ' || query;
  perform set_config('diamond_lookup_expand', (not independent)::text, true);
  perform set_config('diamond_independent_lookup_expand', independent::text, true);
  select count(*) filter (where case when independent then
           p->>'Node Type' = 'Diamond Expand' else
           p->>'Diamond Lookup Expand' = 'true' end),
         count(*) filter (where p->>'Node Type' = 'Diamond Lookup')
    into enabled_joins, lookups
    from diamond_plan('create table diamond_rows as ' || query) p;
  select not exists (
    (table native_rows except all table diamond_rows)
    union all
    (table diamond_rows except all table native_rows)
  ) into same_rows;
  drop table native_rows, diamond_rows;
  return same_rows and enabled_joins = expected_joins and
         (not independent or lookups = expected_joins);
end;
$$;

show diamond_lookup_expand;
select label, diamond_same_rows(query, expected_joins) as correct_path_and_bag
from (values
  ('duplicates/projection', 'select r.k,s.k as sk,r.x+1 as x from probe r join build s on r.k=s.k', 1),
  ('residual', 'select r.id,s.id as sid from probe r join build s on r.k=s.k and r.x<s.v', 1),
  ('reject all', 'select r.id,s.id as sid from probe r join build s on r.k=s.k and r.x<s.v-100', 1),
  ('no match', 'select r.id,s.id as sid from probe r join build s on r.k=s.id', 1),
  ('empty input', 'select r.id from probe r join empty_build s on r.k=s.k', 1),
  ('early stop', 'select r.k,s.k as sk from probe r join build s on r.k=s.k limit 1', 1),
  ('expression fallback', 'select r.id,s.id as sid from probe r join build s on r.k=s.k+1', 0),
  ('inequality fallback', 'select r.id,s.id as sid from probe r join build s on r.k<s.k', 0),
  ('outer fallback', 'select r.id,s.id as sid from probe r full join build s on r.k=s.k', 0),
  ('semi fallback', 'select r.id from probe r where exists (select from build s where r.k=s.k)', 0),
  ('anti fallback', 'select r.id from probe r where not exists (select from build s where r.k=s.k)', 0)
) cases(label, query, expected_joins);
create table unique_build(k int primary key);
insert into unique_build values (1),(2),(3);
analyze unique_build;
select diamond_same_rows('select r.id from probe r join unique_build s using(k)') as unique_build_bag;
select p->>'Diamond Lookup Expand' = 'true' as plain_execution_choice,
       p - 'Diamond Lookup Expand' = (select p from expected_plan) as same_native_plan
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k', false) p;

-- A forced Gather can wrap a serial-looking HashJoin.  The planned statement,
-- not just per-node parallel_aware flags, must select native fallback.
set local max_parallel_workers_per_gather = 1;
set local debug_parallel_query = on;
select not (p ? 'Diamond Lookup Expand') as forced_gather_native
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k') p;
set local debug_parallel_query = off;
set local max_parallel_workers_per_gather = 0;

-- Executor shutdown is also called between NO SCROLL FETCHes.  It must not
-- discard a live private cursor before the next pull resumes its duplicates.
declare diamond_forward no scroll cursor for
  select r.k,s.k as sk from probe r join build s on r.k=s.k;
fetch 1 from diamond_forward;
fetch 1 from diamond_forward;
fetch all from diamond_forward;
close diamond_forward;

-- By-reference keys/payloads must survive per-tuple expression resets.  Two
-- duplicate probe and build rows also check multiplicity on both sides.
create table text_probe(k text collate "C", n int, payload text);
create table text_build(k text collate "C", n int, payload text);
insert into text_probe values ('a',1,repeat('p',3000)),('a',1,'p'),('b',2,'b'),(null,1,'null');
insert into text_build values ('a',1,repeat('q',3000)),('a',1,'q'),('b',3,'b'),(null,1,'null');
analyze text_probe, text_build;
select diamond_same_rows('select r.payload,s.payload as sp from text_probe r join text_build s using(k)') as text_duplicates;
select diamond_same_rows('select r.payload,s.payload as sp from text_probe r join text_build s using(k,n)') as multiple_column_keys;

-- These unequal int8 values have the same hashint8 hash (high XOR low = 1).
-- Expand must recheck equality throughout the chain, not just at Lookup.
create table collisions(k bigint);
insert into collisions values (1),(1),(4294967296),(8589934595),(null);
analyze collisions;
select hashint8(1)=hashint8(4294967296) and
       hashint8(1)=hashint8(8589934595) as actual_hash_collision;
select diamond_same_rows('select r.k,s.k as sk from collisions r join collisions s using(k)') as collision_bag;
select p->>'Diamond Build Matches' = '6' as equality_rechecked,
       p->>'Diamond Lookup Expand' = 'true' as cursor_used
from diamond_plan('select r.k,s.k from collisions r join collisions s using(k)') p;

-- An equality candidate reaches a volatile residual exactly once; rejecting
-- the first candidate must not discard later matches or repeat side effects.
create sequence residual_calls;
create function count_residual(a int, b int) returns boolean
language plpgsql volatile as $$
begin
  perform nextval('residual_calls');
  return a < b;
end;
$$;
select diamond_same_rows('select r.id,s.id as sid from probe r join build s on r.k=s.k and count_residual(r.x,s.v)') as volatile_residual_bag;
select last_value=6 as residual_once_per_pair_off_and_on from residual_calls;

-- Reuse the single-batch table with a changed residual parameter.  LIMIT
-- leaves a partially expanded probe to invalidate before each rescan.
select p->>'Diamond Lookup Expand' = 'true' as rescan_cursor,
       p->>'Actual Loops' = '3' as rescanned,
       p->>'Diamond Build Matches' = '9' as cumulative_matches
from diamond_plan($q$
  select o.n,j.* from (values (1),(2),(3)) o(n)
  cross join lateral (
    select r.id,s.id from probe r join build s on r.k=s.k
    where r.x<s.v+o.n offset 0
  ) j
$q$) p;
select diamond_same_rows($q$
  select o.n,j.* from (values (1),(2),(3)) o(n)
  cross join lateral (
    select r.k,s.k as sk from probe r join build s on r.k=s.k
    where r.x<s.v+o.n limit 1
  ) j
$q$) as partial_expand_rescan;

-- A parameter in the build scan's filter rebuilds the table even though its
-- hash key is a simple column.  This case stays eligible, unlike key expressions.
select diamond_same_rows($q$
  select o.n,j.* from (values (0),(10),(20)) o(n)
  cross join lateral (
    select r.id,s.id as sid from probe r join build s on r.k=s.k
    where s.v>o.n offset 0
  ) j
$q$) as parameter_build_rebuild;

-- Parameterized build expressions remain native and still rebuild correctly.
select diamond_same_rows($q$
  select o.n,j.* from (values (0),(1),(2)) o(n)
  cross join lateral (
    select r.id,s.id as sid from probe r join build s on r.k=s.k+o.n offset 0
  ) j
$q$, 0) as parameter_expression_fallback;

-- Error unwinding while a cursor is live must release its query context.
-- The residual depends on both sides, so it cannot run before the join.
create function cancel_expansion(a int, b int) returns boolean
language plpgsql volatile as $$
begin
  raise exception 'cancel live expansion' using errcode = '57014';
end;
$$;
do $$
begin
  begin
    perform r.id from probe r join build s on r.k=s.k
      and cancel_expansion(r.x,s.v);
    raise exception 'expected cancellation';
  exception when query_canceled then
    null;
  end;
end;
$$;
select diamond_same_rows('select r.k,s.k as sk from probe r join build s on r.k=s.k') as usable_after_cancel;

-- One-to-one keys give an exact oracle across batch deferral and workers.
create table batch_data as
  select i as id, repeat('x',128) as payload from generate_series(1,20000) i;
alter table batch_data set (parallel_workers = 2);
analyze batch_data;
set local work_mem = '64kB';
set local hash_mem_multiplier = 1;
select p->>'Diamond Hash Probes' = '20000' as probes_once_per_batch,
       p->>'Diamond Successful Probes' = '20000' as successes,
       p->>'Diamond Build Matches' = '20000' as matches,
       p->>'Diamond Tuples Emitted' = '20000' as emitted,
       (p#>>'{Plans,1,Hash Batches}')::int > 1 as spilled,
       p->>'Diamond Lookup Expand' = 'true' as batch_cursor
from diamond_plan('select l.id,l.payload,r.payload from batch_data l join batch_data r using(id)') p;
select diamond_same_rows('select l.id,l.payload,r.payload as rp from batch_data l join batch_data r using(id)') as spilled_bag;
select diamond_same_rows($q$
  select o.n,j.* from (values (0),(1)) o(n)
  cross join lateral (
    select l.id,l.payload,r.payload as rp from batch_data l join batch_data r using(id)
    where l.id>o.n offset 0
  ) j
$q$) as spilled_rebuild_bag;

-- Native skew storage keeps the frequent probe key resident in batch zero.
-- Retain both wide payloads so the smaller batch_data is the build input.
create table skew_probe as
  select case when i<=20000 then 1 else i-20000 end as id,
         repeat('s',128) as payload from generate_series(1,40000) i;
analyze skew_probe;
select p->>'Diamond Lookup Expand' = 'true' as skew_cursor,
       p#>>'{Plans,0,Relation Name}' = 'skew_probe' as skew_probe_side,
       (p#>>'{Plans,1,Hash Batches}')::int > 1 as skew_batched,
       p->>'Diamond Build Matches' = '40000' as skew_matches
from diamond_plan('select l.id,l.payload,r.payload from skew_probe l join batch_data r using(id)') p;
select diamond_same_rows('select l.id,l.payload,r.payload as rp from skew_probe l join batch_data r using(id)') as skew_bag;

set local max_parallel_workers_per_gather = 2;
set local min_parallel_table_scan_size = 0;
set local parallel_setup_cost = 0;
set local parallel_tuple_cost = 0;
set local parallel_leader_participation = off;
set local enable_parallel_hash = off;
select p->>'Parallel Aware' = 'false' as private_hash,
       not (p ? 'Diamond Lookup Expand') as private_native_fallback,
       p->>'Diamond Hash Probes' = '20000' as worker_probes,
       p->>'Diamond Build Matches' = '20000' as worker_matches,
       p->>'Diamond Tuples Emitted' = '20000' as emitted
from diamond_plan('select count(*) from batch_data l join batch_data r using(id)') p;

set local enable_parallel_hash = on;
select p->>'Parallel Aware' = 'true' as shared_hash,
       not (p ? 'Diamond Lookup Expand') as shared_native_fallback,
       p->>'Diamond Hash Probes' = '20000' as worker_probes,
       p->>'Diamond Successful Probes' = '20000' as worker_successes,
       p->>'Diamond Build Matches' = '20000' as worker_matches,
       p->>'Diamond Tuples Emitted' = '20000' as emitted
from diamond_plan('select count(*) from batch_data l join batch_data r using(id)') p;

-- Pattern from join_hash: force Gather below a nested loop so workers are
-- relaunched.  A fresh worker's counters must add to its previous DSM slot.
create table rescan_outer as select generate_series(1,3) as id;
alter table rescan_outer set (parallel_workers = 0);
analyze rescan_outer;
select (p->>'Actual Loops')::int >= 3 as workers_rescanned,
       p->>'Diamond Hash Probes' = '60000' as relaunched_probes,
       p->>'Diamond Build Matches' = '60000' as relaunched_matches
from diamond_plan($q$
  select count(*) from rescan_outer o left join
    (select l.id from batch_data l join batch_data r using(id)) j
    on o.id<j.id+1 and o.id>j.id-1
$q$) p;

-- Phase 3: real plan/state nodes, preserving the same native bags.  The
-- existing comparator switches the two opt-in modes independently.
set local max_parallel_workers_per_gather = 0;
show diamond_independent_lookup_expand;
select label, diamond_same_rows(query, expected_pairs, true) as independent_bag
from (values
  ('duplicates', 'select r.k,s.k as sk,r.x+1 as x from probe r join build s on r.k=s.k', 1),
  ('residual', 'select r.id,s.id as sid from probe r join build s on r.k=s.k and r.x<s.v', 1),
  ('reject all', 'select r.id,s.id as sid from probe r join build s on r.k=s.k and r.x<s.v-100', 1),
  ('empty', 'select r.id from probe r join empty_build s on r.k=s.k', 1),
  ('no match', 'select r.id,s.id as sid from probe r join build s on r.k=s.id', 1),
  ('limit', 'select r.k,s.k as sk from probe r join build s on r.k=s.k limit 1', 1),
  ('text keys', 'select r.payload,s.payload as sp from text_probe r join text_build s using(k,n)', 1),
  ('collision', 'select r.k,s.k as sk from collisions r join collisions s using(k)', 1),
  ('unique', 'select r.id from probe r join unique_build s using(k)', 1),
  ('subplan fallback', 'select r.id,s.id as sid,(select max(x) from probe) as m from probe r join build s on r.k=s.k', 0),
  ('expression fallback', 'select r.id,s.id as sid from probe r join build s on r.k=s.k+1', 0),
  ('outer fallback', 'select r.id,s.id as sid from probe r full join build s on r.k=s.k', 0),
  ('semi fallback', 'select r.id from probe r where exists (select from build s where r.k=s.k)', 0),
  ('anti fallback', 'select r.id from probe r where not exists (select from build s where r.k=s.k)', 0)
) cases(label, query, expected_pairs);
select p->>'Node Type' as operator,
       case when p->>'Node Type' = 'Diamond Expand' then
         (p->>'Actual Rows')::numeric = 3 else
         (p->>'Actual Rows')::numeric =
           case when p#>>'{Plans,0,Alias}' = 'r' then 2 else 3 end
       end as correct_rows
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k') p;
select diamond_same_rows('select r.id,s.id as sid from probe r join build s on r.k=s.k and count_residual(r.x,s.v)', 1, true) as independent_volatile;
select last_value=12 as volatile_once_off_and_on from residual_calls;
select diamond_same_rows('select l.id,l.payload,r.payload as rp from batch_data l join batch_data r using(id)', 1, true) as independent_batches;
select diamond_same_rows('select l.id,l.payload,r.payload as rp from skew_probe l join batch_data r using(id)', 1, true) as independent_skew;
select diamond_same_rows($q$
  select o.n,j.* from (values (0),(10),(20)) o(n)
  cross join lateral (
    select r.id,s.id as sid from probe r join build s on r.k=s.k
    where s.v>o.n limit 1
  ) j
$q$, 1, true) as independent_partial_rebuild;
declare independent_forward no scroll cursor for
  select r.k,s.k as sk from probe r join build s on r.k=s.k;
fetch 1 from independent_forward;
fetch 1 from independent_forward;
fetch all from independent_forward;
close independent_forward;

-- Exercise generated copy/read support and EXPLAIN's deferred INNER_VAR map.
set local debug_copy_parse_plan_trees = on;
set local debug_write_read_parse_plan_trees = on;
select diamond_same_rows('select r.x,s.v from probe r join build s on r.k=s.k and r.x<s.v', 1, true) as plan_roundtrip;
set local debug_copy_parse_plan_trees = off;
set local debug_write_read_parse_plan_trees = off;

-- Both parallel hash flavors and forced Gather retain native plans.
set local max_parallel_workers_per_gather = 2;
set local enable_parallel_hash = off;
select bool_and(p->>'Node Type' = 'Hash Join') as independent_private_fallback
from diamond_plan('select count(*) from batch_data l join batch_data r using(id)') p;
set local enable_parallel_hash = on;
select bool_and(p->>'Node Type' = 'Hash Join') as independent_shared_fallback
from diamond_plan('select count(*) from batch_data l join batch_data r using(id)') p;
set local debug_parallel_query = on;
select bool_and(p->>'Node Type' = 'Hash Join') as independent_forced_fallback
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k') p;
set local debug_parallel_query = off;
set local max_parallel_workers_per_gather = 0;

-- The existing C regression module assembles a physical stack, not a query
-- rewrite or shipping optimizer rule.  L2 returns 11 heads before E1 emits
-- 33 S pairs; E2 then emits 66 rows with T's duplicate multiplicities.
\getenv libdir PG_LIBDIR
\getenv dlsuffix PG_DLSUFFIX
\set regresslib :libdir '/regress' :dlsuffix
create function test_deferred(query text, heads bigint, expanded bigint,
                             expire boolean default false,
                             spill boolean default false)
returns setof record as :'regresslib', 'test_diamond_deferred_plan'
language c strict;
select bool_and(p->>'Node Type' = 'Hash Join') as independent_lock_fallback
from diamond_plan('select r.id,s.id from probe r join build s on r.k=s.k for update of r') p;
select bool_and(p->>'Node Type' = 'Hash Join') as independent_update_fallback
from diamond_plan('update probe r set x=r.x from build s where r.k=s.k') p;
create table stack_head as select i as a,i as b from generate_series(1,200) i;
create table stack_s as select (i%40)+1 as a from generate_series(0,119) i;
create table stack_t as select (i%11)+20 as b from generate_series(0,21) i;
analyze stack_head, stack_s, stack_t;
set local join_collapse_limit = 1;
set local diamond_independent_lookup_expand = off;
create table stack_expected as
  select r.a,r.b,s.a as sa,t.b as tb from
    (stack_head r join stack_s s on r.a=s.a) join stack_t t on r.b=t.b;
set local diamond_independent_lookup_expand = on;
select diamond_same_rows($q$
  select r.a,r.b,s.a as sa,t.b as tb from
    (stack_head r join stack_s s on r.a=s.a) join stack_t t on r.b=t.b
$q$, 2, true) as adjacent_pairs_bag;
create table stack_observed as
  select * from test_deferred($q$
    select r.a,r.b,s.a as sa,t.b as tb from
      (stack_head r join stack_s s on r.a=s.a) join stack_t t on r.b=t.b
  $q$, 11, 33) as result(a int,b int,sa int,tb int);
select (select count(*) from stack_observed)=66 and not exists (
  (table stack_expected except all table stack_observed)
  union all
  (table stack_observed except all table stack_expected)
) as independently_deferred_bag;

-- An expired owner must fail before accessing borrowed tuples.  This also
-- exercises cleanup after an interrupted partially enumerated physical stack.
savepoint expired_stack;
select count(*) from test_deferred($q$
  select r.a,r.b,s.a as sa,t.b as tb from
    (stack_head r join stack_s s on r.a=s.a) join stack_t t on r.b=t.b
$q$, 11, 33, true) as result(a int,b int,sa int,tb int);
rollback to savepoint expired_stack;
select diamond_same_rows('select r.k,s.k as sk from probe r join build s on r.k=s.k', 1, true) as usable_after_expired_stack;

-- An invalid manually assembled stack must reject spilling deferred heads
-- before output; ordinary adjacent pairs still support native batching.
savepoint spilling_stack;
select count(*) from test_deferred($q$
  select r.a,r.b,s.a as sa,t.b as tb from
    (stack_head r join stack_s s on r.a=s.a) join stack_t t on r.b=t.b
$q$, 0, 0, false, true) as result(a int,b int,sa int,tb int);
rollback to savepoint spilling_stack;
-- Retained nested build: S heads cross the parent hash build while T stays
-- deferred. Text probe payloads, duplicates and NULLs survive input overwrite.
set local work_mem = '16MB';
set local hash_mem_multiplier = 1;
create function test_nested(query text, expire boolean default false,
                            spill boolean default false,
                            underestimate boolean default false)
returns setof record as :'regresslib', 'test_diamond_nested_plan'
language c strict;
create table nest_r as select i as a from generate_series(1,2000) i;
create table nest_s(a int,b int,payload text);
alter table nest_s alter column payload set storage plain;
insert into nest_s select (i%40)+1,(i%40)+1,repeat(md5(i::text),128)
  from generate_series(0,119) i;
insert into nest_s values (null,20,'null parent key'),(20,null,'null child key');
analyze nest_r, nest_s;
set local diamond_independent_lookup_expand = off;
create table nested_expected as
  select r.a,s.a as sa,s.b,s.payload,t.b as tb from nest_r r
  join (nest_s s join stack_t t on s.b=t.b) on r.a=s.a;
set local diamond_independent_lookup_expand = on;
create table nested_observed as select * from test_nested($q$
  select r.a,s.a as sa,s.b,s.payload,t.b as tb from nest_r r
  join (nest_s s join stack_t t on s.b=t.b) on r.a=s.a
$q$) as result(a int,sa int,b int,payload text,tb int);
select (select count(*) from nested_observed)=66 and not exists (
  (table nested_expected except all table nested_observed)
  union all
  (table nested_observed except all table nested_expected)
) as retained_nested_build_bag;
savepoint expired_nested;
select count(*) from test_nested($q$
  select r.a,s.a as sa,s.b,s.payload,t.b as tb from nest_r r
  join (nest_s s join stack_t t on s.b=t.b) on r.a=s.a
$q$, true) as result(a int,sa int,b int,payload text,tb int);
rollback to savepoint expired_nested;
savepoint spilling_nested;
select count(*) from test_nested($q$
  select r.a,s.a as sa,s.b,s.payload,t.b as tb from nest_r r
  join (nest_s s join stack_t t on s.b=t.b) on r.a=s.a
$q$, false, true) as result(a int,sa int,b int,payload text,tb int);
rollback to savepoint spilling_nested;
set local work_mem = '64kB';
savepoint memory_nested;
select count(*) from test_nested($q$
  select r.a,s.a as sa,s.b,s.payload,t.b as tb from nest_r r
  join (nest_s s join stack_t t on s.b=t.b) on r.a=s.a
$q$, false, false, true) as result(a int,sa int,b int,payload text,tb int);
rollback to savepoint memory_nested;
set local work_mem = '16MB';
select count(*)=66 as usable_after_nested_errors from test_nested($q$
  select r.a,s.a as sa,s.b,s.payload,t.b as tb from nest_r r
  join (nest_s s join stack_t t on s.b=t.b) on r.a=s.a
$q$) as result(a int,sa int,b int,payload text,tb int);
-- Automatic alternatives use normal native methods and compare fully
-- expanded outputs. The opt-in adds candidates; cheap native plans still win.
set local diamond_independent_lookup_expand = off;
set local diamond_lookup_expand = off;
set local enable_nestloop = on;
set local enable_mergejoin = on;
set local join_collapse_limit = 8;
set local work_mem = '16MB';
create function auto_same_rows(query text, expected_pairs int)
returns boolean language plpgsql as $$
declare
  wrappers int;
  lookups int;
  expands int;
  same_rows boolean;
begin
  perform set_config('diamond_acyclic','off',true);
  execute 'create table auto_native_rows as ' || query;
  perform set_config('diamond_acyclic','on',true);
  select count(*) filter (where p->>'Node Type'='Diamond Join'
                              and (p->>'Actual Loops')::int>0
                              and p->>'Diamond Runtime Fallback'='false'),
         count(*) filter (where p->>'Node Type'='Diamond Lookup'
                              and (p->>'Actual Loops')::int>0),
         count(*) filter (where p->>'Node Type'='Diamond Expand'
                              and (p->>'Actual Loops')::int>0)
  into wrappers,lookups,expands
  from diamond_plan('create table auto_diamond_rows as ' || query) p;
  select not exists (
    (table auto_native_rows except all table auto_diamond_rows)
    union all
    (table auto_diamond_rows except all table auto_native_rows)
  ) into same_rows;
  drop table auto_native_rows,auto_diamond_rows;
  return same_rows and wrappers=(expected_pairs>0)::int
         and lookups=expected_pairs and expands=expected_pairs;
end;
$$;
create table auto_root as select i%2 as a,i%2 as b from generate_series(1,400) i;
create table auto_s as select i%2 as a from generate_series(1,40) i;
create table auto_t as select i%2 as b from generate_series(1,40) i;
analyze auto_root,auto_s,auto_t;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)',2) as automatic_star;
-- One equality class, despite three textual edges: not a genuine cycle.
-- This ordered-join diagnostic exposes the alternative to native pruning;
-- it is a classification test, not a performance comparison.
set local join_collapse_limit=1;
select auto_same_rows('select r.a,s.a as sa,t.a as ta from (auto_root r join auto_s s on r.a=s.a) join auto_s t on s.a=t.a and r.a=t.a',2) as redundant_equality_triangle;
set local join_collapse_limit=8;
create table auto_a as select i%2 as a from generate_series(1,400) i;
create table auto_b as select i%2 as a,i%2 as b from generate_series(1,40) i;
create table auto_c as select i%2 as b,i%2 as c from generate_series(1,40) i;
create table auto_d as select i%2 as c from generate_series(1,40) i;
analyze auto_a,auto_b,auto_c,auto_d;
select auto_same_rows('select a,b,c from auto_a join auto_b using(a) join auto_c using(b) join auto_d using(c)',3) as automatic_nested_chain;
create table auto_h as select i%2 as a,i%2 as b,i%2 as c from generate_series(1,40) i;
create table auto_l as select i%2 as a from generate_series(1,20) i;
create table auto_m as select i%2 as b from generate_series(1,20) i;
create table auto_n as select i%2 as c from generate_series(1,20) i;
analyze auto_h,auto_l,auto_m,auto_n;
select auto_same_rows('select a,b,c from auto_h join auto_l using(a) join auto_m using(b) join auto_n using(c)',3) as automatic_branch;
-- Diamond's memo is independent of PostgreSQL's native join-search method.
-- Force only selects an already eligible resident candidate after GEQO.
set local geqo=on;
set local geqo_threshold=3;
set local diamond_acyclic_force=on;
select auto_same_rows('select a,b,c from auto_a join auto_b using(a) join auto_c using(b) join auto_d using(c)',3) as automatic_geqo_chain;
set local diamond_acyclic_force=off;
set local geqo_threshold=12;
-- Genuine cycle and unsupported expression/residual dependencies stay native.
select auto_same_rows('select x.a,x.b,y.c from auto_b x join auto_c y on x.b=y.b join auto_h z on y.c=z.c and x.a=z.a',0) as genuine_cycle_native;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_s s on r.a+1=s.a join auto_t t on r.b=t.b',0) as expression_key_native;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b) where s.a<t.b',0) as cross_residual_native;
create table auto_small as select i as a,i as b from generate_series(1,4) i;
analyze auto_small;
select auto_same_rows('select x.a from auto_small x join auto_small y on x.a=y.a join auto_small z on x.b=z.b',0) as cheap_native_wins;
-- Copy/read and whole-plan rescan exercise an actually cost-selected plan.
create function test_automatic(query text, fallback boolean default false,
                               low_memory boolean default false)
returns setof record as :'regresslib', 'test_diamond_automatic_plan'
language c strict;
create table auto_roundtrip as select * from test_automatic($q$
  select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)
$q$) as result(a int,sa int,b int);
create table auto_fallback as select * from test_automatic($q$
  select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)
$q$,true) as result(a int,sa int,b int);
select (select count(*) from auto_fallback)=160000 and not exists (
  (table auto_roundtrip except all table auto_fallback)
  union all
  (table auto_fallback except all table auto_roundtrip)
) as automatic_copy_rescan_native_fallback;
-- Native path pruning may remove the pure heap/hash shape. Independent
-- scan construction and fallback must still admit safe indexed SQL tuples.
create function auto_scan_kind(query text, kind text)
returns boolean language plpgsql as $$
declare p jsonb; ok boolean;
begin
  execute 'explain (analyze,format json) ' || query into p;
  with recursive nodes(n) as (
    select p->0->'Plan'
    union all
    select c from nodes, lateral jsonb_array_elements(n->'Plans') c
  )
  select bool_or(n->>'Node Type'='Diamond Join'
                  and n->>'Diamond Runtime Fallback'='false')
     and bool_or(n->>'Node Type'=kind and (n->>'Actual Loops')::int>0)
    into ok from nodes;
  return ok;
end;
$$;
create table auto_index_root as
  select i as id,i%2 as a,i%2 as b from generate_series(1,100000) i;
create table auto_index_leaf as
  select i as id,i%2 as a from generate_series(1,100000) i;
create index on auto_index_root(id);
create index on auto_index_leaf(id);
analyze auto_index_root,auto_index_leaf;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_index_leaf s using(a) join auto_t t using(b) where s.id<=40',2) as automatic_index_build_bag;
select auto_scan_kind('select r.a,s.a as sa,t.b from auto_index_root r join auto_s s using(a) join auto_t t using(b) where r.id<=400','Index Scan') as automatic_index_probe;
create table auto_index_fallback as select * from test_automatic($q$
  select r.a,s.a as sa,t.b from auto_index_root r
  join auto_s s using(a) join auto_t t using(b) where r.id<=400
$q$,true) as result(a int,sa int,b int);
set local diamond_acyclic=off;
select (select count(*) from auto_index_fallback)=160000 and not exists (
  (select r.a,s.a as sa,t.b from auto_index_root r join auto_s s using(a)
   join auto_t t using(b) where r.id<=400 except all table auto_index_fallback)
  union all
  (table auto_index_fallback except all
   select r.a,s.a as sa,t.b from auto_index_root r join auto_s s using(a)
   join auto_t t using(b) where r.id<=400)
) as automatic_index_copy_rescan_fallback;
set local diamond_acyclic=on;
drop index auto_index_root_id_idx;
create index on auto_index_root(id) include(a,b);
select auto_same_rows('select r.a,s.a as sa,t.b from auto_index_root r join auto_s s using(a) join auto_t t using(b) where r.id<=400',2) as automatic_index_only_bag;
select auto_scan_kind('select r.a,s.a as sa,t.b from auto_index_root r join auto_s s using(a) join auto_t t using(b) where r.id<=400','Index Only Scan') as automatic_index_only_probe;
create table auto_bitmap_root as select (i*7919::bigint)%100003 as id,
  i%2 as a,i%2 as b from generate_series(1,100000) i;
create index on auto_bitmap_root(id);
analyze auto_bitmap_root;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_bitmap_root r join auto_s s using(a) join auto_t t using(b) where r.id<=400',2) as automatic_bitmap_bag;
select auto_scan_kind('select r.a,s.a as sa,t.b from auto_bitmap_root r join auto_s s using(a) join auto_t t using(b) where r.id<=400','Bitmap Heap Scan') as automatic_bitmap_probe;
insert into auto_root values (null,0),(0,null);
insert into auto_s values (null);
insert into auto_t values (null);
analyze auto_root,auto_s,auto_t;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)',2) as automatic_null_duplicate_bag;
create table auto_text_root as select 'k'||(i%2)::text as k,i%2 as n from generate_series(1,400) i;
create table auto_text_leaf as select 'k'||(i%2)::text as k,i%2 as n from generate_series(1,40) i;
analyze auto_text_root,auto_text_leaf;
select auto_same_rows('select r.k,s.n,t.k as tk from auto_text_root r join auto_text_leaf s on r.k=s.k and r.n=s.n join auto_text_leaf t on r.k=t.k and r.n=t.n',2) as automatic_text_multiple_keys;
-- The final projection may depend on both sides and use immutable expressions.
select auto_same_rows('select r.a+s.a as sum,t.b*2 as projected from auto_root r join auto_s s using(a) join auto_t t using(b) where r.a>=0',2) as automatic_projection_filter;
set local plan_cache_mode=force_generic_plan;
set local diamond_acyclic=on;
prepare automatic_cached(int) as
  select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)
  where r.a >= $1;
create table automatic_cache_plan as select p->>'Node Type' as kind
  from diamond_plan('execute automatic_cached(0)',false) p;
select exists(select from automatic_cache_plan where kind='Diamond Join') as automatic_cache_selected;
set local diamond_acyclic=off;
select not exists (
  (table automatic_cache_plan except all
   select p->>'Node Type' from diamond_plan('execute automatic_cached(0)',false) p)
  union all
  (select p->>'Node Type' from diamond_plan('execute automatic_cached(0)',false) p
   except all table automatic_cache_plan)
) as automatic_cached_plan_stable;
create table automatic_param0 as execute automatic_cached(0);
create table automatic_param1 as execute automatic_cached(1);
select (select count(*) from automatic_param0)=160000
   and (select count(*) from automatic_param1)=80000 as automatic_parameters;
deallocate automatic_cached;
set local diamond_acyclic=on;
-- A live automatically selected iterator must survive cursor shutdown, and
-- a real timer cancellation must propagate rather than choosing fallback.
set local cursor_tuple_fraction=1.0;
declare automatic_forward no scroll cursor for
  select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b);
move forward 1 from automatic_forward;
move forward 1 from automatic_forward;
move all from automatic_forward;
close automatic_forward;
savepoint automatic_cancel;
declare automatic_cancel_cursor no scroll cursor for
  select a,b,c from auto_a join auto_b using(a) join auto_c using(b) join auto_d using(c);
move forward 1 from automatic_cancel_cursor;
set local statement_timeout='1ms';
move all from automatic_cancel_cursor;
rollback to savepoint automatic_cancel;
set local statement_timeout=0;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)',2) as automatic_usable_after_cancel;
-- Runtime allocation, not just an estimate, can trigger the retained native
-- branch. The C fixture plans at16MiB then executes the cached shape at64KiB.
create table auto_memory_fallback as select * from test_automatic($q$
  select a,b,c from auto_a join auto_b using(a) join auto_c using(b) join auto_d using(c)
$q$,false,true) as result(a int,b int,c int);
set local diamond_acyclic=off;
select not exists (
  (select a,b,c from auto_a join auto_b using(a) join auto_c using(b) join auto_d using(c)
   except all table auto_memory_fallback)
  union all
  (table auto_memory_fallback except all
   select a,b,c from auto_a join auto_b using(a) join auto_c using(b) join auto_d using(c))
) as automatic_actual_memory_native_bag;
-- Cost forcing is diagnostic only and still requires an eligible plan.
set local diamond_acyclic=on;
set local diamond_acyclic_force=on;
select exists (
  select from diamond_plan(
    'select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)',
    false) p
  where p->>'Node Type'='Diamond Join'
    and (p->>'Diamond Forced')::boolean
    and (p->>'Diamond Estimated Total Cost')::numeric > 0
) as automatic_force_reports_estimate;
select auto_same_rows('select r.a,s.a as sa,t.b from auto_root r join auto_s s using(a) join auto_t t using(b)',2) as automatic_force_bag;
set local diamond_acyclic_force=off;
rollback;
