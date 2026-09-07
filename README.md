# swift-winui

Swift Language Bindings for common WinRT APIs and the Windows App SDK. For now, this package hosts bindings for WinUI 3, the Windows App SDK, UWP, Windows Foundation, and WebView 2 Core.

## Prebuilt binaries (this fork)

Compiling these projections dominates the cold build of anything that depends on
them. This fork publishes them prebuilt as a SwiftPM artifact bundle, measured on
identical `windows-latest` runners with Swift 6.3.1:

| | cold build of the same consumer |
|---|---|
| from source | 582 s |
| prebuilt | 72 s, including the 55 MB download |

Set `SWIFT_WINUI_PREBUILT=1` and depend on this fork as usual; the six products
are unchanged. Unset, the package builds from source exactly as upstream does,
which is also the fallback whenever no bundle matches your toolchain.

```
SWIFT_WINUI_PREBUILT=1 swift build
```

`SWIFT_WINUI_PREBUILT=<path to a .artifactbundle>` uses a local bundle instead.

### How it works, and what it costs

The bundle is an SE-0482 `staticLibrary` artifact: one `libSwiftWinUIAggregate.a`
holding every target, plus the five `.swiftmodule` files, the `CWinRT` and
`CWinAppSDK` headers with a combined modulemap, and the Windows App Runtime
bootstrapper as an `experimentalWindowsDLL` artifact.

SE-0482 is specified for C libraries and its metadata has no field for a Swift
module. It works here because SwiftPM passes every `headerPaths` entry to the
Swift frontend as a plain `-I` as well as `-Xcc -I`
([BuildPlan+Swift.swift](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/Build/BuildPlan/BuildPlan%2BSwift.swift)),
so `.swiftmodule` files placed on that path are found by the module importer.
That is undocumented and outside what the proposal promises; it is not a
sanctioned mechanism and could regress.

Two hard constraints follow from shipping binary `.swiftmodule` files:

- **A bundle is valid for exactly one Swift release.** The module format is not
  stable across compiler versions, so the toolchain is part of the asset name and
  a new release is needed per toolchain. `.swiftinterface` plus library evolution
  would remove this, but the projections have not been built that way and Apple's
  own prebuilts pin exact compiler versions rather than rely on it.
- **One triple per bundle.** Only `x86_64-unknown-windows-msvc` is published;
  arm64 needs a second bundle.

Built and published by [`.github/workflows/prebuilts.yml`](.github/workflows/prebuilts.yml);
[`verify-prebuilt.yml`](.github/workflows/verify-prebuilt.yml) consumes the
published release over the network and produces the numbers above.

## Bindings

The bindings are generated using [thebrowsercompany/swift-winrt](https://github.com/thebrowsercompany/swift-winrt). To discover which bindings each product provides bindings for, see the `projections.json` file in the corresponding subdirectory of the `Support` directory.

## Useful resources

- [Windows App SDK API documentation](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls?view=windows-app-sdk-1.5)
- [Official WinUI 3 GitHub repo](https://github.com/microsoft/microsoft-ui-xaml)

## SDK Versions

These bindings target a specific Windows SDK and a specific Windows App SDK. Bindings for the Windows SDK are compatible with all Windows SDK versions that follow. Bindings for Windows App SDK APIs on the other hand require that a matching Windows App Runtime version is installed.

1. Windows SDK: `10.0.17763.0`
2. Windows App SDK: `1.5-preview1`

## Depenencies

### Compiletime dependencies

To compile an app that uses swift-winui, you must install a matching version of the Windows SDK;

```pwsh
winget install --id Microsoft.WindowsSDK.10.0.17763
```

### Runtime dependencies

To run an app that uses swift-winui, you must install the correct version of the Windows App Runtime;

- x64: [windowsappruntimeinstall-x64.exe](https://aka.ms/windowsappsdk/1.5/1.5.240205001-preview1/windowsappruntimeinstall-x64.exe)
- arm64: [windowsappruntimeinstall-arm64.exe](https://aka.ms/windowsappsdk/1.5/1.5.240205001-preview1/windowsappruntimeinstall-arm64.exe)
