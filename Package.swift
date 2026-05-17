// swift-tools-version:5.9
//
// Auto-generated for the v2026.05.17 release by
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
            url: "https://github.com/NodePassProject/EverywhereCore/releases/download/v2026.05.17/EverywhereCore-v2026.05.17.xcframework.zip",
            checksum: "29500182cf9e814b8523e0f8d29109c56f55e818bb11a368ee64465d23a2276f"
        ),
    ]
)
