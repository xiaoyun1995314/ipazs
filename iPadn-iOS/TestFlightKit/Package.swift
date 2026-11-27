// swift-tools-version: 5.9
import PackageDescription

// TestFlightKit imports AppleAuth (private GSA/Store/TestFlight C++ core, local path
// dependency) and uses ZIPFoundation through TFZipShim, which exposes the tf_zip_*/tf_add_sinf/
// tf_free/tf_last_error C symbols that TFSINF calls via @_silgen_name. The app target links
// TestFlightKit; AppleAuth and ZIPFoundation come through transitively.
let package = Package(
    name: "TestFlightKit",
    platforms: [.iOS(.v16)],
    products: [.library(name: "TestFlightKit", targets: ["TestFlightKit"])],
    dependencies: [
        .package(path: "../Vendor/AppleAuth"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19")
    ],
    targets: [
        .target(
            name: "TestFlightKit",
            dependencies: [
                .product(name: "AppleAuth", package: "AppleAuth"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        )
    ]
)
