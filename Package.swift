// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "powernapv2new",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "powernapv2new",
            targets: ["powernapv2new"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "powernapv2new"),
        .testTarget(
            name: "powernapv2newTests",
            dependencies: ["powernapv2new"]
        ),
    ]
)
