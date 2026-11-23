import Darwin
import DesktopApplications

func applicationProcessSnapshot(
  processIdentifier: pid_t = 1,
  bundleIdentifier: String? = "com.example.app",
  displayName: String? = "Example",
  isTerminated: Bool = false
) -> ApplicationSnapshot {
  ApplicationSnapshot(
    processIdentifier: processIdentifier,
    bundleIdentifier: bundleIdentifier,
    displayName: displayName,
    isTerminated: isTerminated
  )
}
