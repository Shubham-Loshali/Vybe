# GitHub debug Firebase configuration

`google-services.json` belongs to the registered Firebase Android app
`com.vybe.music.debug` in project `vybe-36c4f`. The Google Services Gradle plugin
selects this build-type/flavor configuration for `githubDebug`.

Build the same variant used in GitHub Actions with:

```sh
flutter build apk --debug --flavor github
```

Google sign-in on a debug installation additionally requires its signing
certificate's SHA fingerprint to be registered on this Firebase Android app.
GitHub-hosted runners generate their own debug signing certificates.
