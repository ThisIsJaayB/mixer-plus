#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Replaces the original project's name with this fork's in the text the app shows.

The app's text lives in string tables in fifteen languages, and the original
project keeps changing them. Run this after merging its updates:

    python3 Tools/rebrand-strings.py          # rewrite
    python3 Tools/rebrand-strings.py --check  # list what would change, change nothing

Only string literals in the tables are touched. Left alone on purpose:
  - anything that credits the original project or asks for support for it
    (donations, its GitHub stars, its Discord, its Homebrew cask);
  - identifiers, bundle ids, file names, paths and web addresses;
  - comments and copyright headers.
It is safe to run twice: text that already carries the fork's name is skipped.
"""
import glob
import re
import sys

OLD = "Vorssaint"
NEW = "JaysHub Mixer Plus"

# Fields whose text is about the original project itself, by name.
CREDIT_KEYS = re.compile(
    r"donat|supportIntro|sponsor|discord|community|coffee|star(Button|Message|Hint)|homebrewOfficial|"
    r"forkCredit|originalProject|upstream", re.IGNORECASE)
# Literals that are names of things on disk or on the web, not prose.
TECHNICAL = re.compile(
    r"vorssaint\.com|com\.vorssaint|Vorssaint\.app|Vorssaint Utils|Vorssaint \(Developer\)|"
    r"/Vorssaint|Vorssaint/|github\.com", re.IGNORECASE)

TABLES = sorted(set(
    glob.glob("Sources/Vorssaint/Core/Localization.swift")
    + glob.glob("Sources/Vorssaint/Core/Localizations/*.swift")
    + glob.glob("Sources/Vorssaint/**/*Strings.swift", recursive=True)
    + glob.glob("Sources/Vorssaint/**/*Strings+*.swift", recursive=True)))
PLISTS = ["Resources/Info.plist"] + sorted(glob.glob("Resources/*.lproj/InfoPlist.strings"))

# An optional `name:` label, then one string literal.
LITERAL = re.compile(r'(?:\b(\w+)\s*:\s*)?"((?:[^"\\]|\\.)*)"')


def rewrite_swift(text):
    changed = 0

    def replace(match):
        nonlocal changed
        key, body = match.group(1), match.group(2)
        if OLD not in body or TECHNICAL.search(body) or (key and CREDIT_KEYS.search(key)):
            return match.group(0)
        changed += body.count(OLD)
        # Only the text between the quotes: a field's own name may contain
        # the word too, and that is code.
        quoted = match.start(2) - match.start(0)
        whole = match.group(0)
        return whole[:quoted] + body.replace(OLD, NEW) + whole[quoted + len(body):]

    lines = []
    for line in text.split("\n"):
        stripped = line.lstrip()
        if OLD not in line or stripped.startswith("//"):
            lines.append(line)
            continue
        lines.append(LITERAL.sub(replace, line))
    return "\n".join(lines), changed


def rewrite_plist(text):
    """Permission prompts and their translations. The bundle's name and the
    copyright line are identity and credit, and stay as they are."""
    changed = 0
    key = ""
    lines = []
    for line in text.split("\n"):
        found = re.search(r"<key>([^<]+)</key>", line) or re.match(r'\s*"([^"]+)"\s*=', line)
        if found:
            key = found.group(1)
        is_value = "<string>" in line or re.match(r'\s*"[^"]+"\s*=\s*"', line)
        if OLD in line and is_value and key.endswith("UsageDescription") and not TECHNICAL.search(line):
            head, sep, tail = line.partition("<string>" if "<string>" in line else "=")
            changed += tail.count(OLD)
            line = head + sep + tail.replace(OLD, NEW)
        lines.append(line)
    return "\n".join(lines), changed


def main():
    check = "--check" in sys.argv
    total = 0
    for path in TABLES + PLISTS:
        text = open(path, encoding="utf-8").read()
        new, changed = (rewrite_plist if path in PLISTS else rewrite_swift)(text)
        if changed:
            total += changed
            print(f"{changed:5d}  {path}")
            if not check:
                open(path, "w", encoding="utf-8").write(new)
    print(f"{total} mention(s) {'would be ' if check else ''}rewritten in {len(TABLES) + len(PLISTS)} files")


if __name__ == "__main__":
    main()
