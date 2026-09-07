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
