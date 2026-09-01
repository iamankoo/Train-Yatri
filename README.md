# Train Yatri

Train Yatri is a fast, simple Indian Railways companion app: search trains,
track them live, and check PNR/status without wading through clutter.

This is the native Flutter rebuild of Train Yatri (Android + iOS). It
replaces the project's earlier React Native/Expo implementation, which is
no longer the active codebase.

## Status

Foundation stage. The current build ships:

- App shell, branding, splash screen and Home screen UI
- The Train Yatri design system (theme, buttons, fields, empty/loading/error
  states)
- Navigation and architecture foundation for the features below
- The offline railway database schema, import pipeline and repository
  layer (see [`docs/RAILWAY_DATABASE.md`](docs/RAILWAY_DATABASE.md)) -
  **infrastructure only for now: no railway dataset is bundled yet**,
  since none has been supplied. Nothing in the running app depends on
  it until a real dataset lands.

Station/train search, live status, offline tracking, ratings, PNR and
booking are being built out feature-by-feature on top of this foundation -
none of them show placeholder or fabricated data in the meantime.

## Tech stack

- Flutter / Dart
- Riverpod (state management)
- SQLite (`sqflite`) for the offline railway database

No AI, chatbot, or LLM features are part of this product.

## Getting started

```bash
flutter pub get
flutter run
```

Android debug build:

```bash
flutter build apk --debug
```

iOS builds require Xcode on macOS.

## Project layout

```
lib/
  core/      # routing, environment config
  data/      # database, import pipeline, repositories
  domain/    # entities, repository interfaces, services
  services/  # backend clients (RailRadar, location) - added later
  features/  # one folder per screen/feature
  shared/    # design system: theme, reusable widgets, utils
bin/
  import_railway_data.dart  # rebuilds assets/database/railway.db from CSV
```

## Configuration

The app only ever receives non-secret configuration (e.g. `API_BASE_URL`)
via `--dart-define`. Provider API keys stay server-side in the Train Yatri
backend and are never bundled into the app.

## Author

Aniket
