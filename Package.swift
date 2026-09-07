// swift-tools-version: 5.10

import PackageDescription
import Foundation

#if arch(x86_64)
    let windowsAppRTBootstrapDll: Resource = .copy("nuget/bin/x86_64/Microsoft.WindowsAppRuntime.Bootstrap.dll")
#elseif arch(arm64)
    let windowsAppRTBootstrapDll: Resource = .copy("nuget/bin/arm64/Microsoft.WindowsAppRuntime.Bootstrap.dll")
#endif

let package = Package(
    name: "swift-winui",
    products: [
        .library(name: "WinUI", type: .static, targets: ["WinUI"]),
        .library(name: "WebView2Core", type: .static, targets: ["WebView2Core"]),
        .library(name: "WinAppSDK", type: .static, targets: ["WinAppSDK"]),
        .library(name: "UWP", type: .static, targets: ["UWP"]),
        .library(name: "WindowsFoundation", type: .static, targets: ["WindowsFoundation"]),
        .library(name: "CWinRT", type: .static, targets: ["CWinRT"]),
    ],
    targets: [
        .target(
            name: "WinUI",
            dependencies: [
                "CWinRT",
                "UWP",
                "WinAppSDK",
                "WindowsFoundation",
                "WebView2Core",
            ]
        ),
        .target(name: "CWinRT"),
        .target(
            name: "UWP",
            dependencies: [
                "CWinRT",
                "WindowsFoundation",
            ]
        ),
        .target(
            name: "WinAppSDK",
            dependencies: [
                "CWinRT",
                "UWP",
                "WindowsFoundation",
                "CWinAppSDK",
            ]
        ),
        .target(
            name: "CWinAppSDK",
            resources: [
                windowsAppRTBootstrapDll,
            ]
        ),
        .target(
            name: "WindowsFoundation",
            dependencies: [
                "CWinRT",
            ]
        ),
        .target(
            name: "WebView2Core",
            dependencies: [
                "CWinRT",
                "UWP",
                "WindowsFoundation",
            ]
        ),
    ]
)

// Release asset published by .github/workflows/prebuilts.yml, and its checksum
// as reported by `swift package compute-checksum`. Updated per prebuilt release.
let prebuiltVersion = "0.2.2"
let prebuiltSwiftTag = "6.3.1-RELEASE"
let prebuiltURL =
    "https://github.com/fredericgermain/swift-winui/releases/download/"
    + "prebuilt-\(prebuiltVersion)/swift-winui-\(prebuiltVersion)"
    + "-x86_64-unknown-windows-msvc-\(prebuiltSwiftTag).artifactbundle.zip"
let prebuiltChecksum = "f5332134a1b36c9efc1292b1a2a098a225242a42ecb6e61039e283ac786f69a6"

// MARK: - Prebuilt aggregation
//
// When SWIFT_WINUI_AGGREGATE is set, expose a single static library product that
// archives every target in this package into one `.lib`. This is what the
// prebuilts workflow (.github/workflows/prebuilts.yml) builds and ships inside a
// SwiftPM artifact bundle. It is opt-in so that ordinary source consumers of this
// package see exactly the same six products as upstream.
if ProcessInfo.processInfo.environment["SWIFT_WINUI_AGGREGATE"] != nil {
    package.products += [
        .library(
            name: "SwiftWinUIAggregate",
            type: .static,
            targets: [
                "WinUI",
                "UWP",
                "WinAppSDK",
                "WindowsFoundation",
                "WebView2Core",
                "CWinRT",
                "CWinAppSDK",
            ]
        )
    ]
}

// MARK: - Prebuilt consumption
//
// Setting SWIFT_WINUI_PREBUILT makes this package vend its six public products
// from a prebuilt artifact bundle instead of compiling the ~317 generated WinRT
// projection sources. Unset (the default) the package builds from source exactly
// as upstream does, which is the fallback whenever no bundle matches the host.
//
//   SWIFT_WINUI_PREBUILT=1            use the release named by prebuiltURL below
//   SWIFT_WINUI_PREBUILT=<path>       use a local .artifactbundle (used by CI)
//
// Caveat: a Swift module is only loadable by the compiler version that produced
// it, so a bundle is valid for one Swift release only. The toolchain version is
// part of the release asset name, and the pin below must match it.
if let prebuilt = ProcessInfo.processInfo.environment["SWIFT_WINUI_PREBUILT"],
   !prebuilt.isEmpty
{
    let binaryTarget: Target
    if prebuilt == "1" || prebuilt.lowercased() == "true" {
        binaryTarget = .binaryTarget(
            name: "SwiftWinUIPrebuilt",
            url: prebuiltURL,
            checksum: prebuiltChecksum
        )
    } else {
        // A path to a locally built bundle.
        binaryTarget = .binaryTarget(name: "SwiftWinUIPrebuilt", path: prebuilt)
    }

    // Every product resolves to the one binary target. SwiftPM collects binary
    // library paths into a set, so the archive is still linked exactly once.
    package.targets = [binaryTarget]
    package.products = [
        .library(name: "WinUI", targets: ["SwiftWinUIPrebuilt"]),
        .library(name: "UWP", targets: ["SwiftWinUIPrebuilt"]),
        .library(name: "WinAppSDK", targets: ["SwiftWinUIPrebuilt"]),
        .library(name: "WindowsFoundation", targets: ["SwiftWinUIPrebuilt"]),
        .library(name: "WebView2Core", targets: ["SwiftWinUIPrebuilt"]),
        .library(name: "CWinRT", targets: ["SwiftWinUIPrebuilt"]),
    ]
}
