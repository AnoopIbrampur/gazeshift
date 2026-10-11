// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GazeShiftCore",
    platforms: [.iOS("16.4"), .macOS("13.3")],
    products: [.library(name: "GazeShiftCore", targets: ["GazeShiftCore"])],
    targets: [
        .target(name: "GazeNumerics", cSettings: [.define("ACCELERATE_NEW_LAPACK")],
                linkerSettings: [.linkedFramework("Accelerate")]),
        .target(name: "GazeShiftCore", dependencies: ["GazeNumerics"]),
        .testTarget(name: "GazeShiftCoreTests", dependencies: ["GazeShiftCore"])
    ]
)
