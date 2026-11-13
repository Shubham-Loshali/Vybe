# Version 10.6.5 rollout

Build the companion release with version `10.6.5+208` and publish it as `Vybe.apk`
on GitHub release `v10.6.5` before activating this policy. Copy `check.json` to
the repository's `update` branch and deploy the same policy through the existing
Cloudflare Worker's `/check` route with `Cache-Control: no-store`.

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
