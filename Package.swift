// swift-tools-version:5.9
//
// Auto-generated for the v2026.06.01 release by
// .github/workflows/upstream-watch.yml. The `main` branch
// keeps a local `binaryTarget(path:)` variant for in-tree
// development; this variant lives only on the tag.

import PackageDescription

let package = Package(
    name: "EverywhereCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "EverywhereCore", targets: ["EverywhereCore"]),
    ],
    targets: [
        .binaryTarget(
            name: "EverywhereCore",
            url: "https://github.com/NodePassProject/EverywhereCore/releases/download/v2026.06.01/EverywhereCore-v2026.06.01.xcframework.zip",
            checksum: "c360da061d0e9045d75222dcd808cfb5e5d7eaac98a34e7eb1f6cfa435348b6a"
        ),
    ]
)
