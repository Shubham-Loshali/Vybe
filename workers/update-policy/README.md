# Android 10.6.8 rollout

Version: 10.6.8+218. Preserve both existing Android package identities:

| Asset | Package | Signing certificate SHA-256 |
| --- | --- | --- |
| Vybe.apk | com.vybe.music | 2c55f7dbcacfc3f77d3b1a7d4a401db7e28db5636eba2f0170dfc667d17acf29 |
| Vybe-companion.apk | com.vybe.music.updated | 7e4d85cf51de24f54478078f60cf032d10d181598706ca00798f80b4e57b0581 |

Both assets are universal APKs. The public 10.6.5 companion APK reads companion_url; original-package builds use url/arm64url. Never change an installed app's package or signing key to distribute an update.

Publish release v10.6.8 and verify BOTH asset downloads before advancing the policy in root check.json and workers/update-policy/check.json. Set url and arm64url to Vybe.apk; set companion_url to the Worker route /download/v10.6.8/companion/Vybe.apk. This route streams the matching Vybe-companion.apk bytes with Content-Disposition filename Vybe.apk, preserving the package and signature while using the requested visible filename. Deploy and verify the route before changing the policy link. Keep force_shutdown false so the new version remains usable. Older builds that perform update checks show a mandatory update when version advances; builds with disabled checks cannot be remotely blocked.

The root wrangler.toml deploys the update worker only. The Cloudflare Git integration uses main for production. Keep both policy copies identical and fast-forward update after verifying its history is an ancestor: git push --atomic origin main main:update. Verify the live Worker and raw GitHub fallback after deployment. Publishing source files does not deploy Firebase rules or the desktop backend.

The release workflow builds both flavors, checks their package and signing certificate, and publishes both assets together under a v-prefixed tag. It runs manually or on main commits containing Update: v. It requires encrypted Actions secrets VYBE_ORIGINAL_KEYSTORE and VYBE_COMPANION_KEYSTORE (base64), and VYBE_STORE_PASSWORD. Both existing keys use alias androiddebugkey. Private-key upload requires the owner's explicit approval; until configured, publish the locally signed verified APKs instead. Keep keystores, signing settings, and passwords outside Git source control.

For future versions, update pubspec.yaml and lib/constants/version.dart together and increase the Android build number beyond 218. Change update-policy tests with the next rollout. Do not advance policy before the matching release files are downloadable.
