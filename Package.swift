// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "Wyrm",
  platforms: [.macOS(.v14)],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
    .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.2.2"),
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can
    // define a module or a test suite. Targets can depend on other targets
    // in this package, and on products in packages this package depends on.
    .executableTarget(
      name: "Wyrm",
      dependencies: ["TOMLDecoder"]),
    .testTarget(
      name: "WyrmTests",
      dependencies: ["Wyrm"]),
  ]
)
