---
name: flutter-github-deploy
description: Add a tag-driven GitHub Actions Android APK release flow with signed release builds to a Flutter project.
---

# When to use
Use when a Flutter project needs a GitHub-based Android release flow that:
- creates a signed release APK when a git tag matching `v*` is pushed
- publishes that APK as a GitHub Release asset
- bumps `pubspec.yaml` version from a release tag through a local helper script

This skill sets up a generic signed Android GitHub Release flow for Flutter. It does not add Play Store publishing, App Store publishing, or Fastlane unless the user explicitly asks for them.

# What this deploy system contains
The deploy flow is made of these pieces:
- `.github/workflows/android-release-build.yml`
- `android/app/build.gradle` or `android/app/build.gradle.kts`
- `scripts/tag-release.sh`
- `android/key.properties_sample`
- optional release instructions in `README.md`

The behavior is:
1. A maintainer runs `./scripts/tag-release.sh vX.Y.Z` locally.
2. The script updates `pubspec.yaml`, commits the version bump, pushes it, creates an annotated tag, and pushes the tag.
3. GitHub Actions runs on tag push.
4. The workflow reconstructs the Android signing files from GitHub secrets.
5. The workflow builds `build/app/outputs/flutter-apk/app-release.apk`.
6. The workflow publishes that APK to the GitHub Release for the tag.

# Source pattern to mirror
Mirror this structure and sequence unless the target project clearly requires a small adaptation:

```yaml
name: Android Publish Build

on:
  push:
    tags:
      - 'v*'

jobs:
  build-android-publish:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Decode keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/release.keystore

      - name: Create key.properties
        run: |
          echo "storePassword=${{ secrets.KEYSTORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=release.keystore" >> android/key.properties

      - name: Build release APK
        run: flutter build apk --release

      - name: Upload release APK
        uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-release.apk
```

The local release helper script to mirror is:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <tag>" >&2
  exit 1
fi

tag="$1"
version="${tag#v}"

if [[ "$tag" == "$version" ]]; then
  echo "tag must start with v (example: v1.2.3)" >&2
  exit 1
fi

if [[ ! -f "pubspec.yaml" ]]; then
  echo "pubspec.yaml not found" >&2
  exit 1
fi

if ! grep -q "^version:" pubspec.yaml; then
  echo "version field not found in pubspec.yaml" >&2
  exit 1
fi

sed -i.bak -E "s/^version: .*/version: ${version}/" pubspec.yaml
rm -f pubspec.yaml.bak

git add pubspec.yaml
git commit -m "Bump version to ${tag}"
git push

