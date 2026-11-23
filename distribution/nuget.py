#!/usr/bin/env python3
"""Pack selected verified native assets and test a fresh local NuGet consumer."""

import argparse
import hashlib
import os
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

from sdk_tooling import artifacts
from sdk_tooling import dotnet as managed
from sdk_tooling import nuget as packages
from sdk_tooling.adapters import support_inputs
from sdk_tooling.xcframework import xcframework

PACKAGE = "NaviApps.DesktopApplications"
MACOS_RUNTIMES = ("osx-arm64", "osx-x64")
WINDOWS_RUNTIME = "win-x64"


def pack_and_consume(
    root,
    *,
    dotnet,
    env,
    version,
    output,
    runtime_files,
    reviewed_support,
    runtime=None,
    verified_hashes=None,
):
    dotnet_root = root / "bindings/dotnet"
    project = dotnet_root / "src" / PACKAGE / f"{PACKAGE}.csproj"
    name = f"{PACKAGE}.{version}.nupkg"
    verified_hashes = verified_hashes or {}
    notices = {
        "licenses/" + path.relative_to(root / "ThirdParty").as_posix(): path
        for path in (root / "ThirdParty").rglob("*")
        if path.is_file() and path.name not in (".DS_Store", "registry-notices.json")
    }
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pack-", dir=output) as directory:
        stage = Path(directory)
        staged = {}
        for member, library in runtime_files.items():
            path = artifacts.stage_native(library, stage / member)
            expected = verified_hashes.get(member)
            if expected is not None and hashlib.sha256(path.read_bytes()).hexdigest() != expected:
                raise ValueError("Staged runtime asset differs from the verified native receipt")
            staged[member] = path
        managed.pack_project(
            dotnet,
            project,
            output=stage,
            env=env,
            cwd=root,
            nuget_config=dotnet_root / "NuGet.Config",
            properties={
                "Version": version,
                "DesktopApplicationsRuntimeAssets": stage / "runtimes",
            },
        )
        package = stage / name
        digest = packages.audit_package(
            package,
            expected_files={
                "LICENSE": root / "LICENSE",
                "README.md": root / "README.md",
                **notices,
            },
            runtime_files=staged,
        )
        if verified_hashes:
            with zipfile.ZipFile(package) as archive:
                for member, expected in verified_hashes.items():
                    with archive.open(member) as runtime_asset:
                        if hashlib.file_digest(runtime_asset, "sha256").hexdigest() != expected:
                            raise ValueError(
                                "Packaged runtime asset differs from the verified native receipt"
                            )
        packages.run_isolated_consumer(
            dotnet,
            packages=[package],
            references={PACKAGE: version},
            source=(root / "fixtures/consumers/dotnet/Program.cs").read_text(encoding="utf-8"),
            work_parent=stage,
            env=env,
            runtime=runtime,
            exclude_paths=(
                root / "target",
                *(library.parent for library in runtime_files.values()),
            ),
            properties={"Nullable": "enable", "TreatWarningsAsErrors": "true"},
        )
        if support_inputs() != reviewed_support:
            raise ValueError("SDK support sources changed during NuGet acceptance")
        if hashlib.sha256(package.read_bytes()).hexdigest() != digest:
            raise ValueError("NuGet package changed during isolated acceptance")
        os.replace(package, output / name)
    return {name: digest}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument(
        "--include-windows",
        action="store_true",
        help="Also package a verified win-x64 DLL from this checkout",
    )
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        raise SystemExit("Run the Windows distribution fixture on an owned Windows worker.")

    support = support_inputs()
    env = dict(
        os.environ,
        DOTNET_CLI_TELEMETRY_OPTOUT="1",
        DOTNET_NOLOGO="1",
        DOTNET_CLI_USE_MSBUILD_SERVER="0",
        MSBUILDDISABLENODEREUSE="1",
    )
    dotnet = env.get("DOTNET_BIN") or shutil.which("dotnet", path=env.get("PATH"))
    if not dotnet:
        raise SystemExit("Install .NET 10 or set DOTNET_BIN.")
    native = xcframework()
    native.verify(env)
    root = native.root
    framework = (
        native.artifact / "macos-arm64_x86_64" / (native.module + ".framework") / native.module
    )
    runtime_files = {
        f"runtimes/{rid}/native/lib{native.library}.dylib": framework for rid in MACOS_RUNTIMES
    }
    verified_hashes = {}
    if args.include_windows:
        from distribution.verify_windows import verify_retained_artifact

        library, digest = verify_retained_artifact(native)
        member = f"runtimes/{WINDOWS_RUNTIME}/native/{library.name}"
        runtime_files[member] = library
        verified_hashes[member] = digest
    dotnet_root = root / "bindings/dotnet"
    managed.run_managed(
        dotnet,
        dotnet_root / "tests/DesktopApplications.Tests/DesktopApplications.Tests.csproj",
        cwd=root,
        env=env,
        properties={"DesktopApplicationsNativeLibrary": str(framework)},
        nuget_config=dotnet_root / "NuGet.Config",
        verify_style=True,
    )
    output = root / ".native-build/packages"
    for name in pack_and_consume(
        root,
        dotnet=dotnet,
        env=env,
        version=native.version,
        output=output,
        runtime_files=runtime_files,
        verified_hashes=verified_hashes,
        reviewed_support=support,
    ):
        print(f"Verified local package: {output / name}")


if __name__ == "__main__":
    main()
