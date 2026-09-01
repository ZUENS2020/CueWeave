// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CueWeaveMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CueWeaveMac", targets: ["CueWeaveMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.3.2"),
        .package(url: "https://github.com/dmrschmidt/DSWaveformImage.git", exact: "14.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "CueWeaveMac",
            dependencies: [
                .product(name: "DSWaveformImage", package: "DSWaveformImage"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .testTarget(
            name: "CueWeaveMacTests",
            dependencies: [
                "CueWeaveMac",
                .product(name: "Testing", package: "swift-testing"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
