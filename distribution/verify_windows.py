#!/usr/bin/env python3
"""Build and validate Windows x64 packages on an owned Windows worker."""

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

from sdk_tooling import c_compiler
from sdk_tooling import dotnet as managed
from sdk_tooling import vm_environment as vm
from sdk_tooling.adapters import load, support_inputs
from sdk_tooling.native_plan import builder

from distribution.nuget import OVERRIDE, WINDOWS_RUNTIME, pack_and_consume

ROOT = Path(__file__).resolve().parents[1]
TARGET = "x86_64-pc-windows-msvc"
RID = WINDOWS_RUNTIME


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
    parser.add_argument(
        "--verify-artifact",
        action="store_true",
        help="Check retained x64 bytes without running Windows fixtures",
    )
    args = parser.parse_args(argv)
    if not args.verify_artifact and sys.platform != "win32":
        parser.error("Use an owned Windows worker for runtime acceptance")
    native = builder(ROOT)
    if args.verify_artifact:
        _, digest = verify_retained_artifact(native)
        print(json.dumps({"dllSha256": digest}))
        return

    support = support_inputs()
    windows = load("windows")
    library = native.library + ".dll"
    artifacts_tooling = load("artifacts")
    output_dir = ROOT / ".native-build"
    host = windows.host_architecture()
    env, tools, dotnet = windows.native_environment(host, target_architecture="x64")
    artifacts = vm.artifacts_dir(env) or output_dir
    identity = vm.source_identity(require_fingerprint=False)
    if identity is None:
        identity = (
            subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
            None,
        )
    source, fingerprint = identity
    version = subprocess.check_output([dotnet, "--version"], cwd=ROOT, env=env, text=True).strip()
    if version != tomllib.loads((ROOT / "mise.toml").read_text())["tools"]["dotnet"]:
        raise SystemExit("Use the pinned x64 .NET SDK from mise.toml")

    def run(*args):
        subprocess.run([str(a) for a in args], cwd=ROOT, env=env, check=True)

    run("cargo", "fetch", "--locked", "--target", TARGET)
    run("cargo", "fmt", "--all", "--", "--check")
    built = windows.build_library(native, env, tools, "x64", native_host=host)
    run(
        "cargo",
        "clippy",
        "--workspace",
        "--all-targets",
        "--target",
        TARGET,
        "--locked",
        "--offline",
        "--",
        "-D",
        "warnings",
    )
    run("cargo", "test", "--workspace", "--target", TARGET, "--locked", "--offline")
    packages = output_dir / "packages"
    with (
        artifacts_tooling.build_lock(output_dir),
        tempfile.TemporaryDirectory(dir=output_dir, prefix="windows-x64-") as temporary,
    ):
        directory, native_receipt = windows.verify_artifact(native, "x64", environment=env)
        if directory != built:
            raise ValueError("Windows DLL verification selected a different native output")
        candidate = Path(temporary)
        dll = artifacts_tooling.stage_native(built / library, candidate / library)
        import_library = artifacts_tooling.stage_native(
            built / (library + ".lib"), candidate / (library + ".lib")
        )
        for path in (dll, import_library):
            if (
                hashlib.sha256(path.read_bytes()).hexdigest()
                != native_receipt["outputs"][path.name]
            ):
                raise ValueError("Windows fixture input differs from its verified native receipt")
        windows.require_pe_machine(dll, "x64")
        c_fixture = candidate / "abi.exe"
        c_compiler.compile_c(
            ROOT / "fixtures/consumers/c/main.c",
            output=c_fixture,
            compiler=[tools / "cl.exe"],
            include_dirs=[ROOT / "crates/ffi/include"],
            libraries=[import_library],
            style="msvc",
            cwd=candidate,
            env=env,
        )
        windows.require_pe_machine(c_fixture, "x64")
        run(c_fixture)
        run_managed_fixtures(windows, dotnet, env, candidate, dll, run)
        member = f"runtimes/{RID}/native/{library}"
        dll_hash = native_receipt["outputs"][library]
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
        )
        if support_inputs() != support:
            raise ValueError("SDK support sources changed during Windows acceptance")
        artifacts.mkdir(parents=True, exist_ok=True)
        if artifacts.resolve() != output_dir.resolve():
            shutil.copytree(built, artifacts / "sdk-windows" / RID)
        for name, digest in package_hashes.items():
            if packages.resolve() != artifacts.resolve():
                shutil.copyfile(packages / name, artifacts / name)
            if hashlib.sha256((artifacts / name).read_bytes()).hexdigest() != digest:
                raise ValueError("Exported Windows package differs from the accepted package")
        receipt = {
            "source": source,
            "workspaceFingerprint": fingerprint,
            "target": TARGET,
            "runtime": RID,
            "hostArchitecture": host,
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
                "clean NuGet consumer",
            ],
            "packages": package_hashes,
            "dllSha256": dll_hash,
        }
        artifacts_tooling.write_json(artifacts / "desktop-applications-windows.json", receipt)
    print(f"Windows x64 desktop-applications acceptance passed on {host}.")


def run_managed_fixtures(windows, dotnet, env, candidate, dll, run):
    output = candidate / "fixture-build"
    run(
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
    windows.require_pe_machine(executable, "x64")
    managed.run_managed(
        dotnet,
        ROOT / "bindings/dotnet/tests/DesktopApplications.Tests/DesktopApplications.Tests.csproj",
        cwd=ROOT,
        env=dict(env, **{OVERRIDE: str(dll)}),
        arguments=[executable],
        properties={"RuntimeIdentifier": RID, "UseAppHost": "false", "SelfContained": "false"},
        verify_style=True,
    )


if __name__ == "__main__":
    main()
