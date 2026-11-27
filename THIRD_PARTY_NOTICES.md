# Third-Party Notices

AI Expense Tracker uses open-source libraries and third-party SDKs across the
backend, Flutter client, infrastructure, and public site.

## Dependency Notices

Primary dependency manifests:

- Backend: `backend/pyproject.toml` and `backend/uv.lock`
- Flutter: `expense_tracker_app/pubspec.yaml` and `expense_tracker_app/pubspec.lock`
- Container images: `Dockerfile`, `site/Dockerfile`, and `infra/images/postgres-backup/Dockerfile`

Flutter bundles the license notices from the mobile build's package
dependencies. Open **Settings → About → Licenses → View all license notices**
to read the full texts.

## Interface Icons

App-owned interface icons use [Lucide](https://lucide.dev), maintained by Lucide
Icons and Contributors, through the
[`lucide_icons_flutter`](https://pub.dev/packages/lucide_icons_flutter) adapter.
Lucide is licensed under ISC (copyright © 2026 Lucide Icons and Contributors).
Icons derived from Feather also retain the MIT notice (copyright © 2013–present
Cole Bemis). The complete upstream notices are bundled in
`expense_tracker_app/assets/licenses/lucide-LICENSE` and available through
the full license list in the app.

The Flutter adapter is MIT licensed (copyright © 2024 vqhapp); its license is
included by Flutter's dependency license registry. Flutter's native controls
and their bundled Material assets retain their own licenses, available on the
same Licenses page. The Lucide license does not replace Flutter's notices.

See the [official Lucide license](https://lucide.dev/license) and
[adapter license](https://pub.dev/packages/lucide_icons_flutter/license).

## Brand And Platform Assets

The Google sign-in mark under `expense_tracker_app/assets/auth/google_g.png`
is used to support Google authentication UX and remains subject to Google's
branding guidelines. It is not relicensed under the MIT license for this
repository.

Application icons and brand images under `expense_tracker_app/assets/brand/`
and platform icon folders should only be reused if you have the rights to do so.

## External Services

This project integrates with Firebase, Google Gemini, RevenueCat, S3-compatible
object storage, and optional LangSmith tracing. Their SDKs, APIs, dashboards,
and service terms remain governed by their respective providers.
