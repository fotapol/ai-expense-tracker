# Security Policy

AI Expense Tracker processes authentication data, receipt images, expense
records, object-storage URLs, subscription events, and AI provider requests.
Please report security issues privately and do not open public issues for
vulnerabilities or exposed secrets.

## Supported Versions

This repository is an open-source application project. Security fixes are accepted
against the default branch unless a maintained release branch is explicitly
listed in the README or changelog.

## Reporting A Vulnerability

If you find a vulnerability, use GitHub's private vulnerability reporting for
this repository. Do not create a public issue for security-sensitive reports.

Include:

- A concise description of the issue.
- Impact and affected component.
- Reproduction steps or proof of concept.
- Any logs, screenshots, or request examples with secrets redacted.

Expected response:

- Initial acknowledgement: within 7 days.
- Triage update: within 14 days when enough detail is provided.
- Coordinated disclosure: after a fix or mitigation is available.

## Secret Handling

Never include real credentials in issues, pull requests, screenshots, logs, or
test fixtures. This includes Firebase service accounts, Google/Gemini keys,
RevenueCat secrets, database URLs, RabbitMQ passwords, S3/MinIO credentials,
private certificates, keystores, and production `.env` files.

Before publishing a fork or archive:

```bash
gitleaks detect --source . --config .gitleaks.toml --redact --verbose
```

Also verify that local Git stashes and reflogs do not contain sensitive files
before publishing a fork, mirror, or archive.

## Public Client Configuration

Mobile Firebase configuration files may contain public client identifiers. They
are not treated as server secrets, but production projects must restrict API
keys in Google Cloud/Firebase by platform package/bundle identifiers, signing
certificate fingerprints, API allowlists, quotas, App Check where appropriate,
and locked-down Firebase security rules.
