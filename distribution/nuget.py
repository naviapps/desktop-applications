#!/usr/bin/env python3
"""Pack selected verified native assets and test a fresh local NuGet consumer."""

import argparse
import hashlib
import os
import shutil
import sys
import tempfile
from pathlib import Path

from sdk_tooling import artifacts
from sdk_tooling import dotnet as managed
from sdk_tooling import nuget as packages
from sdk_tooling.adapters import support_inputs
from sdk_tooling.c_headers import prepare_generated
from sdk_tooling.xcframework import xcframework

from distribution.pack_nuget import MACOS_RUNTIMES, PACKAGE, package_files


def pack_and_consume(
    root,
    *,
    dotnet,
    env,
    version,
    work_parent=None,
    runtime_files,
    reviewed_support,
    runtime=None,
    verified_hashes=None,
    native_aot=False,
):
    dotnet_root = root / "bindings/dotnet"
    project = dotnet_root / "src" / PACKAGE / f"{PACKAGE}.csproj"
    name = f"{PACKAGE}.{version}.nupkg"
    verified_hashes = verified_hashes or {}
    with tempfile.TemporaryDirectory(prefix="pack-", dir=work_parent) as directory:
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
                "SdkNativeRuntimeAssets": stage / "runtimes",
            },
        )
        package = stage / name
        digest = packages.audit_package(
            package,
            expected_files=package_files(root),
            expected_sha256=verified_hashes,
            runtime_files=staged,
        )
        properties = {"Nullable": "enable", "TreatWarningsAsErrors": "true"}
        if native_aot:
            properties.update(
                DefineConstants="NATIVE_AOT_FIXTURE",
                ILLinkTreatWarningsAsErrors="true",
                JsonSerializerIsReflectionEnabledByDefault="false",
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
            properties=properties,
            native_aot=native_aot,
        )
        if support_inputs() != reviewed_support:
            raise ValueError("SDK support sources changed during NuGet acceptance")
        if hashlib.sha256(package.read_bytes()).hexdigest() != digest:
            raise ValueError("NuGet package changed during isolated acceptance")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.parse_args(argv)
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
    prepare_generated(Path.cwd(), env=env, verify=True)
    native = xcframework()
    native.verify(env)
    root = native.root
    framework = (
        native.artifact / "macos-arm64_x86_64" / (native.module + ".framework") / native.module
    )
    runtime_files = {
        f"runtimes/{rid}/native/lib{native.library}.dylib": framework for rid in MACOS_RUNTIMES
    }
    dotnet_root = root / "bindings/dotnet"
    tests = dotnet_root / "tests/DesktopApplications.Tests"
    managed.run_managed(
        dotnet,
        tests / "DesktopApplications.Tests.csproj",
        cwd=root,
        env=env,
        properties={"DesktopApplicationsNativeLibrary": str(framework)},
        nuget_config=tests / "NuGet.Config",
        verify_style=True,
    )
    pack_and_consume(
        root,
        dotnet=dotnet,
        env=env,
        version=native.version,
        runtime_files=runtime_files,
        reviewed_support=support,
    )
    print("Clean macOS NuGet fixture passed.")


if __name__ == "__main__":
    main()
