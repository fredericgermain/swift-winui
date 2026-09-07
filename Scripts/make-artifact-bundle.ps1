<#
.SYNOPSIS
    Assembles a SwiftPM artifact bundle containing prebuilt swift-winui modules.

.DESCRIPTION
    swift-winui is ~317 machine-generated Swift files (WinRT projections of the
    Windows API). Compiling them from source dominates every cold build of any
    package that depends on it. This script packages an already-built copy.

    The bundle uses the SE-0482 `staticLibrary` artifact type. SE-0482 is
    specified for C libraries, but SwiftPM's implementation passes each
    `headerPaths` entry to the Swift frontend as a plain `-I` as well as
    `-Xcc -I` (Sources/Build/BuildPlan/BuildPlan+Swift.swift), so a directory of
    `.swiftmodule` files placed in `headerPaths` is found by the Swift module
    importer. That is what makes shipping prebuilt *Swift* modules possible here.

    Layout produced:

        swift-winui.artifactbundle/
          info.json
          <triple>/
            SwiftWinUIAggregate.lib      one static lib holding every target
            Microsoft.WindowsAppRuntime.Bootstrap.dll
            include/
              module.modulemap           declares CWinRT + CWinAppSDK
              Modules/                   *.swiftmodule, *.swiftdoc
              CWinRT/include/
              CWinAppSDK/{include,nuget/include}

.PARAMETER BuildDir
    The `.build/release` directory of a completed release build.

.PARAMETER Triple
    Target triple, e.g. x86_64-unknown-windows-msvc.

.PARAMETER OutDir
    Directory in which to create swift-winui.artifactbundle.

.PARAMETER Version
    Version string recorded in info.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuildDir,
    [Parameter(Mandatory = $true)][string]$Triple,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Path([string]$Path, [string]$What) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$What not found at '$Path'"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$BuildDir = Require-Path $BuildDir "build directory"

# Architecture of the bootstrap DLL that ships with CWinAppSDK.
$dllArch = if ($Triple -like "aarch64-*" -or $Triple -like "arm64-*") { "arm64" } else { "x86_64" }

$bundle = Join-Path $OutDir "swift-winui.artifactbundle"
if (Test-Path -LiteralPath $bundle) { Remove-Item -LiteralPath $bundle -Recurse -Force }

$archDir = Join-Path $bundle $Triple
$incDir = Join-Path $archDir "include"
$modulesDir = Join-Path $incDir "Modules"
New-Item -ItemType Directory -Force -Path $modulesDir | Out-Null

# --- 1. the static library ------------------------------------------------
$lib = Require-Path (Join-Path $BuildDir "SwiftWinUIAggregate.lib") "aggregate static library"
Copy-Item -LiteralPath $lib -Destination $archDir
Write-Host "lib: $([math]::Round((Get-Item $lib).Length / 1MB, 1)) MB"

# --- 2. the Swift module descriptions -------------------------------------
# `-I <dir>` makes swiftc look for <ModuleName>.swiftmodule in <dir>.
$srcModules = Require-Path (Join-Path $BuildDir "Modules") "Modules directory"
$expected = @("WinUI", "UWP", "WinAppSDK", "WindowsFoundation", "WebView2Core")
foreach ($m in $expected) {
    $sm = Join-Path $srcModules "$m.swiftmodule"
    if (-not (Test-Path -LiteralPath $sm)) { throw "missing $m.swiftmodule in $srcModules" }
    Copy-Item -LiteralPath $sm -Destination $modulesDir
    $doc = Join-Path $srcModules "$m.swiftdoc"
    if (Test-Path -LiteralPath $doc) { Copy-Item -LiteralPath $doc -Destination $modulesDir }
}
Write-Host "modules: $($expected -join ', ')"

# --- 3. the C module headers ----------------------------------------------
# The prebuilt .swiftmodules were compiled against these Clang modules and must
# be able to re-import them in the consumer's build, so the headers travel too.
$cwinrtDst = Join-Path $incDir "CWinRT"
New-Item -ItemType Directory -Force -Path $cwinrtDst | Out-Null
Copy-Item -Path (Join-Path $SourceRoot "Sources/CWinRT/include") -Destination $cwinrtDst -Recurse

# CWinAppSDK-Bridging-Header.h includes <../nuget/include/...>, so the include/
# and nuget/include/ siblings must keep their relative layout.
$sdkDst = Join-Path $incDir "CWinAppSDK"
New-Item -ItemType Directory -Force -Path (Join-Path $sdkDst "nuget") | Out-Null
Copy-Item -Path (Join-Path $SourceRoot "Sources/CWinAppSDK/include") -Destination $sdkDst -Recurse
Copy-Item -Path (Join-Path $SourceRoot "Sources/CWinAppSDK/nuget/include") -Destination (Join-Path $sdkDst "nuget") -Recurse

# A single modulemap can declare several top-level modules, which is what lets
# both C modules ride in one artifact (a variant carries one moduleMapPath).
# Paths are resolved relative to the modulemap's own directory.
@'
module CWinRT {
    umbrella header "CWinRT/include/CWinRT.h"
    export *
}

module CWinAppSDK {
    header "CWinAppSDK/include/CWinAppSDK-Bridging-Header.h"
    export *
}
'@ | Set-Content -LiteralPath (Join-Path $incDir "module.modulemap") -Encoding utf8

# --- 4. the Windows App Runtime bootstrapper ------------------------------
# Shipped as an `experimentalWindowsDLL` artifact, which makes SwiftPM copy it
# next to the consumer's built products.
$dll = Require-Path (Join-Path $SourceRoot "Sources/CWinAppSDK/nuget/bin/$dllArch/Microsoft.WindowsAppRuntime.Bootstrap.dll") "bootstrap DLL"
Copy-Item -LiteralPath $dll -Destination $archDir

# --- 5. info.json ---------------------------------------------------------
# Two staticLibrary artifacts point at the same .lib: SwiftPM collects library
# paths into a Set so it is linked once, but this gives us a second slot for
# metadata if a future split is needed.
$info = [ordered]@{
    schemaVersion = "1.0"
    artifacts     = [ordered]@{
        "SwiftWinUI"                  = [ordered]@{
            version  = $Version
            type     = "staticLibrary"
            variants = @(
                [ordered]@{
                    path                 = "$Triple/SwiftWinUIAggregate.lib"
                    supportedTriples     = @($Triple)
                    staticLibraryMetadata = [ordered]@{
                        headerPaths   = @(
                            "$Triple/include/Modules",
                            "$Triple/include"
                        )
                        moduleMapPath = "$Triple/include/module.modulemap"
                    }
                }
            )
        }
        "WindowsAppRuntimeBootstrap" = [ordered]@{
            version  = $Version
            type     = "experimentalWindowsDLL"
            variants = @(
                [ordered]@{
                    path             = "$Triple/Microsoft.WindowsAppRuntime.Bootstrap.dll"
                    supportedTriples = @($Triple)
                }
            )
        }
    }
}
$info | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $bundle "info.json") -Encoding utf8

Write-Host "bundle: $bundle"
Get-ChildItem -LiteralPath $bundle -Recurse -File | Measure-Object -Property Length -Sum |
    ForEach-Object { Write-Host "total: $([math]::Round($_.Sum / 1MB, 1)) MB in $($_.Count) files" }
