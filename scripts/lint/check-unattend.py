#!/usr/bin/env python3
"""Fail on unattend answer-file values Windows Setup rejects at runtime.

Sysprep does not validate these limits when it generalizes, so a too-long command only shows up
on the first clone as "Windows could not parse or process unattend answer file ... The answer
file is invalid" - a modal dialog that blocks the VM headless. Catch it in lint instead.

Usage: check-unattend.py <answer file>...   (*.xml or *.xml.pkrtpl)
"""
import html
import re
import sys

# Microsoft unattend reference: RunSynchronousCommand/Path and RunAsynchronousCommand/Path
# max 259 chars; FirstLogonCommands|LogonCommands/SynchronousCommand/CommandLine max 1024.
LIMITS = {"Path": 259, "CommandLine": 1024}
PATTERN = re.compile(r"<(Path|CommandLine)>(.*?)</\1>", re.DOTALL)


def check(path: str) -> list[str]:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    errors = []
    for match in PATTERN.finditer(text):
        tag, raw = match.group(1), match.group(2)
        value = html.unescape(raw.strip())  # Setup counts the decoded value (&amp; -> &)
        if len(value) > LIMITS[tag]:
            line = text.count("\n", 0, match.start()) + 1
            errors.append(
                f"{path}:{line}: <{tag}> is {len(value)} chars, Windows Setup allows "
                f"{LIMITS[tag]} - move the logic into a script file"
            )
    return errors


def main(paths: list[str]) -> int:
    errors = [e for p in paths for e in check(p)]
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
