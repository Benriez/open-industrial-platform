#!/usr/bin/env python3
"""Synthetic storage benchmark, explicitly fixtures, never live/operator data. No SLA claim."""
import json,pathlib,subprocess,time,statistics,os
R=pathlib.Path(__file__).resolve().parents[2];OUT=R/'target/oip0082-performance';OUT.mkdir(exist_ok=True);DB=OUT/('fixture-'+str(os.getpid())+'.sqlite');SQL='/opt/homebrew/opt/sqlite/bin/sqlite3'
assert not DB.exists(),'Use a fresh output directory; no overwrite'
def sql(q):return subprocess.check_output([SQL,'-cmd','.explain off','-json',DB,q],text=True)
# SQLite CLI is >=3.37; use exact committed migrations through the operator bootstrap.
plan=R/'examples/multi-infrastructure-plan.json';config=json.loads((R/'examples/multi-infrastructure-core.json').read_text());config['database']=str(DB);config['web_dir']=None
(OUT/'core.json').write_text(json.dumps(config));subprocess.run([R/'target/debug/oip-server','--config',OUT/'core.json','--provision',plan],check=True,capture_output=True)
# Provisioning intentionally stops at schema3. Apply exact new query DDL only to
# this disposable benchmark fixture; migration correctness is tested separately.
new_ddl=(R/'crates/oip-storage/src/history.rs').read_text().split('r#"',1)[1].split('"#',1)[0]
sql(new_ddl)
# Fixed fixture IDs/payloads are intentionally distinguishable from measured events.
sql("BEGIN; WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<100000) INSERT INTO collection_events(event_key,data_source_id,origin_class,kind,at_ms,payload_json) SELECT printf('%064x',x),'source-a','simulation','connection_lost',1000+x/5,json_object('ConnectionLost',json_object('at',1000+x/5,'reason','synthetic benchmark fixture')) FROM n; COMMIT;")
queries={
 'source_time':"SELECT event_key,at_ms,payload_json FROM collection_events WHERE data_source_id='source-a' AND at_ms BETWEEN 19000 AND 21000 AND (at_ms,event_key)>(19500,'') ORDER BY at_ms,event_key LIMIT 101",
 'kind_time':"SELECT event_key,at_ms FROM collection_events WHERE data_source_id='source-a' AND kind='connection_lost' AND at_ms BETWEEN 19000 AND 21000 ORDER BY at_ms,event_key LIMIT 101",
 'event_detail':"SELECT event_key,payload_json FROM collection_events WHERE event_key=printf('%064x',50000) AND data_source_id='source-a'",
 'internal_watermark':"SELECT max(rowid) FROM collection_events",
 'source_parent':"SELECT s.source_id FROM source_placements s JOIN sites p ON s.site_id=p.id JOIN infrastructures i ON p.infrastructure_id=i.id WHERE i.organization_id='org-a'",
}
results={}
for name,q in queries.items():
 plan=json.loads(sql('EXPLAIN QUERY PLAN '+q));samples=[]
 for _ in range(60):
  start=time.perf_counter();value=sql(q);samples.append((time.perf_counter()-start)*1000)
 results[name]={'query':q,'plan':plan,'p50_ms_including_cli':round(statistics.median(samples),3),'p95_ms_including_cli':round(sorted(samples)[56],3),'rows':len(json.loads(value))}
assert 'history_events' in json.dumps(results['source_time']['plan'])
assert 'history_events_kind' in json.dumps(results['kind_time']['plan'])
assert json.loads(sql('pragma integrity_check'))[0]['integrity_check']=='ok'
report={'status':'PASS','fixture_events':100000,'method':'60 local SQLite CLI invocations/query, cold process overhead included, synthetic history, separate database; not application latency or production SLA','results':results}
(OUT/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
