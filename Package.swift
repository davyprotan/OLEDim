// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OLEDim",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "OLEDim",
            path: "Sources/OLEDim",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]
        )
    ]
)
