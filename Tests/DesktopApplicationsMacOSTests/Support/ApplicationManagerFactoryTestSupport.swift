import AppKit
import Darwin
import XCTest

@testable import DesktopApplicationsMacOS

@MainActor
func applicationRuntimeReturningCurrentApplication(
  _ application: FakeRuntimeRunningApplication?,
  unexpectedProcessLookupMessage: String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      currentApplication: { application },
      runningApplication: { _ in
        if let unexpectedProcessLookupMessage {
          XCTFail(unexpectedProcessLookupMessage, file: file, line: line)
        }
        return nil
      }
    )
  )
}

@MainActor
func applicationRuntimeReturningRunningApplication(
  _ application: FakeRuntimeRunningApplication?,
  for expectedProcessIdentifier: pid_t,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  applicationRuntimeReturningRunningApplication(
    { _ in application },
    for: expectedProcessIdentifier,
    file: file,
    line: line
  )
}

@MainActor
func applicationRuntimeReturningRunningApplication(
  _ applicationProvider:
    @escaping @MainActor @Sendable (pid_t)
    -> FakeRuntimeRunningApplication?,
  for expectedProcessIdentifier: pid_t,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      runningApplication: { processIdentifier in
        XCTAssertEqual(
          processIdentifier,
          expectedProcessIdentifier,
          file: file,
          line: line
        )
        return applicationProvider(processIdentifier)
      }
    )
  )
}

@MainActor
func applicationRuntimeRejectingRunningApplicationLookup(
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      runningApplication: { _ in
        XCTFail(message, file: file, line: line)
        return FakeRuntimeRunningApplication()
      }
    )
  )
}

@MainActor
func applicationRuntimeReturningRunningApplications(
  _ applications: [FakeRuntimeRunningApplication],
  for expectedBundleIdentifier: String = "com.example.app",
  unexpectedProcessLookupMessage: String? = nil,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      runningApplication: { _ in
        if let unexpectedProcessLookupMessage {
          XCTFail(unexpectedProcessLookupMessage, file: file, line: line)
        }
        return nil
      },
      runningApplications: { bundleIdentifier in
        XCTAssertEqual(
          bundleIdentifier,
          expectedBundleIdentifier,
          file: file,
          line: line
        )
        return applications
      }
    )
  )
}

@MainActor
func applicationRuntimeRejectingRunningApplicationsLookup(
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      runningApplications: { _ in
        XCTFail(message, file: file, line: line)
        return [FakeRuntimeRunningApplication()]
      }
    )
  )
}

@MainActor
func applicationRuntimeRejectingBundleIdentifierLookups(
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    dependencies: ApplicationManagerDependencies(
      runningApplication: { _ in
        XCTFail(
          "Blank bundle identifier should not perform a process lookup.",
          file: file,
          line: line
        )
        return nil
      },
      runningApplications: { _ in
        XCTFail(
          "Blank bundle identifier should not perform a running application lookup.",
          file: file,
          line: line
        )
        return [FakeRuntimeRunningApplication()]
      }
    )
  )
}

@MainActor
func applicationRuntimeReturningFrontmostApplication(
  _ application: FakeRuntimeRunningApplication?,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    workspace: .shared,
    dependencies: ApplicationManagerDependencies(
      frontmostApplication: { workspace in
        XCTAssertTrue(workspace === NSWorkspace.shared, file: file, line: line)
        return application
      }
    )
  )
}

@MainActor
func applicationRuntimeReturningInstalledApplicationURL(
  _ url: URL?,
  for expectedBundleIdentifier: String = "com.example.app",
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    workspace: .shared,
    dependencies: ApplicationManagerDependencies(
      installedApplicationURL: { workspace, bundleIdentifier in
        XCTAssertTrue(workspace === NSWorkspace.shared, file: file, line: line)
        XCTAssertEqual(bundleIdentifier, expectedBundleIdentifier, file: file, line: line)
        return url
      }
    )
  )
}

@MainActor
func applicationRuntimeRejectingInstalledApplicationLookup(
  _ message: String,
  file: StaticString = #filePath,
  line: UInt = #line
) -> ApplicationManager {
  ApplicationManager(
    workspace: .shared,
    dependencies: ApplicationManagerDependencies(
      installedApplicationURL: { _, _ in
        XCTFail(message, file: file, line: line)
        return URL(fileURLWithPath: "/Applications/Example.app")
      }
    )
  )
}
