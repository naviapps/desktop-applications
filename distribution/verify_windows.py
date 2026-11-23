#!/usr/bin/env python3
"""Build and validate Windows x64 packages on an owned Windows worker."""

import argparse
import json
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from sdk_tooling import dotnet as managed
from sdk_tooling import vm_environment as vm
from sdk_tooling.adapters import load, support_inputs
from sdk_tooling.native_plan import ffi_product
from sdk_tooling.windows_delivery import RID, TARGET, X64Acceptance

from distribution.nuget import pack_and_consume

ROOT = Path(__file__).resolve().parents[1]


def verify_retained_artifact(native):
    support = support_inputs()
    windows = load("windows")
    with load("artifacts").build_lock(native.root / ".native-build"):
        directory, receipt = windows.verify_artifact(native, "x64")
        library = directory / (native.library + ".dll")
        windows.require_pe_machine(library, "x64")
        if support_inputs() != support:
            raise ValueError("SDK support sources changed during Windows artifact verification")
    return library, receipt["outputs"][library.name]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--verify-artifact",
        action="store_true",
        help="Check retained x64 bytes without running Windows fixtures",
    )
    mode.add_argument(
        "--native-aot", action="store_true", help="Publish and run the win-x64 Native AOT consumer"
    )
    args = parser.parse_args(argv)
    if not args.verify_artifact and sys.platform != "win32":
        parser.error("Use an owned Windows worker for runtime acceptance")
    native = ffi_product(ROOT)
    if args.verify_artifact:
        _, digest = verify_retained_artifact(native)
        print(json.dumps({"dllSha256": digest}))
        return

    support = support_inputs()
    windows = load("windows")
    artifacts_tooling = load("artifacts")
    output_dir = ROOT / ".native-build"
    acceptance = X64Acceptance(ROOT)
    env, dotnet = acceptance.env, acceptance.dotnet
    artifacts = vm.artifacts_dir(env) or output_dir
    identity = vm.source_identity(require_fingerprint=False)
    if identity is None:
        identity = (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            None,
        )
    source, fingerprint = identity
    built = acceptance.build(native)
    packages = output_dir / "packages"
    with (
        artifacts_tooling.build_lock(output_dir),
        tempfile.TemporaryDirectory(dir=output_dir, prefix="windows-x64-") as temporary,
    ):
        candidate = Path(temporary)
        dll, import_library, native_receipt = acceptance.stage(native, built, candidate)
        windows.require_pe_machine(dll, "x64")
        acceptance.run_c(
            ROOT / "fixtures/consumers/c/main.c",
            include_directory=ROOT / "crates/ffi/include",
            import_library=import_library,
        )
        run_managed_fixtures(acceptance, candidate, dll)
        member = f"runtimes/{RID}/native/{dll.name}"
        dll_hash = native_receipt["outputs"][dll.name]
        package_hashes = pack_and_consume(
            ROOT,
            dotnet=dotnet,
            output=packages,
            env=env,
            version=native.version,
            runtime_files={member: dll},
            runtime=RID,
            verified_hashes={member: dll_hash},
            reviewed_support=support,
            native_aot=args.native_aot,
        )
        if support_inputs() != support:
            raise ValueError("SDK support sources changed during Windows acceptance")
        artifacts.mkdir(parents=True, exist_ok=True)
        if artifacts.resolve() != output_dir.resolve():
            shutil.copytree(built, artifacts / "sdk-windows" / RID)
        for name, digest in package_hashes.items():
            if packages.resolve() != artifacts.resolve():
                shutil.copyfile(packages / name, artifacts / name)
            if artifacts_tooling.file_sha256(artifacts / name) != digest:
                raise ValueError("Exported Windows package differs from the accepted package")
        receipt = {
            "source": source,
            "workspaceFingerprint": fingerprint,
            "target": TARGET,
            "runtime": RID,
            "hostArchitecture": acceptance.host,
            "supportInputs": support,
            "os": platform.platform(),
            "exports": native_receipt["exports"],
            "run": env.get("GITHUB_RUN_ID"),
            "attempt": env.get("GITHUB_RUN_ATTEMPT"),
            "acceptance": [
                "Rust identity/lifecycle",
                "C ownership",
                ".NET common contracts",
                "owned separate-process application lifecycle",
                "clean Native AOT NuGet consumer" if args.native_aot else "clean NuGet consumer",
            ],
            "packages": package_hashes,
            "dllSha256": dll_hash,
        }
        artifacts_tooling.write_json(artifacts / "desktop-applications-windows.json", receipt)
    print(f"Windows x64 desktop-applications acceptance passed on {acceptance.host}.")


def run_managed_fixtures(acceptance, candidate, dll):
    properties = {
        "RuntimeIdentifier": RID,
        "UseAppHost": "false",
        "SelfContained": "false",
        "DesktopApplicationsNativeLibrary": str(dll),
    }
    managed.run_managed(
        acceptance.dotnet,
        ROOT / "bindings/dotnet/tests/DesktopApplications.Tests/DesktopApplications.Tests.csproj",
        cwd=ROOT,
        env=acceptance.env,
        properties=properties,
        verify_style=True,
    )

    output = candidate / "fixture-build"
    acceptance.run(
        "cargo",
        "build",
        "--manifest-path",
        ROOT / "fixtures/acceptance/windows/Cargo.toml",
        "--target",
        TARGET,
        "--target-dir",
        output,
        "--release",
        "--locked",
        "--offline",
    )
    executable = candidate / "target-app/DesktopApplications.TestTarget.exe"
    executable.parent.mkdir()
    shutil.copyfile(output / TARGET / "release/desktop-applications-test-target.exe", executable)
    load("windows").require_pe_machine(executable, "x64")
    managed.run_managed(
        acceptance.dotnet,
        ROOT / "fixtures/acceptance/windows/dotnet/DesktopApplications.WindowsAcceptance.csproj",
        cwd=ROOT,
        env=acceptance.env,
        arguments=[executable],
        properties=properties,
        nuget_config=ROOT / "bindings/dotnet/NuGet.Config",
        verify_style=True,
    )


if __name__ == "__main__":
    main()
