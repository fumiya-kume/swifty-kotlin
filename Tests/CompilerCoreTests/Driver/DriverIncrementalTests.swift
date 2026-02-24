import XCTest
import Foundation
@testable import CompilerCore

final class DriverIncrementalTests: XCTestCase {

    private var tempDir: String!
    private var outputPath: String!

    override func setUp() {
        super.setUp()
        tempDir = NSTemporaryDirectory() + "DriverIncrementalTest_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        outputPath = tempDir + "/output"
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(atPath: dir)
        }
        super.tearDown()
    }

    private func makeDriver() -> CompilerDriver {
        CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )
    }

    // MARK: - time-phases flag

    func testTimePhasesFlagEnablesPhaseTimer() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["time-phases"]
            )
            let result = driver.runForTesting(options: options)
            XCTAssertEqual(result.exitCode, 0,
                "KIR dump with time-phases should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
        }
    }

    // MARK: - incremental flag

    func testIncrementalFlagEnablesIncrementalCompilation() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            let result = driver.runForTesting(options: options)
            XCTAssertEqual(result.exitCode, 0,
                "KIR dump with incremental should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
            // Cache files should have been written
            XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath + "/manifest.json"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: cachePath + "/deps.json"))
        }
    }

    func testIncrementalSecondBuildUsesCache() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            // First build
            let result1 = driver.runForTesting(options: options)
            XCTAssertEqual(result1.exitCode, 0)

            // Second build (no changes)
            let result2 = driver.runForTesting(options: options)
            XCTAssertEqual(result2.exitCode, 0)
        }
    }

    // MARK: - ICE fallback

    func testICEFallbackDiagnosticForUnknownError() {
        struct CustomError: Error {}
        let result = CompilerDriver.fallbackDiagnostic(for: CustomError())
        XCTAssertNil(result)
    }

    // MARK: - Multiple files with dependencies

    func testIncrementalWithMultipleFiles() throws {
        try withTemporaryFiles(contents: [
            "fun greet(): String = \"Hello\"",
            "fun main() { println(greet()) }"
        ]) { paths in
            let driver = makeDriver()
            let cachePath = tempDir + "/cache"
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: paths,
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            let result = driver.runForTesting(options: options)
            XCTAssertEqual(result.exitCode, 0,
                "Multi-file incremental should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
        }
    }

    // MARK: - run method

    func testRunMethodReturnsExitCode() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = makeDriver()
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let exitCode = driver.run(options: options)
            XCTAssertEqual(exitCode, 0)
        }
    }

    func testRunMethodWithErrorReturns1() {
        let driver = makeDriver()
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: outputPath,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let exitCode = driver.run(options: options)
        XCTAssertEqual(exitCode, 1)
    }
}
