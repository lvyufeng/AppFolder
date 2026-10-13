// swift-tools-version: 6.4
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
        // The app and its widget both deploy to iOS 27: the whole product turns on
        // iOS 27's `RunSystemShortcutIntent`, and there is no older fallback. The
        // package states the same floor so a target cannot link it and quietly
        // build for a version the shipping app never runs on.
        .iOS(.v27),
        // Not a shipping target. Declaring macOS lets `swift build` run on the
        // host for a fast syntax/type check without a full Xcode device build.
        .macOS(.v15)
    ],
    products: [
        .library(name: "AppFolderKit", targets: ["AppFolderKit"])
    ],
    targets: [
        .target(
            name: "AppFolderKit",
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
