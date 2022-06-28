// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Wyrm",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio", from: "2.0.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.2.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can
        // define a module or a test suite. Targets can depend on other targets
        // in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "Wyrm",
            dependencies: ["TOMLDecoder",
                           .product(name: "NIOCore", package: "swift-nio"),
                           .product(name: "NIOPosix", package: "swift-nio"),
                           .product(name: "NIOHTTP1", package: "swift-nio"),
                           .product(name: "NIOWebSocket", package: "swift-nio")]),
        .testTarget(
            name: "WyrmTests",
            dependencies: ["Wyrm"]),
    ]
)
