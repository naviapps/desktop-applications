.DEFAULT_GOAL := check
SWIFT_FLAGS := -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
.PHONY: check check-source test-managed check-distribution native native-verify test test-consumer test-installed-consumers test-rust test-tools test-dotnet lint docs
check: check-source test test-consumer

check-source: lint test-rust test-managed
check-distribution: lint test-tools test-rust test-dotnet docs
lint:
	mise exec -- python3 -B tools/quality.py check --dotnet
native:
	python3 tools/native.py
native-verify:
	python3 tools/native.py --verify
test:
	swift test $(SWIFT_FLAGS)
test-consumer:
	python3 -B tools/consumer.py
test-installed-consumers:
	python3 -B tools/install-consumers.py
test-dotnet:
	python3 -B tools/nuget.py
test-tools:
	python3 -B -m unittest discover -s tools/tests -v
test-rust:
	cargo clippy --workspace --all-targets --locked --offline -- -D warnings
	cargo test --workspace --locked --offline
	cargo fmt --manifest-path fixtures/windows/Cargo.toml -- --check
	cargo test --manifest-path fixtures/windows/Cargo.toml --locked --offline

docs:
	python3 tools/docs.py

.PHONY: format
format:
	mise exec -- python3 -B tools/quality.py format --dotnet

test-managed:
	DESKTOP_APPLICATIONS_NATIVE_LIBRARY="$(CURDIR)/Artifacts/CDesktopApplications.xcframework/macos-arm64_x86_64/CDesktopApplications.framework/CDesktopApplications" \
		dotnet run --configuration Release --project bindings/dotnet/tests/DesktopApplications.Tests/DesktopApplications.Tests.csproj
