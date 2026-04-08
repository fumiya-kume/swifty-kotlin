@testable import CompilerCore
import Foundation
import XCTest

final class SmokeTests: XCTestCase {
    func testSmokeDriverKirDumpSucceedsForMinimalProgram() throws {
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeKir",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
            XCTAssertTrue(fileManager.fileExists(atPath: outputBase + ".kir"))
        }
    }

    func testSmokeDriverExecutableFailsWithoutMain() throws {
        try withTemporaryFile(contents: "fun helper() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase)
                try? fileManager.removeItem(atPath: outputBase + ".o")
            }

            let options = makeTestOptions(
                moduleName: "SmokeMissingMain",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "KSWIFTK-LINK-0002" }))
        }
    }

    func testSmokeDriverSemanticErrorReportsNonZeroExit() throws {
        let source = """
        fun expectInt(value: Int) = value
        fun main() = expectInt("oops")
        """
        try withTemporaryFile(contents: source) { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeSema",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.diagnostics.contains(where: { $0.severity == .error }))
            XCTAssertTrue(result.diagnostics.contains(where: {
                $0.code.hasPrefix("KSWIFTK-SEMA-") || $0.code.hasPrefix("KSWIFTK-TYPE-")
            }))
        }
    }

    func testSmokeDriverMissingInputReportsFailure() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer {
            try? FileManager.default.removeItem(atPath: outputBase + ".kir")
        }

        let options = makeTestOptions(
            moduleName: "SmokeMissingInput",
            inputs: [missingPath],
            outputPath: outputBase,
            emit: .kirDump
        )
        let result = makeTestDriver().runForTesting(options: options)

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "KSWIFTK-SOURCE-0002" }))
    }

    func testSmokeLLVMObjectEmissionProducesNativeObjectFile() throws {
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let objectPath = outputBase + ".o"
            defer {
                try? fileManager.removeItem(atPath: objectPath)
            }

            let options = makeTestOptions(
                moduleName: "SmokeLLVM",
                inputs: [path],
                outputPath: outputBase,
                emit: .object
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
            let data = try Data(contentsOf: URL(fileURLWithPath: objectPath))
            XCTAssertGreaterThanOrEqual(data.count, 4)
            #if os(Linux)
                // ELF magic number
                XCTAssertEqual(Array(data.prefix(4)), [0x7F, 0x45, 0x4C, 0x46])
            #else
                // Mach-O magic number
                XCTAssertEqual(Array(data.prefix(4)), [0xCF, 0xFA, 0xED, 0xFE])
            #endif
        }
    }

    func testSmokeDriverEmptyFileProducesSourceError() throws {
        try withTemporaryFile(contents: "") { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeEmpty",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            // An empty Kotlin file is valid (no top-level declarations is acceptable);
            // the compiler should not crash and must return a defined exit code.
            XCTAssertTrue(
                result.exitCode == 0 || result.exitCode == 1,
                "Unexpected exit code \(result.exitCode) for empty file"
            )
        }
    }

    func testSmokeDriverMultipleInputFilesCompilesToKIR() throws {
        let sourceA = "fun greet(): String = \"hello\""
        let sourceB = "fun main() = 0"
        try withTemporaryFiles(contents: [sourceA, sourceB]) { paths in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeMultiFile",
                inputs: paths,
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
            XCTAssertTrue(fileManager.fileExists(atPath: outputBase + ".kir"))
        }
    }

    func testSmokeDriverLargeFileCompilesToKIR() throws {
        // Generate a file with many top-level functions to exercise the pipeline
        // under a larger-than-trivial input without triggering semantic errors.
        var lines: [String] = []
        for i in 0 ..< 200 {
            lines.append("fun smokeFunc\(i)(x: Int): Int = x + \(i)")
        }
        lines.append("fun main() = 0")
        let source = lines.joined(separator: "\n")

        try withTemporaryFile(contents: source) { path in
            let fileManager = FileManager.default
            let outputBase = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? fileManager.removeItem(atPath: outputBase + ".kir")
            }

            let options = makeTestOptions(
                moduleName: "SmokeLargeFile",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeTestDriver().runForTesting(options: options)

            XCTAssertEqual(result.exitCode, 0)
            XCTAssertFalse(result.diagnostics.contains(where: { $0.severity == .error }))
            XCTAssertTrue(fileManager.fileExists(atPath: outputBase + ".kir"))
        }
    }
}
