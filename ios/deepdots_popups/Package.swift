// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "deepdots_popups",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "deepdots-popups", targets: ["deepdots_popups"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // SDK nativo de Deepdots (KMP). Misma versión que DEEPDOTS_SDK_VERSION en el podspec.
        .package(url: "https://github.com/MagicFeedback/DeepdotsSDK-SPM", exact: "0.7.5")
    ],
    targets: [
        .target(
            name: "deepdots_popups",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                // El producto se llama ComposeApp; el módulo que se importa es DeepdotsSDK.
                .product(name: "ComposeApp", package: "DeepdotsSDK-SPM")
            ],
            resources: [
                // If your plugin requires a privacy manifest, for example if it uses any required
                // reason APIs, update the PrivacyInfo.xcprivacy file to describe your plugin's
                // privacy impact, and then uncomment these lines. For more information, see
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
