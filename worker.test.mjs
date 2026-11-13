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