git tag -a "$tag" -m "Release $tag"
git push origin "$tag"
```

# Workflow

1. Inspect the target Flutter project first.
   - Confirm `pubspec.yaml` exists at repo root.
   - Confirm the project is using Flutter.
   - Check whether `android/` already exists and is committed.
   - Check whether the Android app uses `build.gradle` or `build.gradle.kts`.
   - Check whether a release workflow or tag script already exists, and extend or replace carefully.
   - Check whether the project uses code generation such as `build_runner`.

2. Create or update Android release signing.
   - Update `android/app/build.gradle` or `android/app/build.gradle.kts`.
   - Load `android/key.properties` with Gradle `Properties`.
   - Define a `release` signing config using:
     - `storePassword`
     - `keyPassword`
     - `keyAlias`
     - `storeFile`
   - Set `buildTypes.release` to use that `release` signing config.
   - Match the target repo's DSL style instead of converting between Groovy and Kotlin DSL unnecessarily.
   - Do not add a fallback to debug signing unless the user explicitly asks for that behavior.

3. Create or update `.github/workflows/android-release-build.yml`.
   - Keep the trigger as tag push on `v*`.
   - Use `actions/checkout@v4`.
   - Use `actions/setup-java@v4` with Java 17 unless the repository already clearly uses a different Java version.
   - Use `subosito/flutter-action@v2` with `channel: 'stable'` and `cache: true`, unless the repo already pins Flutter another way.
   - Run `flutter pub get`.
   - Decode `${{ secrets.KEYSTORE_BASE64 }}` into a keystore file under `android/app/`.
   - Write `android/key.properties` from GitHub secrets.
   - Run code generation only if the target project actually needs it.
   - Build with `flutter build apk --release`.
   - Upload `build/app/outputs/flutter-apk/app-release.apk` using `softprops/action-gh-release@v2`.

4. Create `android/key.properties_sample`.
   - Include these keys with placeholder values:
     - `storePassword`
     - `keyPassword`
     - `keyAlias`
     - `storeFile`
   - Do not commit real signing values.

5. Create `scripts/tag-release.sh`.
   - Accept a single tag argument like `v1.2.3`.
   - Validate that the tag starts with `v`.
   - Strip the leading `v` to get the Flutter version string.
   - Update the `version:` field in `pubspec.yaml`.
   - Commit and push that version bump.
   - Create and push an annotated tag.

6. Optionally document the flow in `README.md`.
   - Add the release command: `./scripts/tag-release.sh vX.Y.Z`.
   - Explain that pushing the tag triggers a signed GitHub Release build.
   - List the required GitHub secrets.

7. Verify the integration.
   - Run `flutter pub get` if possible.
   - Run `flutter analyze` if possible.
   - Run code generation only if the target project requires it.
   - Run a debug build if it is useful to confirm Android config health without local signing files.
   - Confirm the workflow YAML is valid.
   - Confirm the keystore path written in the workflow matches `storeFile` in `android/key.properties`.
   - Confirm the release artifact path matches the built APK path.

# Required GitHub secrets
The workflow expects these GitHub secrets:
- `KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`
- `KEY_ALIAS`

# Signing file template
The sample `android/key.properties_sample` should look like:

```properties
storePassword=<password-from-previous-step>
keyPassword=<password-from-previous-step>
keyAlias=upload
storeFile=<keystore-file-location>
```

# Adaptation rules
Apply only minimal adaptations. Keep the overall approach identical.

- Keep the workflow filename as `.github/workflows/android-release-build.yml` unless the repository already has a naming convention to follow.
- Keep the release helper at `scripts/tag-release.sh`.
- Keep the tag format `v*`.
- Keep the GitHub Release asset approach. Do not replace it with artifacts-only upload unless asked.
- Keep the APK output path unless the target build is intentionally changed.
- Remove any code generation step if the target project does not need it.
- Match the target repository's Flutter version pinning conventions instead of forcing a new versioning strategy.
- Match the target repository's Gradle DSL instead of rewriting `build.gradle` to `build.gradle.kts` or vice versa.
- Do not run `flutter create --platforms=android .` unless the Android project is actually missing or the user explicitly wants regeneration.
- Do not add Gradle wrapper patch steps unless the target repository actually needs them.

# Important caveats
- This is a GitHub Release APK pipeline, not a mobile store deployment pipeline.
- Signed release builds require the signing config in Gradle and the signing files generated from GitHub secrets.
- If the repository has no Android project yet, the Android platform setup may need to be created before applying this flow.
- The workflow's code generation step is project-specific. Only include it when the target project requires generated files to build.
- A local `flutter build apk --release` may fail without a local `android/key.properties` and keystore, even when the GitHub workflow is configured correctly.

# Implementation checklist for OpenCode
When using this skill to implement the deploy system in another repository:
- inspect the existing Flutter and Android setup first
- identify whether the Android app uses Groovy or Kotlin DSL
- create or update Android release signing in `android/app/build.gradle` or `android/app/build.gradle.kts`
- create or update `.github/workflows/android-release-build.yml`
- create `scripts/tag-release.sh`
- create `android/key.properties_sample`
- make the script executable if needed
- update `README.md` if release usage or secrets need documenting
- verify whether code generation is needed before adding that step
- avoid adding Play Store config, Fastlane, or unrelated mobile deploy tooling unless explicitly requested

# Expected outcome
After applying this skill, the target repository should support this release flow:

```bash
./scripts/tag-release.sh v1.2.3
```

That command should bump the app version, push the commit and tag, trigger GitHub Actions, reconstruct Android signing files from secrets, build a signed release APK, and publish the APK to the GitHub Release for `v1.2.3`.
