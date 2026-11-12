# Vybe Spotify CSV exporter

The Worker accepts `GET /spotify-playlist?id=<22-character Spotify playlist ID>`,
requests public track metadata from the
[Clearpath Apify actor](https://apify.com/clearpath/spotify-playlist-scraper), and
returns UTF-8 CSV. The Android app reads the CSV in memory. It does not send
users to a website or ask them to download a file. The separate Worker does
not replace Vybe's existing update service.

To activate it:

1. Sign in to Cloudflare and Apify as the maintainer. Review the actor's pricing
   and set an Apify monthly spending limit before exposing the public endpoint.
   The Worker also limits requests per IP and caps each actor run's charge.
2. From this directory, run `npx wrangler secret put APIFY_TOKEN` and enter
   the Apify token in the terminal prompt. Then run `npx wrangler deploy`.
   The token belongs only in Cloudflare's secret store.
3. Check the deployed `/spotify-playlist?id=...` with a public playlist. A
   complete response includes `X-Playlist-Complete: true`. Then rebuild Vybe
   with `--dart-define=SPOTIFY_CSV_EXPORT_URL=https://<worker-host>/spotify-playlist`.
   Vybe tries this endpoint when Spotify's public preview is incomplete or
   unavailable. If the exporter fails, Vybe can still offer the public preview.

The provider advertises up to 10,000 tracks. A blocked, unavailable, or
truncated playlist can still return an error or a partial result. The importer
asks before saving a partial list.

Run the local Worker tests with `node --test worker.test.mjs`.
