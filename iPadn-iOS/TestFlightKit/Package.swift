// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TestFlightKit",
    platforms: [.iOS(.v16)],
    products: [.library(name: "TestFlightKit", targets: ["TestFlightKit"])],
    targets: [
        .target(
            name: "TestFlightKit",
            dependencies: ["AppleAuth"]
        )
    ]
)
