// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NexusHILBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NexusHILBridge", targets: ["NexusHILBridge"]),
    ],
    dependencies: [
        // WebSocket client
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        // JSON handling
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
        // Async utilities
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "NexusHILBridge",
            dependencies: [
                "Starscream",
                "SwiftyJSON",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources"
        ),
    ]
)
