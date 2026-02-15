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

let defaultTarget = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
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
    target: defaultTarget,
    optLevel: optLevel,
    debugInfo: debugInfo
)

let exitCode = driver.run(options: options)
exit(Int32(exitCode))
