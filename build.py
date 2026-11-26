#!/usr/bin/env python3
"""
Package NLSound (AROMA-Next Edition) into a ready-to-flash Recovery & Magisk/KSU/APatch ZIP.
Sets proper Unix permissions (0755 on binaries & shell scripts, 0644 on data/configs)
and enforces LF line endings on all shell scripts and Edify configs.
"""

import argparse
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent

EXCLUDED_TOP = {
    ".git",
    ".github",
    ".gitignore",
    "dist",
    "docs",
    "build.py",
    "__pycache__",
}

EXEC_SUFFIXES = (".sh",)
EXEC_NAMES = {
    "update-binary",
    "magisk-installer",
    "aroma_installer-arm64",
    "aroma_installer-arm32",
    "tinymix_ext",
}
TEXT_LF_NAMES = {
    "update-binary",
    "updater-script",
    "magisk-installer",
    "aroma-config",
    "module.prop",
}
TEXT_LF_SUFFIXES = (".sh", ".prop", ".lang", ".edify", ".txt")


def read_version() -> str:
    prop = (ROOT / "module.prop").read_text(encoding="utf-8")
    m = re.search(r"^version=(.+)$", prop, re.MULTILINE)
    return m.group(1).strip() if m else "v4.5-AROMA"


def build_zip(out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    count = 0

    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for p in sorted(ROOT.rglob("*")):
            if not p.is_file():
                continue
            rel = p.relative_to(ROOT)
            if rel.parts[0] in EXCLUDED_TOP:
                continue
            if rel.suffix == ".zip":
                continue

            arc = rel.as_posix()
            data = p.read_bytes()

            # Enforce LF line endings on shell scripts, Edify configs, and prop files
            if p.name in TEXT_LF_NAMES or p.suffix in TEXT_LF_SUFFIXES:
                data = data.replace(b"\r\n", b"\n")

            is_exec = (p.suffix in EXEC_SUFFIXES) or (p.name in EXEC_NAMES)
            mode = 0o755 if is_exec else 0o644

            zi = zipfile.ZipInfo(arc)
            zi.external_attr = (0o100000 | mode) << 16
            zf.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED)
            count += 1

    print(f"[ok] Built {out_path} ({out_path.stat().st_size:,} bytes, {count} entries)")


def main() -> None:
    ver = read_version()
    ap = argparse.ArgumentParser(description="Build NLSound AROMA-Next flashable ZIP")
    ap.add_argument(
        "-o",
        "--output",
        type=Path,
        default=ROOT / "dist" / f"NLSound-{ver}-Next.zip",
        help="Output ZIP path",
    )
    args = ap.parse_args()
    build_zip(args.output)


if __name__ == "__main__":
    main()
