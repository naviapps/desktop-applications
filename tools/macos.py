#!/usr/bin/env python3
"""Accept application effects in a unique owned app bundle, never an installed app."""

import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    fixture = ROOT / "fixtures/macos"
    env = os.environ.copy()
    subprocess.run(["swift", "build", "--package-path", str(fixture)], check=True, env=env)
    binary = Path(
        subprocess.check_output(
            ["swift", "build", "--package-path", str(fixture), "--show-bin-path"],
            text=True,
            env=env,
        ).strip()
    )
    root = ROOT / ".native-build"
    root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=root, prefix="macos-") as temporary:
        work = Path(temporary)
        app = work / "DesktopApplications Target.app"
        executable = app / "Contents/MacOS"
        executable.mkdir(parents=True)
        shutil.copy2(binary / "Target", executable / "Target")
        (app / "Contents/Info.plist").write_bytes(
            plistlib.dumps(
                {
                    "CFBundleIdentifier": "com.naviapps.desktop-applications.acceptance."
                    + uuid.uuid4().hex,
                    "CFBundleExecutable": "Target",
                    "CFBundleName": "DesktopApplications Target",
                    "CFBundlePackageType": "APPL",
                    "LSMinimumSystemVersion": "26.0",
                }
            )
        )
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, env=env)
        subprocess.run([str(binary / "Host"), str(app), str(work)], check=True, env=env, timeout=90)


if __name__ == "__main__":
    main()
