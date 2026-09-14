// swift-tools-version: 6.2
import Foundation
import PackageDescription

let nativeTestDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .appendingPathComponent("_build/default/native/test").path

let package = Package(
  name: "BonsaiSwiftUI",
  platforms: [.iOS(.v18), .macOS(.v26)],
  products: [.library(name: "BonsaiSwiftUI", targets: ["BonsaiSwiftUI"])],
  targets: [
    .systemLibrary(name: "CBonsaiSwiftUI", path: "native/src"),
    .target(
      name: "BonsaiSwiftUI",
      dependencies: ["CBonsaiSwiftUI"],
      path: "swift/BonsaiSwiftUI/Sources",
      resources: [.copy("PrivacyInfo.xcprivacy")]
    ),
    .testTarget(
      name: "BonsaiSwiftUITests",
      dependencies: ["BonsaiSwiftUI"],
      path: "swift/BonsaiSwiftUI/Tests",
      linkerSettings: [
        .unsafeFlags([
          "-L", nativeTestDirectory, "-lruntime_fixture",
          "-Xlinker", "-rpath", "-Xlinker", nativeTestDirectory,
        ])
      ]
    ),
  ]
)
