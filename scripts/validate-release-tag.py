"""Reject release tags that do not exactly identify the bundled app version."""
import plistlib
import re
import sys
from pathlib import Path


def validate(tag, version):
    if not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
        raise ValueError("Release tag must have the stable version format vMAJOR.MINOR.PATCH")
    if tag != f"v{version}":
        raise ValueError(f"Tag {tag} does not match CFBundleShortVersionString {version}")


if __name__ == "__main__":
    with (Path(__file__).resolve().parents[1] / "Resources/Info.plist").open("rb") as source:
        version = plistlib.load(source)["CFBundleShortVersionString"]
    try:
        validate(sys.argv[1], version)
    except (ValueError, IndexError) as error:
        sys.exit(f"Release validation failed: {error}")
    print(f"Release tag matches app version: {version}")
