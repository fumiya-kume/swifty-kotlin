@testable import CompilerCore
@testable import KSwiftKCLI
import XCTest

final class CLIParserTests: XCTestCase {
    func testParsesMinimalInput() throws {
        let options = try CLIParser.parse(args: ["input.kt"])
        XCTAssertEqual(options.inputs, ["input.kt"])
        XCTAssertEqual(options.outputPath, "./a.out")
        XCTAssertEqual(options.moduleName, "Main")
        XCTAssertEqual(options.emit, .executable)
    }

    func testParsesOptionsAndFlags() throws {
        let options = try CLIParser.parse(args: [
            "-o", "out.bin",
            "-m", "Demo",
            "--emit", "kir",
            "-O2",
            "-I", "include",
            "-L", "lib",
            "-l", "runtime",
            "--target", "x86_64-apple-macos",
            "-Xfrontend", "time-phases",
            "-Xir", "trace-lowering",
            "-Xruntime", "trace=true",
            "-g",
            "main.kt",
        ])

        XCTAssertEqual(options.outputPath, "out.bin")
        XCTAssertEqual(options.moduleName, "Demo")
        XCTAssertEqual(options.emit, .kirDump)
        XCTAssertEqual(options.optLevel, .O2)
        XCTAssertEqual(options.searchPaths, ["include"])
        XCTAssertEqual(options.libraryPaths, ["lib"])
        XCTAssertEqual(options.linkLibraries, ["runtime"])
        XCTAssertEqual(options.frontendFlags, ["time-phases"])
        XCTAssertEqual(options.irFlags, ["trace-lowering"])
        XCTAssertEqual(options.runtimeFlags, ["trace=true"])
        XCTAssertTrue(options.debugInfo)
        XCTAssertEqual(options.inputs, ["main.kt"])
        XCTAssertEqual(options.target.arch, "x86_64")
        XCTAssertEqual(options.target.vendor, "apple")
        XCTAssertEqual(options.target.os, "macos")
    }

    func testThrowsMissingValue() {
        XCTAssertThrowsError(try CLIParser.parse(args: ["-o"])) { error in
            XCTAssertEqual(error as? CLIParseError, .missingValue("-o"))
        }
    }

    func testThrowsInvalidTargetTriple() {
        XCTAssertThrowsError(try CLIParser.parse(args: ["--target", "invalid", "main.kt"])) { error in
            XCTAssertEqual(error as? CLIParseError, .invalidTargetTriple("invalid"))
        }
    }

    func testThrowsUnknownOption() {
        XCTAssertThrowsError(try CLIParser.parse(args: ["--unknown", "main.kt"])) { error in
            XCTAssertEqual(error as? CLIParseError, .unknownOption("--unknown"))
        }
    }

    func testHelpFlagRequestsUsage() {
        XCTAssertThrowsError(try CLIParser.parse(args: ["--help"])) { error in
            XCTAssertEqual(error as? CLIParseError, .usageRequested)
        }
    }
}
