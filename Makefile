.DEFAULT_GOAL := check
SDK_TOOLING ?= mise run sdk-tooling --
SWIFT_FLAGS := -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
.PHONY: check check-source check-ci-source test-managed check-distribution native native-verify check-header generate-header test test-consumer test-installed-consumers test-rust test-distribution-tools test-nuget lint clean
check: check-source test test-consumer

check-source: lint check-header test-rust test-managed

check-ci-source:
	cargo fetch --locked --manifest-path fixtures/acceptance/windows/Cargo.toml
	$(MAKE) check-source

check-distribution: check-header test-distribution-tools test-nuget
clean:
	$(SDK_TOOLING) clean .build target .native-build \
	  fixtures/consumers/swift/.build fixtures/acceptance/macos/.build fixtures/acceptance/windows/target \
	  bindings/dotnet/src/NaviApps.DesktopApplications/bin bindings/dotnet/src/NaviApps.DesktopApplications/obj \
	  bindings/dotnet/tests/DesktopApplications.Tests/bin bindings/dotnet/tests/DesktopApplications.Tests/obj \
	  fixtures/acceptance/windows/dotnet/bin fixtures/acceptance/windows/dotnet/obj
lint:
	$(SDK_TOOLING) quality check --dotnet
native: generate-header
	$(SDK_TOOLING) xcframework
native-verify: check-header
	$(SDK_TOOLING) xcframework --verify
check-header:
	$(SDK_TOOLING) c-headers check
generate-header:
	$(SDK_TOOLING) c-headers generate
test:
	swift test $(SWIFT_FLAGS)
test-consumer:
	$(SDK_TOOLING) swift-consumer
test-installed-consumers:
	$(SDK_TOOLING) rust-c-consumers
test-nuget:
	$(SDK_TOOLING) python -m distribution.nuget
test-distribution-tools:
	$(SDK_TOOLING) python -m unittest discover -s distribution/tests -v
test-rust:
	cargo clippy --workspace --all-targets --locked --offline -- -D warnings
	cargo test --workspace --locked --offline
	cargo fmt --manifest-path fixtures/acceptance/windows/Cargo.toml -- --check
	cargo test --manifest-path fixtures/acceptance/windows/Cargo.toml --locked --offline

.PHONY: format
format:
	$(SDK_TOOLING) quality format --dotnet

test-managed:
	dotnet run --configuration Release --project bindings/dotnet/tests/DesktopApplications.Tests/DesktopApplications.Tests.csproj \
		-p:DesktopApplicationsNativeLibrary="$(CURDIR)/Artifacts/CDesktopApplications.xcframework/macos-arm64_x86_64/CDesktopApplications.framework/CDesktopApplications"
