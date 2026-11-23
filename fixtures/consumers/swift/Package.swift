// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "DesktopApplicationsConsumer",
  platforms: [.macOS(.v26)],
  dependencies: [.package(name: "desktop-applications", path: "../sdk")],
  targets: [
    .executableTarget(
      name: "DesktopApplicationsConsumer",
      dependencies: [
        .product(name: "DesktopApplications", package: "desktop-applications"),
        .product(name: "DesktopApplicationsMacOS", package: "desktop-applications"),
      ])
  ]
)
