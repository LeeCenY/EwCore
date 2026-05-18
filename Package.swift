// swift-tools-version:5.9
//
// Auto-generated for the v2026.05.18 release by
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
            url: "https://github.com/NodePassProject/EverywhereCore/releases/download/v2026.05.18/EverywhereCore-v2026.05.18.xcframework.zip",
            checksum: "90ec535ad46ff8ac7ba3b304f2c7b0ea6cfdfcb1a57a8511032cbbafe640dfa2"
        ),
    ]
)
