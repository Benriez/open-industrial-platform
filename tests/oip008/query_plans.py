#!/usr/bin/env python3
"""Read-only SQL plans/timing on the actual four-source acceptance database."""
import json,pathlib,subprocess,time
root=pathlib.Path(__file__).resolve().parents[2];report=json.loads((root/'target/oip008-e2e/report.json').read_text());db=pathlib.Path(report['runtime_directory'])/'core.sqlite';cli='/opt/homebrew/opt/sqlite/bin/sqlite3'
queries={
 'organization_infrastructures':"SELECT id FROM infrastructures WHERE organization_id='org-a' ORDER BY id LIMIT 100",
 'infrastructure_sites':"SELECT id FROM sites WHERE infrastructure_id='infra-a1' ORDER BY id LIMIT 100",
 'site_sources':"SELECT source_id FROM source_placements WHERE site_id='site-a1' ORDER BY source_id LIMIT 100",
 'device_lookup':"SELECT source_id FROM source_placements WHERE device_id='device-a'",
 'latest_observation':"SELECT payload_json FROM observations WHERE entity_id='M-01' AND data_source_id='source-a' AND metric_id='temperature' ORDER BY source_ts_ms DESC LIMIT 1",
 'control_events':"SELECT e.event_key FROM control_event_index i JOIN collection_events e ON e.event_key=i.event_key WHERE i.source_id='source-a' AND i.sequence>0 ORDER BY i.sequence LIMIT 100",
}
rows=[]
for name,query in queries.items():
 plan=json.loads(subprocess.check_output([cli,'-readonly','-json','-cmd','.explain off',str(db),'EXPLAIN QUERY PLAN '+query],text=True));assert any('INDEX' in r['detail'] for r in plan),plan
 assert not any('SCAN observations' in r['detail'] or 'SCAN collection_events' in r['detail'] for r in plan),plan
 script='.output /dev/null\n'+(query+';\n')*100;begin=time.perf_counter();subprocess.run([cli,'-readonly',str(db)],input=script,text=True,check=True,stdout=subprocess.DEVNULL);elapsed=(time.perf_counter()-begin)*1000
 rows.append(dict(name=name,plan=plan,selects=100,cli_startup_plus_100_queries_ms=elapsed))
result={'status':'PASS','database':str(db),'method':'SQLite CLI 100 SELECTs per process, includes CLI startup; no isolated per-query latency claim','results':rows,'note':'Small local four-source/two-organization database; no scale or SLA guarantee.'};(root/'target/oip008-e2e/query-plans.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
