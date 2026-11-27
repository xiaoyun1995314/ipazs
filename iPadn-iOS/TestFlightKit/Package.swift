// swift-tools-version: 5.9
import PackageDescription

// TestFlightKit imports AppleAuth; the private GSA/Store/TestFlight C++ core lives in
// the local AppleAuth package, declared here as a local path dependency so SPM resolves
// it in the same package graph. The app target links TestFlightKit; AppleAuth comes
// through transitively.
let package = Package(
    name: "TestFlightKit",
    platforms: [.iOS(.v16)],
    products: [.library(name: "TestFlightKit", targets: ["TestFlightKit"])],
    dependencies: [
        .package(path: "../Vendor/AppleAuth")
    ],
    targets: [
        .target(
            name: "TestFlightKit",
            dependencies: [
                .product(name: "AppleAuth", package: "AppleAuth")
            ]
        )
    ]
)
