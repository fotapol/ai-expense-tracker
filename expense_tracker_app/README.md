# AI Expense Tracker Flutter App

Flutter client for AI Expense Tracker.

The app provides authentication, receipt scanning/upload, transaction review,
analytics, planning, settings, subscription UI, and account-management flows.

## Local Setup

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Use `10.0.2.2` for an Android emulator. For a physical device, use your
development machine's LAN IP, for example:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
```

## Production Build Inputs

Production builds should pass public runtime values with `--dart-define`:

- `API_BASE_URL`
- `APP_WEBSITE_URL`
- `APP_PRIVACY_URL`
- `APP_TERMS_URL`
- `APP_DELETE_ACCOUNT_URL`
- `APP_SUPPORT_EMAIL`
- `REVENUECAT_ANDROID_API_KEY`
- `REVENUECAT_IOS_API_KEY`
- `REVENUECAT_PREMIUM_ENTITLEMENT_ID`

Do not include server-side secrets in Flutter builds.

## Checks

```bash
flutter analyze
flutter test
```

## Notes

Firebase client configuration is intentionally part of the mobile app. Treat it
as public client configuration and restrict API keys in Firebase/Google Cloud.
