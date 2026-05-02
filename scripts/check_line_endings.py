from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
GITATTRIBUTES = ROOT / ".gitattributes"
BINARY_SUFFIXES = {
    ".bmp",
    ".gif",
    ".jpg",
    ".jpeg",
    ".pdf",
    ".png",
    ".zip",
}


def tracked_files() -> list[Path]:
    completed = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "git ls-files failed")
    return [ROOT / line for line in completed.stdout.splitlines() if line]


def main() -> int:
    errors: list[str] = []
    attributes = GITATTRIBUTES.read_text(encoding="utf-8")
    for required in [
        "* text=auto eol=lf",
        "*.lean text eol=lf",
        "*.json text eol=lf",
        "*.txt text eol=lf",
        "*.yml text eol=lf",
        "*.py text eol=lf",
    ]:
        if required not in attributes:
            errors.append(f".gitattributes is missing `{required}`")

    try:
        paths = tracked_files()
    except RuntimeError as error:
        errors.append(str(error))
        paths = []

    for path in paths:
        if path.suffix.lower() in BINARY_SUFFIXES:
            continue
        data = path.read_bytes()
        if b"\r\n" in data:
            errors.append(f"{path.relative_to(ROOT).as_posix()} contains CRLF line endings")

    if errors:
        print("\n".join(f"- {error}" for error in errors), file=sys.stderr)
        return 1

    print(f"Line endings validated for {len(paths)} tracked file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
