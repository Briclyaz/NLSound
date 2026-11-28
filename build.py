#!/usr/bin/env python3
"""
Local packager for NLSound (AROMA-Next Edition).
Fetches AROMA-Next-Installer (ANI) binaries, UI assets & Magisk dispatcher from
Miustone/AROMA-Next-Installer releases (cached in .aroma-cache/ or supplied via
--aroma-zip for offline builds), overlays NLSound files (incl. custom magisk-installer
and aroma-config) on top, and enforces Unix 0755/0644 permissions & LF line endings.

In GitHub Actions, CI uses Miustone/aroma-next-action@v1 directly.
"""

import argparse
import json
import os
import re
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CACHE_DIR = ROOT / ".aroma-cache"

UPSTREAM_REPO = "Miustone/AROMA-Next-Installer"
ASSET_NAME = "AROMA-Next-Magisk-Template.zip"

EXCLUDED_TOP = {
    ".git",
    ".github",
    ".gitignore",
    ".aroma-cache",
    "dist",
    "docs",
    "screenshots",
    "CHANGELOG.md",
    "XDA_THREAD.txt",
    "README.md",
    "README_RU.md",
    "README_ZH.md",
    "build.py",
    "__pycache__",
}

EXEC_SUFFIXES = (".sh",)
EXEC_NAMES = {
    "update-binary",
    "magisk-installer",
    "aroma_installer-arm64",
    "aroma_installer-arm32",
    "aroma_installer-x86_64",
    "tinymix_ext",
}
TEXT_LF_NAMES = {
    "update-binary",
    "updater-script",
    "magisk-installer",
    "aroma-config",
    "module.prop",
}
TEXT_LF_SUFFIXES = (".sh", ".prop", ".lang", ".edify", ".txt", ".rc")
MAGISK_TEMPLATE_SCRIPTS = {
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/magisk-installer",
    "META-INF/com/google/android/aroma-mod-lib.sh",
    "META-INF/com/google/android/updater-script",
}


def read_version() -> str:
    prop = (ROOT / "module.prop").read_text(encoding="utf-8")
    m = re.search(r"^version=(.+)$", prop, re.MULTILINE)
    return m.group(1).strip() if m else "v4.5-AROMA-RC5"


def maybe_lf(arc: str, data: bytes) -> bytes:
    p = Path(arc)
    if p.name in TEXT_LF_NAMES or p.suffix in TEXT_LF_SUFFIXES:
        return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data


def mode_for(arc: str) -> int:
    p = Path(arc)
    if p.suffix in EXEC_SUFFIXES or p.name in EXEC_NAMES:
        return 0o755
    return 0o644


def gh_request(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "NLSound-packager/1.0"})
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read()


def resolve_aroma_zip(version: str, local_zip: str) -> tuple[Path, str]:
    if local_zip:
        p = Path(local_zip).resolve()
        if not p.is_file():
            raise SystemExit(f"Local ANI ZIP not found: {p}")
        return p, f"local:{p.name}"

    if version.lower() == "latest":
        api_url = f"https://api.github.com/repos/{UPSTREAM_REPO}/releases/latest"
    else:
        api_url = f"https://api.github.com/repos/{UPSTREAM_REPO}/releases/tags/{version}"

    meta = json.loads(gh_request(api_url).decode("utf-8"))
    tag = meta.get("tag_name", version)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cached = CACHE_DIR / f"{tag}-{ASSET_NAME}"
    if cached.is_file():
        return cached, tag

    dl_url = None
    for a in meta.get("assets", []):
        if a.get("name") == ASSET_NAME:
            dl_url = a.get("browser_download_url")
            break
    if not dl_url:
        raise SystemExit(f"Asset '{ASSET_NAME}' not found in {UPSTREAM_REPO} release '{tag}'")

    print(f"[ani] Downloading {ASSET_NAME} ({tag}) -> {cached.relative_to(ROOT)} ...")
    cached.write_bytes(gh_request(dl_url))
    return cached, tag


def should_include_from_ani(arc: str, archs: set[str]) -> bool:
    if arc.startswith("META-INF/com/google/android/bin/aroma_installer-"):
        return arc.rsplit("-", 1)[-1] in archs
    if arc.startswith("META-INF/com/google/android/aroma/"):
        return not arc.endswith((".edify", "changelog.txt"))
    return arc in MAGISK_TEMPLATE_SCRIPTS


def build_zip(out_path: Path, version: str = "latest", local_zip: str = "", archs: set[str] | None = None) -> None:
    if archs is None:
        archs = {"arm64", "arm32"}

    ani_zip, resolved_tag = resolve_aroma_zip(version, local_zip)
    entries: dict[str, tuple[bytes, int]] = {}

    with zipfile.ZipFile(ani_zip, "r") as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            arc = info.filename
            if should_include_from_ani(arc, archs):
                entries[arc] = (maybe_lf(arc, zf.read(info)), mode_for(arc))

    # Overlay NLSound files (takes precedence over ANI template defaults!)
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(ROOT)
        if rel.parts[0] in EXCLUDED_TOP:
            continue
        if rel.suffix == ".zip":
            continue
        arc = rel.as_posix()
        entries[arc] = (maybe_lf(arc, p.read_bytes()), mode_for(arc))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for arc in sorted(entries.keys()):
            data, mode = entries[arc]
            zi = zipfile.ZipInfo(arc)
            zi.create_system = 3  # Unix
            zi.external_attr = (0o100000 | mode) << 16
            zf.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED)

    print(f"[ok] Built {out_path} ({out_path.stat().st_size:,} bytes, {len(entries)} entries, ANI {resolved_tag})")


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
    ap.add_argument("--aroma-version", default="latest", help="ANI release tag (default: latest)")
    ap.add_argument("--aroma-zip", default="", help="Optional local AROMA-Next-Magisk-Template.zip for offline builds")
    ap.add_argument("--architectures", default="arm64,arm32", help="Comma-separated ANI archs (default: arm64,arm32)")
    args = ap.parse_args()
    archs = {a.strip() for a in args.architectures.split(",") if a.strip()}
    build_zip(args.output, version=args.aroma_version, local_zip=args.aroma_zip, archs=archs)


if __name__ == "__main__":
    main()
