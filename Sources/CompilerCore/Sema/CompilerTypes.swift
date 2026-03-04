import Foundation

public struct CompilerVersion: Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let gitHash: String?

    public init(major: Int, minor: Int, patch: Int, gitHash: String?) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.gitHash = gitHash
    }
}

public enum KotlinLanguageVersion: Equatable {
    case v2_3_10
}

public struct TargetTriple: Equatable {
    public let arch: String
    public let vendor: String
    public let os: String
    public let osVersion: String?

    public init(arch: String, vendor: String, os: String, osVersion: String?) {
        self.arch = arch
        self.vendor = vendor
        self.os = os
        self.osVersion = osVersion
    }

    public static func hostDefault() -> TargetTriple {
        #if arch(arm64)
            let arch = "arm64"
        #elseif arch(x86_64)
            let arch = "x86_64"
        #else
            let arch = "arm64"
        #endif
        #if os(Linux)
            return TargetTriple(arch: arch, vendor: "unknown", os: "linux-gnu", osVersion: nil)
        #else
            return TargetTriple(arch: arch, vendor: "apple", os: "macosx", osVersion: nil)
        #endif
    }
}

public enum OptimizationLevel: Int {
    case O0
    case O1
    case O2
    case O3
}

public enum EmitMode: String {
    case executable
    case object
    case llvmIR
    case kirDump
    case library
}

/// Thread-safety mode for `by lazy { }` delegates (P5-80).
public enum LazyDelegateThreadSafetyMode: Int, Equatable {
    /// `LazyThreadSafetyMode.SYNCHRONIZED` – uses a lock (default).
    case synchronized = 1
    /// `LazyThreadSafetyMode.NONE` – no synchronization.
    case none = 0
}

/// Format for diagnostic output.
public enum DiagnosticsFormat: String, Equatable {
    /// Default human-readable text format.
    case text
    /// JSON format conforming to the LSP diagnostic schema.
    case json
}

public struct CompilerOptions: Equatable {
    public var moduleName: String
    public var inputs: [String]
    public var outputPath: String
    public var emit: EmitMode
    public var searchPaths: [String]
    public var libraryPaths: [String]
    public var linkLibraries: [String]
    public var target: TargetTriple
    public var optLevel: OptimizationLevel
    public var debugInfo: Bool
    public var frontendFlags: [String]
    public var irFlags: [String]
    public var runtimeFlags: [String]
    public var diagnosticsFormat: DiagnosticsFormat

    /// Path to the incremental compilation cache directory, if any.
    /// Incremental compilation is enabled when either this is non-nil or the
    /// `incremental` frontend flag is set; when enabled and a cache is
    /// available, the compiler will attempt to reuse results from previous builds.
    public var incrementalCachePath: String?

    public init(
        moduleName: String,
        inputs: [String],
        outputPath: String,
        emit: EmitMode,
        searchPaths: [String] = [],
        libraryPaths: [String] = [],
        linkLibraries: [String] = [],
        target: TargetTriple,
        optLevel: OptimizationLevel = .O0,
        debugInfo: Bool = false,
        frontendFlags: [String] = [],
        irFlags: [String] = [],
        runtimeFlags: [String] = [],
        incrementalCachePath: String? = nil,
        diagnosticsFormat: DiagnosticsFormat = .text
    ) {
        self.moduleName = moduleName
        self.inputs = inputs
        self.outputPath = outputPath
        self.emit = emit
        self.searchPaths = searchPaths
        self.libraryPaths = libraryPaths
        self.linkLibraries = linkLibraries
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.frontendFlags = frontendFlags
        self.irFlags = irFlags
        self.runtimeFlags = runtimeFlags
        self.incrementalCachePath = incrementalCachePath
        self.diagnosticsFormat = diagnosticsFormat
    }

    /// The number of frontend parallel jobs parsed from `-Xfrontend jobs=N`.
    /// Controls **BuildASTPhase** concurrency only; LexPhase and ParsePhase
    /// always submit all file tasks concurrently (unchanged from pre-PR
    /// behaviour).  Returns 1 (sequential) when the flag is not present.
    public var frontendJobs: Int {
        for flag in frontendFlags {
            if flag.hasPrefix("jobs="),
               let n = Int(flag.dropFirst(5)),
               n >= 1
            {
                return n
            }
        }
        return 1
    }

    /// Thread-safety mode for `by lazy { }` delegates, parsed from
    /// `-Xfrontend lazy-thread-safety=SYNCHRONIZED|NONE`.
    /// Defaults to `.synchronized` when the flag is absent.
    public var lazyThreadSafetyMode: LazyDelegateThreadSafetyMode {
        for flag in frontendFlags where flag.hasPrefix("lazy-thread-safety=") {
            let value = String(flag.dropFirst("lazy-thread-safety=".count))
                .uppercased()
            switch value {
            case "NONE":
                return .none
            case "SYNCHRONIZED":
                return .synchronized
            default:
                return .synchronized
            }
        }
        return .synchronized
    }
}
