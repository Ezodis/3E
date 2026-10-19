#!/usr/bin/env python3
"""Plan, stamp, package and publish every 3E module on one shared version line.

Every module (Combined, TouchBar, TouchTab, 3£Windows) uses the same version:
release-versions.json's "base" plus the release workflow's run number. A module is
only rebuilt and re-released when its own source changed since its last release,
so an unchanged module keeps the version it last shipped with and an updated one
takes the version of the run that updated it. Editing release-versions.json counts
as a change for every module, which re-syncs them all to one version.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
REPO = "Ezodis/3E"
EDITIONS = {
    "combined": ("combined", "3E-Combined.zip", "3E Combined"),
    "touchbar": ("touchbar", "TouchBar.zip", "TouchBar only"),
    "touchtab": ("touchtab", "TouchTab.zip", "TouchTab only"),
}

def run(*args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()

# Release tag prefix and the source paths whose changes trigger a new release.
MODULES = {
    "combined": ("combined", ("TouchBar/", "TouchTab/", "Shared/")),
    "touchbar": ("touchbar", ("TouchBar/", "Shared/")),
    "touchtab": ("touchtab", ("TouchTab/",)),
    "windows": ("windows", ("Windows/", "Shared/")),
}
SYNC_FILE = "release-versions.json"

def versions(offset):
    base = json.loads((ROOT / SYNC_FILE).read_text())["base"]
    major, minor, patch = map(int, base.split("."))
    version = f"{major}.{minor}.{patch + offset}"
    return {module: version for module in MODULES}

def parse_version(text):
    return tuple(map(int, text.split("."))) if re.fullmatch(r"\d+\.\d+\.\d+", text) else None

def latest_tag(prefix, tags):
    found = [(parse_version(tag[len(prefix) + 2:]), tag) for tag in tags if tag.startswith(f"{prefix}-v")]
    found = [item for item in found if item[0]]
    return max(found)[1] if found else None

def changed_since(tag, paths):
    if tag is None:
        return True
    try:
        run("git", "rev-parse", "--verify", f"{tag}^{{commit}}")
    except subprocess.CalledProcessError:
        return True
    changed = run("git", "diff", "--name-only", tag, "HEAD").splitlines()
    return any(name == SYNC_FILE or name.startswith(paths) for name in changed)

def plan(tags=None, changed=changed_since):
    """Return the modules whose source changed since their latest release tag."""
    if tags is None:
        tags = run("git", "tag", "--list").splitlines()
    return [module for module, (prefix, paths) in MODULES.items()
            if changed(latest_tag(prefix, tags), paths)]

def stamp_windows(values):
    path = ROOT / "Windows/version.json"
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps({"version": values["windows"]}, separators=(",", ":")))

def stamp(values):
    path = ROOT / "TouchBar/musicstrip/Source/Info.plist"
    info = plistlib.loads(path.read_bytes())
    info["CFBundleShortVersionString"] = values["touchbar"]
    info["CFBundleVersion"] = values["touchbar"]
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
    path = ROOT / "TouchBar/musicstrip/Source/ReleaseUpdates.h"
    source, count = re.subn(r'StripReleaseVersion=@"[0-9.]+"',
                           f'StripReleaseVersion=@"{values["touchbar"]}"', path.read_text())
    assert count == 1, "Missing release-version declaration"
    path.write_text(source)
    path = ROOT / "TouchTab/Touch-Tab.xcodeproj/project.pbxproj"
    source = re.sub(r"MARKETING_VERSION = [0-9.]+;",
                    f'MARKETING_VERSION = {values["touchtab"]};', path.read_text())
    source = re.sub(r"CURRENT_PROJECT_VERSION = [0-9.]+;",
                    f'CURRENT_PROJECT_VERSION = {values["touchtab"]};', source)
    path.write_text(source)

def verify_architectures(executable):
    # -verify_arch parsing differs across Xcode versions; -archs is stable.
    architectures = set(run("xcrun", "lipo", "-archs", str(executable)).split())
    assert {"arm64", "x86_64"} <= architectures, f"Not a universal binary: {architectures}"

def required_module_files(edition):
    files = []
    if edition == "combined":
        files.append("Contents/Frameworks/ThreeEGestureEngine.dylib")
    if edition in ("combined", "touchbar"):
        files.append("Contents/Helpers/MIDI Touchbar.app/Contents/MacOS/MIDI Touchbar")
        for arch in ("arm64", "x64"):
            for name in ("ThreeE.PhoneHost", "ThreeE.PhoneHost.dll", "ThreeE.PhoneControl.dll", "libThreeEPhoneNative.dylib"):
                files.append(f"Contents/Resources/PhoneControl/{arch}/{name}")
    return files

def verify_modules(app, edition):
    for relative in required_module_files(edition):
        assert (app / relative).is_file(), f"Missing bundled module: {relative}"

def package(edition, values):
    destination = ROOT / "build/releases"
    destination.mkdir(parents=True, exist_ok=True)
    app = ROOT / ("build/TouchTab/Build/Products/Release/Touch-Tab.app"
                  if edition == "touchtab" else "TouchBar/build/musicstrip/3E.app")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleShortVersionString"] == values[edition], "Stale app version"
    assert bool(info.get("ThreeEIncludesTouchTab")) == (edition == "combined"), "Wrong edition"
    verify_modules(app, edition)
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    verify_architectures(executable)
    run("codesign", "--verify", "--deep", "--strict", str(app))
    archive = destination / EDITIONS[edition][1]
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / f"{edition}-SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n")
    (destination / f"{edition}-build.json").write_text(json.dumps({
        "edition": edition, "version": values[edition], "source_commit": run("git", "rev-parse", "HEAD"),
        "architectures": ["arm64", "x86_64"], "sha256": digest,
    }, indent=2) + "\n")
    print(f"Verified and packaged {archive.name} ({values[edition]})")

def credentials():
    env = os.environ.copy()
    if not env.get("GH_TOKEN") and not env.get("GITHUB_TOKEN"):
        # Reuse the existing Git credential without printing or saving it.
        raw = run("git", "credential", "fill", input="protocol=https\nhost=github.com\n\n")
        fields = dict(line.split("=", 1) for line in raw.splitlines() if "=" in line)
        if not fields.get("password"):
            raise RuntimeError("A GitHub release credential is required")
        env["GH_TOKEN"] = fields["password"]
    return env

def publish(values, editions):
    env = credentials()
    directory = ROOT / "build/releases"
    commit = run("git", "rev-parse", "HEAD")
    prepared = []
    # Validate ALL packages before creating any release; never upload stale files.
    selected = {edition: item for edition, item in EDITIONS.items() if edition in editions}
    for edition, (_, asset, _) in selected.items():
        manifest = json.loads((directory / f"{edition}-build.json").read_text())
        assert manifest["source_commit"] == commit and manifest["version"] == values[edition]
        assert hashlib.sha256((directory / asset).read_bytes()).hexdigest() == manifest["sha256"]
    for edition, (prefix, asset, title) in selected.items():
        tag = f"{prefix}-v{values[edition]}"
        existing = subprocess.run(["gh", "release", "view", tag, "--repo", REPO],
                                  env=env, capture_output=True)
        if existing.returncode == 0:
            metadata = json.loads(run("gh", "release", "view", tag, "--repo", REPO,
                                      "--json", "isDraft,targetCommitish", env=env))
            if not metadata["isDraft"] or metadata["targetCommitish"] != commit:
                raise RuntimeError(f"Refusing to overwrite an existing release: {tag}")
        else:
            notes = (f"Built from commit `{commit}`. Universal Intel/Apple Silicon.\n\n"
                     "Choose this edition alone; do not run both gesture engines. "
                     "Development-signed or ad-hoc signed, not notarized. Approve this app "
                     "on your Mac when required. If an enabled permission still denies access, "
                     "remove only its stale entry and re-add the installed app in System Settings.\n\n"
                     "Includes checksum and source/build metadata. MIDI presets are not bundled "
                     "with personal settings; existing settings are preserved.")
            run("gh", "release", "create", tag, "--repo", REPO, "--draft", "--target", commit,
                "--title", f"{title} {values[edition]}", "--notes", notes, env=env)
        run("gh", "release", "upload", tag, "--repo", REPO, "--clobber",
            str(directory / asset), str(directory / f"{edition}-SHA256SUMS.txt"),
            str(directory / f"{edition}-build.json"), env=env)
        prepared.append(tag)
    for tag in prepared:
        run("gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest=false", env=env)
        print(f"Published https://github.com/{REPO}/releases/tag/{tag}")
    # GitHub's generic Latest link should lead to the integrated edition;
    # standalone updaters continue using their own edition-specific tags.
    if "combined" in selected:
        run("gh", "release", "edit", prepared[0], "--repo", REPO, "--latest", env=env)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("plan", "stamp", "stamp-windows", "package", "publish", "versions"))
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--edition", choices=EDITIONS)
    parser.add_argument("--editions", default=",".join(EDITIONS),
                        help="Comma-separated Mac editions to publish")
    args = parser.parse_args()
    assert args.offset >= 0
    values = versions(args.offset)
    if args.action == "stamp":
        stamp(values)
        stamp_windows(values)
    elif args.action == "stamp-windows": stamp_windows(values)
    elif args.action == "package":
        assert args.edition
        package(args.edition, values)
    elif args.action == "publish":
        publish(values, [item for item in args.editions.split(",") if item])
    elif args.action == "plan":
        modules = plan()
        print(json.dumps({"mac": [m for m in modules if m in EDITIONS],
                          "windows": "windows" in modules, "versions": values}))
    else: print(json.dumps(values))
