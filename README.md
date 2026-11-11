# SkyNest

SkyNest Android app source and automated APK builds.

## Android identity

- Display name: SkyNest
- Android application ID: `com.hello22_.chuka`
- Version: `1.0.7+2005`

The Android project scaffolding is generated in GitHub Actions so the repository keeps only the Flutter source and avoids committing generated build files.

## Build

The workflow uses the current stable Flutter SDK and Java 17. Push a version tag beginning with `v` to build an APK and attach it to a GitHub Release. You can also run the workflow manually from the Actions tab.

**Signing note:** without the original private release keystore configured in GitHub Secrets, the generated release APK uses the debug signing key. It is suitable for testing, but it may not install as an update over an APK signed with a different key.
