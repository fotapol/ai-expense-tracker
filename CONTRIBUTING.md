# Contributing

Thanks for taking a look at AI Expense Tracker. This repository is maintained
as a practical full-stack, AI-assisted expense tracking system.

## Development Principles

- Preserve user data boundaries and authentication checks.
- Keep receipt images, secrets, and production configuration out of Git.
- Prefer focused changes over broad rewrites.
- Add tests for behavior changes.
- Document operational or AI-quality tradeoffs when they matter.

## Local Setup

Start the backend dependencies and services from the repository root:

```bash
cp .env.example .env
docker compose up --build
```

Run backend checks:

```bash
cd backend
uv sync --frozen --all-groups
uv run ruff check .
uv run pytest
```

Run mobile checks:

```bash
cd expense_tracker_app
flutter pub get
flutter analyze
flutter test
```

## Pull Requests

Before opening a PR:

- Run the relevant backend and Flutter checks.
- Run Gitleaks locally when changing configuration, CI, docs, or env examples.
- Keep generated files out of the PR unless they are intentionally updated.
- Explain security, privacy, or AI-quality implications when relevant.
- Include screenshots only when UI behavior changes.

## Security Rules

Do not commit:

- `.env` or `.env.production`
- Firebase service-account JSON
- Google/Gemini/OpenAI/Anthropic API keys
- RevenueCat secret keys or webhook secrets
- Database, RabbitMQ, Redis, or S3 credentials
- Private certificates, origin keys, keystores, or signing material
- Real receipt images or user data

Use sanitized examples, synthetic receipts, and placeholder credentials in docs
and tests.

## Coding Style

- Python: Ruff with the repository configuration.
- Dart/Flutter: `flutter analyze` and the configured Flutter lints.
- Documentation: concise Markdown, no real production secrets, no private
  domains unless they are intentionally public examples.
