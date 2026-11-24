#!/usr/bin/env python3
"""Build and validate Windows x64 packages on an owned Windows worker."""

import argparse
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from sdk_tooling import dotnet as managed
from sdk_tooling import vm_environment as vm
from sdk_tooling.adapters import load, support_inputs
from sdk_tooling.c_headers import prepare_generated
from sdk_tooling.native_plan import ffi_product
from sdk_tooling.windows_delivery import RID, TARGET, X64Acceptance

from distribution.nuget import pack_and_consume

ROOT = Path(__file__).resolve().parents[1]


def export_native(built, inventory, artifact_root, tooling):
    destination = artifact_root / "sdk-windows" / RID
    destination.parent.mkdir(parents=True, exist_ok=True)
    if (
        destination.exists()
        or destination.is_symlink()
        or not destination.parent.resolve().is_relative_to(artifact_root.resolve())
    ):
        raise ValueError("Windows native export requires a new directory inside the artifact root")
    with tempfile.TemporaryDirectory(dir=destination.parent, prefix="native-export-") as temporary:
        stage = Path(temporary) / RID
        shutil.copytree(built, stage, symlinks=True)
        if tooling.hashes(tooling.files(stage), stage) != inventory:
            raise ValueError("Exported Windows native files differ from the accepted build")
        stage.rename(destination)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument(
        "--native-aot", action="store_true", help="Publish and run the win-x64 Native AOT consumer"
    )
    args = parser.parse_args(argv)
    if sys.platform != "win32":
        parser.error("Use an owned Windows worker for runtime acceptance")
    prepare_generated(ROOT)
    native = ffi_product(ROOT)

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
    with (
        artifacts_tooling.build_lock(output_dir),
        tempfile.TemporaryDirectory(dir=output_dir, prefix="windows-x64-") as temporary,
    ):
        candidate = Path(temporary)
        dll, import_library, native_receipt = acceptance.stage(native, built, candidate)
        native_receipt_digest = artifacts_tooling.file_sha256(built / "native-build.json")
        windows.require_pe_machine(dll, "x64")
        acceptance.run_c(
            ROOT / "fixtures/consumers/c/main.c",
            include_directory=ROOT / "crates/ffi/include",
            import_library=import_library,
        )
        run_managed_fixtures(acceptance, candidate, dll)
        member = f"runtimes/{RID}/native/{dll.name}"
        dll_hash = native_receipt["outputs"][dll.name]
        pack_and_consume(
            ROOT,
            dotnet=dotnet,
            work_parent=candidate,
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
            export_native(
                built,
                native_receipt["outputs"] | {"native-build.json": native_receipt_digest},
                artifacts,
                artifacts_tooling,
            )
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
            "nativeBuildSha256": native_receipt_digest,
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
