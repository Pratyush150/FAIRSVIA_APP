#!/usr/bin/env python3
"""Release APK build that bundles only the art and fonts of the look it builds.

Flutter bundles every asset and font a package's pubspec lists, whether or not
the build's code ever reads it. packages/design_system carries the art for
every look (THEME=ink, clay3d, local, midnight, daylight/daynight ...), but
only Plan F "Map Glass" (the default, no THEME flag) ships. In
packages/design_system/pubspec.yaml, entries only one look needs sit between

    # @variant: <THEME value> [<THEME value> ...]
    ...
    # @end-variant

This script removes the blocks whose THEME list does not include the build's
THEME, runs `flutter build apk --release`, and always puts the pubspec back
(also on Ctrl-C / SIGTERM, and on the next run if a previous one was killed).
Plain `flutter test` / `flutter run` / `flutter build` never go through here,
so they keep every asset and every THEME build still works.

Usage (from anywhere):
    tools/apk/release_apk.py rider_app                     # arm64 phone APK (+ v7a, x86_64)
    tools/apk/release_apk.py driver_app --universal        # one fat APK
    tools/apk/release_apk.py rider_app --theme clay3d      # keeps clay3d's art only
    tools/apk/release_apk.py rider_app --bundle            # Play Store .aab
    tools/apk/release_apk.py rider_app -- --dart-define=API_BASE_URL=https://api.example/api/v1

Everything after `--` goes to `flutter build apk`. A `--dart-define=THEME=x`
there is honoured as if `--theme x` had been given.
"""

from __future__ import annotations

import argparse
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = ROOT / "packages/design_system/pubspec.yaml"
BACKUP = PUBSPEC.with_name(".pubspec.yaml.release-backup")
BEGIN = re.compile(r"^\s*#\s*@variant:\s*(.+?)\s*$")
END = re.compile(r"^\s*#\s*@end-variant\s*$")


def strip_variants(text: str, theme: str) -> tuple[str, list[str]]:
    """Returns [text] without the @variant blocks that [theme] does not use,
    and the removed asset/font lines (for the log)."""
    out: list[str] = []
    removed: list[str] = []
    keep = True
    in_block = False
    for line in text.splitlines(keepends=True):
        m = BEGIN.match(line)
        if m:
            if in_block:
                raise SystemExit(f"nested @variant block in {PUBSPEC}")
            in_block = True
            keep = theme in m.group(1).split()
            out.append(line)
            continue
        if END.match(line):
            if not in_block:
                raise SystemExit(f"@end-variant without @variant in {PUBSPEC}")
            in_block = False
            keep = True
            out.append(line)
            continue
        if keep:
            out.append(line)
        elif "asset" in line or "family:" in line:
            removed.append(line.strip())
    if in_block:
        raise SystemExit(f"unterminated @variant block in {PUBSPEC}")
    return "".join(out), removed


def restore() -> None:
    if BACKUP.exists():
        shutil.copy2(BACKUP, PUBSPEC)
        BACKUP.unlink()


def main() -> int:
    argv = sys.argv[1:]
    passthrough: list[str] = []
    if "--" in argv:
        i = argv.index("--")
        argv, passthrough = argv[:i], argv[i + 1 :]
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("app", choices=["rider_app", "driver_app"])
    ap.add_argument("--theme", default="", help="THEME value (default: the shipped Glass look)")
    ap.add_argument("--universal", action="store_true", help="one APK with all ABIs instead of --split-per-abi")
    ap.add_argument("--bundle", action="store_true", help="build a Play Store App Bundle (.aab) instead of APKs")
    ap.add_argument("--keep-all-assets", action="store_true", help="do not strip anything (for comparison)")
    ap.add_argument("--out", type=Path, help="copy the built APK(s) into this directory")
    args = ap.parse_args(argv)

    theme = args.theme
    for a in passthrough:
        if a.startswith("--dart-define=THEME="):
            theme = a.split("=", 2)[2]
    if theme and not any(a.startswith("--dart-define=THEME=") for a in passthrough):
        passthrough.append(f"--dart-define=THEME={theme}")
    effective = theme or "glass"

    # A run killed with SIGKILL leaves the stripped pubspec behind: undo it.
    restore()

    original = PUBSPEC.read_text()
    stripped, removed = (original, []) if args.keep_all_assets else strip_variants(original, effective)

    def on_signal(signum, _frame):
        restore()
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    cmd = ["flutter", "build", "appbundle" if args.bundle else "apk", "--release"]
    if not args.universal and not args.bundle:
        cmd.append("--split-per-abi")
    cmd += passthrough
    print(f"THEME={effective}: leaving out {len(removed)} variant-only asset/font entries")
    for r in removed:
        print(f"  {r}")
    app_dir = ROOT / "apps" / args.app
    try:
        if stripped != original:
            shutil.copy2(PUBSPEC, BACKUP)
            PUBSPEC.write_text(stripped)
        print("+", " ".join(cmd), f"(in apps/{args.app})", flush=True)
        rc = subprocess.call(cmd, cwd=app_dir)
    finally:
        restore()
    if rc != 0:
        return rc

    out_dir = app_dir / "build/app/outputs/flutter-apk"
    apks = sorted(out_dir.glob("app-*release.apk"))
    if args.bundle:
        apks = [app_dir / "build/app/outputs/bundle/release/app-release.aab"]
    elif not args.universal:
        apks = [p for p in apks if p.name != "app-release.apk"]
    else:
        apks = [p for p in apks if p.name == "app-release.apk"]
    for apk in apks:
        print(f"{apk.stat().st_size / 1e6:7.1f} MB  {apk.relative_to(ROOT)}")
        if args.out:
            args.out.mkdir(parents=True, exist_ok=True)
            shutil.copy2(apk, args.out / f"{args.app}-{effective}-{apk.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
