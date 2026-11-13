# Vybe update policy

This branch hosts `check.json` at the fallback URL used by the Android app.
The app source and production Worker are maintained on the [main branch](https://github.com/Shubham-Loshali/Vybe/tree/main).

`worker.mjs` and `wrangler.toml` let Cloudflare build this branch using
`npx wrangler preview`. The empty `previews` block is required by Wrangler and
creates a branch Preview without promoting it to production. Production
continues to deploy from `main`.

Run `node --test worker.test.mjs` to check the policy endpoints and cache headers.

Publish the verified APK before raising the version in `check.json`. Keep
`force_shutdown` false so the current release remains usable; older clients
require an update when the advertised version is higher than their own.
