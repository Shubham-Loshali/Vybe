# Version 10.6.5 rollout

Build the companion release with version `10.6.5+208` and publish it as `Vybe.apk`
on GitHub release `v10.6.5` before activating this policy. Keep the root
`check.json` identical to `workers/update-policy/check.json`. The existing
Cloudflare Worker's `/check` route returns that policy with
`Cache-Control: no-store`.

The `main` and `update` branches share the same commit and source files.
Production deploys from `main`; `update` builds its branch Preview using the
same root `wrangler.toml`, including `previews = {}`. The root fallback
`check.json` remains available at its existing URL on the `update` branch.
After preparing and checking a release, keep both branches aligned with
`git push --atomic origin main main:update`.

Clients with update checks block themselves when `version` is higher than their
installed version. The policy requires `10.6.5` and explicitly lists versions
`10.6.0` through `10.6.4` as blocked. Keep `force_shutdown` false: clients apply
that flag to every version, including the replacement release.

The original public signing key is unavailable. This release distributes
`Vybe.apk` with package `com.vybe.music.updated`, signed with the local key used
for companion builds 189–205. It updates those installations in place. Users
of the original `com.vybe.music` app must install this release alongside it;
Android will not transfer the original app's data automatically. Preserve the
original installation and any backups. Its signing key must be recovered
before a compatible in-place update can be produced.

Previously distributed companion 10.6.2 builds disabled update checks and
cannot be remotely shut down. Checks are enabled from 10.6.3 onward.

Build number is 208. Preserve the companion signing key outside source control.
