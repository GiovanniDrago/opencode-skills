---
name: flutter-android-starter
description: Scaffold a new Flutter Android project with Material 3 themes (light/dark catalog), Riverpod state management, English/Italian localization, and a production-ready foundation.
---

# When to use
Use this skill **only for brand-new Flutter Android projects** that need a solid, production-ready foundation before feature development begins.

This skill sets up:
- **Material 3 dynamic theming** with a curated light/dark theme catalog (inspired by `ColorScheme.fromSeed`)
- **Riverpod v2** state management with `StateNotifierProvider` for theme and locale persistence
- **Localization** pre-configured for **English + Italian**, with infrastructure to add more languages
- **Comprehensive `.gitignore`** for Flutter, Android, and VSCode
- **README** with a human-friendly title and startup commands
- **GitHub deploy integration** via the `flutter-github-deploy` skill if available

This skill is **not** for existing projects. For existing codebases, apply the individual domain skills (`flutter-localizing-apps`, `flutter-github-deploy`) instead.

# What this foundation contains

## Theme system
A Material 3 theme catalog managed by Riverpod and persisted with `shared_preferences`.

- `lib/theme/app_theme.dart` — defines `AppThemeOption`, the theme catalog, and `buildAppTheme()`
- `lib/providers/theme_provider.dart` — `StateNotifierProvider` that loads/saves the active theme
- Themes are generated dynamically via `ColorScheme.fromSeed(seedColor, brightness)` with `useMaterial3: true`
- Light and dark variants are discrete options in the catalog

## Localization
Flutter's built-in `flutter_localizations` + `intl` with code generation.

- `l10n.yaml` — gen-l10n configuration
- `lib/l10n/app_en.arb` — English template
- `lib/l10n/app_it.arb` — Italian translation
- `lib/providers/locale_provider.dart` — `StateNotifierProvider` for locale persistence
- Adding a new language later: create `app_XX.arb`, add `Locale('XX')` to `supportedLocales`, run `flutter gen-l10n`

## State management
Riverpod v2 with `flutter_riverpod`.

- Root app wrapped in `ProviderScope`
- `ConsumerWidget` / `ConsumerStatefulWidget` for UI
- `StateNotifierProvider` for theme and locale
- `shared_preferences` used for lightweight persistence (swappable to Hive/ObjectBox later without changing provider structure)

## GitHub Actions deploy
This skill **references** `flutter-github-deploy` rather than duplicating it.

- If `flutter-github-deploy` is available in the OpenCode skills registry, load and apply it after the foundation is set.
- If it is not available, document in the README that the user can apply it later.

# Source patterns to mirror

## pubspec.yaml dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^2.6.1
  shared_preferences: ^2.5.3
  intl: any

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
  generate: true
```

## l10n.yaml

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

## lib/l10n/app_en.arb

```json
{
  "@@locale": "en",
  "appTitle": "My App",
  "@appTitle": {
    "description": "Application title"
  },
  "themeLabel": "Theme",
  "@themeLabel": {
    "description": "Theme setting label"
  },
  "languageLabel": "Language",
  "@languageLabel": {
    "description": "Language setting label"
  }
}
```

## lib/l10n/app_it.arb

```json
{
  "@@locale": "it",
  "appTitle": "La Mia App",
  "themeLabel": "Tema",
  "languageLabel": "Lingua"
}
```

## lib/theme/app_theme.dart

```dart
import 'package:flutter/material.dart';

class AppThemeOption {
  final String id;
  final String name;
  final Color seedColor;
  final Brightness brightness;

  const AppThemeOption({
    required this.id,
    required this.name,
    required this.seedColor,
    required this.brightness,
  });
}

const List<AppThemeOption> appThemes = [
  AppThemeOption(
    id: 'default_light',
    name: 'Default Light',
    seedColor: Color(0xFF6750A4),
    brightness: Brightness.light,
  ),
  AppThemeOption(
    id: 'ocean_light',
    name: 'Ocean Light',
    seedColor: Color(0xFF00677D),
    brightness: Brightness.light,
  ),
  AppThemeOption(
    id: 'default_dark',
    name: 'Default Dark',
    seedColor: Color(0xFFD0BCFF),
    brightness: Brightness.dark,
  ),
  AppThemeOption(
    id: 'forest_dark',
    name: 'Forest Dark',
    seedColor: Color(0xFF2E5D3B),
    brightness: Brightness.dark,
  ),
];

AppThemeOption appThemeById(String id) {
  return appThemes.firstWhere(
    (theme) => theme.id == id,
    orElse: () => appThemes.first,
  );
}

