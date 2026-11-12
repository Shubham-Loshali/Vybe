import assert from "node:assert/strict";
import test from "node:test";
import { exportSpotifyPlaylist } from "./worker.mjs";

const id = "37i9dQZF1DXbITWG1ZJKYt";
const request = new Request(`https://vybe.example/spotify-playlist?id=${id}`);
const env = {
  APIFY_TOKEN: "test-token",
  EXPORT_RATE_LIMIT: { limit: async () => ({ success: true }) },
};
const context = {};
const first = {
  itemType: "track",
  name: 'First, "Live"',
  artists: [{ name: "Singer" }, { name: "Guest" }],
};
const second = {
  itemType: "track",
  name: "दूसरा",
  artists: [{ name: "गायक" }],
};

test("returns quoted UTF-8 CSV in playlist order", async () => {
  const response = await exportSpotifyPlaylist(request, env, context, async (url, init) => {
    assert.equal(url.origin, "https://api.apify.com");
    assert.equal(init.headers.Authorization, "Bearer test-token");
    assert.equal(url.searchParams.get("maxTotalChargeUsd"), "0.02");
    assert.deepEqual(JSON.parse(init.body).urls, [`https://open.spotify.com/playlist/${id}`]);
    return Response.json([{
      type: "playlist", id, name: "रात की Playlist",
      trackCount: 2, tracksComplete: true, tracks: [first, second],
    }]);
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Playlist-Complete"), "true");
  assert.equal(response.headers.get("X-Playlist-Total"), "2");
  assert.equal(decodeURIComponent(response.headers.get("X-Playlist-Name-Encoded")), "रात की Playlist");
  assert.equal(await response.text(),
    'Track Name,Artist Name(s)\r\n"First, ""Live""","Singer, Guest"\r\n"दूसरा","गायक"\r\n');
});

test("flags truncated results without caching them", async () => {
  const response = await exportSpotifyPlaylist(request, env, context, async () =>
    Response.json([{
      type: "playlist", id, trackCount: 245, tracksComplete: false,
      tracks: [first, { itemType: "episode", name: "Podcast" }],
    }]),
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Playlist-Total"), "245");
  assert.equal(response.headers.get("X-Playlist-Complete"), "false");
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.doesNotMatch(await response.text(), /Podcast/);
});

test("rejects invalid input, missing setup and rate-limited requests before calling provider", async () => {
  const neverFetch = () => assert.fail("Unexpected call to Apify");
  const invalid = new Request("https://vybe.example/spotify-playlist?id=https://example.org");
  assert.equal((await exportSpotifyPlaylist(invalid, env, context, neverFetch)).status, 400);
  assert.equal((await exportSpotifyPlaylist(request, {}, context, neverFetch)).status, 503);
  const limited = { ...env, EXPORT_RATE_LIMIT: { limit: async () => ({ success: false }) } };
  assert.equal((await exportSpotifyPlaylist(request, limited, context, neverFetch)).status, 429);
});

test("does not expose upstream errors or accept a different playlist", async () => {
  const failure = await exportSpotifyPlaylist(request, env, context, async () =>
    new Response("sensitive provider error", { status: 403 }),
  );
  assert.equal(failure.status, 502);
  assert.doesNotMatch(await failure.text(), /sensitive/);
  const mismatch = await exportSpotifyPlaylist(request, env, context, async () =>
    Response.json([{ type: "playlist", id: "other", tracks: [first] }]),
  );
  assert.equal(mismatch.status, 502);
});
