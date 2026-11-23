import AppKit
import Darwin
import Foundation

private func watchOwner(_ owner: pid_t) {
  // A killed or timed-out Host must not leave this owned target behind.
  let deadline = ContinuousClock.now + .seconds(60)
  Thread.detachNewThread {
    while kill(owner, 0) == 0 && ContinuousClock.now < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
    _exit(1)
  }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
  let receipt: URL
  let refusesClose: Bool
  var closeRequests = 0
  var window: NSWindow?

  init(receipt: URL, refusesClose: Bool) {
    self.receipt = receipt
    self.refusesClose = refusesClose
  }

  func applicationDidFinishLaunching(_: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 520, height: 280),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "DesktopApplications owned acceptance"
    window.makeKeyAndOrderFront(nil)
    self.window = window
    record()
  }

  func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
    closeRequests += 1
    record()
    return refusesClose ? .terminateCancel : .terminateNow
  }

  func record() {
    let data = try! JSONSerialization.data(withJSONObject: [
      "processId": ProcessInfo.processInfo.processIdentifier,
      "closeRequests": closeRequests, "refusesClose": refusesClose,
    ])
    try! data.write(to: receipt, options: .atomic)
  }
}

guard [3, 4].contains(CommandLine.arguments.count) else {
  fatalError("Expected an owned receipt and close mode, optionally the owner PID")
}
if CommandLine.arguments.count == 4 {
  guard let owner = pid_t(CommandLine.arguments[3]), owner > 0 else {
    fatalError("Expected the owned Host PID")
  }
  watchOwner(owner)
}
let app = NSApplication.shared
let delegate = Delegate(
  receipt: URL(fileURLWithPath: CommandLine.arguments[1]),
  refusesClose: CommandLine.arguments[2] == "refuse")
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
withExtendedLifetime(delegate) {}
