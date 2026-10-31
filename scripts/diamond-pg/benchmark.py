#!/usr/bin/env python3
"""Compare native and automatic Diamond plans in the preserved .work datasets.

Use TESTING.md for optimized build, database loading and identical settings.
Raw results/checkpoints stay ignored under .work; this script never changes
schema or source. Optional suite names: tpch, job, paper (default: all).
"""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

w = Path(__file__).resolve().parent / '.work'
out = w / 'bench-auto-opt'
out.mkdir(exist_ok=True)
env = os.environ.copy()
env['LD_LIBRARY_PATH'] = str(w/'tools/usr/lib/x86_64-linux-gnu')
psql = [str(w/'install-opt/bin/psql'), '-X', '-qAt', '-v', 'ON_ERROR_STOP=1',
        '-h', str(w/'s'), '-p', '55434']
setup = """BEGIN; SET LOCAL statement_timeout='30s'; SET LOCAL jit=off;
SET LOCAL diamond_hashjoin_stats=off; SET LOCAL diamond_lookup_expand=off;
SET LOCAL diamond_independent_lookup_expand=off; SET LOCAL work_mem='64MB';
SET LOCAL hash_mem_multiplier=2; SET LOCAL max_parallel_workers_per_gather=2;
SET LOCAL enable_hashjoin=on; SET LOCAL enable_mergejoin=on; SET LOCAL enable_nestloop=on;
"""

def execute(db, query, mode, explain=False, q15=False):
    """Use identical transactions/settings; Q15 keeps its view setup/cleanup."""
    if explain:
        if q15:
            prefix, body = query.split(';', 1)
            select, suffix = body.rsplit(';', 2)[:2]
            query = prefix + '; EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + select + ';' + suffix + ';'
        else:
            query = 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + query
    start = time.monotonic()
    timeout = 120 if db == 'diamond_micro' else 30
    settings = setup.replace("statement_timeout='30s'",
                             f"statement_timeout='{timeout}s'")
    p = subprocess.run(psql+['-d',db],input=settings+'SET LOCAL diamond_acyclic='+mode+';\n'+query.rstrip(';\n ')+'; COMMIT;',
                       env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout+10)
    elapsed = time.monotonic()-start
    if p.returncode:
        raise RuntimeError(p.stderr.strip())
    return p.stdout, elapsed

def walk(node):
    yield node
    for child in node.get('Plans',[]):
        yield from walk(child)

def checkpoint(path, data):
    # Preserve a complete summary even if the cloud session stops mid-suite.
    tmp=path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data,indent=2))
    tmp.replace(path)

def run_suite(name, db, queries):
    """Verify bags, then alternate modes and retain every raw measured plan.

    A failed mode remains visible and is not retried as a timing success.
    Partial/unverified pairs have no reported speedup ratio.
    """
    dest=out/name
    dest.mkdir(exist_ok=True)
    timeout = 120 if name == 'paper-acyclic' else 30
    summary = {
        'suite': name, 'database': db,
        'method': ('native/automatic, identical optimized build and settings; '
                   'one bag-check warmup per mode; three interleaved '
                   f'EXPLAIN ANALYZE repetitions; medians; {timeout}s per query'),
        'results': [],
    }
    started=time.monotonic()
    for number,path in enumerate(queries):
        text=path.read_text()
        q15=name=='tpch-sf1' and path.stem=='15'
        row={'query':path.stem,'measurements':{'off':[],'on':[]},'errors':{}}
        bags={}
        order=['off','on'] if number%2==0 else ['on','off']
        for mode in order:
            try:
                data,wall=execute(db,text,mode,q15=q15)
                (dest/f'{path.stem}-{mode}-result.txt').write_text(data)
                bags[mode]=sorted(data.splitlines())
                if name=='paper-acyclic' and bags[mode]!=['1|1|1|1']:
                    raise RuntimeError('Paper expected tuple (1,1,1,1) differs')
                row.setdefault('warmup_wall_seconds',{})[mode]=wall
            except (RuntimeError,subprocess.TimeoutExpired) as e:
                row['errors'][mode]=str(e)
        if len(bags)==2:
            row['same_rows']=bags['off']==bags['on']
            row['result_hashes']={m:hashlib.sha256('\n'.join(b).encode()).hexdigest() for m,b in bags.items()}
            if not row['same_rows']:
                row['errors']['correctness']='Result bags differ; no timings accepted'
        # A surviving mode may still be measured after its peer times out.
        if row.get('same_rows',True):
            for rep in range(3):
                for mode in (order if rep%2==0 else list(reversed(order))):
                    if mode in row['errors']:
                        continue
                    try:
                        data,wall=execute(db,text,mode,True,q15)
                        (dest/f'{path.stem}-{mode}-{rep}.json').write_text(data)
                        plan=json.loads(data)[0]
                        nodes=list(walk(plan['Plan']))
                        row['measurements'][mode].append({
                            'planning_ms':plan['Planning Time'],'execution_ms':plan['Execution Time'],
                            'wall_seconds':wall,
                            'selected_diamond_regions':sum(n['Node Type']=='Diamond Join' for n in nodes),
                            'runtime_native_fallback':any(n.get('Diamond Runtime Fallback',False) for n in nodes),
                            'executed_lookups':sum(n['Node Type']=='Diamond Lookup' and n.get('Actual Loops',0)>0 for n in nodes),
                            'executed_expands':sum(n['Node Type']=='Diamond Expand' and n.get('Actual Loops',0)>0 for n in nodes),
                            'root_temp_read_blocks':plan['Plan'].get('Temp Read Blocks',0),
                            'root_temp_written_blocks':plan['Plan'].get('Temp Written Blocks',0),
                            'operators': [
                                {k: v for k, v in n.items() if k in [
                                    'Node Type', 'Actual Rows', 'Actual Loops',
                                    'Hash Batches', 'Original Hash Batches',
                                    'Peak Memory Usage', 'Sort Space Used',
                                    'Sort Space Type', 'Temp Read Blocks',
                                    'Temp Written Blocks',
                                    'Diamond Estimated Live Bytes',
                                ]} for n in nodes
                            ]})
                    except (RuntimeError,subprocess.TimeoutExpired,ValueError) as e:
                        row['errors'][mode]=str(e)
        row['median_execution_ms']={m:statistics.median(x['execution_ms'] for x in samples)
                                    for m,samples in row['measurements'].items() if len(samples)==3}
        if row.get('same_rows') and len(row['median_execution_ms'])==2:
            row['ratio_native_over_automatic']=row['median_execution_ms']['off']/row['median_execution_ms']['on']
        summary['results'].append(row)
        summary['elapsed_seconds']=time.monotonic()-started
        checkpoint(dest/'summary.json',summary)
        print(name,path.stem,'verified',row.get('same_rows'),'medians',row['median_execution_ms'],'errors',row['errors'],flush=True)
    return summary

if __name__=='__main__':
    suites=sys.argv[1:] or ['tpch','job','paper']
    if 'tpch' in suites:
        paths=sorted((w/'tpch-queries').glob('*.sql'))
        if len(paths)!=22:raise RuntimeError('Expected all22 TPC-H queries')
        run_suite('tpch-sf1','tpch_sf1',paths)
    if 'job' in suites:
        paths=sorted(p for p in (w/'job').glob('*.sql') if p.stem[0].isdigit())
        if len(paths)!=113:raise RuntimeError(f'Expected all113 JOB queries, got {len(paths)}')
        run_suite('job-standard','job_cloud',paths)

    if 'paper' in suites:
        run_suite('paper-acyclic','diamond_micro',sorted((w/'paper-acyclic-queries').glob('*.sql')))
