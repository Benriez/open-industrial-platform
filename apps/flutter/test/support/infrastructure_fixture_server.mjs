#!/usr/bin/env node
// OIP-009 UI contract fixture harness. No Core credentials, no real inventory,
// no anonymous tenant fallback and no production authorization claim.
import {createServer} from 'node:http';
import {createReadStream} from 'node:fs';
import {readFile, stat} from 'node:fs/promises';
import {extname, normalize, resolve, sep} from 'node:path';

const port = Number(process.env.PORT ?? 18950);
const webRoot = resolve(process.env.OIP_WEB_ROOT ?? 'build/web');
const fixtureRoot = resolve(process.env.OIP_INFRASTRUCTURE_FIXTURES ?? 'test/fixtures/infrastructure');
const load = async name => JSON.parse(await readFile(resolve(fixtureRoot, name), 'utf8'));
const full = {
  organizations: await load('organizations.json'),
  infrastructures: await load('infrastructures.json'),
  sites: await load('sites.json'),
  snapshot: await load('snapshot.json'),
  inventory: await load('inventory.json'),
  findings: await load('findings.json'),
  events: await load('events-history.json'),
};
let restricted = false;
const streams = new Set();

function data() {
  if (!restricted) return full;
  const locations = full.snapshot.locations.filter(item => item.infrastructure_id === 'infra-a1');
  const sourceIds = new Set(locations.map(item => item.source_id));
  const inventory = full.inventory.items.filter(item => item.infrastructure_id === 'infra-a1');
  const deviceIds = new Set(inventory.map(item => item.record.device.id));
  const snapshot = {
    ...full.snapshot,
    locations,
    sources: full.snapshot.sources.filter(item => sourceIds.has(item.id)),
    devices: full.snapshot.devices.filter(item => deviceIds.has(item.id)),
    observations: full.snapshot.observations.filter(item => sourceIds.has(item.data_source_id)),
    events: full.snapshot.events.filter(item => sourceIds.has(item.context.data_source_id)),
  };
  const findings = {
    ...full.findings,
    items: full.findings.items.filter(item => item.record.evidence.some(e => sourceIds.has(e.source))),
  };
  const events = {
    ...full.events,
    items: full.events.items.filter(item => sourceIds.has(item.record.source)),
  };
  return {
    organizations: {...full.organizations, items: full.organizations.items.filter(item => item.id === 'org-a')},
    infrastructures: {...full.infrastructures, items: full.infrastructures.items.filter(item => item.id === 'infra-a1')},
    sites: {...full.sites, items: full.sites.items.filter(item => item.infrastructure_id === 'infra-a1')},
    snapshot,
    inventory: {...full.inventory, items: inventory},
    findings,
    events,
  };
}

function headers(res, json = true) {
  res.setHeader('cache-control', 'no-store');
  res.setHeader('x-oip-contract-fixture', 'oip-009-contract-fixture');
  res.setHeader('x-oip-contract-principal', restricted ? 'fixture-restricted' : 'fixture-operator');
  if (json) res.setHeader('content-type', 'application/json; charset=utf-8');
}
function send(res, body, status = 200) {
  headers(res);
  res.statusCode = status;
  res.end(JSON.stringify(body));
}
function denied(res, status = 403, code = 'PERMISSION_DENIED') {
  send(res, {ok: false, code, message: 'Fixture boundary'}, status);
}
function matches(item, query) {
  if (query.organization && item.organization_id !== query.organization) return false;
  if (query.infrastructure && item.infrastructure_id !== query.infrastructure) return false;
  if (query.site && item.site_id !== query.site) return false;
  if (query.source && !(item.sources ?? []).includes(query.source)) return false;
  return true;
}
function locationMatches(location, query) {
  return (!query.organization || location.organization_id === query.organization) &&
    (!query.infrastructure || location.infrastructure_id === query.infrastructure) &&
    (!query.site || location.site_id === query.site) &&
    (!query.source || location.source_id === query.source);
}
function paged(items, url, cursorBased = false) {
  const limit = Math.min(100, Math.max(1, Number(url.searchParams.get('limit') ?? 100)));
  const offset = cursorBased
    ? Number.parseInt(url.searchParams.get('cursor') ?? '0', 16) || 0
    : Number(url.searchParams.get('offset') ?? 0);
  const batch = items.slice(offset, offset + limit);
  if (cursorBased) {
    const more = offset + batch.length < items.length;
    return {items: batch, truncated: more, next_cursor: more ? (offset + limit).toString(16).padStart(64, '0') : null,
      missing_evidence: [], time_semantics: 'event_time'};
  }
  return {items: batch, offset, limit, has_more: offset + batch.length < items.length};
}

