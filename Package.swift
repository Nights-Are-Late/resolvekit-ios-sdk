// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ResolveKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(name: "ResolveKitCore", type: .dynamic, targets: ["ResolveKitCore"]),
        .library(name: "ResolveKitAuthoring", targets: ["ResolveKitAuthoring"]),
        .library(name: "ResolveKitNetworking", type: .dynamic, targets: ["ResolveKitNetworking"]),
        .library(name: "ResolveKitUI", type: .dynamic, targets: ["ResolveKitUI"]),
        .plugin(name: "ResolveKitPlugin", targets: ["ResolveKitPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0")
    ],
    targets: [
        .target(
            name: "ResolveKitCore"
        ),
        .target(
            name: "ResolveKitAuthoring",
            dependencies: [
                "ResolveKitCore",
                "ResolveKitMacros"
            ]
        ),
        .target(
            name: "ResolveKitNetworking",
            dependencies: [
                "ResolveKitCore"
            ]
        ),
        .target(
            name: "ResolveKitUI",
            dependencies: [
                "ResolveKitCore",
                "ResolveKitNetworking"
            ]
        ),
        .macro(
            name: "ResolveKitMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .executableTarget(
            name: "ResolveKitCodegen",
            dependencies: []
        ),
        .plugin(
            name: "ResolveKitPlugin",
            capability: .buildTool(),
            dependencies: ["ResolveKitCodegen"]
        ),
        .testTarget(
            name: "ResolveKitCoreTests",
            dependencies: ["ResolveKitCore"]
        ),
        .testTarget(
            name: "ResolveKitMacroTests",
            dependencies: [
                "ResolveKitAuthoring",
                "ResolveKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "ResolveKitIntegrationTests",
            dependencies: ["ResolveKitCore", "ResolveKitUI", "ResolveKitNetworking"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
