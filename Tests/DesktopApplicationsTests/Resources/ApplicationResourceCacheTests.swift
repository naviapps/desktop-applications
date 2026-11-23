import DesktopApplications
import XCTest

final class ApplicationResourceCacheTests: XCTestCase {
  func testEvictionCanInvalidateFromAResourceDeinitializerBeforeAnotherLoadStarts() throws {
    final class Resource {
      let onRelease: () -> Void
      init(_ onRelease: @escaping () -> Void = {}) { self.onRelease = onRelease }
      deinit { onRelease() }
    }
    let cache = ApplicationResourceCache<Resource>()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    func identity(_ index: Int) -> ApplicationResourceIdentity {
      .init(identifier: identifier, location: "/\(index).app", revision: "1", variant: "icon")
    }
    var reentered = false
    var first: Resource? = Resource {
      reentered = true
      try! cache.invalidate()
    }
    _ = try cache.value(for: identity(0)) { first }
    first = nil
    for index in 1..<128 { _ = try cache.value(for: identity(index)) { Resource() } }
    var loads = 0
    let result = try cache.value(for: identity(128)) {
      loads += 1
      return Resource()
    }
    XCTAssertTrue(reentered)
    XCTAssertNil(result)
    XCTAssertEqual(loads, 0)
  }

  func testUnrelatedReentrantLoadRetainsBothResources() throws {
    let cache = ApplicationResourceCache<String>()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    let first = ApplicationResourceIdentity(
      identifier: identifier, location: "/first.app", revision: "1", variant: "name")
    let second = ApplicationResourceIdentity(
      identifier: identifier, location: "/second.app", revision: "1", variant: "name")
    XCTAssertEqual(
      try cache.value(for: first) {
        _ = try! cache.value(for: second) { "second" }
        return "first"
      }, "first")
    XCTAssertEqual(try cache.value(for: first) { "wrong" }, "first")
    XCTAssertEqual(try cache.value(for: second) { "wrong" }, "second")
  }

  func testInvalidationDuringLoadDiscardsTheStaleValue() throws {
    let cache = ApplicationResourceCache<String>()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    let identity = ApplicationResourceIdentity(
      identifier: identifier, location: "/selected.app", revision: "1", variant: "name")
    let result = try cache.value(for: identity) {
      try! cache.invalidate()
      return "stale"
    }
    XCTAssertNil(result)
    XCTAssertEqual(try cache.value(for: identity) { "fresh" }, "fresh")
  }

  func testReentrantReplacementIsNotOverwrittenByAnOlderLoad() throws {
    let cache = ApplicationResourceCache<String>()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    let identity = ApplicationResourceIdentity(
      identifier: identifier, location: "/selected.app", revision: "1", variant: "name")
    let result = try cache.value(for: identity) {
      try! cache.invalidate()
      _ = try! cache.value(for: identity) { "replacement" }
      return "stale"
    }
    XCTAssertNil(result)
    XCTAssertEqual(try cache.value(for: identity) { "wrong" }, "replacement")
  }

  func testLoaderRetriesAMissingValueAndReloadsAfterInvalidation() throws {
    let cache = ApplicationResourceCache<String>()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    let identity = ApplicationResourceIdentity(
      identifier: identifier, location: "/selected.app", revision: "1", variant: "name")
    XCTAssertNil(try cache.value(for: identity) { nil })
    XCTAssertEqual(try cache.value(for: identity) { "first" }, "first")
    XCTAssertEqual(
      try cache.value(for: identity) {
        XCTFail("A retained hit must not call the loader")
        return nil
      }, "first")
    try cache.invalidate(identifier: identifier)
    XCTAssertEqual(try cache.value(for: identity) { "reloaded" }, "reloaded")
  }

  func testEvictedNativeResourcesAreReleased() throws {
    final class Resource {}
    let cache = ApplicationResourceCache<Resource>()
    let identifier = try ApplicationIdentifier(kind: .bundle, value: "com.example.app")
    func identity(_ index: Int) -> ApplicationResourceIdentity {
      ApplicationResourceIdentity(
        identifier: identifier, location: "/\(index).app", revision: "1", variant: "icon")
    }
    var first: Resource? = Resource()
    weak let released = first
    _ = try cache.value(for: identity(0)) { first }
    first = nil
    XCTAssertNotNil(released)
    for index in 1...128 { _ = try cache.value(for: identity(index)) { Resource() } }
    XCTAssertNil(released)
  }
}
