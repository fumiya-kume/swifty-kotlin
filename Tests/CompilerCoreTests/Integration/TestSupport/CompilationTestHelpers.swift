@testable import CompilerCore
import Foundation
import XCTest

/// Create a ``CompilerDriver`` instance configured for testing.
func makeTestDriver() -> CompilerDriver {
    CompilerDriver(
        version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
        kotlinVersion: .v2_3_10
    )
}

/// Build ``CompilerOptions`` for test compilation.
func makeTestOptions(
    moduleName: String,
    inputs: [String],
    outputPath: String,
    emit: EmitMode
) -> CompilerOptions {
    CompilerOptions(
        moduleName: moduleName,
        inputs: inputs,
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple()
    )
}

/// Compile Kotlin source through the KIR dump phase and assert success.
func assertKotlinCompilesToKIR(
    _ source: String,
    moduleName: String = "TestMod",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try withTemporaryFile(contents: source) { path in
        let fm = FileManager.default
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let kirPath = outputBase + ".kir"
        defer { try? fm.removeItem(atPath: kirPath) }

        let options = makeTestOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: outputBase,
            emit: .kirDump
        )
        let result = makeTestDriver().runForTesting(options: options)

        XCTAssertEqual(result.exitCode, 0,
                       "KIR compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })",
                       file: file, line: line)
        XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }),
                       "Unexpected errors: \(result.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })",
                       file: file, line: line)
        XCTAssertTrue(fm.fileExists(atPath: kirPath),
                      "KIR file not produced at \(kirPath)",
                      file: file, line: line)
    }
}

/// Compile Kotlin source through object emission and assert a valid object file is produced.
func assertKotlinCompilesToObject(
    _ source: String,
    moduleName: String = "TestMod",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try withTemporaryFile(contents: source) { path in
        let fm = FileManager.default
        let outputBase = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let objectPath = outputBase + ".o"
        defer { try? fm.removeItem(atPath: objectPath) }

        let options = makeTestOptions(
            moduleName: moduleName,
            inputs: [path],
            outputPath: outputBase,
            emit: .object
        )
        let result = makeTestDriver().runForTesting(options: options)

        XCTAssertEqual(result.exitCode, 0,
                       "Object compilation failed. Diagnostics: \(result.diagnostics.map { "\($0.code): \($0.message)" })",
                       file: file, line: line)
        XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }),
                       "Unexpected errors: \(result.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })",
                       file: file, line: line)
        XCTAssertTrue(fm.fileExists(atPath: objectPath),
                      "Object file not produced at \(objectPath)",
                      file: file, line: line)
        let data = try Data(contentsOf: URL(fileURLWithPath: objectPath))
        XCTAssertGreaterThan(data.count, 0,
                             "Object file is empty",
                             file: file, line: line)
    }
}
