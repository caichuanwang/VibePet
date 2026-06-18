// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibePet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "VibePetCore",
            targets: ["VibePetCore"]
        ),
        .executable(
            name: "VibePetApp",
            targets: ["VibePetApp"]
        ),
        .executable(
            name: "VibePetHooks",
            targets: ["VibePetHooks"]
        ),
        .executable(
            name: "VibePetSetup",
            targets: ["VibePetSetup"]
        )
    ],
    targets: [
        .target(
            name: "VibePetCore",
            path: "VibePetCore"
        ),
        .executableTarget(
            name: "VibePetApp",
            dependencies: ["VibePetCore"],
            path: "VibePetApp"
        ),
        .executableTarget(
            name: "VibePetHooks",
            dependencies: ["VibePetCore"],
            path: "VibePetHooks"
        ),
        .executableTarget(
            name: "VibePetSetup",
            dependencies: ["VibePetCore"],
            path: "VibePetSetup"
        ),
        .testTarget(
            name: "VibePetCoreTests",
            dependencies: ["VibePetCore"],
            path: "Tests/VibePetCoreTests"
        )
    ]
)
