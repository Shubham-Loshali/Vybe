# Version 10.6.3 rollout

Publish the release APK before activating this policy. Copy `check.json` to the
repository's `update` branch and return the same JSON from the existing
Cloudflare Worker's `/check` route with `Cache-Control: no-store`.

The 10.6.2 public app blocks itself when `version` is higher than its current
version. Keep `force_shutdown` false: the old client applies that flag to every
version, including 10.6.3.

The original public signing key is unavailable. This release distributes
`Vybe.apk` with package `com.vybe.music.updated`, signed with the local key used
for companion builds 189–205. It updates those installations in place. Users
of the original `com.vybe.music` app must install this release alongside it;
Android will not transfer the original app's data automatically. Preserve the
original installation and any backups. Its signing key must be recovered
before a compatible in-place update can be produced.

Previously distributed companion 10.6.2 builds disabled update checks and
cannot be remotely shut down. Checks are enabled from 10.6.3 onward.

Build number is 206. Preserve the companion signing key outside source control.
