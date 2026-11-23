import Foundation
import XCTest

final class DesktopApplicationsMacOSSourceBoundaryTests: XCTestCase {
  func testRuntimeDependencyInjectionStaysOutOfPublicSurface() throws {
    let source = try packageFileText(
      relativePath: "Sources/DesktopApplicationsMacOS/Runtime/ApplicationManager.swift")

    XCTAssertFalse(
      containsPublicInitializer(withParameterLabels: ["workspace", "dependencies"], in: source),
      "ApplicationManager should expose AppKit workspace selection, but keep dependency injection internal to the package."
    )
  }

  func testDuplicateActivationDependencyInjectionStaysOutOfPublicSurface() throws {
    let source = try packageFileText(
      relativePath:
        "Sources/DesktopApplicationsMacOS/DuplicateActivation/ApplicationDuplicateActivationCoordinator.swift"
    )

    let failureMessage =
      "ApplicationDuplicateActivationCoordinator should expose only bundle identifier and "
      + "notification-name configuration; dependency injection stays internal."

    XCTAssertFalse(
      containsPublicInitializer(
        withParameterLabels: ["bundleIdentifier", "notificationName", "dependencies"],
        in: source
      ),
      failureMessage
    )
  }

  func testAppKitSupportTypesStayInternal() throws {
    let sourceText = try packageSourceFilesText(relativeRoot: "Sources/DesktopApplicationsMacOS")
    let internalSupportTypes = [
      "ApplicationManagerDependencies",
      "ApplicationEventSource",
      "WorkspaceApplicationEventSource",
      "ApplicationDuplicateActivationCoordinatorDependencies",
      "ApplicationDuplicateActivationRequestTransport",
      "ApplicationDuplicateActivationNotificationCenter",
      "DistributedNotificationActivationRequestTransport",
      "LiveDuplicateActivationNotificationCenter",
    ]

    for internalSupportType in internalSupportTypes {
      XCTAssertFalse(
        containsPublicTypeDeclaration(named: internalSupportType, in: sourceText),
        "\(internalSupportType) is an AppKit implementation detail and should stay out of the public API."
      )
    }
  }

  private func containsPublicTypeDeclaration(named typeName: String, in source: String) -> Bool {
    let pattern =
      #"^\s*(?:@[\w.]+(?:\([^)]*\))?\s*)*(?:public|open)\s+(?:actor|class|enum|final\s+class|protocol|struct|typealias)\s+"#
      + NSRegularExpression.escapedPattern(for: typeName)
      + #"\b"#

    return source.split(separator: "\n").contains { line in
      line.range(of: pattern, options: .regularExpression) != nil
    }
  }

  private func containsPublicInitializer(
    withParameterLabels labels: [String],
    in source: String
  ) -> Bool {
    let labelPattern =
      labels
      .map { #"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\s*:"# }
      .joined(separator: #"[^{}]*"#)
    let pattern =
      #"(?ms)^\s*(?:@[\w.]+(?:\([^)]*\))?\s*)*public\s+(?:convenience\s+)?init\b[^{}]*"#
      + labelPattern

    return source.range(of: pattern, options: .regularExpression) != nil
  }
}