const contentTypes = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.ttf': 'font/ttf', '.otf': 'font/otf',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
};
async function serveStatic(res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  let file = normalize(resolve(webRoot, `.${rel}`));
  if (file !== webRoot && !file.startsWith(`${webRoot}${sep}`)) return denied(res, 403, 'LOCAL_ONLY');
  let info = await stat(file).catch(() => null);
  if (!info?.isFile() && !extname(file)) {
    file = resolve(webRoot, 'index.html');
    info = await stat(file).catch(() => null);
  }
  if (!info?.isFile()) return denied(res, 404, 'NOT_FOUND');
  res.statusCode = 200;
  res.setHeader('content-type', contentTypes[extname(file)] ?? 'application/octet-stream');
  res.setHeader('cache-control', 'no-store');
  createReadStream(file).pipe(res);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    const query = Object.fromEntries(url.searchParams.entries());
    if (url.pathname === '/__fixture/revoke' && req.method === 'POST') {
      restricted = true;
      for (const stream of streams) stream.end();
      streams.clear();
      return send(res, {restricted: true, fixture_only: true});
    }
    if (url.pathname === '/__fixture/restore' && req.method === 'POST') {
      restricted = false;
      for (const stream of streams) stream.end();
      streams.clear();
      return send(res, {restricted: false, fixture_only: true});
    }
    if (url.pathname === '/__fixture/reconnect' && req.method === 'POST') {
      for (const stream of streams) stream.end();
      streams.clear();
      return send(res, {reconnect: true, fixture_only: true});
    }
    if (url.pathname === '/__fixture/state') {
      return send(res, {restricted, fixture_only: true, secured_browser_e2e: false});
    }
    if (url.pathname.startsWith('/api/v1/')) return denied(res);
    const current = data();
    if (url.pathname === '/api/v2/organizations' || url.pathname === '/api/v2/infrastructures' || url.pathname === '/api/v2/sites') {
      const key = url.pathname.split('/').at(-1);
      return send(res, current[key]);
    }
    if (url.pathname === '/api/v2/snapshot') return send(res, current.snapshot);
    if (url.pathname === '/api/v2/inventory/devices') {
      let items = current.inventory.items.filter(item => matches(item, query));
      if (query.id) items = items.filter(item => item.record.device.id === query.id);
      if (query.q) items = items.filter(item => `${item.record.device.display_name} ${item.record.device.id}`.toLowerCase().includes(query.q.toLowerCase()));
      const page = paged(items, url);
      return send(res, {...page, status: items.length ? 'Devices registered' : 'No devices registered', management_channel: 'offline_requires_restart'});
    }
    if (url.pathname === '/api/v2/sources') {
      const allowed = current.snapshot.locations.filter(item => locationMatches(item, query)).map(item => item.source_id);
      const items = current.snapshot.sources.filter(item => allowed.includes(item.id));
      return send(res, paged(items, url).items);
    }
    if (url.pathname === '/api/v2/events/history') {
      const allowed = current.snapshot.locations.filter(item => locationMatches(item, query)).map(item => item.source_id);
      const items = current.events.items.filter(item => allowed.includes(item.record.source));
      return send(res, paged(items, url, true));
    }
    if (url.pathname === '/api/v2/diagnostics/findings') {
      const allowed = current.snapshot.locations.filter(item => locationMatches(item, query)).map(item => item.source_id);
      const items = current.findings.items.filter(item => item.record.evidence.some(e => allowed.includes(e.source)));
      return send(res, paged(items, url, true));
    }
    if (url.pathname.startsWith('/api/v2/devices/')) {
      const id = decodeURIComponent(url.pathname.split('/').at(-1));
      const device = current.snapshot.devices.find(item => item.id === id);
      if (!device) return denied(res, 404, 'RESOURCE_NOT_ACCESSIBLE');
      return send(res, {device, metrics: current.snapshot.observations.filter(item => item.entity_id === id && item.data_source_id === device.data_source_id)});
    }
    if (url.pathname === '/api/v2/opcua/nodes') {
      const source = query.source;
      if (!source) return denied(res, 400, 'SOURCE_REQUIRED');
      const location = current.snapshot.locations.find(item => item.source_id === source);
      if (!location || !locationMatches(location, query)) return denied(res, 404, 'RESOURCE_NOT_ACCESSIBLE');
      const observations = current.snapshot.observations.filter(item => item.data_source_id === source);
      const items = observations.map(item => ({node_id: `ns=2;s=${item.metric_id}`, name: item.metric_id, folder: item.entity_id, data_type: 'Double', access: 'Read', namespace: 2, observation: item}));
      const offset = Number(query.offset ?? 0);
      // The Core delivers the folders of the address space with every page.
      const folders = [...new Set(items.map(item => item.folder))].sort();
      return send(res, {items: items.slice(offset, offset + 40), total: items.length, offset, limit: 40, folders});
    }
    if (url.pathname === '/api/v2/stream') {
      headers(res, false);
      res.statusCode = 200;
      res.setHeader('content-type', 'text/event-stream');
      res.setHeader('connection', 'keep-alive');
      res.flushHeaders();
      const write = () => res.write(`event: snapshot\ndata: ${JSON.stringify(data().snapshot)}\n\n`);
      write();
      const timer = setInterval(write, 1000);
      streams.add(res);
      req.on('close', () => {clearInterval(timer); streams.delete(res);});
      return;
    }
    if (url.pathname.startsWith('/api/')) return denied(res, 404, 'NOT_FOUND');
    return await serveStatic(res, url);
  } catch (error) {
    send(res, {ok: false, code: 'HARNESS_ERROR', message: 'Fixture harness error'}, 500);
  }
});
server.listen(port, '127.0.0.1', () => console.log(JSON.stringify({
  port, webRoot, fixtureRoot, fixture_only: true, browserCredentialsExposed: false,
  secured_browser_e2e: false,
})));
