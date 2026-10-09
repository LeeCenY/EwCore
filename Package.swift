// swift-tools-version:5.9
//
// Auto-generated for the v2026.10.09 release by
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
            url: "https://github.com/NodePassProject/EverywhereCore/releases/download/v2026.10.09/EverywhereCore-v2026.10.09.xcframework.zip",
            checksum: "594207eb21011f34a96e79378c8b11e7cd0e20cb6db1814026deb02439c2cb75"
        ),
    ]
)
