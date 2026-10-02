// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barista",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "Barista", targets: ["Barista"])],
    targets: [.executableTarget(name: "Barista")]
)
