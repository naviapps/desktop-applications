// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "DesktopApplicationsAcceptance",
  platforms: [.macOS(.v26)],
  dependencies: [.package(name: "desktop-applications", path: "../../..")],
  targets: [
    .executableTarget(
      name: "Host",
      dependencies: [
        .product(name: "DesktopApplications", package: "desktop-applications"),
        .product(name: "DesktopApplicationsMacOS", package: "desktop-applications"),
      ]),
    .executableTarget(name: "Target"),
  ]
)
