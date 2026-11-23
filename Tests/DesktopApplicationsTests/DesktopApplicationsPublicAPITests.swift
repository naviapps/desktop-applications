import DesktopApplications
import XCTest

final class DesktopApplicationsPublicAPITests: XCTestCase {
  func testDocumentationExamplesAreUsableWithoutTestableImport() {
    let snapshot = documentationProcessSnapshot
    let event = documentationRuntimeEvent

    XCTAssertEqual(snapshot.processIdentifier, 123)
    XCTAssertEqual(snapshot.bundleIdentifier, "com.example.app")
    XCTAssertEqual(snapshot.displayName, "Example")
    XCTAssertFalse(snapshot.isTerminated)
    XCTAssertEqual(event.lifecycle, .activated)
    XCTAssertEqual(event.application, snapshot)
  }

  func testPublicConformancesAreUsableWithoutTestableImport() {
    let snapshot = ApplicationSnapshot(
      processIdentifier: 123,
      bundleIdentifier: "com.example.app",
      displayName: "Example"
    )
    let event = ApplicationEvent(lifecycle: .activated, application: snapshot)

    assertHashableSendable(ApplicationSnapshot.self, snapshot)
    assertHashableSendable(ApplicationEvent.self, event)
    assertHashableSendable(ApplicationEvent.Lifecycle.self, .activated)
    assertHashableSendable(
      ApplicationRequestResult<ApplicationOperationError>.self, .failed(.requestRejected))
    assertHashableSendable(
      ApplicationRequestResult<ApplicationLaunchError>.self, .failed(.requestRejected))
    assertHashableSendable(ApplicationTerminationMode.self, .forced)
    assertErrorHashableSendable(ApplicationOperationError.self, .requestRejected)
    assertErrorHashableSendable(ApplicationLaunchError.self, .requestRejected)
  }

  func testIdentityKeysDistinguishOriginalUnicodeSpelling() throws {
    let composed = "caf\u{00E9}.app"
    let decomposed = "cafe\u{0301}.app"
    let first = try ApplicationIdentifier(kind: .executable, value: composed)
    let second = try ApplicationIdentifier(kind: .executable, value: decomposed)
    XCTAssertTrue(first.value.utf8.elementsEqual(composed.utf8))
    XCTAssertTrue(second.value.utf8.elementsEqual(decomposed.utf8))
    XCTAssertEqual(Set([first, second]).count, 2)

    let resources = [
      ApplicationResourceIdentity(
        identifier: first, location: composed, revision: composed, variant: composed),
      ApplicationResourceIdentity(
        identifier: first, location: decomposed, revision: composed, variant: composed),
      ApplicationResourceIdentity(
        identifier: first, location: composed, revision: decomposed, variant: composed),
      ApplicationResourceIdentity(
        identifier: first, location: composed, revision: composed, variant: decomposed),
    ]
    XCTAssertEqual(Set(resources).count, resources.count)
  }

  func testRequestResultDoesNotRequireHashableFailureForPlainUse() {
    let result = nonHashableRequestResult()

    switch result {
    case .requestAccepted:
      XCTFail("The result should preserve the non-hashable failure payload.")
    case .failed(let error):
      XCTAssertEqual(error, NonHashableRequestError(code: 1))
    }
  }
}

private func nonHashableRequestResult() -> ApplicationRequestResult<NonHashableRequestError> {
  .failed(NonHashableRequestError(code: 1))
}

private struct NonHashableRequestError: Error, Equatable {
  let code: Int
}

private let documentationProcessSnapshot = ApplicationSnapshot(
  processIdentifier: 123,
  bundleIdentifier: "com.example.app",
  displayName: "Example"
)

private let documentationRuntimeEvent = ApplicationEvent(
  lifecycle: .activated,
  application: documentationProcessSnapshot
)
