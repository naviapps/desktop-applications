.DEFAULT_GOAL := check
SDK_TOOLING ?= mise run sdk-tooling --
SWIFT_FLAGS := -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
.PHONY: check check-source test-managed check-distribution native native-verify test test-consumer test-installed-consumers test-rust test-distribution-tools test-nuget lint docs
check: check-source test test-consumer

check-source: lint test-rust test-managed
check-distribution: test-distribution-tools test-nuget docs
lint:
	$(SDK_TOOLING) quality check --dotnet
native:
	$(SDK_TOOLING) xcframework
native-verify:
	$(SDK_TOOLING) xcframework --verify
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

docs:
	$(SDK_TOOLING) docs

.PHONY: format
format:
	$(SDK_TOOLING) quality format --dotnet

test-managed:
	DESKTOP_APPLICATIONS_NATIVE_LIBRARY="$(CURDIR)/Artifacts/CDesktopApplications.xcframework/macos-arm64_x86_64/CDesktopApplications.framework/CDesktopApplications" \
		dotnet run --configuration Release --project bindings/dotnet/tests/DesktopApplications.Tests/DesktopApplications.Tests.csproj
