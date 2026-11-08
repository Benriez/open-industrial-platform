#!/usr/bin/env node
// Controlled Settings test harness for the isolated UI verification only.
//
// - Serves the release web build.
// - Proxies legacy /api/v1 to a private local Core test runtime. In fixture and
//   unauthorized modes it injects the server-side test credential so the shell
//   can render real v1 data; the credential never reaches the browser.
// - In fixture mode it serves sanitized OIP-008.4 v2 contract captures and marks
//   them with x-oip-contract-fixture so the UI can label them as test data.
// - In unauthorized mode v2 is proxied without Authorization, which exercises
//   the honest HTTP 403 browser-identity boundary.
//
// The credential is read once from OIP_TEST_CREDENTIAL_FILE and never logged,
// serialized or written into the workspace.
import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { extname, normalize, resolve, sep } from 'node:path';
import { Readable } from 'node:stream';

const port = Number(process.env.PORT ?? 18945);
const core = (process.env.OIP_CORE_URL ?? 'http://127.0.0.1:18940').replace(/\/$/, '');
const mode = process.env.OIP_SETTINGS_MODE ?? 'fixture';
const context = process.env.OIP_SETTINGS_CONTEXT ?? 'platform';
const webRoot = resolve(process.env.OIP_WEB_ROOT ?? 'build/web');
const fixtureRoot = resolve(process.env.OIP_SETTINGS_FIXTURES ?? 'test/fixtures/settings', context);
const credentialFile = process.env.OIP_TEST_CREDENTIAL_FILE;
const testToken = credentialFile ? (await readFile(credentialFile)).toString('hex').trim() : null;

if (mode !== 'live' && !testToken) {
  console.error('fixture/unauthorized modes require OIP_TEST_CREDENTIAL_FILE');
  process.exit(2);
}

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.map': 'application/json; charset=utf-8',
};

function forwardHeaders(req, authorize) {
  const headers = {};
  for (const [key, value] of Object.entries(req.headers)) {
    if (['host', 'authorization', 'cookie', 'connection', 'content-length', 'accept-encoding'].includes(key)) continue;
    headers[key] = value;
  }
  if (authorize && testToken) headers.authorization = `Bearer ${testToken}`;
  return headers;
}

async function proxy(req, res, { authorize }) {
  const body = req.method === 'GET' || req.method === 'HEAD' ? undefined : req;
  let upstream;
  try {
    upstream = await fetch(`${core}${req.url}`, {
      method: req.method,
      headers: forwardHeaders(req, authorize),
      body,
      duplex: body ? 'half' : undefined,
    });
  } catch (error) {
    res.statusCode = 502;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ code: 'CORE_UNREACHABLE', message: String(error) }));
    return;
  }
  res.statusCode = upstream.status;
  const stream = (upstream.headers.get('content-type') ?? '').includes('text/event-stream');
  upstream.headers.forEach((value, key) => {
    if (['content-encoding', 'transfer-encoding', 'connection', 'content-length'].includes(key)) return;
    res.setHeader(key, value);
  });
  if (stream) {
    res.setHeader('cache-control', 'no-cache');
    Readable.fromWeb(upstream.body).pipe(res);
    return;
  }
  const buffer = Buffer.from(await upstream.arrayBuffer());
  res.setHeader('content-length', buffer.length);
  res.end(buffer);
}

function fixtureName(url) {
  if (url.pathname === '/api/v2/settings') {
    return url.searchParams.get('catalog') === 'true' ? 'settings-catalog.json' : 'settings-platform.json';
  }
  if (url.pathname === '/api/v2/management') {
    const section = url.searchParams.get('section');
    return section ? `management-${section.replaceAll('_', '-')}.json` : null;
  }
  return null;
}

async function serveFixture(res, name) {
  try {
    const body = await readFile(resolve(fixtureRoot, name));
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json; charset=utf-8');
    res.setHeader('cache-control', 'no-store');
    res.setHeader('x-oip-contract-fixture', 'oip-0084-contract-fixture');
    res.end(body);
  } catch {
    res.statusCode = 404;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ code: 'FIXTURE_NOT_FOUND', message: `${context}/${name} is not captured` }));
  }
}

async function serveStatic(res, url) {
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  let file = normalize(resolve(webRoot, `.${rel}`));
  if (file !== webRoot && !file.startsWith(`${webRoot}${sep}`)) {
    res.statusCode = 403;
    res.end('forbidden');
    return;
  }
  let info = await stat(file).catch(() => null);
  if (!info?.isFile() && !extname(file)) {
    rel = '/index.html';
    file = resolve(webRoot, 'index.html');
    info = await stat(file).catch(() => null);
  }
  if (!info?.isFile()) {
    res.statusCode = 404;
    res.end('not found');
    return;
  }
  res.statusCode = 200;
  res.setHeader('content-type', contentTypes[extname(file)] ?? 'application/octet-stream');
  res.setHeader('cache-control', 'no-store');
  createReadStream(file).pipe(res);
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://127.0.0.1:${port}`);
    if (url.pathname.startsWith('/api/v2/')) {
      if (mode === 'fixture') {
        const name = fixtureName(url);
        if (!name) {
          res.statusCode = 404;
          res.setHeader('content-type', 'application/json');
          res.end(JSON.stringify({ code: 'UNKNOWN_MANAGEMENT_SECTION', message: 'section is required' }));
          return;
        }
        return await serveFixture(res, name);
      }
      if (mode === 'unauthorized') return await proxy(req, res, { authorize: false });
      return await proxy(req, res, { authorize: false });
    }
    if (url.pathname.startsWith('/api/v1/')) {
      return await proxy(req, res, { authorize: mode !== 'live' });
    }
    return await serveStatic(res, url);
  } catch (error) {
    res.statusCode = 500;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ code: 'HARNESS_ERROR', message: String(error) }));
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(JSON.stringify({
    port,
    mode,
    context,
    core,
    fixtureRoot,
    webRoot,
    testCredentialInjectedServerSide: Boolean(testToken),
    browserCredentialsExposed: false,
  }));
});
