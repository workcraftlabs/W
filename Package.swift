// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "W", platforms: [.macOS(.v14)],
    products: [.executable(name: "W", targets: ["W"]), .library(name: "WCore", targets: ["WCore"])],
    targets: [.target(name: "WCore"), .executableTarget(name: "W", dependencies: ["WCore"]), .testTarget(name: "WCoreTests", dependencies: ["WCore"])],
    swiftLanguageModes: [.v5]
)
