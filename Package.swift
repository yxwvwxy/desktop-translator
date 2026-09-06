// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopTranslator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DesktopTranslator", targets: ["DesktopTranslator"]),
    ],
    targets: [
        .executableTarget(
            name: "DesktopTranslator",
            path: "Sources",
            exclude: ["Widget"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