ThemeData buildAppTheme(AppThemeOption option) {
  final scheme = ColorScheme.fromSeed(
    seedColor: option.seedColor,
    brightness: option.brightness,
  );
  final isDark = option.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
    ),
    cardTheme: CardThemeData(
      elevation: isDark ? 1 : 2,
      color: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onSecondaryContainer),
      shape: const StadiumBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      textColor: scheme.onSurface,
    ),
  );
}
```

## lib/providers/theme_provider.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeOption>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<AppThemeOption> {
  static const _key = 'theme_id';

  ThemeNotifier() : super(appThemes.first) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_key);
    if (id != null) {
      state = appThemeById(id);
    }
  }

  Future<void> setTheme(String id) async {
    final option = appThemeById(id);
    state = option;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }
}
```

## lib/providers/locale_provider.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  static const _key = 'locale';

  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_key);
    if (tag != null) {
      state = Locale(tag);
    }
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageCode);
  }
}
```

## lib/main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeOption = ref.watch(themeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: AppLocalizations.of(context)?.appTitle ?? 'My App',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(themeOption),
      locale: locale,
      supportedLocales: const [
        Locale('en'),
        Locale('it'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final themeNotifier = ref.read(themeProvider.notifier);
    final localeNotifier = ref.read(localeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.themeLabel, style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              children: appThemes.map((t) {
                return ActionChip(
                  label: Text(t.name),
                  onPressed: () => themeNotifier.setTheme(t.id),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(l10n.languageLabel, style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('English'),
                  onPressed: () => localeNotifier.setLocale(const Locale('en')),
                ),
                ActionChip(
                  label: const Text('Italiano'),
                  onPressed: () => localeNotifier.setLocale(const Locale('it')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

# Workflow

## Phase 1: Project creation and inspection
- [ ] Confirm the target directory is empty or contains a fresh Flutter project.
- [ ] If `pubspec.yaml` is missing, run `flutter create --platforms=android .`
- [ ] Read existing `pubspec.yaml`, `.gitignore`, and `README.md` if they exist.

## Phase 2: Dependencies
- [ ] Update `pubspec.yaml` with the dependencies listed above.
- [ ] Ensure `flutter.generate: true` is present.
- [ ] Run `flutter pub get`.

## Phase 3: Localization infrastructure
- [ ] Create `l10n.yaml` at project root.
- [ ] Create `lib/l10n/app_en.arb` and `lib/l10n/app_it.arb` with starter keys.
- [ ] Run `flutter gen-l10n` to verify ARB syntax and generate `AppLocalizations`.

## Phase 4: Theme system
- [ ] Create `lib/theme/app_theme.dart` with the catalog and `buildAppTheme()`.

## Phase 5: Riverpod providers
- [ ] Create `lib/providers/theme_provider.dart` with `StateNotifierProvider` and `shared_preferences` persistence.
- [ ] Create `lib/providers/locale_provider.dart` with the same pattern.

## Phase 6: Main app entry point
- [ ] Rewrite `lib/main.dart` to:
  - Wrap with `ProviderScope`
  - Use `ConsumerWidget`
  - Build `MaterialApp` with `theme`, `locale`, `supportedLocales`, and `localizationsDelegates`
  - Include a minimal `HomePage` with working theme and locale toggles

## Phase 7: .gitignore
- [ ] Create or update `.gitignore` with the comprehensive Flutter + VSCode template below.

## Phase 8: GitHub deploy integration
- [ ] Check whether the `flutter-github-deploy` skill is available.
- [ ] If available: load and apply it to set up tag-driven GitHub Actions release.
- [ ] If not available: add a note in the README telling the user they can apply it later.

## Phase 9: README
- [ ] Derive a friendly title from `pubspec.yaml` `name`, the folder name, or the user's prompt.
  - Replace underscores with spaces.
  - Title-case the result.
- [ ] Write a short, friendly description.
- [ ] Add the startup commands section:
  ```bash
  flutter pub get
  flutter gen-l10n
  flutter run
  ```
- [ ] Add a note about supported locales and how to add more.
- [ ] Add a note about the theme system.

## Phase 10: Verification
- [ ] Run `flutter pub get`.
- [ ] Run `flutter gen-l10n`.
- [ ] Run `flutter analyze`.
- [ ] Confirm the app builds and runs with working theme and locale toggles.

# Comprehensive .gitignore template

```gitignore
# Miscellaneous
*.class
*.log
*.pyc
*.swp
.DS_Store
.atom/
.buildlog/
.history
.svn/
migrate_working_dir/

# IntelliJ / Android Studio
*.iml
*.ipr
*.iws
.idea/

# VS Code
.vscode/
*.code-workspace

# Flutter / Dart / Pub
**/doc/api/
**/ios/Flutter/.last_build_id
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.pub-cache/
.pub/
/build/
.packages
.packages.generated
.pub-preload-cache/

# Symbolication
app.*.symbols

# Obfuscation
app.*.map.json

