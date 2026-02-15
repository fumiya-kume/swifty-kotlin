import Foundation
import CompilerCore

func printUsage() {
    let usage = """
Usage: kswiftc [options] <input files>
  -o <path>              Output path
  --emit <mode>          executable|object|llvm|kir
  -O0|-O1|-O2|-O3        Optimization level
  -m <name>              Module name
  -I <path>              Search path
  -L <path>              Library path
  -l <name>              Link library
  --target <triple>      Target triple (arch-vendor-os[-version])
  -Xfrontend <flag>      Frontend feature flag
  -Xir <flag>            IR/lowering feature flag (e.g. backend=llvm-c-api, backend-strict=true)
  -Xruntime <flag>       Runtime feature flag
  -g                     Emit debug info
"""
    print(usage)
}

func parseEmitMode(_ value: String) -> EmitMode? {
    switch value {
    case "executable":
        return .executable
    case "object":
        return .object
    case "llvm", "llvm-ir", "ll":
        return .llvmIR
    case "kir", "kir-dump":
        return .kirDump
    case "library", "lib":
        return .library
    default:
        return nil
    }
}

func parseOptimizationLevel(_ value: String) -> OptimizationLevel? {
    switch value {
    case "O0":
        return .O0
    case "O1":
        return .O1
    case "O2":
        return .O2
    case "O3":
        return .O3
    default:
        return nil
    }
}

func parseTargetTriple(_ value: String) -> TargetTriple? {
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

let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
if args.isEmpty {
    printUsage()
    exit(1)
}

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
var target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)

var index = 0
while index < args.count {
    let arg = args[index]
    switch arg {
    case "-o":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        outputPath = args[index]
    case "-m":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        moduleName = args[index]
    case "--emit":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        if let mode = parseEmitMode(args[index]) {
            emitMode = mode
        } else {
            print("Unsupported emit mode: \(args[index])")
            printUsage()
            exit(1)
        }
    case "-O0", "-O1", "-O2", "-O3":
        if let level = parseOptimizationLevel(String(arg.dropFirst())) {
            optLevel = level
        }
    case "-g":
        debugInfo = true
    case "--target":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        guard let parsed = parseTargetTriple(args[index]) else {
            print("Invalid target triple: \(args[index])")
            printUsage()
            exit(1)
        }
        target = parsed
    case "-Xfrontend":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        frontendFlags.append(args[index])
    case "-Xir":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        irFlags.append(args[index])
    case "-Xruntime":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        runtimeFlags.append(args[index])
    case _ where arg.hasPrefix("-O"):
        if let level = parseOptimizationLevel(String(arg.dropFirst())) {
            optLevel = level
        } else {
            print("Unsupported optimization level: \(arg)")
            printUsage()
            exit(1)
        }
    case "-I":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        searchPaths.append(args[index])
    case "-L":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        libraryPaths.append(args[index])
    case "-l":
        index += 1
        if index >= args.count {
            printUsage()
            exit(1)
        }
        linkLibraries.append(args[index])
    case "-h", "--help":
        printUsage()
        exit(0)
    default:
        if !arg.hasPrefix("-") {
            inputPaths.append(arg)
        } else {
            print("Unknown option: \(arg)")
            printUsage()
            exit(1)
        }
    }
    index += 1
}

if inputPaths.isEmpty {
    printUsage()
    exit(1)
}

let defaultVersion = CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil)
let driver = CompilerDriver(
    version: defaultVersion,
    kotlinVersion: .v2_3_10
)

let options = CompilerOptions(
    moduleName: moduleName,
    inputs: inputPaths,
    outputPath: outputPath,
    emit: emitMode,
    searchPaths: searchPaths,
    libraryPaths: libraryPaths,
    linkLibraries: linkLibraries,
    target: target,
    optLevel: optLevel,
    emitsDebugInfo: debugInfo,
    frontendFlags: frontendFlags,
    irFlags: irFlags,
    runtimeFlags: runtimeFlags
)

let exitCode = driver.run(options: options)
exit(Int32(exitCode))
