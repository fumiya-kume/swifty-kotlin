import CompilerCore
import Foundation

enum CLIParseError: Error, Equatable {
    case usageRequested
    case missingValue(String)
    case unsupportedEmitMode(String)
    case unsupportedOptimizationLevel(String)
    case invalidTargetTriple(String)
    case unsupportedDiagnosticsFormat(String)
    case unknownOption(String)
    case noInputFiles
}

enum CLIParser {
    static let usageText = """
    Usage: kswiftc [options] <input files>
      -o <path>              Output path
      --emit <mode>          executable|object|llvm|kir
      -O0|-O1|-O2|-O3        Optimization level
      -m <name>              Module name
      -I <path>              Search path
      -L <path>              Library path
      -l <name>              Link library
      --target <triple>      Target triple (arch-vendor-os[-version])
      -Xfrontend <flag>      Frontend feature flag (e.g. time-phases)
      -Xir <flag>            IR/lowering feature flag (e.g. backend=llvm-c-api, backend-strict=true)
      -Xruntime <flag>       Runtime feature flag
      -Xdiagnostics <format> Diagnostic output format (text|json)
      -g                     Emit debug info
    """

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func parse(args: [String]) throws -> CompilerOptions {
        var inputPaths: [String] = []
        var outputPath = "./a.out"
        var moduleName = "Main"
        var emitMode: EmitMode = .executable
        var searchPaths: [String] = []
        var libraryPaths: [String] = []
        var linkLibraries: [String] = []
        var optLevel: OptimizationLevel = .O0
        var debugInfo = false
        var frontendFlags: [String] = []
        var irFlags: [String] = []
        var runtimeFlags: [String] = []
        var diagnosticsFormat: DiagnosticsFormat = .text
        var target = TargetTriple.hostDefault()

        if args.isEmpty {
            throw CLIParseError.noInputFiles
        }

        var index = 0
        while index < args.count {
            let arg = args[index]

            switch arg {
            case "-h", "--help":
                throw CLIParseError.usageRequested
            case "-o":
                outputPath = try requireValue(option: arg, args: args, index: &index)
            case "-m":
                moduleName = try requireValue(option: arg, args: args, index: &index)
            case "--emit":
                let value = try requireValue(option: arg, args: args, index: &index)
                guard let mode = parseEmitMode(value) else {
                    throw CLIParseError.unsupportedEmitMode(value)
                }
                emitMode = mode
            case "-O0", "-O1", "-O2", "-O3":
                if let level = parseOptimizationLevel(String(arg.dropFirst())) {
                    optLevel = level
                }
            case _ where arg.hasPrefix("-O"):
                guard let level = parseOptimizationLevel(String(arg.dropFirst())) else {
                    throw CLIParseError.unsupportedOptimizationLevel(arg)
                }
                optLevel = level
            case "--target":
                let value = try requireValue(option: arg, args: args, index: &index)
                guard let parsed = parseTargetTriple(value) else {
                    throw CLIParseError.invalidTargetTriple(value)
                }
                target = parsed
            case "-Xfrontend":
                try frontendFlags.append(requireValue(option: arg, args: args, index: &index))
            case "-Xir":
                try irFlags.append(requireValue(option: arg, args: args, index: &index))
            case "-Xruntime":
                try runtimeFlags.append(requireValue(option: arg, args: args, index: &index))
            case "-Xdiagnostics":
                let value = try requireValue(option: arg, args: args, index: &index)
                guard let fmt = DiagnosticsFormat(rawValue: value) else {
                    throw CLIParseError.unsupportedDiagnosticsFormat(value)
                }
                diagnosticsFormat = fmt
            case "-I":
                try searchPaths.append(requireValue(option: arg, args: args, index: &index))
            case "-L":
                try libraryPaths.append(requireValue(option: arg, args: args, index: &index))
            case "-l":
                try linkLibraries.append(requireValue(option: arg, args: args, index: &index))
            case "-g":
                debugInfo = true
            default:
                if arg.hasPrefix("-") {
                    throw CLIParseError.unknownOption(arg)
                }
                inputPaths.append(arg)
            }

            index += 1
        }

        if inputPaths.isEmpty {
            throw CLIParseError.noInputFiles
        }

        return CompilerOptions(
            moduleName: moduleName,
            inputs: inputPaths,
            outputPath: outputPath,
            emit: emitMode,
            searchPaths: searchPaths,
            libraryPaths: libraryPaths,
            linkLibraries: linkLibraries,
            target: target,
            optLevel: optLevel,
            debugInfo: debugInfo,
            frontendFlags: frontendFlags,
            irFlags: irFlags,
            runtimeFlags: runtimeFlags,
            diagnosticsFormat: diagnosticsFormat
        )
    }

    private static func requireValue(option: String, args: [String], index: inout Int) throws -> String {
        index += 1
        guard index < args.count else {
            throw CLIParseError.missingValue(option)
        }
        return args[index]
    }

    private static func parseEmitMode(_ value: String) -> EmitMode? {
        switch value {
        case "executable":
            .executable
        case "object":
            .object
        case "llvm", "llvm-ir", "ll":
            .llvmIR
        case "kir", "kir-dump":
            .kirDump
        case "library", "lib":
            .library
        default:
            nil
        }
    }

    private static func parseOptimizationLevel(_ value: String) -> OptimizationLevel? {
        switch value {
        case "O0":
            .O0
        case "O1":
            .O1
        case "O2":
            .O2
        case "O3":
            .O3
        default:
            nil
        }
    }

    private static func parseTargetTriple(_ value: String) -> TargetTriple? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else {
            return nil
        }
        let arch = parts[0]
        let vendor = parts[1]
        let os = parts[2]
        let version = parts.count > 3 ? parts[3] : nil
        return TargetTriple(arch: arch, vendor: vendor, os: os, osVersion: version)
    }
}
