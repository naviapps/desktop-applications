"""Pack the DesktopApplications NuGet package from verified native outputs."""

import argparse
from pathlib import Path

from sdk_tooling import artifacts, nuget
from sdk_tooling.windows_delivery import RID
from sdk_tooling.xcframework import xcframework

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "NaviApps.DesktopApplications"
MACOS_RUNTIMES = ("osx-arm64", "osx-x64")
RUNTIMES = (*MACOS_RUNTIMES, RID)


def package_files(root):
    notices = root / "ThirdParty"
    return {
        "LICENSE": root / "LICENSE",
        "README.md": root / "README.md",
        **{
            "licenses/" + path.relative_to(notices).as_posix(): path
            for path in artifacts.files(notices)
            if path.name not in (".DS_Store", "registry-notices.json")
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--runtime", action="append", required=True, choices=RUNTIMES)
    parser.add_argument("--result", type=Path, help="Write the accepted package filename")
    args = parser.parse_args(argv)
    if sorted(args.runtime) != sorted(RUNTIMES):
        parser.error("DesktopApplications packages require all three runtimes")
    package = nuget.pack_native(
        xcframework(ROOT),
        project=ROOT / "bindings/dotnet/src" / PACKAGE / f"{PACKAGE}.csproj",
        package_files=package_files(ROOT),
        nuget_config=ROOT / "bindings/dotnet/NuGet.Config",
        runtimes=args.runtime,
        input_files=[Path(__file__), ROOT / "mise.toml", ROOT / "native.toml"],
    )
    if args.result is not None:
        with args.result.open("x", encoding="utf-8") as output:
            output.write(package.name)


if __name__ == "__main__":
    main()
