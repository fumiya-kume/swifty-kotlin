import CompilerCore
import Foundation

func printUsage() {
    print(CLIParser.usageText)
}

func printCLIError(_ error: CLIParseError) {
    switch error {
    case .usageRequested, .noInputFiles:
        break
    case let .missingValue(option):
        print("Missing value for option: \(option)")
    case let .unsupportedEmitMode(value):
        print("Unsupported emit mode: \(value)")
    case let .unsupportedOptimizationLevel(value):
        print("Unsupported optimization level: \(value)")
    case let .invalidTargetTriple(value):
        print("Invalid target triple: \(value)")
    case let .unsupportedDiagnosticsFormat(value):
        print("Unsupported diagnostics format: \(value)")
    case let .unknownOption(option):
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
