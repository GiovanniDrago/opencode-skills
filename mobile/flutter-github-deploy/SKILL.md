---
name: flutter-github-deploy
description: Add a tag-driven GitHub Actions Android APK release flow with signed, ABI-split, reproducible builds to a Flutter project.
---

# When to use
Use when a Flutter project needs a GitHub-based Android release flow that:
- creates signed ABI-split release APKs (armeabi-v7a, arm64-v8a, x86_64) when a git tag matching `v*` is pushed
- publishes all APKs and the AAB as GitHub Release assets
- bumps `pubspec.yaml` version from a release tag through a local helper script
- produces reproducible builds with `SOURCE_DATE_EPOCH`

This skill sets up a generic signed Android GitHub Release flow for Flutter. It does not add Play Store publishing, App Store publishing, Fastlane, or F-Droid publishing unless the user explicitly asks for them.

This skill serves as the foundation for `flutter-fdroid-publish`. Applying this skill first ensures the upstream repo is ready for F-Droid submission later.

# What this deploy system contains
The deploy flow is made of these pieces:
- `.github/workflows/android-release-build.yml`
- `android/app/build.gradle` or `android/app/build.gradle.kts`
- `scripts/tag-release.sh`
- `android/key.properties_sample`
- optional release instructions in `README.md`

The behavior is:
1. A maintainer runs `./scripts/tag-release.sh vX.Y.Z` locally.
2. The script computes the build number (`major*10000 + minor*100 + patch`), updates `pubspec.yaml`, commits the version bump, pushes it, creates an annotated tag, and pushes the tag.
3. GitHub Actions runs on tag push.
4. The workflow exports `SOURCE_DATE_EPOCH` from the commit timestamp.
5. The workflow reconstructs the Android signing files from GitHub secrets.
6. The workflow prepares a reproducible workspace.
7. The workflow builds 3 ABI-split APKs (`--split-per-abi`) and an AAB.
8. The workflow publishes all APKs and the AAB to the GitHub Release for the tag.

# Source pattern to mirror
Mirror this structure and sequence unless the target project clearly requires a small adaptation:

## Workflow

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
    env:
      REPRO_BUILD_DIR: /home/vagrant/build/<package-id>
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

      - name: Set release metadata
        run: |
          version="${GITHUB_REF_NAME#v}"
          IFS='.' read -r major minor patch <<< "$version"
          build_number=$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))
          source_date_epoch=$(git log -1 --format=%ct "$GITHUB_SHA")
          echo "APP_VERSION=$version" >> $GITHUB_ENV
          echo "BUILD_NUMBER=$build_number" >> $GITHUB_ENV
          echo "SOURCE_DATE_EPOCH=$source_date_epoch" >> $GITHUB_ENV

      - name: Decode keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 --decode > android/app/release.keystore

      - name: Create key.properties
        run: |
          echo "storePassword=${{ secrets.KEYSTORE_PASSWORD }}" > android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=release.keystore" >> android/key.properties

      - name: Prepare reproducible workspace
        run: |
          sudo mkdir -p /home/vagrant/build
          sudo chown -R "$USER":"$USER" /home/vagrant
          rsync -a --delete --exclude .git ./ "$REPRO_BUILD_DIR/"

      - name: Build release APKs
        working-directory: ${{ env.REPRO_BUILD_DIR }}
        run: |
          export SOURCE_DATE_EPOCH=${{ env.SOURCE_DATE_EPOCH }}
          flutter build apk --release --split-per-abi \
            --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER"

      - name: Build release AAB
        working-directory: ${{ env.REPRO_BUILD_DIR }}
        run: |
          export SOURCE_DATE_EPOCH=${{ env.SOURCE_DATE_EPOCH }}
          flutter build appbundle --release \
            --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER"

      - name: Upload release artifacts
        uses: softprops/action-gh-release@v2
        with:
          files: |
            ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
            ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
            ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/flutter-apk/app-x86_64-release.apk
            ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/bundle/release/app-release.aab
