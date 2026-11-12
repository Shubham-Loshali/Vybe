const playlistIdPattern = /^[A-Za-z0-9]{22}$/;
const maxPlaylistItems = 10_000;
const apifyUrl = new URL(
  "https://api.apify.com/v2/actors/clearpath~spotify-playlist-scraper/run-sync-get-dataset-items",
);
apifyUrl.search = new URLSearchParams({
  timeout: "35",
  maxItems: "1",
  maxTotalChargeUsd: "0.02",
  fields: "type,id,name,trackCount,tracksComplete,tracks",
}).toString();

function error(status, message, headers = {}) {
  return Response.json({ error: message }, {
    status,
    headers: { "Cache-Control": "no-store", ...headers },
  });
}

function csvCell(value) {
  return '"' + value.replaceAll('"', '""') + '"';
}

export async function exportSpotifyPlaylist(request, env, context, fetcher = fetch) {
  const url = new URL(request.url);
  if (url.pathname !== "/spotify-playlist") return error(404, "Not found");
  if (request.method !== "GET") {
    return error(405, "Use GET", { Allow: "GET" });
  }
  const ids = url.searchParams.getAll("id");
  const id = ids[0];
  if (ids.length !== 1 || !playlistIdPattern.test(id)) {
    return error(400, "Invalid Spotify playlist ID");
  }

  const cache = globalThis.caches?.default;
  const cacheKey = new Request(new URL(`/spotify-playlist?id=${id}`, url.origin));
  const cached = await cache?.match(cacheKey);
  if (cached) return cached;

  if (!env.APIFY_TOKEN || !env.EXPORT_RATE_LIMIT) {
    return error(503, "Playlist exporter is not configured");
  }

  try {
    const { success } = await env.EXPORT_RATE_LIMIT.limit({
      key: request.headers.get("CF-Connecting-IP") ?? "unknown",
    });
    if (!success) return error(429, "Try again later", { "Retry-After": "60" });

    const upstream = await fetcher(apifyUrl, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(42_000),
      headers: {
        Authorization: `Bearer ${env.APIFY_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        urls: [`https://open.spotify.com/playlist/${id}`],
        maxItems: 1,
        maxTracksPerPlaylist: maxPlaylistItems,
        trackRows: false,
        includeTrackInsights: false,
        includeTrackCredits: false,
      }),
    });
    if (!upstream.ok) {
      await upstream.body?.cancel();
      return error(502, "The playlist provider could not complete the export");
    }

    const records = await upstream.json();
    const playlist = Array.isArray(records)
      ? records.find((row) => row?.type === "playlist" && row.id === id)
      : null;
    if (!Array.isArray(playlist?.tracks) || !playlist.tracks.length ||
        playlist.tracks.length > maxPlaylistItems) {
      return error(502, "The playlist provider returned no track list");
    }

    const rows = ["Track Name,Artist Name(s)"];
    for (const track of playlist.tracks) {
      if (track?.itemType !== "track" || typeof track.name !== "string") continue;
      const title = track.name.trim();
      const artist = Array.isArray(track.artists)
        ? track.artists.map((entry) =>
          typeof entry?.name === "string" ? entry.name.trim() : ""
        ).filter(Boolean).join(", ")
        : "";
      if (title && artist) rows.push(`${csvCell(title)},${csvCell(artist)}`);
    }
    if (rows.length === 1) return error(422, "No songs found in this playlist");

    const count = playlist.trackCount;
    const hasCount = Number.isSafeInteger(count) && count >= playlist.tracks.length;
    const complete = playlist.tracksComplete === true && hasCount &&
      count === rows.length - 1;
    const headers = {
      "Content-Type": "text/csv; charset=utf-8",
      "Cache-Control": complete ? "public, max-age=600" : "no-store",
      "X-Playlist-Complete": String(complete),
    };
    if (hasCount) headers["X-Playlist-Total"] = String(count);
    if (typeof playlist.name === "string" && playlist.name.trim()) {
      headers["X-Playlist-Name-Encoded"] = encodeURIComponent(playlist.name.trim());
    }
    const response = new Response(rows.join("\r\n") + "\r\n", { headers });
    if (complete && cache) {
      context.waitUntil(cache.put(cacheKey, response.clone()).catch(() => {}));
    }
    return response;
  } catch {
    return error(502, "The playlist provider could not complete the export");
  }
}

export default { fetch: exportSpotifyPlaylist };
