# SillyTavern Headless Flutter

Flutter mobile client for the SillyTavern headless API.

This first pass focuses on data compatibility with the existing server:

- Configure a backend URL directly in the app.
- Load bootstrap, library, model provider metadata, characters, chats, and pages
  of chat messages from `/api/headless/v1`.
- Switch model provider/source/model settings through the headless settings API.
- Switch character cards and edit common TavernCard front-end fields.
- Manage character chat files by date and size, delete old files, and create
  branches from any loaded message.
- Keep only small local cache values such as the backend URL and last selection.

## Running

Android and iOS runners are included. Install dependencies, check the project,
then run it against a headless backend:

```bash
cd mobile/flutter_headless
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=HEADLESS_BASE_URL=https://st.example.com
```

If the platform runners ever need to be regenerated, run
`flutter create --platforms=android,ios --project-name sillytavern_headless .`
from this directory.

The server must expose:

```text
/api/headless/v1
/csrf-token
/thumbnail
/characters
```

Use the app settings tab to change the backend URL without rebuilding.
