// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeclarativeJSON",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "DeclarativeJSON", targets: ["DeclarativeJSON"])
    ],
    dependencies: [
        .package(url: "https://github.com/nothingsh/DeclarativeUIKit.git", from: "0.2.0"),
        .package(url: "https://github.com/nothingsh/DeclarativeCombine.git", from: "0.3.0")
    ],
    targets: [
        .target(name: "DeclarativeJSON", dependencies: ["DeclarativeUIKit", "DeclarativeCombine"]),
        .testTarget(name: "DeclarativeJSONTests", dependencies: ["DeclarativeJSON"])
    ],
    swiftLanguageVersions: [.v5]
)
