import CWinRT
import CWinAppSDK
import Foundation
import WindowsFoundation
import WinSDK

public enum ThreadingModel {
    case single
    case multi
}

enum InitializationError: LocalizedError {
    case failedToInstallWindowsAppRuntime
    case missingBootstrapper(_ paths: [String])
    case failedToLoadBootstrapper(_ path: String)
    case missingExecutableURL

    var errorDescription: String? {
        switch self {
            case .failedToInstallWindowsAppRuntime:
                return "Failed to install Windows App Runtime (installer produced non-zero exit status)"
            case .missingBootstrapper(let paths):
                return "Could not find bootstrapper DLL; expected to find it at one of \(paths)"
            case .failedToLoadBootstrapper(let path):
                return "Failed to load bootstrapper DLL at \(path)"
            case .missingExecutableURL:
                return "Missing executable URL"
        }
    }
}

/// WindowsAppRuntimeInitializer is used to properly initialize the Windows App SDK runtime, along with the Windows Runtime.
/// The runtime is initalized for the lifetime of the object, and is deinitialized when the object is deallocated.
/// Example usage:
/// ```
/// public static func main() {
///        do {
///            try withExtendedLifetime(WindowsAppRuntimeInitializer()) {
///                initialization code here
///            }
///        }
///        catch {
///            fatalError("Failed to initialize WindowsAppRuntimeInitializer: \(error)")
///        }
///    }
/// ```
public class WindowsAppRuntimeInitializer {
    // TODO: Figure out how to properly link against delayimp.lib so that we can delay load the bootstrap dll.
    private typealias pfnMddBootstrapInitialize2 = @convention(c) (UInt32, PCWSTR?, PACKAGE_VERSION, MddBootstrapInitializeOptions) -> HRESULT
    private typealias pfnMddBootstrapShutdown = @convention(c) () -> Void
    private let bootstrapperDll: HMODULE!

    private lazy var Initialize: pfnMddBootstrapInitialize2 = {
        let pfn = GetProcAddress(bootstrapperDll, "MddBootstrapInitialize2")
        return unsafeBitCast(pfn, to: pfnMddBootstrapInitialize2.self)
    }()

    private lazy var Shutdown: pfnMddBootstrapShutdown = {
        let pfn = GetProcAddress(bootstrapperDll, "MddBootstrapShutdown")
        return unsafeBitCast(pfn, to: pfnMddBootstrapShutdown.self)
    }()

    private func processHasIdentity() -> Bool {
        var length: UInt32 = 0
        return GetCurrentPackageFullName(&length, nil) != APPMODEL_ERROR_NO_PACKAGE
    }

    public init(threadingModel: ThreadingModel = .single) throws  {
        guard let executableURL = Bundle.main.executableURL else {
            throw InitializationError.missingExecutableURL
        }
        let appDirectory = executableURL
            .deletingLastPathComponent()

        let libraryPaths = [
            "swift-winui_CWinAppSDK.resources\\Microsoft.WindowsAppRuntime.Bootstrap.dll",
            "swift-winui_CWinAppSDK.bundle\\Microsoft.WindowsAppRuntime.Bootstrap.dll",
            // When swift-winui is consumed as a prebuilt binary artifact there is no
            // SwiftPM resource bundle; the bootstrapper DLL is copied next to the
            // executable by the artifact bundle's `experimentalWindowsDLL` artifact.
            "Microsoft.WindowsAppRuntime.Bootstrap.dll",
        ]
        guard
            let libraryPath = libraryPaths.first(where: { libraryPath in
                FileManager.default.fileExists(
                    atPath: appDirectory.appendingPathComponent(libraryPath).path
                )
            })
        else {
            print("Expected to find bootstrapper dll at one of \(libraryPaths)")
            throw InitializationError.missingBootstrapper(libraryPaths)
        }
        guard let dll = LoadLibraryA(libraryPath) else {
            print("Failed to load bootstrapper dll at \(libraryPath)")
            throw InitializationError.failedToLoadBootstrapper(libraryPath)
        }
        bootstrapperDll = dll
        let roInitParam = switch threadingModel {
            case .single: RO_INIT_SINGLETHREADED
            case .multi: RO_INIT_MULTITHREADED
        }

        try CHECKED(RoInitialize(roInitParam))

        try CHECKED(SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE))

        guard !processHasIdentity() else {
            return
        }

        let runtimeInstaller = appDirectory
            .appendingPathComponent("WindowsAppRuntimeInstaller.exe")
        let installerExists = FileManager.default.fileExists(atPath: runtimeInstaller.path)

        func doInit(showUIOnNoMatch: Bool) throws {
            try CHECKED(Initialize(
                UInt32(WINDOWSAPPSDK_RELEASE_MAJORMINOR),
                WINDOWSAPPSDK_RELEASE_VERSION_TAG_SWIFT,
                .init(),
                MddBootstrapInitializeOptions(
                    showUIOnNoMatch
                        ? MddBootstrapInitializeOptions_OnNoMatch_ShowUI.rawValue
                        : MddBootstrapInitializeOptions_None.rawValue
                )
            ))
        }

        do {
            try doInit(showUIOnNoMatch: !installerExists)
        } catch {
            guard installerExists else {
                print("Windows App Runtime not found on system, and no installer was present to install it (expected at '\(runtimeInstaller.lastPathComponent)')")
                throw error
            }

            let process = Process()
            process.executableURL = runtimeInstaller
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                throw InitializationError.failedToInstallWindowsAppRuntime
            }

            try doInit(showUIOnNoMatch: false)
        }
    }

    deinit {
        RoUninitialize()
        if !processHasIdentity() {
            Shutdown()
        }
        FreeLibrary(bootstrapperDll)
    }
}
