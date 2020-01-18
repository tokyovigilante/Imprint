// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Imprint",
    products: [
        .executable(name: "Imprint", targets: ["Imprint"]),
        .library(name: "EPUBCore", targets: ["EPUBCore"]),
        .library(name: "ZipReader", targets: ["ZipReader"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/tadija/AEXML", .branch("master")),
        .package(url: "https://github.com/tokyovigilante/HeliumLogger", .branch("master")),
        .package(url: "https://github.com/tokyovigilante/Harness", .branch("master")),
    ],
    targets: [
        .target(
            name: "Imprint",
            dependencies: ["EPUBCore"]),
        .target(
            name: "EPUBCore",
            dependencies: [
                "ZipReader",
                "AEXML",
            ]),
        .target(
            name: "ZipReader",
            dependencies: [
                "CMinizip",
                "CShims",
                "HeliumLogger",
                "Harness",
            ]),
        .target(
            name: "CShims",
            dependencies: []
        ),
        .systemLibrary(
            name: "CMinizip",
            pkgConfig: "minizip"),
        .testTarget(
            name: "ImprintTests",
            dependencies: ["Imprint"]),
    ]
)
