// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "deepdots_popups",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "deepdots-popups", targets: ["deepdots_popups"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // SDK nativo de Deepdots (KMP), vendorizado para la prueba de concepto. En producción
        // vendría del paquete SPM publicado (repo DeepdotsSDK-SPM).
        .binaryTarget(name: "DeepdotsSDK", path: "Frameworks/DeepdotsSDK.xcframework"),
        .target(
            name: "deepdots_popups",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "DeepdotsSDK"
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
