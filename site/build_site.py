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


def slugify(value: str, seen: dict[str, int]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "section"
    count = seen.get(base, 0) + 1
    seen[base] = count
    return base if count == 1 else f"{base}-{count}"


def strip_inline_markup(value: str) -> str:
    value = INLINE_LINK_PATTERN.sub(r"\1", value)
    value = value.replace("`", "").replace("*", "").replace("_", "")
    return value.strip()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def site_config() -> dict[str, str]:
    return {
        "appWebsiteUrl": (os.environ.get("APP_WEBSITE_URL") or "/").strip() or "/",
        "privacyUrl": (os.environ.get("APP_PRIVACY_URL") or "/privacy").strip() or "/privacy",
        "termsUrl": (os.environ.get("APP_TERMS_URL") or "/terms").strip() or "/terms",
        "supportEmail": (os.environ.get("APP_SUPPORT_EMAIL") or "").strip(),
        "supportSubject": (os.environ.get("APP_SUPPORT_SUBJECT") or "").strip(),
        "appStoreUrl": (os.environ.get("SITE_APP_STORE_URL") or "").strip(),
        "googlePlayUrl": (os.environ.get("SITE_GOOGLE_PLAY_URL") or "").strip(),
        "openAppUrl": (os.environ.get("SITE_OPEN_APP_URL") or "").strip(),
    }


def preprocess_legal_markdown(raw_markdown: str, fallback_title: str) -> tuple[str, str, list[tuple[int, str, str]]]:
    title = fallback_title
    seen: dict[str, int] = {}
    toc: list[tuple[int, str, str]] = []
    lines: list[str] = []
    title_consumed = False

    for line in raw_markdown.splitlines():
        stripped = line.strip()
        if not title_consumed and stripped.startswith("# "):
            title = stripped[2:].strip() or fallback_title
            title_consumed = True
            continue

        match = HEADING_PATTERN.match(line)
        if match:
            level = len(match.group(1))
            text = re.sub(r"\s+\{#.+\}\s*$", "", match.group(2)).strip()
            display_text = strip_inline_markup(text)
            anchor = slugify(display_text, seen)
            toc.append((level, display_text, anchor))
            lines.append(f"{match.group(1)} {text} {{#{anchor}}}")
            continue

        lines.append(line)

    return title, "\n".join(lines).strip() + "\n", toc


def render_markdown(markdown_text: str) -> str:
    return markdown.markdown(markdown_text, extensions=["extra", "sane_lists"])


def nav_link(label: str, href: str, data_attr: str, current_page: str, page_key: str) -> str:
    current = ' aria-current="page"' if current_page == page_key else ""
    return f'<a class="nav-link" data-{data_attr} href="{href}"{current}>{html.escape(label)}</a>'


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
            <a data-home-link href="/">Home</a>
            <a data-privacy-link href="/privacy">Privacy</a>
            <a data-terms-link href="/terms">Terms</a>
            <a data-support-email-link href="#" hidden>support@example.com</a>
          </div>
        </footer>
        """
    ).strip()


def shell(title: str, description: str, current_page: str, body_class: str, main_content: str) -> str:
    nav = "\n".join(
        [
            nav_link("Home", "/", "home-link", current_page, "home"),
            nav_link("Privacy", "/privacy", "privacy-link", current_page, "privacy"),
            nav_link("Terms", "/terms", "terms-link", current_page, "terms"),
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
          <title>{html.escape(title)} | AI Expense Tracker</title>
          {THEME_BOOTSTRAP}
          <link rel="stylesheet" href="/styles.css" />
          <script src="/site-config.js" defer></script>
          <script src="/site.js" defer></script>
        </head>
        <body class="{body_class}">
          <div class="page-shell">
            <header class="site-header">
              <a class="brand-lockup" data-home-link href="/">
                <span class="brand-mark" aria-hidden="true"></span>
                <span class="brand-copy">
                  <strong>AI Expense Tracker</strong>
                  <span>Minimal, modern expense control</span>
                </span>
              </a>
              <nav class="site-nav" aria-label="Primary">
                {nav}
              </nav>
              <button class="theme-toggle" type="button" data-theme-toggle aria-live="polite">
                Theme: Light
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
            <span class="eyebrow">Built for real-life spending, not spreadsheet theater</span>
            <h1>Turn receipts into a clear, calmer picture of your money.</h1>
            <p class="hero-lede">
              AI Expense Tracker helps you scan receipts, organize purchases, follow spending
              patterns, and stay ahead of budgets and bill reminders from one place.
            </p>
            <div class="hero-actions" data-cta-group hidden>
              <a class="button button-primary" data-open-app-link href="#" hidden>Open app</a>
              <a class="button button-secondary" data-app-store-link href="#" hidden>App Store</a>
              <a class="button button-secondary" data-google-play-link href="#" hidden>Google Play</a>
            </div>
            <p class="hero-meta" data-support-line hidden>
              Need help? <a data-support-email-link href="#">support@example.com</a>
            </p>
            <div class="hero-links">
              <a class="inline-link" data-privacy-link href="/privacy">Read the Privacy Policy</a>
              <a class="inline-link" data-terms-link href="/terms">Read the Terms of Service</a>
            </div>
          </div>
          <div class="hero-panel" aria-hidden="true">
            <div class="dashboard-card dashboard-card-primary">
              <div class="panel-chip">This month</div>
              <h2>Receipts, categories, and budget signals in one quiet workflow.</h2>
              <div class="mini-bars">
                <span></span>
                <span></span>
                <span></span>
                <span></span>
                <span></span>
              </div>
            </div>
            <div class="panel-stack">
              <article class="stack-card">
                <p class="stack-label">Receipt scan</p>
                <strong>Capture the details once.</strong>
                <span>Keep the original receipt and the structured expense record together.</span>
              </article>
              <article class="stack-card">
                <p class="stack-label">Trend view</p>
                <strong>See spending shifts faster.</strong>
                <span>Review categories, labels, and movement over time without extra busywork.</span>
              </article>
              <article class="stack-card accent-card">
                <p class="stack-label">Budget rhythm</p>
                <strong>Plan ahead without losing flexibility.</strong>
                <span>Use reminders and budget checkpoints to stay close to what matters.</span>
              </article>
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
          <article class="feature-card">
            <span class="card-kicker">Privacy-aware workflow</span>
            <h2>Know where the boundaries are.</h2>
            <p>The public legal pages are easy to review, and the product keeps direct links to your policies close by.</p>
          </article>
        </section>

        <section class="story-band">
          <div>
            <span class="eyebrow">Why this site exists</span>
            <h2>A simple public home for the product and its legal pages.</h2>
          </div>
          <p>
            This website keeps the essentials easy to find: what the app does, how to contact support,
            and where to review the Privacy Policy and Terms of Service without digging through the app.
          </p>
        </section>

        <section class="legal-callout">
          <div class="legal-copy">
            <span class="eyebrow">Policies</span>
            <h2>Clear links, no maze.</h2>
            <p>Privacy Policy and Terms of Service live on dedicated pages and are generated from the root legal markdown files in this repository.</p>
          </div>
          <div class="legal-actions">
            <a class="button button-secondary" data-privacy-link href="/privacy">Privacy Policy</a>
            <a class="button button-secondary" data-terms-link href="/terms">Terms of Service</a>
          </div>
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
          <div class="legal-meta-card">
            <p>Source of truth</p>
            <strong>{html.escape(source_file)}</strong>
            <span>The public page is generated directly from the repository root markdown file.</span>
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


def copy_assets(output_dir: Path) -> None:
    for filename in ("styles.css", "site.js", "site-config.template.js"):
        shutil.copy2(SRC_ROOT / filename, output_dir / filename)


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
    }

    for filename, contents in pages.items():
        (output_dir / filename).write_text(contents, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    args = parser.parse_args()
    build(Path(args.output).resolve())


if __name__ == "__main__":
    main()
