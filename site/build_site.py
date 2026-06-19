from __future__ import annotations

import argparse
import html
import json
import os
import shutil
from pathlib import Path
from textwrap import dedent


SITE_ROOT = Path(__file__).resolve().parent
REPO_ROOT = SITE_ROOT.parent
SRC_ROOT = SITE_ROOT / "src"
DEFAULT_OUTPUT = SITE_ROOT / "dist"

THEME_BOOTSTRAP = """<script>(function(){try{var saved=localStorage.getItem("site-theme");var theme=saved||(window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light");document.documentElement.dataset.theme=theme;}catch(_){document.documentElement.dataset.theme="light";}})();</script>"""


def site_config() -> dict[str, str]:
    return {
        "supportEmail": (os.environ.get("APP_SUPPORT_EMAIL") or "").strip(),
        "supportSubject": (os.environ.get("APP_SUPPORT_SUBJECT") or "").strip(),
    }


def nav_link(label: str, href: str, current_page: str, page_key: str) -> str:
    current = ' aria-current="page"' if current_page == page_key else ""
    return f'<a class="nav-link" href="{href}"{current}>{html.escape(label)}</a>'


def footer(current_page: str) -> str:
    del current_page
    return dedent(
        """
        <footer class="site-footer">
          <div class="footer-copy">
            <span class="footer-brand">AI Expense Tracker</span>
            <p>Scan receipts, review spending, and keep budgets and reminders close at hand.</p>
          </div>
          <div class="footer-links">
            <a href="/">Home</a>
            <a href="/delete-account">Delete account</a>
            <a data-support-email-link href="#" hidden>support@example.com</a>
          </div>
        </footer>
        """
    ).strip()


def shell(title: str, description: str, current_page: str, body_class: str, main_content: str) -> str:
    nav = "\n".join(
        [
            nav_link("Home", "/", current_page, "home"),
            nav_link("Delete account", "/delete-account", current_page, "delete-account"),
        ]
    )
    return dedent(
        f"""\
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="description" content="{html.escape(description)}" />
          <meta name="theme-color" content="#111418" />
          <title>{html.escape(title)} | AI Expense Tracker</title>
          <link rel="icon" type="image/png" href="/favicon.png" />
          {THEME_BOOTSTRAP}
          <link rel="stylesheet" href="/styles.css" />
          <script src="/site-config.js" defer></script>
          <script src="/site.js" defer></script>
        </head>
        <body class="{body_class}">
          <div class="page-shell">
            <header class="site-header">
              <a class="brand-lockup" href="/" aria-label="AI Expense Tracker home">
                <span class="brand-mark" aria-hidden="true">
                  <img class="brand-logo brand-logo-light" src="/logo-login-black.png" alt="" />
                  <img class="brand-logo brand-logo-dark" src="/logo-login-white.png" alt="" />
                </span>
              </a>
              <nav class="site-nav" aria-label="Primary">
                {nav}
              </nav>
              <button class="theme-toggle" type="button" data-theme-toggle aria-label="Switch theme" title="Switch theme">
                <svg class="theme-icon theme-icon-moon" aria-hidden="true" viewBox="0 0 24 24">
                  <path d="M20 15.7A8.8 8.8 0 0 1 8.3 4a7.2 7.2 0 1 0 11.7 11.7Z" />
                </svg>
                <svg class="theme-icon theme-icon-sun" aria-hidden="true" viewBox="0 0 24 24">
                  <path d="M12 7a5 5 0 1 1 0 10 5 5 0 0 1 0-10Zm0-5v3m0 14v3M4.2 4.2l2.1 2.1m11.4 11.4 2.1 2.1M2 12h3m14 0h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1" />
                </svg>
              </button>
            </header>
            <main class="page-main">
              {main_content}
            </main>
            {footer(current_page)}
          </div>
        </body>
        </html>
        """
    )