# Android build artifacts
/android/app/debug
/android/app/profile
/android/app/release
.gradle/
**/android/**/gradle-wrapper.jar
**/android/captures/
**/android/gradlew
**/android/gradlew.bat
**/android/local.properties
**/android/**/GeneratedPluginRegistrant.java
/android/key.properties
*.jks
**/android/app/*.keystore

# iOS / Xcode
**/ios/**/*.mode1v3
**/ios/**/*.mode2v3
**/ios/**/*.moved-aside
**/ios/**/*.pbxuser
**/ios/**/*.perspectivev3
**/ios/**/*sync/
**/ios/**/.sconsign.dblite
**/ios/**/.tags*
**/ios/**/.vagrant/
**/ios/**/DerivedData/
**/ios/**/Icon?
**/ios/**/Pods/
**/ios/**/.symlinks/
**/ios/**/profile
**/ios/**/xcuserdata
**/ios/.generated/
**/ios/Flutter/.last_build_id
**/ios/Flutter/App.framework
**/ios/Flutter/Flutter.framework
**/ios/Flutter/Flutter.podspec
**/ios/Flutter/Generated.xcconfig
**/ios/Flutter/ephemeral
**/ios/Flutter/app.flx
**/ios/Flutter/app.zip
**/ios/Flutter/flutter_assets/
**/ios/Flutter/flutter_export_environment.sh
**/ios/ServiceDefinitions.json
**/ios/Runner/GeneratedPluginRegistrant.*

# macOS
**/Flutter/ephemeral/
**/Pods/
**/macos/Flutter/GeneratedPluginRegistrant.swift
**/macos/Flutter/ephemeral
**/xcuserdata/

# Windows
**/windows/flutter/generated_plugin_registrant.cc
**/windows/flutter/generated_plugin_registrant.h
**/windows/flutter/generated_plugins.cmake

# Linux
**/linux/flutter/generated_plugin_registrant.cc
**/linux/flutter/generated_plugin_registrant.h
**/linux/flutter/generated_plugins.cmake

# Generated files
*.g.dart
*.freezed.dart
*.mocks.dart

# Environment
.env
.env.local
.env.*.local

# Coverage
coverage/

# Temporary
*.tmp
*.temp
*.cache
pubspec.lock
```

# Adaptation rules
Apply only minimal adaptations. Keep the foundation identical.

- Keep the folder structure (`lib/theme/`, `lib/providers/`, `lib/l10n/`).
- Keep the theme catalog pattern; only adapt seed colors if the user explicitly requests different ones.
- Keep `shared_preferences` as the default persistence layer. Do not swap to Hive or ObjectBox unless the user explicitly asks.
- Keep the default locales as English and Italian. Add more only when the user requests them.
- Keep the `flutter-github-deploy` reference as a delegation, not an inline duplicate.
- Do not add architecture patterns (Clean Architecture, BLoC, etc.) unless the user explicitly asks.
- Do not add Firebase, analytics, or push notifications unless the user explicitly asks.
- Do not add test files unless the user explicitly asks.

# Integration with flutter-github-deploy
After the foundation is complete:

1. Check if `flutter-github-deploy` is in the available skills.
2. If yes, load it and follow its workflow to add the tag-driven GitHub Actions Android release flow.
3. If no, append this section to the README:
   ```markdown
   ## GitHub Release Build (Optional)
   To add automated signed APK releases via GitHub Actions, apply the `flutter-github-deploy` skill.
   ```

# Important caveats
- This skill is designed for **new projects**. Running it on an existing project may overwrite `lib/main.dart` and `pubspec.yaml`.
- The demo `HomePage` in `lib/main.dart` is intentionally minimal. It should be replaced with real app screens.
- `shared_preferences` is suitable for small config data (theme ID, locale). Do not use it for large datasets or complex relational data.
- A local `flutter build apk --release` may fail without local Android signing files. The debug build will work for development.

# Implementation checklist for OpenCode
- inspect the target directory; run `flutter create --platforms=android .` only if needed
- update `pubspec.yaml` with dependencies and `generate: true`
- create `l10n.yaml` and starter ARB files
- create `lib/theme/app_theme.dart`
- create `lib/providers/theme_provider.dart` and `lib/providers/locale_provider.dart`
- rewrite `lib/main.dart` with `ProviderScope`, `ConsumerWidget`, `MaterialApp`, and demo `HomePage`
- create or update `.gitignore` with the comprehensive template
- check for `flutter-github-deploy` skill availability and apply if present
- generate or update `README.md` with a friendly title and startup commands
- run `flutter pub get`, `flutter gen-l10n`, and `flutter analyze`
- verify the app runs and theme/locale toggles work

# Expected outcome
After applying this skill, the target repository should be a runnable Flutter Android project with:

- A working Material 3 theme system with multiple light and dark options
- English and Italian localization via `AppLocalizations`
- Riverpod-managed theme and locale state persisted across app restarts
- A comprehensive `.gitignore` ready for VSCode and Flutter development
- A friendly README with install and run commands
- Optionally, the `flutter-github-deploy` release pipeline if that skill was available

The user can then immediately start building features on top of this foundation.
