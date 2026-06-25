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
        ),
        .testTarget(
            name: "VibePetE2ETests",
            // Depends on the VibePetHooks executable so `swift test` builds the real
            // CLI binary; the subprocess test exercises its actual process entry
            // point (main.swift wiring), which in-process tests cannot cover.
            dependencies: ["VibePetCore", "VibePetHooks"],
            path: "Tests/E2E"
        ),
        .testTarget(
            name: "VibePetAppTests",
            dependencies: ["VibePetApp", "VibePetCore"],
            path: "Tests/VibePetAppTests"
        ),
        .testTarget(
            name: "VibePetSetupTests",
            // The installer logic (binary copy, manifest, config writers) lives in
            // VibePetCore so it is shared with VibePetApp (trust activation) and
            // unit-testable in-process; the VibePetSetup executable is a thin shell.
            dependencies: ["VibePetCore"],
            path: "Tests/VibePetSetupTests"
        )
    ]
)
