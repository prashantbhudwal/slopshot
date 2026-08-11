// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SlopShot",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "SlopShotCore", targets: ["SlopShotCore"]),
    .executable(name: "SlopShot", targets: ["SlopShot"]),
    .executable(name: "SlopShotCoreTests", targets: ["SlopShotCoreTests"]),
  ],
  dependencies: [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.10.0")
  ],
  targets: [
    .target(name: "SlopShotCore"),
    .executableTarget(
      name: "SlopShot",
      dependencies: [
        "SlopShotCore",
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
      ]
    ),
    .executableTarget(
      name: "SlopShotCoreTests",
      dependencies: ["SlopShotCore"]
    ),
  ]
)
