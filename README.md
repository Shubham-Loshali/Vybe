# Vybe update policy

This branch hosts `check.json` at the fallback URL used by the Android app.
The app source and production Worker are maintained on the [main branch](https://github.com/Shubham-Loshali/Vybe/tree/main).

`worker.mjs` and `wrangler.toml` let Cloudflare validate this branch using the
preview command `npx wrangler versions upload`. This uploads a Worker version
without promoting it to production. Production continues to deploy from `main`.

Run `node --test worker.test.mjs` to check the policy endpoints and cache headers.

Publish the verified APK before raising the version in `check.json`. Keep
`force_shutdown` false so the current release remains usable; older clients
require an update when the advertised version is higher than their own.
