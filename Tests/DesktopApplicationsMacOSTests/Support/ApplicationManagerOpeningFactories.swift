import AppKit
import Foundation
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
func applicationRuntimeRejectingOpeningRequestDependencies(
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      installedApplicationURL: { _, _ in
        XCTFail("Invalid input should not perform an application lookup.", file: file, line: line)
        return nil
      },
      requestOpening: { _, _ in
        XCTFail("Invalid input should not request opening.", file: file, line: line)
        return true
      },
      requestConfiguredApplicationOpening: { _, _, _, completion in
        XCTFail(
          "Invalid input should not request configured application bundle opening.",
          file: file,
          line: line
        )
        completion(true)
      }
    )
  )
}

@MainActor
func applicationRuntimeResolvingApplicationBundleURL(
  _ url: URL,
  for expectedBundleIdentifier: String = "com.example.app",
  unexpectedOpenMessage: String,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      installedApplicationURL: { _, bundleIdentifier in
        XCTAssertEqual(bundleIdentifier, expectedBundleIdentifier, file: file, line: line)
        return url
      },
      requestOpening: { _, _ in
        XCTFail(unexpectedOpenMessage, file: file, line: line)
        return true
      },
      requestConfiguredApplicationOpening: { _, _, _, completion in
        XCTFail(unexpectedOpenMessage, file: file, line: line)
        completion(true)
      }
    )
  )
}
