// swift-tools-version:5.9
//
// Auto-generated for the v2026.06.25 release by
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
            url: "https://github.com/NodePassProject/EverywhereCore/releases/download/v2026.06.25/EverywhereCore-v2026.06.25.xcframework.zip",
            checksum: "bc52a79ea3758ab07050d76e8f7ad4451567f2c8a1bc9a55c51ee7ca7d5d1422"
        ),
    ]
)
