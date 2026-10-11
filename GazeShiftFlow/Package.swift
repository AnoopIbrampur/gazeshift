// swift-tools-version: 6.0
import PackageDescription

// App-flow logic (air-trace pairing, calibration run, comparison composition) layered on the
// reviewed GazeShiftCore math. Kept as its own package so the core stays untouched and these
// tests run with Swift Testing on machines that only have the command-line tools.
let package = Package(
    name: "GazeShiftFlow",
    platforms: [.iOS("16.4"), .macOS("13.3")],
    products: [.library(name: "GazeShiftFlow", targets: ["GazeShiftFlow"])],
    dependencies: [.package(path: "../GazeShiftCore")],
    targets: [
        .target(name: "GazeShiftFlow", dependencies: [.product(name: "GazeShiftCore", package: "GazeShiftCore")]),
        .testTarget(name: "GazeShiftFlowTests", dependencies: ["GazeShiftFlow"])
    ]
)
