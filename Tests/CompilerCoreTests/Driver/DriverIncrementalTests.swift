@testable import CompilerCore
import Foundation
import XCTest

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
        CompilerDriver()
    }

    private func kirOutputPath() -> String {
        outputPath + ".kir"
    }

    private func cachedOutputArtifactPath(in cachePath: String) throws -> String {
        let artifactsPath = cachePath + "/artifacts"
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: artifactsPath))
        for case let path as String in enumerator where URL(fileURLWithPath: path).lastPathComponent == "output" {
            let output = artifactsPath + "/" + path
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: output, isDirectory: &isDirectory), !isDirectory.boolValue {
                return output
            }
        }
        XCTFail("Expected cached output artifact under \(artifactsPath)")
        return artifactsPath + "/missing"
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

    func testIncrementalNoOpBuildRestoresCachedOutputArtifact() throws {
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

            let first = driver.runForTesting(options: options)
            XCTAssertEqual(first.exitCode, 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            let sentinel = "// cached artifact\n"
            try sentinel.write(toFile: cachedOutputArtifactPath(in: cachePath), atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: kirOutputPath())

            let second = driver.runForTesting(options: options)
            XCTAssertEqual(second.exitCode, 0,
                           "No-op incremental build should restore cached artifact. Diagnostics: \(second.diagnostics.map(\.message))")
            XCTAssertEqual(try String(contentsOfFile: kirOutputPath(), encoding: .utf8), sentinel)
        }
    }

    func testIncrementalChangedInputDoesNotRestoreStaleOutputArtifact() throws {
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

            let first = driver.runForTesting(options: options)
            XCTAssertEqual(first.exitCode, 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            let sentinel = "// stale cached artifact\n"
            try sentinel.write(toFile: cachedOutputArtifactPath(in: cachePath), atomically: true, encoding: .utf8)
            try "fun main() { println(\"changed\") }".write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: kirOutputPath())

            let second = driver.runForTesting(options: options)
            XCTAssertEqual(second.exitCode, 0,
                           "Changed input should fall back to a full build. Diagnostics: \(second.diagnostics.map(\.message))")
            XCTAssertNotEqual(try String(contentsOfFile: kirOutputPath(), encoding: .utf8), sentinel)
        }
    }

    func testIncrementalChangedConfigurationDoesNotRestoreStaleOutputArtifact() throws {
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

            let first = driver.runForTesting(options: options)
            XCTAssertEqual(first.exitCode, 0,
                           "Initial incremental build should succeed. Diagnostics: \(first.diagnostics.map(\.message))")

            let sentinel = "// stale cached artifact\n"
            try sentinel.write(toFile: cachedOutputArtifactPath(in: cachePath), atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: kirOutputPath())

            let changedOptions = CompilerOptions(
                moduleName: "ChangedTest",
                inputs: [path],
                outputPath: outputPath,
                emit: .kirDump,
                target: defaultTargetTriple(),
                frontendFlags: ["incremental"],
                incrementalCachePath: cachePath
            )
            let second = driver.runForTesting(options: changedOptions)
            XCTAssertEqual(second.exitCode, 0,
                           "Changed build configuration should fall back to a full build. Diagnostics: \(second.diagnostics.map(\.message))")
            XCTAssertNotEqual(try String(contentsOfFile: kirOutputPath(), encoding: .utf8), sentinel)
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
            "fun main() { println(greet()) }",
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