def home_page() -> str:
    content = dedent(
        """
        <section class="hero">
          <div class="hero-copy">
            <span class="eyebrow">AI Expense Tracker</span>
            <h1>Receipts become spending clarity.</h1>
            <p class="hero-lede">
              Scan receipts, organize purchases, understand trends, and keep budgets and bill
              reminders close without turning personal finance into a second job.
            </p>
            <p class="hero-meta" data-support-line hidden>
              Need help? <a class="inline-link" data-support-email-link href="#">support@example.com</a>
            </p>
            <div class="hero-links">
              <a class="inline-link" href="/delete-account">Delete account</a>
            </div>
          </div>
        </section>

        <section class="section-grid">
          <article class="feature-card">
            <span class="card-kicker">Receipt scanning</span>
            <h2>Start with the paper trail.</h2>
            <p>Upload receipts, extract the useful details, and keep the source image attached to the record.</p>
          </article>
          <article class="feature-card">
            <span class="card-kicker">Analytics</span>
            <h2>Spot the pattern, not just the total.</h2>
            <p>Review spending trends, categories, and labels to understand where your money is actually moving.</p>
          </article>
          <article class="feature-card">
            <span class="card-kicker">Budget planning</span>
            <h2>Keep the month from sneaking up on you.</h2>
            <p>Track progress against budgets and use bill reminders to stay ahead of upcoming obligations.</p>
          </article>
        </section>
        """
    ).strip()
    return shell(
        title="Home",
        description="Public home page for AI Expense Tracker with product details, support contact, and account deletion help.",
        current_page="home",
        body_class="page-home",
        main_content=content,
    )


def delete_account_page() -> str:
    content = dedent(
        """
        <section class="legal-hero">
          <div>
            <span class="eyebrow">Account support</span>
            <h1>Delete Account</h1>
            <p>How AI Expense Tracker users can request account deletion.</p>
          </div>
        </section>

        <section class="legal-layout legal-layout-single">
          <article class="legal-article prose">
            <p>AI Expense Tracker users can request account deletion in one of the following ways:</p>
            <ol>
              <li>Open the app, go to Settings, and use Delete Account.</li>
              <li>Contact <a href="mailto:support@example.com">support@example.com</a> from the email address associated with your Google login.</li>
            </ol>
            <p>To protect accounts from unauthorized deletion, we may ask you to verify that you own the account.</p>
            <p>Deleting your account deletes or anonymizes account-related data where possible. Some data may be retained where required for legal, security, fraud-prevention, backup, accounting, or legitimate operational purposes.</p>
            <p>Deleting the app does not cancel your Google Play subscription. Subscriptions must be canceled through Google Play.</p>
          </article>
        </section>
        """
    ).strip()
    return shell(
        title="Delete Account",
        description="How AI Expense Tracker users can request account deletion.",
        current_page="delete-account",
        body_class="page-legal page-delete-account",
        main_content=content,
    )


def copy_assets(output_dir: Path) -> None:
    for filename in ("styles.css", "site.js", "site-config.template.js"):
        shutil.copy2(SRC_ROOT / filename, output_dir / filename)
    for source, destination in (
        (REPO_ROOT / "expense_tracker_app" / "web" / "favicon.png", "favicon.png"),
        (
            REPO_ROOT / "expense_tracker_app" / "assets" / "brand" / "logo-login-black.png",
            "logo-login-black.png",
        ),
        (
            REPO_ROOT / "expense_tracker_app" / "assets" / "brand" / "logo-login-white.png",
            "logo-login-white.png",
        ),
    ):
        shutil.copy2(source, output_dir / destination)


def write_default_site_config(output_dir: Path) -> None:
    payload = json.dumps(site_config(), indent=2)
    (output_dir / "site-config.js").write_text(
        f"window.__SITE_CONFIG__ = {payload};\n",
        encoding="utf-8",
        newline="\n",
    )


def build(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    copy_assets(output_dir)
    write_default_site_config(output_dir)

    pages = {
        "index.html": home_page(),
        "delete-account.html": delete_account_page(),
    }

    for filename, contents in pages.items():
        (output_dir / filename).write_text(contents, encoding="utf-8", newline="\n")
        if filename != "index.html":
            route_dir = output_dir / filename.removesuffix(".html")
            route_dir.mkdir(parents=True, exist_ok=True)
            (route_dir / "index.html").write_text(contents, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    args = parser.parse_args()
    build(Path(args.output).resolve())


if __name__ == "__main__":
    main()
