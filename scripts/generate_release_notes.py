"""Generate release notes from git commit subjects."""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

SECTION_TITLES = {
    "feat": "Features",
    "fix": "Fixes",
    "chore": "Chores",
    "style": "Style",
    "docs": "Documentation",
    "test": "Tests",
    "ci": "CI",
    "build": "Build",
    "refactor": "Refactors",
    "perf": "Performance",
}
SECTION_ORDER = [
    "feat",
    "fix",
    "chore",
    "style",
    "docs",
    "test",
    "ci",
    "build",
    "refactor",
    "perf",
    "other",
]
SEMANTIC_PREFIX_RE = re.compile(
    r"^(?P<prefix>feat|fix|chore|style|docs|test|ci|build|refactor|perf)"
    r"(?:\([^)]+\))?!?:\s*(?P<summary>.+)$",
    re.IGNORECASE,
)


def _git_subjects(from_ref: str, to_ref: str) -> list[str]:
    completed = subprocess.run(
        ["git", "log", "--format=%s", f"{from_ref}..{to_ref}"],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def _group_subjects(subjects: list[str]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {section: [] for section in SECTION_ORDER}
    for subject in subjects:
        match = SEMANTIC_PREFIX_RE.match(subject)
        if match is None:
            grouped["other"].append(subject)
            continue
        prefix = match.group("prefix").lower()
        summary = match.group("summary").strip()
        grouped[prefix].append(summary or subject)
    return grouped


def _render_notes(*, title: str, from_ref: str, to_ref: str, subjects: list[str]) -> str:
    grouped = _group_subjects(subjects)
    lines = [
        f"# {title}",
        "",
        f"Range: `{from_ref}..{to_ref}`",
        "",
    ]
    if not subjects:
        lines.extend(["No commits found in this range.", ""])
        return "\n".join(lines)

    for section in SECTION_ORDER:
        entries = grouped[section]
        if not entries:
            continue
        heading = "Other Changes" if section == "other" else SECTION_TITLES[section]
        lines.extend([f"## {heading}", ""])
        lines.extend(f"- {entry}" for entry in entries)
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--from-ref", required=True)
    parser.add_argument("--to-ref", default="HEAD")
    parser.add_argument("--title", default="AI Expense Tracker Release Notes")
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    subjects = _git_subjects(args.from_ref, args.to_ref)
    notes = _render_notes(
        title=args.title,
        from_ref=args.from_ref,
        to_ref=args.to_ref,
        subjects=subjects,
    )

    if args.output == "-":
        print(notes)
        return
    Path(args.output).write_text(notes, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()

