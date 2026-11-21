# Vybe Spotify CSV Exporter Worker

This is a dedicated, separate Cloudflare Worker (`vybe-spotify-exporter`) that accepts `GET /spotify-playlist?id=<22-character Spotify playlist ID>` and returns the complete playlist as UTF-8 CSV with track names and artists.

It runs independently from the update-policy / kill-switch worker.

## Features
- **Fast Pagination**: Fetches all pages of playlists up to 10,000 tracks in parallel.
- **Edge Caching**: Caches full playlists for 10 minutes at Cloudflare's edge so duplicate requests respond instantly in milliseconds.
- **Multiple Providers**:
  1. **Spotify Web API (Recommended & Free)**: Uses Spotify Developer Client ID and Secret (`SPOTIFY_CLIENT_ID` and `SPOTIFY_CLIENT_SECRET`). 100% free with official pagination.
  2. **Apify Actor (Optional)**: Uses `APIFY_TOKEN` if configured.
  3. **Rate Limiting**: Protects against abusive loops via `EXPORT_RATE_LIMIT`.

## Deployment

1. From `workers/spotify-exporter`:
   ```bash
   # Set your Spotify Developer credentials (create a free app at https://developer.spotify.com/dashboard)
   npx wrangler secret put SPOTIFY_CLIENT_ID
   npx wrangler secret put SPOTIFY_CLIENT_SECRET

   # Deploy the worker to Cloudflare
   npx wrangler deploy
   ```

2. Your deployed worker URL will look like:
   `https://vybe-spotify-exporter.<your-subdomain>.workers.dev/spotify-playlist`

3. To connect Vybe Android, build with:
   ```bash
   flutter build apk --release --flavor github --dart-define=SPOTIFY_CSV_EXPORT_URL=https://<your-worker>/spotify-playlist
   ```

## Local Tests
Run tests with:
```bash
node --test worker.test.mjs
```
