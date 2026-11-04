// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BrianDesktop",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "BrianClient", targets: ["BrianClient"]),
        .executable(name: "BrianDesktop", targets: ["BrianDesktop"]),
    ],
    targets: [
        .target(name: "BrianClient"),
        .executableTarget(
            name: "BrianDesktop",
            dependencies: ["BrianClient"]
        ),
        .testTarget(
            name: "BrianClientTests",
            dependencies: ["BrianClient"]
        ),
    ]
)
