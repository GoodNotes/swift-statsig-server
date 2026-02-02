// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "statsig-swift",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(name: "StatsigCpp", targets: ["StatsigCpp"]),
        .library(name: "Statsig", targets: ["Statsig"]),
        .executable(name: "StatsigSwiftExample", targets: ["StatsigSwiftExample"]),
    ],
    targets: [
        .target(
            name: "StatsigCpp",
            path: "src",
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("../third_party/nlohmann_json/include"),
                .headerSearchPath("../third_party/cpp-httplib/include"),
                .unsafeFlags([
                    "-I/opt/homebrew/include",
                    "-I/usr/local/include",
                    "-I/opt/homebrew/opt/openssl@3/include",
                    "-I/usr/local/opt/openssl@3/include",
                ]),
                .define("CPPHTTPLIB_OPENSSL_SUPPORT"),
            ],
            linkerSettings: [
                .linkedLibrary("ssl"),
                .linkedLibrary("crypto"),
                .linkedLibrary("boost_regex"),
                .linkedLibrary("boost_thread"),
                .linkedLibrary("boost_chrono"),
                .unsafeFlags(["-L/opt/homebrew/lib"]),
                .unsafeFlags(["-L/usr/local/lib"]),
                .unsafeFlags(["-L/opt/homebrew/opt/openssl@3/lib"]),
                .unsafeFlags(["-L/usr/local/opt/openssl@3/lib"]),
            ]
        ),
        .target(
            name: "Statsig",
            dependencies: ["StatsigCpp"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
        .executableTarget(
            name: "StatsigSwiftExample",
            dependencies: ["Statsig"],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
