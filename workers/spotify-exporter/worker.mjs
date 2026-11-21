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
  return '"' + String(value).replaceAll('"', '""') + '"';
}

function buildCsvResponse(name, tracks, totalCount, isComplete, cache, cacheKey, context) {
  const rows = ["Track Name,Artist Name(s)"];
  for (const track of tracks) {
    if (track?.itemType !== "track" || typeof track.name !== "string") continue;
    const title = track.name.trim();
    const artist = Array.isArray(track.artists)
      ? track.artists.map((entry) =>
        typeof entry?.name === "string" ? entry.name.trim() : ""
      ).filter(Boolean).join(", ")
      : (typeof track.artists === "string" ? track.artists.trim() : "");
    if (title && artist) rows.push(`${csvCell(title)},${csvCell(artist)}`);
  }
  if (rows.length === 1) return error(422, "No songs found in this playlist");

  const count = totalCount ?? (rows.length - 1);
  const hasCount = Number.isSafeInteger(count) && count >= (rows.length - 1);
  const complete = isComplete === true && hasCount && count === (rows.length - 1);
  const headers = {
    "Content-Type": "text/csv; charset=utf-8",
    "Cache-Control": complete ? "public, max-age=600" : "no-store",
    "X-Playlist-Complete": String(complete),
  };
  if (hasCount) headers["X-Playlist-Total"] = String(count);
  if (typeof name === "string" && name.trim()) {
    headers["X-Playlist-Name-Encoded"] = encodeURIComponent(name.trim());
  }
  const response = new Response(rows.join("\r\n") + "\r\n", { headers });
  if (complete && cache) {
    context?.waitUntil?.(cache.put(cacheKey, response.clone()).catch(() => {}));
  }
  return response;
}

async function fetchFromSpotifyApi(id, clientId, clientSecret, fetcher) {
  const tokenRes = await fetcher("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
    },
    body: "grant_type=client_credentials",
  });
  if (!tokenRes.ok) return null;
  const tokenData = await tokenRes.json();
  const token = tokenData.access_token;
  if (!token) return null;

  const metaRes = await fetcher(
    `https://api.spotify.com/v1/playlists/${id}?fields=name,tracks(total,limit,offset,items(track(name,artists(name))))`,
    {
      headers: { Authorization: `Bearer ${token}` },
    }
  );
  if (!metaRes.ok) return null;
  const meta = await metaRes.json();
  const name = meta.name ?? "";
  const total = meta.tracks?.total ?? 0;
  const rawItems = meta.tracks?.items ?? [];

  const tracks = [];
  for (const item of rawItems) {
    const t = item.track;
    if (t?.name) {
      tracks.push({
        itemType: "track",
        name: t.name,
        artists: t.artists ?? [],
      });
    }
  }

  if (total > tracks.length && total <= maxPlaylistItems) {
    const offsets = [];
    for (let offset = tracks.length; offset < total && offset < maxPlaylistItems; offset += 100) {
      offsets.push(offset);
    }

    const pageResults = await Promise.all(
      offsets.map(async (offset) => {
        try {
          const res = await fetcher(
            `https://api.spotify.com/v1/playlists/${id}/tracks?limit=100&offset=${offset}&fields=items(track(name,artists(name)))`,
            {
              headers: { Authorization: `Bearer ${token}` },
            }
          );
          if (!res.ok) return [];
          const data = await res.json();
          return (data.items ?? []).map((item) => ({
            itemType: "track",
            name: item.track?.name,
            artists: item.track?.artists ?? [],
          })).filter((t) => t.name);
        } catch {
          return [];
        }
      })
    );

    for (const page of pageResults) {
      tracks.push(...page);
    }
  }

  return {
    name,
    total,
    tracks,
    isComplete: tracks.length === total,
  };
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

  if (env.EXPORT_RATE_LIMIT) {
    const { success } = await env.EXPORT_RATE_LIMIT.limit({
      key: request.headers.get("CF-Connecting-IP") ?? "unknown",
    });
    if (!success) return error(429, "Try again later", { "Retry-After": "60" });
  }

  if (env.SPOTIFY_CLIENT_ID && env.SPOTIFY_CLIENT_SECRET) {
    try {
      const result = await fetchFromSpotifyApi(
        id,
        env.SPOTIFY_CLIENT_ID,
        env.SPOTIFY_CLIENT_SECRET,
        fetcher,
      );
      if (result && result.tracks.length > 0) {
        return buildCsvResponse(
          result.name,
          result.tracks,
          result.total,
          result.isComplete,
          cache,
          cacheKey,
          context,
        );
      }
    } catch {
      // Fall through to other providers
    }
  }

  if (env.APIFY_TOKEN) {
    try {
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

      return buildCsvResponse(
        playlist.name,
        playlist.tracks,
        playlist.trackCount,
        playlist.tracksComplete,
        cache,
        cacheKey,
        context,
      );
    } catch {
      return error(502, "The playlist provider could not complete the export");
    }
  }

  return error(503, "Playlist exporter is not configured");
}

export default { fetch: exportSpotifyPlaylist };
