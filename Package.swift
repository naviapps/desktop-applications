// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "DesktopApplications",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "DesktopApplications", targets: ["DesktopApplications"]),
    .library(name: "DesktopApplicationsMacOS", targets: ["DesktopApplicationsMacOS"]),
  ],
  targets: [
    .binaryTarget(
      name: "CDesktopApplications", path: "Artifacts/CDesktopApplications.xcframework"),
    .target(name: "DesktopApplications", dependencies: ["CDesktopApplications"]),
    .target(name: "DesktopApplicationsMacOS", dependencies: ["DesktopApplications"]),
    .testTarget(name: "DesktopApplicationsTests", dependencies: ["DesktopApplications"]),
    .testTarget(
      name: "DesktopApplicationsMacOSTests",
      dependencies: ["DesktopApplicationsMacOS", "DesktopApplications"]),
  ]
)
