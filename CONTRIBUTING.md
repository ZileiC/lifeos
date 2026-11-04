# Contributing

Thanks for taking a look. LifeOS is a small, opinionated project; the most useful contributions are bug reports with reproduction steps and focused patches.

## Before you start

- The product direction is documented in the README. In particular: the phone does not record completion, and AI is suggestion-only.
- Open an issue before a large change so the scope is agreed on. Small fixes can go straight to a PR.
- Keep changes narrow. Do not add features outside the current roadmap without an issue first.

## Development

```bash
flutter pub get
flutter run -d windows   # desktop preview (developer mode enabled for symlinks)
flutter analyze
flutter test
```

Requirements: Flutter 3.x (the CI pins a stable version), Dart 3.13+, Android SDK for APK builds. No API key is needed to build or test; AI flows use fakes in tests.

## Code style

- Source code and comments are English. UI strings are Chinese.
- Follow the existing layering: `lib/data` (Drift, repositories), `lib/ai` (provider, client, prompts, validator, services), `lib/ui` (widgets).
- New behavior needs a test at the relevant seam. For AI changes, prefer the fake-client tests over network calls.
- Never commit API keys, signing material, or personal data. The AI key is entered at runtime and stored in the platform keystore.

## Pull requests

- One logical change per PR; include the reason and the user-visible effect.
- Run `flutter analyze` and `flutter test` locally before opening the PR; the CI runs both.
- Add or update tests for behavior changes.
- Keep commit messages imperative and scoped (e.g. `fix: keep weekly slices on template edit`).

## Reporting bugs

Use the issue template and include:

- app version and Android version (or that you run it on Windows);
- exact steps to reproduce;
- expected vs actual;
- screenshots or a short screen recording when the UI is involved;
- whether AI was involved (provider/model), and never paste an API key.

## Security

Do not open public issues for security problems. See [SECURITY.md](SECURITY.md).
