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
        runtimeFlags: [String] = []
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
    }
}
