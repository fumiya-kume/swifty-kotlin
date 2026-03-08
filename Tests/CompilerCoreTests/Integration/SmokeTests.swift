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

            let options = makeOptions(
                moduleName: "SmokeKir",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeDriver().runForTesting(options: options)

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

            let options = makeOptions(
                moduleName: "SmokeMissingMain",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeDriver().runForTesting(options: options)

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

            let options = makeOptions(
                moduleName: "SmokeSema",
                inputs: [path],
                outputPath: outputBase,
                emit: .kirDump
            )
            let result = makeDriver().runForTesting(options: options)

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

        let options = makeOptions(
            moduleName: "SmokeMissingInput",
            inputs: [missingPath],
            outputPath: outputBase,
            emit: .kirDump
        )
        let result = makeDriver().runForTesting(options: options)

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

            let options = makeOptions(
                moduleName: "SmokeLLVM",
                inputs: [path],
                outputPath: outputBase,
                emit: .object
            )
            let result = makeDriver().runForTesting(options: options)

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

    private func makeDriver() -> CompilerDriver {
        CompilerDriver(
            version: CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil),
            kotlinVersion: .v2_3_10
        )
    }

    private func makeOptions(
        moduleName: String,
        inputs: [String],
        outputPath: String,
        emit: EmitMode,
        irFlags: [String] = []
    ) -> CompilerOptions {
        CompilerOptions(
            moduleName: moduleName,
            inputs: inputs,
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple(),
            irFlags: irFlags
        )
    }
}
