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
            checksum: "62cf748bd56a93899055580cb27d60ab14246dbe4f8e31083d2474fd6e4dfa19"
        ),
    ]
)
