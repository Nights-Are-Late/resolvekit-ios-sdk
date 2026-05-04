// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ResolveKitDemo",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "ResolveKitDemo", targets: ["ResolveKitDemo"])
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "ResolveKitDemo",
            dependencies: [
                .product(name: "ResolveKitUI", package: "resolvekit-ios-sdk")
            ],
            path: "Sources/ResolveKitDemo"
        )
    ]
)
