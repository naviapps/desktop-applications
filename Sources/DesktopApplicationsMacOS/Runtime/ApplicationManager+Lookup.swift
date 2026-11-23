import Darwin
import DesktopApplications

extension ApplicationManager {
  enum ApplicationLookupError: Error {
    case invalidProcessIdentifier
    case invalidBundleIdentifier
    case processIdentityUnavailable
    case processIdentityMismatch
    case applicationNotFound
    case applicationTerminated
    case applicationBundleIdentifierUnavailable
    case applicationBundleIdentifierMismatch

    var requestError: ApplicationOperationError {
      switch self {
      case .invalidProcessIdentifier:
        .invalidProcessIdentifier
      case .invalidBundleIdentifier:
        .invalidBundleIdentifier
      case .processIdentityUnavailable:
        .processIdentityUnavailable
      case .processIdentityMismatch:
        .processIdentityMismatch
      case .applicationNotFound:
        .applicationNotFound
      case .applicationTerminated:
        .applicationTerminated
      case .applicationBundleIdentifierUnavailable:
        .applicationBundleIdentifierUnavailable
      case .applicationBundleIdentifierMismatch:
        .applicationBundleIdentifierMismatch
      }
    }
  }

  static func applicationRequestResult(
    fromApplicationLookupResult applicationLookupResult: Result<
      any ApplicationManagerRunningApplication,
      ApplicationLookupError
    >,
    request: (any ApplicationManagerRunningApplication) -> ApplicationRequestResult<
      ApplicationOperationError
    >
  ) -> ApplicationRequestResult<ApplicationOperationError> {
    switch applicationLookupResult {
    case .success(let application):
      request(application)
    case .failure(let error):
      .failed(error.requestError)
    }
  }

  func currentApplicationLookupResult()
    -> Result<any ApplicationManagerRunningApplication, ApplicationLookupError>
  {
    guard let application = dependencies.currentApplication() else {
      return .failure(.applicationNotFound)
    }
    guard application.processIdentifier > 0 else {
      return .failure(.invalidProcessIdentifier)
    }
    guard !application.isTerminated else {
      return .failure(.applicationTerminated)
    }
    return .success(application)
  }

  func runningApplication(
    matchingProcessIdentifier processIdentifier: pid_t
  ) -> Result<any ApplicationManagerRunningApplication, ApplicationLookupError> {
    guard processIdentifier > 0 else {
      return .failure(.invalidProcessIdentifier)
    }
    guard let application = dependencies.runningApplication(processIdentifier),
      application.processIdentifier == processIdentifier
    else {
      return .failure(.applicationNotFound)
    }
    guard !application.isTerminated else {
      return .failure(.applicationTerminated)
    }
    return .success(application)
  }

  func runningApplication(
    matchingProcessIdentifier processIdentifier: pid_t,
    expectedBundleIdentifier: String
  ) -> Result<any ApplicationManagerRunningApplication, ApplicationLookupError> {
    guard let expected = try? ApplicationIdentifier(kind: .bundle, value: expectedBundleIdentifier)
    else {
      return .failure(.invalidBundleIdentifier)
    }
    switch runningApplication(matchingProcessIdentifier: processIdentifier) {
    case .failure(let error):
      return .failure(error)
    case .success(let application):
      let snapshot = ApplicationSnapshot(runningApplication: application)
      guard let identifier = snapshot.identifier else {
        return .failure(.applicationBundleIdentifierUnavailable)
      }
      guard identifier == expected else {
        return .failure(.applicationBundleIdentifierMismatch)
      }
      return runningApplication(matching: snapshot)
    }
  }

  func runningApplication(
    matching snapshot: ApplicationSnapshot
  ) -> Result<any ApplicationManagerRunningApplication, ApplicationLookupError> {
    guard snapshot.processIdentifier > 0 else {
      return .failure(.invalidProcessIdentifier)
    }
    guard !snapshot.isTerminated else {
      return .failure(.applicationTerminated)
    }
    if let identifier = snapshot.bundleIdentifier,
      ApplicationBundleIdentifierInput.trimmedNonEmpty(identifier) == nil
    {
      return .failure(.invalidBundleIdentifier)
    }
    let application: any ApplicationManagerRunningApplication
    switch runningApplication(matchingProcessIdentifier: snapshot.processIdentifier) {
    case .success(let value): application = value
    case .failure(let error): return .failure(error)
    }
    do {
      switch try snapshot.validationError(
        against: ApplicationSnapshot(runningApplication: application))
      {
      case nil: break
      case .invalidProcessID: return .failure(.invalidProcessIdentifier)
      case .invalidIdentifier: return .failure(.invalidBundleIdentifier)
      case .identityUnavailable: return .failure(.processIdentityUnavailable)
      case .targetChanged, .duplicateProcess: return .failure(.processIdentityMismatch)
      case .identifierUnavailable: return .failure(.applicationBundleIdentifierUnavailable)
      case .identifierMismatch: return .failure(.applicationBundleIdentifierMismatch)
      case .terminated: return .failure(.applicationTerminated)
      }
    } catch {
      return .failure(.processIdentityUnavailable)
    }
    return .success(application)
  }

  func runningApplication(
    matchingBundleIdentifier bundleIdentifier: String
  ) -> Result<any ApplicationManagerRunningApplication, ApplicationLookupError> {
    guard let bundleIdentifier = ApplicationBundleIdentifierInput.trimmedNonEmpty(bundleIdentifier)
    else {
      return .failure(.invalidBundleIdentifier)
    }
    guard let application = runningApplications(matchingBundleIdentifier: bundleIdentifier).first
    else {
      return .failure(.applicationNotFound)
    }
    return .success(application)
  }

  static func snapshot(
    for application: any ApplicationManagerRunningApplication
  ) -> ApplicationSnapshot? {
    guard application.processIdentifier > 0, !application.isTerminated else {
      return nil
    }
    return ApplicationSnapshot(runningApplication: application)
  }

  func runningApplications(
    matchingBundleIdentifier bundleIdentifier: String
  ) -> [any ApplicationManagerRunningApplication] {
    dependencies
      .runningApplications(bundleIdentifier)
      .filter {
        $0.processIdentifier > 0
          && !$0.isTerminated
          && $0.bundleIdentifier == bundleIdentifier
      }
  }
}
