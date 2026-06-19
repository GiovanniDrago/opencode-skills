---
name: flutter-fdroid-publish
description: Publish a Flutter Android app to F-Droid by setting up ABI-split reproducible builds, generating metadata, and submitting a merge request to fdroiddata.
---

# When to use

Use this skill when you want to publish an **existing Flutter Android app** to F-Droid. This skill handles:

- **Upstream repo preparation** — ABI split, reproducible builds, GitHub Actions workflow
- **F-Droid metadata creation** — `fdroiddata` YAML with proper ABI entries, `VercodeOperation`, and `binary` URLs
- **Local validation** — running `fdroid rewritemeta` and `fdroid lint` before pushing
- **MR iteration** — handling reviewer feedback and formatting fixes

This skill is **for existing Flutter apps**. For new projects, use `flutter-android-starter` first.

# Prerequisites

Before starting, confirm the user has:

1. **An existing Flutter app** with Android platform support
2. **A GitHub repository** with the app source code
3. **A fork/clone of `fdroiddata`** (https://gitlab.com/fdroid/fdroiddata) for creating the MR
4. **Signing keys** for release APKs (or willingness to use debug signing for initial setup)
5. **Flutter version pinned** in `.github/workflows/` (e.g., `flutter-version: '3.41.6'`)

# Workflow overview

The workflow is split into two repos:

1. **Upstream app repo** — make it reproducible and ABI-split
2. **fdroiddata repo** — create metadata and submit MR

Each phase asks the user before making changes. The agent never pushes without explicit confirmation.

---

## Phase 1: Inspect upstream repo

**Goal**: Understand the current state of the Flutter app.

**Steps**:
- [ ] Read `pubspec.yaml` — check version, dependencies, Flutter SDK constraint
- [ ] Read `android/app/build.gradle` — check for NDK pinning, flavors, signing configs
- [ ] Read `.github/workflows/` — check for release workflow, Flutter version pin
- [ ] Check for `fastlane/metadata/android/` structure — F-Droid will pull metadata from there
- [ ] Ask the user:
  - "What is your app's package ID?" (e.g., `com.example.myapp`)
  - "What is your GitHub repo URL?"
  - "Do you have a release signing keystore?"
  - "What Flutter version should be pinned?" (read from workflow if present)

**Decision points**:
- If the app has no release workflow → ask if they want to add one (delegate to `flutter-github-deploy`)
- If the app has no `fastlane` metadata → ask if they want to add it

---

## Phase 2: Prepare upstream repo for reproducible builds

**Goal**: Make the app build reproducibly so F-Droid can verify it matches your GitHub release.

**Steps**:

### 2.1 Remove unnecessary NDK pinning

- [ ] Check if `android/app/build.gradle` has `ndkVersion flutter.ndkVersion` or a hardcoded NDK version
- [ ] If yes, ask the user: "Should I remove the NDK pin? F-Droid reviewers typically ask for this."
- [ ] If user confirms, remove the NDK pin

### 2.2 Add `dependenciesInfo` block

Add this to `android/app/build.gradle` inside the `android { ... }` block to prevent the "Dependency metadata" scanner error:

```gradle
dependenciesInfo {
    includeInApk = false
    includeInBundle = false
}
```

### 2.3 Add ABI split with versionCodeOverride

Add this to `android/app/build.gradle` **after** the `android { ... }` block and **before** the `flutter { ... }` block:

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

### 2.4 Fix GitHub Actions workflow for reproducibility

The release workflow needs to:
1. Export `SOURCE_DATE_EPOCH` from the commit timestamp
2. Build from a reproducible path (e.g., `/home/vagrant/build/<package-id>`)
3. Build with `--split-per-abi` and upload all 3 APKs

**Key workflow pattern**:

```yaml
env:
  REPRO_BUILD_DIR: /home/vagrant/build/<package-id>

steps:
  - name: Set release metadata
    run: |
      version="${GITHUB_REF_NAME#v}"
      IFS='.' read -r major minor patch <<< "$version"
      build_number=$((10#$major * 10000 + 10#$minor * 100 + 10#$patch))
      source_date_epoch=$(git log -1 --format=%ct "$GITHUB_SHA")
      echo "APP_VERSION=$version" >> $GITHUB_ENV
      echo "BUILD_NUMBER=$build_number" >> $GITHUB_ENV
      echo "SOURCE_DATE_EPOCH=$source_date_epoch" >> $GITHUB_ENV

  - name: Prepare reproducible workspace
    run: |
      sudo mkdir -p /home/vagrant/build
      sudo chown -R "$USER":"$USER" /home/vagrant
      rsync -a --delete --exclude .git ./ "$REPRO_BUILD_DIR/"

  - name: Build direct release APKs
    working-directory: ${{ env.REPRO_BUILD_DIR }}
    run: |
      flutter build apk --release --flavor direct --split-per-abi --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER" <dart-defines>

  - name: Upload release artifacts
    uses: softprops/action-gh-release@v2
    with:
      files: |
        ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/flutter-apk/app-armeabi-v7a-direct-release.apk
        ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/flutter-apk/app-arm64-v8a-direct-release.apk
        ${{ env.REPRO_BUILD_DIR }}/build/app/outputs/flutter-apk/app-x86_64-direct-release.apk
```

**Critical**: The APK filenames are `app-<abi>-<flavor>-release.apk` (ABI first, then flavor). Do NOT use `app-<flavor>-<abi>-release.apk`.

### 2.5 Bump version and create release

- [ ] Ask the user: "What version should I bump to?" (e.g., `2.0.1+20001`)
- [ ] Update `pubspec.yaml` version
- [ ] Commit, tag, and push
- [ ] Wait for the GitHub Actions workflow to complete
- [ ] Verify the release has 3 APK assets + 1 AAB

---

## Phase 3: Create fdroiddata metadata

**Goal**: Create the F-Droid metadata file that tells F-Droid how to build and verify your app.

**Steps**:

### 3.1 Gather information

Ask the user:
- "What category should the app be in?" Check the official list at https://gitlab.com/fdroid/fdroiddata/-/blob/master/config/categories.yml (e.g., `Games`, `Internet`, `Multimedia`)
- "What is the license?" (e.g., `GPL-3.0-only`, `MIT`, `Apache-2.0`)
- "What is your full name for AuthorName?"
- "Do you have a signing certificate SHA-256?" (if not, we'll add it later)

### 3.2 Create the metadata file

Create `metadata/<package-id>.yml` with this structure:

```yaml
Categories:
  - <category>
License: <license>
AuthorName: <author>
SourceCode: <github-repo-url>
IssueTracker: <github-repo-url>/issues
Changelog: <github-repo-url>/releases

AutoName: <app-name>

RepoType: git
Repo: <github-repo-url>.git

Builds:
  - versionName: <version>
    versionCode: <base-code * 10 + 1>
    commit: <full-commit-hash>
    output: build/app/outputs/flutter-apk/app-armeabi-v7a-<flavor>-release.apk
    binary: 
      <github-repo-url>/releases/download/v%v/app-armeabi-v7a-<flavor>-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
      - linux
      - macos
      - web
      - windows
    prebuild:
      - "flutterVersion=$(sed -n -E \"s/.*flutter-version: '(.*)'/\\1/p\" .github/workflows/<workflow-file>.yml)"
      - '[[ $flutterVersion ]]'
      - git -C $$flutter$$ checkout -f $flutterVersion
      - export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
    scandelete:
      - .pub-cache
    build:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --flavor <flavor> --split-per-abi
        --target-platform="android-arm" --build-name $$VERSION$$ --build-number $(( $$VERCODE$$ / 10 )) --dart-define=DISTRIBUTION_CHANNEL=<flavor>
        <other-dart-defines>

  - versionName: <version>
    versionCode: <base-code * 10 + 2>
    commit: <full-commit-hash>
    output: build/app/outputs/flutter-apk/app-arm64-v8a-<flavor>-release.apk
    binary: 
      <github-repo-url>/releases/download/v%v/app-arm64-v8a-<flavor>-release.apk
    <same prebuild/build as above, but with --target-platform="android-arm64">

  - versionName: <version>
    versionCode: <base-code * 10 + 3>
    commit: <full-commit-hash>
    output: build/app/outputs/flutter-apk/app-x86_64-<flavor>-release.apk
    binary: 
      <github-repo-url>/releases/download/v%v/app-x86_64-<flavor>-release.apk
    <same prebuild/build as above, but with --target-platform="android-x64">

AllowedAPKSigningKeys: <sha256-of-signing-cert>

AutoUpdateMode: Version
UpdateCheckMode: Tags ^v[\d.]+$
VercodeOperation:
  - '%c * 10 + 1'
  - '%c * 10 + 2'
  - '%c * 10 + 3'
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: <version>
CurrentVersionCode: <base-code * 10 + 3>
```

**Important rules**:
- `CurrentVersionCode` must be the **highest** ABI code (the one with `+ 3`)
- `binary:` must have a **trailing space** when the URL is on the next line
- Build command line wrapping is exact — run `fdroid rewritemeta` to verify

### 3.3 Add fastlane metadata to upstream repo

If the upstream repo doesn't have `fastlane/metadata/android/`, ask the user:
- "Should I add fastlane metadata to your repo? F-Droid will pull images and descriptions from there."

Create:
- `fastlane/metadata/android/en-US/title.txt`
- `fastlane/metadata/android/en-US/short_description.txt`
- `fastlane/metadata/android/en-US/full_description.txt`
- `fastlane/metadata/android/en-US/images/icon.png`
- `fastlane/metadata/android/en-US/images/phoneScreenshots/*.png`

---

## Phase 4: Local validation

**Goal**: Catch formatting errors before pushing to the MR.

**Steps**:

### 4.1 Install fdroidserver

```bash
python3 -m venv ~/.local/venvs/fdroidserver
source ~/.local/venvs/fdroidserver/bin/activate
pip install fdroidserver
```

### 4.2 Run validation checks

```bash
cd /path/to/fdroiddata

# Check formatting
fdroid rewritemeta <package-id>

# Check for semantic errors
fdroid lint <package-id>

# Check for changes
git diff --stat
```

If `git diff --stat` shows changes after `rewritemeta`, the formatting is wrong. Fix the exact diff before committing.

**Important**: `fdroid rewritemeta` line wrapping depends on character count. The exact wrap points vary based on:
- `--target-platform` length (e.g., `"android-arm64"` is longer than `"android-arm"`)
- URL lengths
- Dart-define flag lengths

**Pattern**: If `rewritemeta` shows a diff, apply that exact diff. Do not try to guess the wrap logic.

---

## Phase 5: Submit MR

**Goal**: Create the fdroiddata merge request.

**Steps**:
- [ ] Create a branch named after the package ID (e.g., `<package-id>`)
- [ ] Commit the metadata file
- [ ] Push the branch
- [ ] Create MR on GitLab
- [ ] Tell the user the MR URL

---

## Phase 6: Handle reviewer feedback

**Goal**: Address reviewer comments and fix CI failures.

**Common issues**:

### 6.1 `fdroid rewritemeta` fails

Read the CI log diff carefully. Apply the exact changes it shows. Common issues:
- `binary:` missing trailing space
- Build command line wrapping not matching expected wrap points
- `CurrentVersionCode` not set to highest ABI code

### 6.2 `fdroid build` fails

Possible causes:
- Missing `binary:` URL → the upstream release doesn't have the APK
- Wrong `output:` path → the APK filename doesn't match what Flutter produces
- Wrong `commit:` hash → the commit doesn't match the release tag

### 6.3 APK scanner fails

- "Dependency metadata" → add `dependenciesInfo` block in `build.gradle`
- "Signing block issues" → check the upstream APK was built with the same signing config

### 6.4 Reviewer requests changes

Follow the reviewer's instructions exactly. If they suggest:
- "Use `$$VERSION$$` and `$$VERCODE$$`" → replace hardcoded values
- "Add `VercodeOperation`" → add it at root level
- "Don't add images here" → remove images from `metadata/` and add to upstream `fastlane/`

---

## Phase 7: Final verification

**Goal**: Confirm everything is correct.

**Checklist**:
- [ ] GitHub release has 3 APKs + 1 AAB
- [ ] `fdroid rewritemeta` produces no diff
- [ ] `fdroid lint` produces no errors
- [ ] MR pipeline is green
- [ ] Reviewer has approved

---

# Key patterns to mirror

## ABI version code scheme

For base version code `N`:
- `armeabi-v7a`: `N * 10 + 1`
- `arm64-v8a`: `N * 10 + 2`
- `x86_64`: `N * 10 + 3`

Example with base `20011`:
- `200111`
- `200112`
- `200113`

## APK filename pattern

With `--flavor direct --split-per-abi`, Flutter produces:
- `app-armeabi-v7a-direct-release.apk`
- `app-arm64-v8a-direct-release.apk`
- `app-x86_64-direct-release.apk`

**Not** `app-direct-armeabi-v7a-release.apk` (wrong order).

## Build command variable substitution

Use `$$VERSION$$` and `$$VERCODE$$` so the metadata works with `VercodeOperation`:

```yaml
- $$flutter$$/bin/flutter build apk --release --flavor direct --split-per-abi
  --target-platform="android-arm" --build-name $$VERSION$$ --build-number $(( $$VERCODE$$ / 10 )) --dart-define=DISTRIBUTION_CHANNEL=direct
```

## Local validation script

```bash
#!/bin/bash
cd /path/to/fdroiddata
source ~/.local/venvs/fdroidserver/bin/activate

echo "=== rewritemeta ==="
fdroid rewritemeta <package-id>

echo ""
echo "=== lint ==="
fdroid lint <package-id>

echo ""
echo "=== diff ==="
git diff --stat

if [ -n "$(git diff --stat)" ]; then
    echo "❌ Changes detected. Fix formatting before pushing."
    exit 1
else
    echo "✅ Clean. Ready to push."
fi
```

---

# Adaptation rules

- This skill is for **existing Flutter Android apps**. Do not create a new project.
- The app must have a **GitHub release workflow** that produces APKs. If not, delegate to `flutter-github-deploy` first.
- The app should have **fastlane metadata** in the upstream repo. If not, ask the user if they want to add it.
- ABI split is required for F-Droid Flutter apps. Do not skip it unless the user explicitly asks.
- Always use the **reviewer's comments** as the source of truth. Their requirements override this skill.
- When in doubt about `rewritemeta` formatting, run it locally and apply the exact diff.

---

# Implementation checklist for OpenCode

- [ ] Inspect upstream repo: `pubspec.yaml`, `android/app/build.gradle`, `.github/workflows/`
- [ ] Ask user for app details (package ID, category, license, author name)
- [ ] Ask user before making upstream changes (ABI split, NDK removal, etc.)
- [ ] Apply upstream changes: NDK removal, `dependenciesInfo`, ABI split, workflow fixes
- [ ] Bump version, commit, tag, and push upstream
- [ ] Wait for GitHub Actions to complete and verify release assets
- [ ] Create fdroiddata metadata with 3 ABI build entries
- [ ] Install `fdroidserver` locally if not present
- [ ] Run `fdroid rewritemeta` and `fdroid lint` locally
- [ ] Fix any formatting issues until `git diff` is clean
- [ ] Commit and push fdroiddata branch
- [ ] Create MR on GitLab
- [ ] Handle reviewer feedback iteratively
- [ ] Verify final pipeline is green

---

# Expected outcome

After applying this skill, the user should have:

- An upstream Flutter app that produces **3 reproducible ABI-split APKs** per release
- A **GitHub release** with all APKs attached
- A **fdroiddata metadata file** that passes `rewritemeta` and `lint`
- An **open MR** on GitLab ready for F-Droid review
- The ability to **validate locally** before pushing

The app should be on a clear path to acceptance into F-Droid.

---

# Important caveats

- `fdroid rewritemeta` line wrapping is **exact** and depends on character counts. Always run it locally.
- The APK filename order is `app-<abi>-<flavor>-release.apk`, not `app-<flavor>-<abi>-release.apk`.
- `CurrentVersionCode` must always be the **highest** ABI-specific code.
- Reviewer feedback is the final authority. This skill provides the standard pattern, but reviewers may have additional requirements.
- Local validation with `fdroidserver` is essential. Do not skip it.
- The `binary:` field must have a **trailing space** when the URL wraps to the next line.

---

# Integration with other skills

This skill **references** these other skills rather than duplicating them:

- `flutter-github-deploy` — if the app has no release workflow, load this skill first
- `flutter-android-starter` — if the app doesn't exist yet, use this instead

After F-Droid acceptance, the user may want to load:
- `flutter-localizing-apps` — if the app needs more languages

---

# Example: Complete metadata file

```yaml
Categories:
  - Games
License: GPL-3.0-only
AuthorName: Giovanni Drago
SourceCode: https://github.com/GiovanniDrago/motivationalApp
IssueTracker: https://github.com/GiovanniDrago/motivationalApp/issues
Changelog: https://github.com/GiovanniDrago/motivationalApp/releases

AutoName: Motivational App

RepoType: git
Repo: https://github.com/GiovanniDrago/motivationalApp.git

Builds:
  - versionName: 2.0.11
    versionCode: 200111
    commit: 0ad749b2c5f010066a9d5136f06fe95aa47dd7a4
    output: build/app/outputs/flutter-apk/app-armeabi-v7a-direct-release.apk
    binary: 
      https://github.com/GiovanniDrago/motivationalApp/releases/download/v%v/app-armeabi-v7a-direct-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
      - linux
      - macos
      - web
      - windows
    prebuild:
      - "flutterVersion=$(sed -n -E \"s/.*flutter-version: '(.*)'/\\1/p\" .github/workflows/android-release-build.yml)"
      - '[[ $flutterVersion ]]'
      - git -C $$flutter$$ checkout -f $flutterVersion
      - export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
    scandelete:
      - .pub-cache
    build:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --flavor direct --split-per-abi
        --target-platform="android-arm" --build-name $$VERSION$$ --build-number $(( $$VERCODE$$ / 10 )) --dart-define=DISTRIBUTION_CHANNEL=direct
        --dart-define=ABOUT_URL=https://github.com/GiovanniDrago/motivationalApp
        --dart-define=DONATION_URL=https://buymeacoffee.com/_takasu_

  - versionName: 2.0.11
    versionCode: 200112
    commit: 0ad749b2c5f010066a9d5136f06fe95aa47dd7a4
    output: build/app/outputs/flutter-apk/app-arm64-v8a-direct-release.apk
    binary: 
      https://github.com/GiovanniDrago/motivationalApp/releases/download/v%v/app-arm64-v8a-direct-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
      - linux
      - macos
      - web
      - windows
    prebuild:
      - "flutterVersion=$(sed -n -E \"s/.*flutter-version: '(.*)'/\\1/p\" .github/workflows/android-release-build.yml)"
      - '[[ $flutterVersion ]]'
      - git -C $$flutter$$ checkout -f $flutterVersion
      - export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
    scandelete:
      - .pub-cache
    build:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --flavor direct --split-per-abi
        --target-platform="android-arm64" --build-name $$VERSION$$ --build-number
        $(( $$VERCODE$$ / 10 )) --dart-define=DISTRIBUTION_CHANNEL=direct --dart-define=ABOUT_URL=https://github.com/GiovanniDrago/motivationalApp
        --dart-define=DONATION_URL=https://buymeacoffee.com/_takasu_

  - versionName: 2.0.11
    versionCode: 200113
    commit: 0ad749b2c5f010066a9d5136f06fe95aa47dd7a4
    output: build/app/outputs/flutter-apk/app-x86_64-direct-release.apk
    binary: 
      https://github.com/GiovanniDrago/motivationalApp/releases/download/v%v/app-x86_64-direct-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
      - linux
      - macos
      - web
      - windows
    prebuild:
      - "flutterVersion=$(sed -n -E \"s/.*flutter-version: '(.*)'/\\1/p\" .github/workflows/android-release-build.yml)"
      - '[[ $flutterVersion ]]'
      - git -C $$flutter$$ checkout -f $flutterVersion
      - export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
    scandelete:
      - .pub-cache
    build:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --flavor direct --split-per-abi
        --target-platform="android-x64" --build-name $$VERSION$$ --build-number $(( $$VERCODE$$ / 10 )) --dart-define=DISTRIBUTION_CHANNEL=direct
        --dart-define=ABOUT_URL=https://github.com/GiovanniDrago/motivationalApp
        --dart-define=DONATION_URL=https://buymeacoffee.com/_takasu_

AllowedAPKSigningKeys: 410e1066bdb3e97eb266feda014c525ae35cbbca581ba397e875640da73fa0b4

AutoUpdateMode: Version
UpdateCheckMode: Tags ^v[\d.]+$
VercodeOperation:
  - '%c * 10 + 1'
  - '%c * 10 + 2'
  - '%c * 10 + 3'
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: 2.0.11
CurrentVersionCode: 200113
```

**Note**: This example shows the exact line wrapping that `rewritemeta` expects. The wrap points vary based on `--target-platform` length and dart-define URLs. Always run `rewritemeta` to verify.