```

## tag-release.sh

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

IFS='.' read -r major minor patch <<< "$version"
build_number=$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))
full_version="${version}+${build_number}"

sed -i.bak -E "s/^version: .*/version: ${full_version}/" pubspec.yaml
rm -f pubspec.yaml.bak

git add pubspec.yaml
git commit -m "Bump version to ${full_version}"
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
    - Check whether the project uses flavors (`--flavor`).

2. Ensure Android manifest permissions are production-ready.
   - Read `android/app/src/main/AndroidManifest.xml`, `android/app/src/debug/AndroidManifest.xml`, and `android/app/src/profile/AndroidManifest.xml`.
   - **Critical rule**: Any permission the app needs must live in `android/app/src/main/AndroidManifest.xml`. Permissions placed only in `debug/` or `profile/` manifests will NOT be present in the release APK.
   - If any permissions are found in `debug/AndroidManifest.xml` or `profile/AndroidManifest.xml` that are NOT in the main manifest, move them to `main/AndroidManifest.xml` to ensure they apply to release builds as well.
   - If a permission is already in both `main/` and `debug/`/`profile/`, remove the duplicate from `debug/` and `profile/` to keep the setup clean.
   - **Example common bug**: Flutter's template puts `<uses-permission android:name="android.permission.INTERNET"/>` in the debug manifest only, causing release APKs to silently fail all network requests while debug builds work fine. Adding it to `main/AndroidManifest.xml` and removing it from `debug/` and `profile/` fixes this.

3. Create or update Android release signing AND ABI split configuration.
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

   **Add `dependenciesInfo` block** inside the `android { ... }` block:

   ```gradle
   dependenciesInfo {
       includeInApk = false
       includeInBundle = false
   }
   ```

   **Add ABI version code override** after the `android { ... }` block and before the `flutter { ... }` block:

   ```gradle
   import com.android.build.gradle.internal.api.ApkVariantOutputImpl

   def abiCodes = ['armeabi-v7a': 1, 'arm64-v8a': 2, 'x86_64': 3]

   android.applicationVariants.configureEach { variant ->
       variant.outputs.each { output ->
           def abiFilter = output.filters.find { it.filterType == "ABI" }
           def abiVersionCode = abiCodes[abiFilter?.identifier]
           if (abiVersionCode != null) {
               ((ApkVariantOutputImpl) output).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
           }
       }
   }
   ```

   **Decision point**: Ask the user: "This will make your app produce 3 APKs instead of 1 fat APK. Is that OK?"

4. Create or update `.github/workflows/android-release-build.yml`.
   - Keep the trigger as tag push on `v*`.
   - Use `actions/checkout@v4`.
   - Use `actions/setup-java@v4` with Java 17 unless the repository already clearly uses a different Java version.
   - Use `subosito/flutter-action@v2` with `channel: 'stable'` and `cache: true`, unless the repo already pins Flutter another way.
   - Run `flutter pub get`.
   - Add the **Set release metadata** step that computes `APP_VERSION`, `BUILD_NUMBER`, and `SOURCE_DATE_EPOCH` from the git tag.
   - Decode `${{ secrets.KEYSTORE_BASE64 }}` into a keystore file under `android/app/`.
   - Write `android/key.properties` from GitHub secrets.
   - Add a **Prepare reproducible workspace** step that rsyncs the source to a fixed path.
   - Run code generation only if the target project actually needs it.
   - Build with `flutter build apk --release --split-per-abi --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER"`.
   - Build with `flutter build appbundle --release --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER"`.
   - Upload all 3 APKs + 1 AAB using `softprops/action-gh-release@v2`.

   **APK filenames** produced by `--split-per-abi`:
   - `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
   - `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
   - `build/app/outputs/flutter-apk/app-x86_64-release.apk`

   **AAB filename**:
   - `build/app/outputs/bundle/release/app-release.aab`

   If the project uses flavors, the filenames become `app-<abi>-<flavor>-release.apk`. Add `--flavor <name>` to the build commands and adjust all paths accordingly.

5. Create `android/key.properties_sample`.
   - Include these keys with placeholder values:
     - `storePassword`
     - `keyPassword`
     - `keyAlias`
     - `storeFile`
   - Do not commit real signing values.

6. Create `scripts/tag-release.sh`.
   - Accept a single tag argument like `v1.2.3`.
   - Validate that the tag starts with `v`.
   - Strip the leading `v` to get the Flutter version string.
   - Compute the build number from the version (`major * 10000 + minor * 100 + patch`).
   - Update the `version:` field in `pubspec.yaml` to `X.Y.Z+<build_number>`.
   - Commit and push that version bump.
   - Create and push an annotated tag.

7. Optionally document the flow in `README.md`.
   - Add the release command: `./scripts/tag-release.sh vX.Y.Z`.
   - Explain that pushing the tag triggers a signed GitHub Release build.
   - List the required GitHub secrets.
   - Note that the release will have 3 APK assets (one per ABI) + 1 AAB.

8. Verify the integration.
   - Run `flutter pub get` if possible.
   - Run `flutter analyze` if possible.
   - Run code generation only if the target project requires it.
   - Run a debug build if it is useful to confirm Android config health without local signing files.
   - Confirm the workflow YAML is valid.
   - Confirm the keystore path written in the workflow matches `storeFile` in `android/key.properties`.
   - Confirm the release artifact paths match the 3 APK paths produced by `--split-per-abi`.
    - Confirm the AAB path matches the built AAB path.
    - Confirm all necessary permissions are in `android/app/src/main/AndroidManifest.xml` and not only in debug/profile manifests.

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

# ABI version code scheme
With `--split-per-abi`, the version code override in `build.gradle` assigns these suffixes:
- `armeabi-v7a`: base code × 10 + 1
- `arm64-v8a`: base code × 10 + 2
- `x86_64`: base code × 10 + 3

