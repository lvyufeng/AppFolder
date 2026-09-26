// swift-tools-version: 6.0
import PackageDescription

/// Code shared between the app and its widget extension.
///
/// Both targets link this package, which matters for one specific reason beyond
/// code reuse: `AppIntent` implementations that a widget's `Button(intent:)`
/// invokes must be compiled into the widget extension itself, and the same
/// intent types must also be visible to the app for Shortcuts. A shared package
/// is the least error-prone way to guarantee that.
let package = Package(
    name: "AppFolderKit",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v18),
        // Not a shipping target. Declaring macOS lets `swift build` run on the
        // host for a fast syntax/type check without a full Xcode device build.
        // 15.0 rather than 14: `OpenURLIntent` — the API the whole app turns on —
        // starts at macOS 15 / iOS 18.
        .macOS(.v15)
    ],
    products: [
        .library(name: "AppFolderKit", targets: ["AppFolderKit"]),
        .executable(name: "appfolder-schemes", targets: ["GenerateQueriedSchemes"])
    ],
    targets: [
        .target(
            name: "AppFolderKit",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // Keeps `LSApplicationQueriesSchemes` in the app's Info.plist in sync
        // with `AppCatalog`. Run with `--check` in CI.
        .executableTarget(
            name: "GenerateQueriedSchemes",
            dependencies: ["AppFolderKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AppFolderKitTests",
            dependencies: ["AppFolderKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
