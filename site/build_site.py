from __future__ import annotations

import argparse
import html
import json
import os
import re
import shutil
from pathlib import Path
from textwrap import dedent

import markdown


SITE_ROOT = Path(__file__).resolve().parent
REPO_ROOT = SITE_ROOT.parent
SRC_ROOT = SITE_ROOT / "src"
DEFAULT_OUTPUT = SITE_ROOT / "dist"

THEME_BOOTSTRAP = """<script>(function(){try{var saved=localStorage.getItem("site-theme");var theme=saved||(window.matchMedia&&window.matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light");document.documentElement.dataset.theme=theme;}catch(_){document.documentElement.dataset.theme="light";}})();</script>"""

HEADING_PATTERN = re.compile(r"^(#{2,3})\s+(.*)$")
INLINE_LINK_PATTERN = re.compile(r"\[([^\]]+)\]\([^)]+\)")
MARKDOWN_ESCAPE_PATTERN = re.compile(r"\\([\\`*{}\[\]()#+\-.!_>])")


def slugify(value: str, seen: dict[str, int]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "section"
    count = seen.get(base, 0) + 1
    seen[base] = count
    return base if count == 1 else f"{base}-{count}"


def strip_inline_markup(value: str) -> str:
    value = INLINE_LINK_PATTERN.sub(r"\1", value)
    value = value.replace("`", "").replace("*", "").replace("_", "")
    value = MARKDOWN_ESCAPE_PATTERN.sub(r"\1", value)
    return value.strip()


def normalize_legal_markdown_line(line: str) -> str:
    if line.strip() == r"\---":
        return "---"
    return line


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def site_config() -> dict[str, str]:
    return {
        "supportEmail": (os.environ.get("APP_SUPPORT_EMAIL") or "").strip(),
        "supportSubject": (os.environ.get("APP_SUPPORT_SUBJECT") or "").strip(),
    }


def preprocess_legal_markdown(raw_markdown: str, fallback_title: str) -> tuple[str, str, list[tuple[int, str, str]]]:
    title = fallback_title
    seen: dict[str, int] = {}
    toc: list[tuple[int, str, str]] = []
    lines: list[str] = []
    title_consumed = False

    for raw_line in raw_markdown.splitlines():
        line = normalize_legal_markdown_line(raw_line)
        stripped = line.strip()
        if not title_consumed and stripped.startswith("# "):
            title = strip_inline_markup(stripped[2:]) or fallback_title
            title_consumed = True
            continue

        match = HEADING_PATTERN.match(line)
        if match:
            level = len(match.group(1))
            text = re.sub(r"\s+\{#.+\}\s*$", "", match.group(2)).strip()
            text = MARKDOWN_ESCAPE_PATTERN.sub(r"\1", text)
            display_text = strip_inline_markup(text)
            anchor = slugify(display_text, seen)
            toc.append((level, display_text, anchor))
            lines.append(f"{match.group(1)} {text} {{#{anchor}}}")
            continue

        lines.append(line)

    return title, "\n".join(lines).strip() + "\n", toc


def render_markdown(markdown_text: str) -> str:
    return markdown.markdown(markdown_text, extensions=["extra", "sane_lists"])


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
            <a href="/privacy">Privacy</a>
            <a href="/terms">Terms</a>
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
            nav_link("Privacy", "/privacy", current_page, "privacy"),
            nav_link("Terms", "/terms", current_page, "terms"),
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
              <a class="inline-link" href="/privacy">Read the Privacy Policy</a>
              <a class="inline-link" href="/terms">Read the Terms of Service</a>
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
        description="Public home page for AI Expense Tracker with product details, support contact, and legal links.",
        current_page="home",
        body_class="page-home",
        main_content=content,
    )


def render_toc(entries: list[tuple[int, str, str]]) -> str:
    if not entries:
        return '<p class="toc-empty">This page does not include any document sections yet.</p>'
    items = []
    for level, text, anchor in entries:
        items.append(
            f'<li class="toc-item toc-level-{level}"><a href="#{anchor}">{html.escape(text)}</a></li>'
        )
    return f'<ol class="toc-list">{"".join(items)}</ol>'


def legal_page(page_key: str, source_file: str, fallback_title: str, description: str) -> str:
    raw = read_text(REPO_ROOT / source_file)
    title, prepared_markdown, toc_entries = preprocess_legal_markdown(raw, fallback_title)
    article_html = render_markdown(prepared_markdown)
    content = dedent(
        f"""
        <section class="legal-hero">
          <div>
            <span class="eyebrow">Legal</span>
            <h1>{html.escape(title)}</h1>
            <p>{html.escape(description)}</p>
          </div>
        </section>

        <section class="legal-layout">
          <aside class="legal-sidebar">
            <div class="toc-shell">
              <p class="toc-title">On this page</p>
              {render_toc(toc_entries)}
            </div>
          </aside>
          <article class="legal-article prose">
            {article_html}
          </article>
        </section>
        """
    ).strip()
    return shell(
        title=title,
        description=description,
        current_page=page_key,
        body_class="page-legal",
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
              <li>Contact <a href="mailto:support@nexavend.store">support@nexavend.store</a> from the email address associated with your Google login.</li>
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
        "privacy.html": legal_page(
            page_key="privacy",
            source_file="PRIVACY.md",
            fallback_title="Privacy Policy",
            description="How AI Expense Tracker collects, uses, shares, and protects your information.",
        ),
        "terms.html": legal_page(
            page_key="terms",
            source_file="TERMS.md",
            fallback_title="Terms of Service",
            description="Rules, responsibilities, and core terms for using AI Expense Tracker.",
        ),
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