For example, with version `1.2.3` (base code `10203`):
- `app-armeabi-v7a-release.apk` → versionCode `102031`
- `app-arm64-v8a-release.apk` → versionCode `102032`
- `app-x86_64-release.apk` → versionCode `102033`

# Adaptation rules
Apply only minimal adaptations. Keep the overall approach identical.

- Keep the workflow filename as `.github/workflows/android-release-build.yml` unless the repository already has a naming convention to follow.
- Keep the release helper at `scripts/tag-release.sh`.
- Keep the tag format `v*`.
- Keep the GitHub Release asset approach. Do not replace it with artifacts-only upload unless asked.
- Keep the ABI-split approach with 3 APKs + 1 AAB. Do not revert to a single fat APK unless the user explicitly asks.
- Keep the reproducible workspace setup. Do not skip `SOURCE_DATE_EPOCH`.
- Keep the `dependenciesInfo` block in `build.gradle`.
- Keep the ABI version code override in `build.gradle`.
- Remove any code generation step if the target project does not need it.
- Match the target repository's Flutter version pinning conventions instead of forcing a new versioning strategy.
- Match the target repository's Gradle DSL instead of rewriting `build.gradle` to `build.gradle.kts` or vice versa.
- If the project uses flavors, add `--flavor <name>` to build commands and adjust APK paths to `app-<abi>-<flavor>-release.apk`.
- Update the `<package-id>` placeholder in `REPRO_BUILD_DIR` to the project's actual application ID.
- Do not run `flutter create --platforms=android .` unless the Android project is actually missing or the user explicitly wants regeneration.
- Do not add Gradle wrapper patch steps unless the target repository actually needs them.

# Important caveats
- This is a GitHub Release APK pipeline, not a mobile store deployment pipeline.
- The release produces **3 ABI-split APKs** (armeabi-v7a, arm64-v8a, x86_64) and 1 AAB, not a single fat APK.
- The ABI version code override scheme (`N * 10 + 1/2/3`) ensures unique version codes per APK.
- Signed release builds require the signing config in Gradle and the signing files generated from GitHub secrets.
- If the repository has no Android project yet, the Android platform setup may need to be created before applying this flow.
- The workflow's code generation step is project-specific. Only include it when the target project requires generated files to build.
- A local `flutter build apk --release` may fail without a local `android/key.properties` and keystore, even when the GitHub workflow is configured correctly.
- The reproducible workspace path `/home/vagrant/build/<package-id>` mirrors the convention used by `flutter-fdroid-publish` for F-Droid build servers. Adjust `<package-id>` to match your project's application ID.
- If the project uses flavors, the APK filenames and build commands must include the flavor name.
- **Permissions in debug/profile manifests do NOT apply to release builds.** Always place every permission the app needs in `android/app/src/main/AndroidManifest.xml`. If a permission only exists in `debug/` or `profile/`, the release APK will lack it and the feature will silently break (e.g. no network access).

# Implementation checklist for OpenCode
When using this skill to implement the deploy system in another repository:
- inspect the existing Flutter and Android setup first
- identify whether the Android app uses Groovy or Kotlin DSL
- identify whether the project uses flavors
- create or update Android release signing in `android/app/build.gradle` or `android/app/build.gradle.kts`
- ensure all app permissions are in `android/app/src/main/AndroidManifest.xml`, not only in debug/profile manifests
- add `dependenciesInfo` block to `build.gradle`
- add ABI version code override to `build.gradle`
- create or update `.github/workflows/android-release-build.yml`
- create `scripts/tag-release.sh`
- create `android/key.properties_sample`
- make the script executable if needed
- update the `<package-id>` placeholder in the workflow's `REPRO_BUILD_DIR`
- update `README.md` if release usage or secrets need documenting
- verify whether code generation is needed before adding that step
- verify the workflow uploads 3 APK paths + 1 AAB path
- avoid adding Play Store config, Fastlane, F-Droid metadata, or unrelated mobile deploy tooling unless explicitly requested

# Expected outcome
After applying this skill, the target repository should support this release flow:

```bash
./scripts/tag-release.sh v1.2.3
```

That command should bump the app version to `1.2.3+10203`, push the commit and tag, trigger GitHub Actions, reconstruct Android signing files from secrets, prepare a reproducible workspace, build 3 signed ABI-split APKs and 1 AAB, and publish all assets to the GitHub Release for `v1.2.3`.

The GitHub Release should contain:
- `app-armeabi-v7a-release.apk`
- `app-arm64-v8a-release.apk`
- `app-x86_64-release.apk`
- `app-release.aab`

# Integration with other skills

This skill serves as the **foundation** for other Flutter publishing skills:

- **`flutter-fdroid-publish`** — extends this setup to publish to F-Droid. The ABI split, reproducible workspace, `dependenciesInfo`, and version code override are all prerequisites for F-Droid submission. Apply this skill first, then load `flutter-fdroid-publish` to create the fdroiddata metadata and submit the merge request.
- **`flutter-android-starter`** — use that skill first if the Flutter project doesn't exist yet.
