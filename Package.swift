// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "Imprint",
    products: [
        .executable(name: "Imprint", targets: ["Imprint"]),
        .library(name: "EPUBCore", targets: ["EPUBCore"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/tadija/AEXML", .branch("master")),
        .package(url: "https://github.com/tokyovigilante/HeliumLogger", .branch("master")),
        .package(url: "https://github.com/tokyovigilante/Harness", .branch("master")),
        .package(url: "https://github.com/tokyovigilante/ZipReader", .branch("master")),
        .package(url: "https://github.com/tokyovigilante/Airframe", .branch("master")),
    ],
    targets: [
        .systemLibrary(
            name: "CWebKitWPEFDO",
            pkgConfig: "wpebackend-fdo-1.0"
        ),
        .systemLibrary(
            name: "CWebKitWPE",
            pkgConfig: "wpe-webkit-1.0"
        ),
        .target(
            name: "Imprint",
            dependencies: [
                "Harness",
                "EPUBCore",
                "CWebKitWPEFDO",
                "CWebKitWPE",
                "Airframe",
            ]),
        .target(
            name: "EPUBCore",
            dependencies: [
                "ZipReader",
                "Harness",
                "AEXML",
            ]),
        .testTarget(
            name: "ImprintTests",
            dependencies: ["Imprint"]),
    ]
)
