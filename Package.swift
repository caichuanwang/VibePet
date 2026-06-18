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
        ),
        .executable(
            name: "CutoutBenchmark",
            targets: ["CutoutBenchmark"]
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
        .executableTarget(
            name: "CutoutBenchmark",
            dependencies: ["VibePetCore"],
            path: "Tools/CutoutBenchmark/Sources/CutoutBenchmark"
        ),
        .testTarget(
            name: "VibePetCoreTests",
            dependencies: ["VibePetCore"],
            path: "Tests/VibePetCoreTests"
        )
    ]
)
