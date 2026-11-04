// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirMouse",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AirMouse", targets: ["AirMouse"]),
        .library(name: "AirMouseCore", targets: ["AirMouseCore"]),
    ],
    targets: [
        // Pure logic: protocol v3, message handling, calibration geometry, ports, QR payload.
        .target(name: "AirMouseCore"),
        // SwiftUI app + Network.framework server + CGEvent output.
        .executableTarget(name: "AirMouse", dependencies: ["AirMouseCore"]),
        .testTarget(name: "AirMouseCoreTests", dependencies: ["AirMouseCore"]),
    ]
)
