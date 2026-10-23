#!/usr/bin/env python3
import os
import plistlib
import subprocess
import sys
from pathlib import Path


def git(*arguments):
    return subprocess.run(["git", *arguments], check=True, capture_output=True, text=True).stdout.strip()


def version_key(tag):
    return tuple(int(part) if part.isdigit() else -1 for part in tag.split("."))


def git_version():
    head_tags = git("tag", "--points-at", "HEAD", "--list", "[0-9]*").split()
    if head_tags:
        version = max(head_tags, key=version_key)
    else:
        try:
            version = git("describe", "--tags", "--abbrev=0", "--match", "[0-9]*")
        except subprocess.CalledProcessError:
            version = "0.0.0"
    return version, git("rev-list", "--count", "HEAD")


def apply_to_info_plist(version, build):
    path = Path(os.environ["TARGET_BUILD_DIR"]) / os.environ["INFOPLIST_PATH"]
    with open(path, "rb") as plist:
        info = plistlib.load(plist)
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = build
    with open(path, "wb") as plist:
        plistlib.dump(info, plist, fmt=plistlib.FMT_BINARY)
    print(f"{path}: {version} ({build})")


def main():
    os.chdir(os.environ.get("SRCROOT", Path(__file__).resolve().parent.parent))
    version, build = git_version()
    if "--print" in sys.argv[1:]:
        print(version, build)
        return
    apply_to_info_plist(version, build)


if __name__ == "__main__":
    main()
