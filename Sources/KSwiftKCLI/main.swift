import Foundation
import CompilerCore

func printUsage() {
    print(CLIParser.usageText)
}

func printCLIError(_ error: CLIParseError) {
    switch error {
    case .usageRequested, .noInputFiles:
        break
    case .missingValue(let option):
        print("Missing value for option: \(option)")
    case .unsupportedEmitMode(let value):
        print("Unsupported emit mode: \(value)")
    case .unsupportedOptimizationLevel(let value):
        print("Unsupported optimization level: \(value)")
    case .invalidTargetTriple(let value):
        print("Invalid target triple: \(value)")
    case .unknownOption(let option):
        print("Unknown option: \(option)")
    }
}

let args = Array(ProcessInfo.processInfo.arguments.dropFirst())

do {
    let options = try CLIParser.parse(args: args)
    let defaultVersion = CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil)
    let driver = CompilerDriver(
        version: defaultVersion,
        kotlinVersion: .v2_3_10
    )
    let exitCode = driver.run(options: options)
    exit(Int32(exitCode))
} catch let error as CLIParseError {
    if error == .usageRequested {
        printUsage()
        exit(0)
    }
    printCLIError(error)
    printUsage()
    exit(1)
} catch {
    print("Compiler internal error: \(error)")
    exit(1)
}
