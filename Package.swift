// swift-tools-version:5.9
//
// Auto-generated for the v2026.10.22 release by
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
            url: "https://github.com/NodePassProject/EverywhereCore/releases/download/v2026.10.22/EverywhereCore-v2026.10.22.xcframework.zip",
            checksum: "7c4a371bf5bb2f46378ff5158176f6aeeb9face8289a7c679562aab3002789a2"
        ),
    ]
)
