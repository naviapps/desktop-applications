"""SDK acceptance consumes the shared builder's output, including redirected Cargo builds."""

import hashlib
import json
import os
import sys
import tempfile
import tomllib
import unittest
import zipfile
from contextlib import nullcontext
from pathlib import Path
from unittest.mock import Mock, patch

from distribution import nuget
from distribution import verify_windows as driver


class WindowsOutputTests(unittest.TestCase):
    def test_fixture_uses_the_registry_inputs_fetched_for_the_sdk(self):
        root = Path(__file__).resolve().parents[2]

        def registry(path):
            return {
                (package["name"], package["version"], package["checksum"])
                for package in tomllib.loads((root / path).read_text())["package"]
                if package.get("source", "").startswith("registry+")
            }

        self.assertEqual(
            registry("fixtures/acceptance/windows/Cargo.lock") - registry("Cargo.lock"), set()
        )

    def test_retained_windows_verification_selects_the_accepted_dll_and_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            windows = Mock()
            artifacts = Mock()
            artifacts.build_lock.return_value = nullcontext()
            native = Mock(root=root, library="desktop_applications")
            directory = root / "accepted"
            library = directory / "desktop_applications.dll"
            digest = "a" * 64
            windows.verify_artifact.return_value = directory, {"outputs": {library.name: digest}}
            with (
                patch.object(driver, "support_inputs", return_value={"native.toml": "b" * 64}),
                patch.object(
                    driver, "load", side_effect={"windows": windows, "artifacts": artifacts}.get
                ),
            ):
                self.assertEqual(driver.verify_retained_artifact(native), (library, digest))
            artifacts.build_lock.assert_called_once_with(root / ".native-build")
            windows.verify_artifact.assert_called_once_with(native, "x64")
            windows.require_pe_machine.assert_called_once_with(library, "x64")

    def test_nuget_checks_the_windows_receipt_digest_before_running_the_consumer(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            library = root / "desktop_applications.dll"
            library.write_bytes(b"accepted DLL")
            member = "runtimes/win-x64/native/desktop_applications.dll"
            digest = hashlib.sha256(library.read_bytes()).hexdigest()
            bindings = Mock()

            def stage(source, destination):
                destination.parent.mkdir(parents=True)
                destination.write_bytes(source.read_bytes())
                return destination

            def pack(dotnet, project, *, output, **options):
                with zipfile.ZipFile(
                    output / "NaviApps.DesktopApplications.0.1.0.nupkg", "w"
                ) as archive:
                    archive.writestr(member, b"different package DLL")

            bindings.stage_native.side_effect = stage
            bindings.pack_project.side_effect = pack
            with (
                patch.multiple(nuget, artifacts=bindings, managed=bindings, packages=bindings),
                self.assertRaisesRegex(ValueError, "Packaged runtime asset differs"),
            ):
                nuget.pack_and_consume(
                    root,
                    dotnet="dotnet",
                    env={},
                    version="0.1.0",
                    output=root / "output",
                    runtime_files={member: library},
                    reviewed_support={},
                    runtime="win-x64",
                    verified_hashes={member: digest},
                )
            bindings.run_isolated_consumer.assert_not_called()
            self.assertFalse(any((root / "output").iterdir()))

    def test_nuget_preserves_the_previous_package_if_support_changes_during_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            consumer = root / "fixtures/consumers/dotnet/Program.cs"
            consumer.parent.mkdir(parents=True)
            consumer.write_text("")
            package = root / "output/NaviApps.DesktopApplications.0.1.0.nupkg"
            package.parent.mkdir()
            package.write_bytes(b"previous package")
            bindings = Mock()
            bindings.pack_project.side_effect = lambda dotnet, project, *, output, **options: (
                output / package.name
            ).write_bytes(b"new package")
            bindings.audit_package.return_value = hashlib.sha256(b"new package").hexdigest()
            support = {"@sdk-tooling/sdk_tooling/nuget.py": "a" * 64}
            reviewed_support = support.copy()

            def consume(*args, **kwargs):
                support["@sdk-tooling/sdk_tooling/nuget.py"] = "b" * 64

            bindings.run_isolated_consumer.side_effect = consume
            with (
                patch.multiple(nuget, managed=bindings, packages=bindings),
                patch.object(nuget, "support_inputs", side_effect=lambda: support.copy()),
                self.assertRaisesRegex(ValueError, "SDK support sources changed"),
            ):
                nuget.pack_and_consume(
                    root,
                    dotnet="dotnet",
                    env={},
                    version="0.1.0",
                    output=package.parent,
                    runtime_files={},
                    reviewed_support=reviewed_support,
                )
            self.assertEqual(package.read_bytes(), b"previous package")

    def test_redirected_build_cannot_consume_missing_or_stale_legacy_output(self):
        for stale, snapshot in ((False, False), (True, False), (False, True), (True, True)):
            with (
                self.subTest(stale_legacy_output=stale, captured_workspace=snapshot),
                tempfile.TemporaryDirectory() as temporary,
            ):
                root = Path(temporary)
                redirected = root / "redirected-cargo"
                published = root / ".native-build/accepted"
                published.mkdir(parents=True)
                library = published / "desktop_applications.dll"
                library.write_bytes(b"fresh SDK DLL")
                linker = published / "desktop_applications.dll.lib"
                linker.write_bytes(b"fresh import library")
                (root / "mise.toml").write_text('[tools]\ndotnet = "10.0.403"\n')
                legacy = root / "target" / driver.TARGET / "release"
                if stale:
                    legacy.mkdir(parents=True)
                    (legacy / library.name).write_bytes(b"stale SDK DLL")
                consumer = root / "fixtures/consumers/dotnet/Program.cs"
                consumer.parent.mkdir(parents=True)
                consumer.write_bytes(
                    (driver.ROOT / "fixtures/consumers/dotnet/Program.cs").read_bytes()
                )
                unselected = root / "bindings/dotnet/runtimes/osx-arm64/native"
                unselected.mkdir(parents=True)
                (unselected / "libdesktop_applications.dylib").write_bytes(b"stale Mac library")
                env = {"CARGO_TARGET_DIR": str(redirected), "PATH": "owned-toolchain"}
                if snapshot:
                    env["VM_RUNNER_ARTIFACTS_DIR"] = str(root / "evidence")
                native = Mock(version="0.1.0", library="desktop_applications")
                shared = Mock()
                shared.host_architecture.return_value = "arm64"
                shared.native_environment.return_value = (env, root / "msvc", "dotnet")
                shared.build_library.return_value = published
                native_receipt = {
                    "outputs": {
                        path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (library, linker)
                    },
                    "exports": ["desktop_applications_abi_version"],
                }
                shared.verify_artifact.return_value = published, native_receipt
                (published / "native-build.json").write_text(json.dumps(native_receipt))

                bindings = Mock()

                def stage(source, destination):
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(source.read_bytes())
                    return destination

                def pack(dotnet, project, *, output, **options):
                    assets = options["properties"]["DesktopApplicationsRuntimeAssets"]
                    self.assertEqual(
                        [
                            path.relative_to(assets).as_posix()
                            for path in assets.rglob("*")
                            if path.is_file()
                        ],
                        ["win-x64/native/desktop_applications.dll"],
                    )
                    with zipfile.ZipFile(
                        output / "NaviApps.DesktopApplications.0.1.0.nupkg", "w"
                    ) as archive:
                        asset = "win-x64/native/desktop_applications.dll"
                        archive.write(assets / asset, "runtimes/" + asset)

                bindings.pack_project.side_effect = pack
                bindings.audit_package.side_effect = lambda path, **_: hashlib.sha256(
                    path.read_bytes()
                ).hexdigest()

                def run(command, **_):
                    if command[:2] == ["cargo", "build"]:
                        output = Path(command[command.index("--target-dir") + 1])
                        target = output / driver.TARGET / "release"
                        target.mkdir(parents=True)
                        (target / "desktop-applications-test-target.exe").write_bytes(b"fixture")

                artifacts = Mock()
                artifacts.stage_native.side_effect = stage
                artifacts.build_lock.side_effect = lambda path: nullcontext()
                artifacts.write_json.side_effect = lambda path, data: path.write_text(
                    json.dumps(data)
                )
                support = {"@sdk-tooling/sdk_tooling/nuget.py": "d" * 64}

                def check_output(command, **options):
                    if command == ["dotnet", "--version"]:
                        return "10.0.403\n"
                    self.assertEqual(command, ["git", "rev-parse", "HEAD"])
                    if snapshot:
                        raise AssertionError("Captured workspaces have no Git metadata")
                    return "a" * 40

                with (
                    patch.dict(
                        os.environ,
                        {
                            "VM_RUNNER_SOURCE_COMMIT": "b" * 40,
                            "VM_RUNNER_SOURCE_FINGERPRINT": "c" * 64,
                        }
                        if snapshot
                        else {},
                        clear=True,
                    ),
                    patch.object(driver, "ROOT", root),
                    patch.object(sys, "platform", "win32"),
                    patch.object(driver, "support_inputs", return_value=support),
                    patch.object(nuget, "support_inputs", return_value=support),
                    patch.object(driver, "builder", return_value=native),
                    patch.multiple(driver, c_compiler=bindings, managed=bindings),
                    patch.multiple(nuget, artifacts=artifacts, managed=bindings, packages=bindings),
                    patch.object(
                        driver,
                        "load",
                        side_effect={
                            "windows": shared,
                            "artifacts": artifacts,
                        }.get,
                    ),
                    patch.object(driver.subprocess, "run", side_effect=run) as commands,
                    patch.object(driver.subprocess, "check_output", side_effect=check_output),
                    patch.object(driver.platform, "platform", return_value="mock Windows ARM64"),
                    patch("builtins.print"),
                ):
                    driver.main([])
                shared.native_environment.assert_called_once_with(
                    "arm64", target_architecture="x64"
                )
                shared.build_library.assert_called_once_with(
                    native, env, root / "msvc", "x64", native_host="arm64"
                )
                self.assertEqual(env["CARGO_TARGET_DIR"], str(redirected))
                shared.verify_artifact.assert_called_once_with(native, "x64", environment=env)
                c = bindings.compile_c.call_args.kwargs
                candidate = c["output"].parent
                builds = [
                    call.args[0]
                    for call in commands.call_args_list
                    if call.args[0][:2] == ["cargo", "build"]
                ]
                self.assertEqual(len(builds), 1)
                self.assertEqual(
                    builds[0][2:],
                    [
                        "--manifest-path",
                        str(root / "fixtures/acceptance/windows/Cargo.toml"),
                        "--target",
                        driver.TARGET,
                        "--target-dir",
                        str(candidate / "fixture-build"),
                        "--release",
                        "--locked",
                        "--offline",
                    ],
                )
                self.assertEqual(c["libraries"], [candidate / linker.name])
                self.assertEqual(c["env"]["PATH"], "owned-toolchain")
                managed = bindings.run_managed.call_args.kwargs
                self.assertEqual(
                    managed["env"]["DESKTOP_APPLICATIONS_NATIVE_LIBRARY"],
                    str(candidate / library.name),
                )
                self.assertEqual(managed["properties"]["UseAppHost"], "false")
                self.assertEqual(managed["properties"]["RuntimeIdentifier"], "win-x64")
                self.assertEqual(
                    managed["arguments"],
                    [candidate / "target-app/DesktopApplications.TestTarget.exe"],
                )
                self.assertEqual(
                    [item.args for item in shared.require_pe_machine.call_args_list],
                    [
                        (candidate / library.name, "x64"),
                        (c["output"], "x64"),
                        (managed["arguments"][0], "x64"),
                    ],
                )
                self.assertEqual(artifacts.stage_native.call_args.args[0], candidate / library.name)
                self.assertEqual(
                    tuple(bindings.audit_package.call_args.kwargs["runtime_files"]),
                    ("runtimes/win-x64/native/desktop_applications.dll",),
                )
                consumer = bindings.run_isolated_consumer.call_args.kwargs
                self.assertEqual(consumer["runtime"], "win-x64")
                self.assertIn(candidate, consumer["exclude_paths"])
                self.assertEqual(
                    consumer["clear_environment"], ("DESKTOP_APPLICATIONS_NATIVE_LIBRARY",)
                )
                destination = root / ("evidence" if snapshot else ".native-build")
                if snapshot:
                    self.assertEqual(
                        (destination / "sdk-windows/win-x64" / library.name).read_bytes(),
                        library.read_bytes(),
                    )
                receipt = json.loads(
                    (destination / "desktop-applications-windows.json").read_text()
                )
                self.assertEqual(receipt["source"], ("b" if snapshot else "a") * 40)
                self.assertEqual(receipt["hostArchitecture"], "arm64")
                self.assertEqual(receipt["runtime"], "win-x64")
                self.assertEqual(receipt["supportInputs"], support)
                self.assertEqual(receipt["workspaceFingerprint"], "c" * 64 if snapshot else None)
                self.assertEqual(
                    receipt["dllSha256"], hashlib.sha256(library.read_bytes()).hexdigest()
                )
                self.assertEqual(receipt["exports"], ["desktop_applications_abi_version"])


if __name__ == "__main__":
    unittest.main()
