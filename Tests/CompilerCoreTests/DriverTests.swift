import XCTest
@testable import CompilerCore

final class DriverTests: XCTestCase {

    // MARK: - fallbackDiagnostic

    func testFallbackDiagnosticForLoadError() {
        let error = CompilerPipelineError.loadError
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.code, "KSWIFTK-PIPELINE-0001")
        XCTAssertTrue(result!.message.contains("loading input sources"))
    }

    func testFallbackDiagnosticForInvalidInput() {
        let error = CompilerPipelineError.invalidInput("bad IR")
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.code, "KSWIFTK-PIPELINE-0002")
        XCTAssertTrue(result!.message.contains("bad IR"))
    }

    func testFallbackDiagnosticForOutputUnavailable() {
        let error = CompilerPipelineError.outputUnavailable
        let result = CompilerDriver.fallbackDiagnostic(for: error)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.code, "KSWIFTK-PIPELINE-0003")
        XCTAssertTrue(result!.message.contains("could not produce"))
    }

    func testFallbackDiagnosticReturnsNilForNonPipelineError() {
        struct OtherError: Error {}
        let result = CompilerDriver.fallbackDiagnostic(for: OtherError())
        XCTAssertNil(result)
    }

    // MARK: - runForTesting

    func testRunForTestingWithNoInputsEmitsError() {
        let driver = CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let result = driver.runForTesting(options: options)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.diagnostics.contains(where: { $0.severity == .error }))
    }

    func testRunForTestingWithNonExistentInputEmitsError() {
        let driver = CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: ["/nonexistent/path.kt"],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let result = driver.runForTesting(options: options)
        XCTAssertEqual(result.exitCode, 1)
    }

    func testRunForTestingWithValidKirDump() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let driver = CompilerDriver(
                version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
                kotlinVersion: .v2_3_10
            )
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let result = driver.runForTesting(options: options)
            // KIR dump should succeed without LLVM
            XCTAssertEqual(result.exitCode, 0, "KIR dump should succeed. Diagnostics: \(result.diagnostics.map(\.message))")
        }
    }

    func testRunForTestingReturnsDiagnosticsForInvalidProgram() throws {
        try withTemporaryFile(contents: "fun main() { val x: Int = \"wrong\" }") { path in
            let driver = CompilerDriver(
                version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
                kotlinVersion: .v2_3_10
            )
            let options = CompilerOptions(
                moduleName: "Test",
                inputs: [path],
                outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
                emit: .kirDump,
                target: defaultTargetTriple()
            )
            let result = driver.runForTesting(options: options)
            // Should have diagnostics for the type mismatch
            XCTAssertFalse(result.diagnostics.isEmpty, "Expected diagnostics for invalid program, but got none")
        }
    }

    // MARK: - run

    func testRunReturnsExitCode() {
        let driver = CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        // Use runForTesting to avoid printing diagnostics to stderr during tests
        let result = driver.runForTesting(options: options)
        XCTAssertEqual(result.exitCode, 1)
    }

    // MARK: - CompilerDriver Init

    func testCompilerDriverInit() {
        let version = CompilerVersion(major: 1, minor: 2, patch: 3, gitHash: "abc123")
        let driver = CompilerDriver(version: version, kotlinVersion: .v2_3_10)
        // Verify the driver works by running with empty inputs
        let options = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "test_out_\(UUID().uuidString)",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let result = driver.runForTesting(options: options)
        XCTAssertEqual(result.exitCode, 1)
    }
}
