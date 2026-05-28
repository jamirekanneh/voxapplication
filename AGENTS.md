# AGENTS.md

## Cursor Cloud specific instructions

### Overview

This is a Flutter mobile/web app called **Vox** — an AI-powered accessibility and productivity app for reading documents with TTS, voice commands, OCR, and study tools. Backend is Firebase (BaaS) — no local backend services to run.

### Environment Setup

- **Flutter SDK** must be installed at `~/flutter` and on PATH. The project requires Dart SDK `^3.9.2` (Flutter 3.44+ satisfies this).
- **Chrome** is available at `/usr/local/bin/google-chrome` for web development.
- The `assets/project.env` file is gitignored. Create it with at minimum: `OPENROUTER_API_KEY=`, `NLP_API_URL=`, `NLP_API_KEY=` (can be empty for basic app functionality).

### Case-Sensitivity Workaround (Linux)

The repo has files `lib/About_Us_Page.dart` and `lib/Statistics_page.dart` but imports reference lowercase `about_us_page.dart` and `statistics_page.dart`. On Linux (case-sensitive FS), symlinks are needed:

```sh
cd lib && ln -sf About_Us_Page.dart about_us_page.dart && ln -sf Statistics_page.dart statistics_page.dart
```

### Running the App

```sh
flutter run -d web-server --web-port=8080 --web-hostname=0.0.0.0
```

Or use Chrome directly:

```sh
flutter run -d chrome
```

### Lint / Analyze

```sh
flutter analyze
```

Only info-level issues exist (deprecation warnings, style). No errors after symlinks.

### Tests

No `test/` directory exists in this repository. `flutter test` will report "Test directory not found."

### Key Notes

- All backend services (Auth, Firestore, Storage) are Firebase cloud-hosted; no local emulators are configured.
- AI features (chatbot, flashcards, summarization) require a valid `OPENROUTER_API_KEY` in `assets/project.env`.
- The app works in guest mode without Firebase auth — click "Continue without account" on the onboarding screen.
