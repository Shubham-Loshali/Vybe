import assert from 'node:assert/strict';
import test from 'node:test';
import worker from './worker.mjs';
import policy from './check.json' with { type: 'json' };

for (const path of ['/', '/check', '/check?version=10.6.2']) {
  test(`serves the current update policy at ${path}`, async () => {
    const response = await worker.fetch(new Request(`https://example.com${path}`));
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), policy);
    assert.match(response.headers.get('cache-control'), /no-store/);
    assert.equal(response.headers.get('access-control-allow-origin'), '*');
    assert.equal(policy.force_shutdown, false);
  });
}

test('does not expose an exporter route on the update service', async () => {
  const response = await worker.fetch(new Request('https://example.com/spotify-export'));
  assert.equal(response.status, 404);
});

const companionPath = '/download/v10.6.8/companion/Vybe.apk';

test('downloads unchanged companion bytes with filename Vybe.apk', async (t) => {
  const bytes = new Uint8Array([80, 75, 3, 4, 42]);
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url, 'https://github.com/Shubham-Loshali/Vybe/releases/download/v10.6.8/Vybe-companion.apk');
    assert.equal(options.method, 'GET');
    return new Response(bytes, { headers: { 'Content-Length': String(bytes.length) } });
  });
  const response = await worker.fetch(new Request(`https://example.com${companionPath}`));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-disposition'), 'attachment; filename="Vybe.apk"');
  assert.equal(response.headers.get('content-type'), 'application/vnd.android.package-archive');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);
});

test('preserves partial downloads and upstream range headers', async (t) => {
  t.mock.method(globalThis, 'fetch', async (_, options) => {
    assert.equal(options.headers.get('range'), 'bytes=5-9');
    assert.equal(options.headers.get('if-range'), '"release-etag"');
    return new Response('12345', {
      status: 206,
      headers: { 'Content-Range': 'bytes 5-9/10', 'Content-Length': '5', 'Accept-Ranges': 'bytes' },
    });
  });
  const response = await worker.fetch(new Request(`https://example.com${companionPath}`, {
    headers: { Range: 'bytes=5-9', 'If-Range': '"release-etag"' },
  }));
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('content-range'), 'bytes 5-9/10');
  assert.equal(response.headers.get('content-length'), '5');
  assert.equal(await response.text(), '12345');
});

test('HEAD checks advertise Vybe.apk without downloading a body', async (t) => {
  t.mock.method(globalThis, 'fetch', async (_, options) => {
    assert.equal(options.method, 'HEAD');
    return new Response(null, { headers: { 'Content-Length': '57884128' } });
  });
  const response = await worker.fetch(new Request(`https://example.com${companionPath}`, { method: 'HEAD' }));
  assert.equal(response.headers.get('content-disposition'), 'attachment; filename="Vybe.apk"');
  assert.equal(await response.text(), '');
});

test('rejects write requests to the download endpoint', async () => {
  const response = await worker.fetch(new Request(`https://example.com${companionPath}`, { method: 'POST' }));
  assert.equal(response.status, 405);
});

test('upstream failures never return an HTML error as an APK', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => new Response('<html>not found</html>', { status: 404 }));
  const response = await worker.fetch(new Request(`https://example.com${companionPath}`));
  assert.equal(response.status, 404);
  assert.equal(response.headers.get('content-disposition'), null);
});

test('network failures return a retryable error', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('network unavailable'); });
  const response = await worker.fetch(new Request(`https://example.com${companionPath}`));
  assert.equal(response.status, 502);
  assert.match(await response.text(), /retry/i);
});
