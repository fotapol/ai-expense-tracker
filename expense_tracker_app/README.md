# AI Expense Tracker Flutter App

Flutter client for AI Expense Tracker.

The app provides authentication, receipt scanning/upload, transaction review,
analytics, planning, settings, subscription UI, and account-management flows.

## Custom Period Filters

In Receipt Manager or Analytics, open **Filters → Custom period**, choose the
start and end dates in the calendar, then press **Apply** in the filter sheet.
Dates from January 1, 2000 through today are supported, including single-day
ranges. Both selected days are included in full using the device's local time.
Canceling the calendar or filter sheet leaves the applied filters unchanged.

Analytics remembers its custom dates across restarts and uses the same range
for summaries, charts, and category/item details. Comparisons use the preceding
interval of equal duration; daily averages use the selected calendar-day count.
Receipt Manager retains its range while its screen remains open. The pages
keep their selections independently, and existing period presets remain available.

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
TZ=UTC flutter test
```

UTC matches CI. Also run the custom-period tests in a daylight-saving timezone:

```bash
TZ=Europe/Berlin flutter test test/period_filter_test.dart test/analytics_filter_preferences_test.dart test/custom_period_filter_widget_test.dart test/custom_period_screens_test.dart test/custom_period_trends_test.dart test/transaction_date_range_api_test.dart
```

## Notes

Firebase client configuration is intentionally part of the mobile app. Treat it
as public client configuration and restrict API keys in Firebase/Google Cloud.
