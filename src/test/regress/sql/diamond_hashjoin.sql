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
    select node from nodes where node->>'Node Type' = 'Hash Join';
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
create function diamond_same_rows(query text, expected_joins int default 1)
returns boolean language plpgsql as $$
declare
  enabled_joins int;
  same_rows boolean;
begin
  perform set_config('diamond_lookup_expand', 'off', true);
  execute 'create table native_rows as ' || query;
  perform set_config('diamond_lookup_expand', 'on', true);
  select count(*) filter (where p->>'Diamond Lookup Expand' = 'true')
    into enabled_joins
    from diamond_plan('create table diamond_rows as ' || query) p;
  select not exists (
    (table native_rows except all table diamond_rows)
    union all
    (table diamond_rows except all table native_rows)
  ) into same_rows;
  drop table native_rows, diamond_rows;
  return same_rows and enabled_joins = expected_joins;
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

rollback;
