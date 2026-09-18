// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorPluginPhotosOriginal",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapacitorPluginPhotosOriginal",
            targets: ["PhotosOriginalPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", branch: "main")
    ],
    targets: [
        .target(
            name: "PhotosOriginalPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm")
            ],
            path: "ios/Plugin"
        )
    ]
)
