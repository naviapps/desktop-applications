import Darwin
import DesktopApplications

func applicationRuntimeSnapshot(
  processIdentifier: pid_t = 456,
  bundleIdentifier: String? = "com.example.app",
  displayName: String? = "Example",
  isTerminated: Bool = false
) -> ApplicationSnapshot {
  ApplicationSnapshot(
    processIdentifier: processIdentifier,
    bundleIdentifier: bundleIdentifier,
    displayName: displayName,
    isTerminated: isTerminated,
    startTime: 1
  )
}
