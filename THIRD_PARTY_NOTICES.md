# Third-Party Notices

AI Expense Tracker uses open-source libraries and third-party SDKs across the
backend, Flutter client, infrastructure, and public site.

## Dependency Notices

Primary dependency manifests:

- Backend: `backend/pyproject.toml` and `backend/uv.lock`
- Flutter: `expense_tracker_app/pubspec.yaml` and `expense_tracker_app/pubspec.lock`
- Site: `site/requirements.txt`
- Container images: `Dockerfile`, `site/Dockerfile`, and `infra/images/postgres-backup/Dockerfile`

Before publishing a formal release, generate a dependency license report from
the current lockfiles and attach it to this file or release artifacts.

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
