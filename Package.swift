// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lyrik",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Lyrik",
            path: "Sources/Lyrik",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Osize"], .when(configuration: .release))],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CoreServices"),
            ]
        )
    ]
)
